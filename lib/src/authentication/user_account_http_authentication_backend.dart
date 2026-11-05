import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'native_authentication_credential_store.dart';
import 'user_account_authentication.dart';
import 'user_account_http_wire.dart';

/// An explicit authority binding. Construction never contacts that authority.
final class UserAccountHttpProfile {
  /// Admits raw configuration before URI parsing can normalize its path.
  factory UserAccountHttpProfile.fromString({
    required String profileId,
    required String serviceBaseUri,
    bool allowDevelopmentHttp = false,
    Duration requestTimeout = const Duration(seconds: 15),
  }) => UserAccountHttpProfile(
    profileId: profileId,
    serviceBaseUri: _rawBase(serviceBaseUri),
    allowDevelopmentHttp: allowDevelopmentHttp,
    requestTimeout: requestTimeout,
  );

  /// Binds an explicitly supplied, already-parsed canonical URI.
  UserAccountHttpProfile({
    required String profileId,
    required Uri serviceBaseUri,
    bool allowDevelopmentHttp = false,
    Duration requestTimeout = const Duration(seconds: 15),
  }) : profileId = _profileId(profileId),
       serviceBaseUri = _base(serviceBaseUri, allowDevelopmentHttp),
       requestTimeout = _timeout(requestTimeout);

  final String profileId;
  final Uri serviceBaseUri;
  final Duration requestTimeout;

  static String _profileId(String value) {
    if (!_matches(RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'), value)) {
      throw _invalidProfile();
    }
    return value;
  }

  static Duration _timeout(Duration value) {
    if (value <= Duration.zero || value > const Duration(seconds: 60)) {
      throw _invalidProfile();
    }
    return value;
  }

  static Uri _rawBase(String value) {
    try {
      if (value.contains('\\') ||
          value.codeUnits.any((c) => c < 32 || c == 127)) {
        throw _invalidProfile();
      }
      final binding = RegExp(
        r'^[A-Za-z][A-Za-z0-9+.-]*://[^/?#]*(/[^?#]*)?(?:[?#].*)?$',
      ).firstMatch(value);
      if (binding == null) {
        throw _invalidProfile();
      }
      _validatePath(binding.group(1) ?? '');
      final parsed = Uri.tryParse(value);
      if (parsed == null) {
        throw _invalidProfile();
      }
      return parsed;
    } catch (_) {
      throw _invalidProfile();
    }
  }

  static void _validatePath(String path) {
    for (final segment in path.split('/')) {
      final decoded = Uri.decodeComponent(segment);
      if (decoded == '.' ||
          decoded == '..' ||
          decoded.contains('\\') ||
          decoded.contains('/') ||
          decoded.codeUnits.any((c) => c < 32 || c == 127)) {
        throw _invalidProfile();
      }
    }
  }

  static Uri _base(Uri value, bool development) {
    try {
      final raw = value.toString();
      if (!value.isAbsolute ||
          value.host.isEmpty ||
          value.userInfo.isNotEmpty ||
          value.hasQuery ||
          value.hasFragment ||
          raw.contains('\\') ||
          raw.codeUnits.any((c) => c < 32 || c == 127) ||
          RegExp(
            r'%(?:2f|5c|0[0-9a-f]|1[0-9a-f]|7f)',
            caseSensitive: false,
          ).hasMatch(value.path)) {
        throw _invalidProfile();
      }
      _validatePath(value.path);
      if (value.scheme != 'https' &&
          !(development &&
              value.scheme == 'http' &&
              _privateHost(value.host))) {
        throw _invalidProfile();
      }
      return value.replace(
        path: '${value.path.replaceFirst(RegExp(r'/+$'), '')}/',
      );
    } catch (_) {
      throw _invalidProfile();
    }
  }

  static bool _privateHost(String host) {
    final normalized = host.toLowerCase();
    if (normalized == 'localhost' ||
        normalized == '::1' ||
        normalized == '[::1]') {
      return true;
    }
    final pieces = host.split('.');
    if (pieces.length != 4 ||
        pieces.any((v) => !RegExp(r'^(0|[1-9][0-9]{0,2})$').hasMatch(v))) {
      return false;
    }
    final parts = pieces.map(int.parse).toList();
    if (parts.any((v) => v > 255)) return false;
    return parts[0] == 127 ||
        parts[0] == 10 ||
        (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) ||
        (parts[0] == 192 && parts[1] == 168);
  }

  @override
  String toString() => 'UserAccountHttpProfile';
}

/// Native server-backed authentication. One instance serves one client lifetime.
/// Credentials remain in private memory and the existing protected native store.
final class UserAccountHttpAuthenticationBackend
    implements UserAccountRestorableAuthenticationBackend {
  UserAccountHttpAuthenticationBackend({
    required this.profile,
    http.Client? client,
    NativeAuthenticationCredentialStore? credentialStore,
  }) : _client = client ?? http.Client(),
       _store = credentialStore ?? NativeAuthenticationCredentialStore(),
       _ownsClient = client == null,
       _ownsStore = credentialStore == null;

  final UserAccountHttpProfile profile;
  final http.Client _client;
  final NativeAuthenticationCredentialStore _store;
  final bool _ownsClient;
  final bool _ownsStore;
  final Completer<void> _closedSignal = Completer<void>();
  bool _closed = false;
  bool _busy = false;
  bool _unresolvedCleanup = false;
  Completer<void>? _workDone;
  Future<void>? _closing;
  _OwnedSession? _active;
  bool _clearanceSelectionRecorded = false;
  _ClearanceOwner? _clearanceOwner;
  UserAccountHttpWireChallenge? _challenge;
  _SessionCommit? _pending;

  void _guard(UserAccountAuthenticationOperation operation) {
    if (_closed || !operation.isCurrent) {
      throw const _SafeFailure(
        UserAccountAuthenticationFailure.transportUnavailable,
      );
    }
  }

  Future<UserAccountSignInResult?> _authenticate(
    UserAccountAuthenticationOperation operation,
    Future<UserAccountSignInResult?> Function() body,
  ) async {
    if (_busy || _pending != null || _unresolvedCleanup) {
      return const UserAccountSignInRejected(
        UserAccountAuthenticationFailure.serviceUnavailable,
      );
    }
    _busy = true;
    final done = Completer<void>();
    _workDone = done;
    try {
      _guard(operation);
      return await body();
    } on _SafeFailure catch (failure) {
      return UserAccountSignInRejected(failure.reason);
    } on UserAccountHttpWireException {
      return const UserAccountSignInRejected(
        UserAccountAuthenticationFailure.invalidResponse,
      );
    } catch (_) {
      return const UserAccountSignInRejected(
        UserAccountAuthenticationFailure.serviceUnavailable,
      );
    } finally {
      _busy = false;
      _workDone = null;
      done.complete();
    }
  }

  @override
  Future<UserAccountSignInResult> signIn({
    required String identifier,
    required String password,
    required UserAccountAuthenticationOperation operation,
  }) async => (await _authenticate(operation, () async {
    _active = null;
    _challenge = null;
    final old = await _read(operation);
    if (old != null) {
      final record = _record(
        old,
      ); // Foreign or malformed data is never removed.
      _selectClearanceOwner(record, old.revision);
      await _remove(old.revision, operation);
    } else {
      _selectEmptyClearance();
    }
    _guard(operation);
    final result = decodeUserAccountHttpLogin(
      await _json(
        'login',
        operation,
        body: {'identifier': identifier, 'password': password},
        refusal: UserAccountAuthenticationFailure.invalidCredentials,
      ),
    );
    _guard(operation);
    switch (result) {
      case UserAccountHttpWireChallenge():
        _challenge = result;
        return UserAccountChallengePending(result.challengeId, result.channel);
      case UserAccountHttpWireSessionPair():
        return _stage(_Pair.login(result), operation);
    }
  }))!;

  @override
  Future<UserAccountSignInResult> verifyChallenge({
    required String challengeId,
    required String code,
    required UserAccountAuthenticationOperation operation,
  }) async => (await _authenticate(operation, () async {
    final expected = _challenge;
    _challenge = null;
    if (expected == null || expected.challengeId != challengeId) {
      throw const _SafeFailure(
        UserAccountAuthenticationFailure.challengeRejected,
      );
    }
    final result = decodeUserAccountHttpLogin(
      await _json(
        'verify-two-factor-login',
        operation,
        body: {'challengeId': challengeId, 'code': code},
        refusal: UserAccountAuthenticationFailure.challengeRejected,
      ),
    );
    _guard(operation);
    if (result is! UserAccountHttpWireSessionPair ||
        result.userAccountId != expected.userAccountId ||
        result.credentialId != expected.credentialId) {
      throw const _SafeFailure(
        UserAccountAuthenticationFailure.invalidResponse,
      );
    }
    return _stage(_Pair.login(result), operation);
  }))!;

  @override
  Future<UserAccountSignInResult> refresh({
    required UserAccountAuthenticationOperation operation,
  }) async => (await _authenticate(operation, () async {
    final old = _active;
    _active = null;
    _challenge = null;
    if (old == null) {
      throw const _SafeFailure(
        UserAccountAuthenticationFailure.authorizationRequired,
      );
    }
    final stored = await _read(operation);
    if (stored == null ||
        stored.revision != old.revision ||
        !_record(stored).same(old.record)) {
      throw const _SafeFailure(
        UserAccountAuthenticationFailure.serviceUnavailable,
      );
    }
    await _remove(old.revision, operation);
    return _rotate(old.record.pair, operation);
  }))!;

  Future<UserAccountSignInResult> _rotate(
    _Pair old,
    UserAccountAuthenticationOperation operation,
  ) async {
    final rotated = decodeUserAccountHttpRefresh(
      await _json(
        'refresh-access-token',
        operation,
        body: {'refreshToken': old.refreshToken},
        refusal: UserAccountAuthenticationFailure.authorizationRequired,
      ),
    );
    _guard(operation);
    if (rotated.userAccountId != old.userAccountId) {
      throw const _SafeFailure(
        UserAccountAuthenticationFailure.invalidResponse,
      );
    }
    return _stage(_Pair.refresh(rotated), operation);
  }

  @override
  Future<UserAccountSignInResult?> restore({
    required UserAccountAuthenticationOperation operation,
  }) => _authenticate(operation, () async {
    _active = null;
    _challenge = null;
    final entry = await _read(operation);
    if (entry == null) {
      _selectEmptyClearance();
      return null;
    }
    final record = _record(entry);
    _selectClearanceOwner(record, entry.revision);
    final response = await _request(
      'get-my-account',
      operation,
      access: record.pair.accessToken,
    );
    _guard(operation);
    if (response.status == 401) {
      await _remove(entry.revision, operation);
      return _rotate(record.pair, operation);
    }
    if (response.status == 403) {
      await _remove(entry.revision, operation);
      throw const _SafeFailure(
        UserAccountAuthenticationFailure.authorizationRequired,
      );
    }
    _status(
      response.status,
      UserAccountAuthenticationFailure.authorizationRequired,
    );
    final account = decodeUserAccountHttpAccount(
      _decode(response.bytes),
      expectedUserAccountId: record.pair.userAccountId,
    );
    _guard(operation);
    return _candidate(record, account, operation, baseline: entry.revision);
  });

  Future<UserAccountSignedIn> _stage(
    _Pair pair,
    UserAccountAuthenticationOperation operation,
  ) async {
    final document = await _json(
      'get-my-account',
      operation,
      access: pair.accessToken,
      refusal: UserAccountAuthenticationFailure.authorizationRequired,
    );
    _guard(operation);
    final account = decodeUserAccountHttpAccount(
      document,
      expectedUserAccountId: pair.userAccountId,
    );
    return _candidate(_Record.fresh(profile, pair), account, operation);
  }

  UserAccountSignedIn _candidate(
    _Record record,
    AuthenticatedUserAccount account,
    UserAccountAuthenticationOperation operation, {
    String? baseline,
  }) {
    _guard(operation);
    final completion = _SessionCommit(this, record, operation, baseline);
    _pending = completion;
    return UserAccountSignedIn(account, sessionCommit: completion);
  }

  Future<NativeAuthenticationCredentialEntry?> _read(
    UserAccountAuthenticationOperation operation,
  ) async {
    _guard(operation);
    final entry = await _store.read(profile.profileId);
    _guard(operation);
    return entry;
  }

  _Record _record(NativeAuthenticationCredentialEntry entry) =>
      _Record.decode(entry.value, profile);

  void _selectClearanceOwner(_Record record, String revision) {
    _clearanceSelectionRecorded = true;
    _clearanceOwner = _ClearanceOwner(
      revision,
      record.writeId,
      record.pair.userAccountId,
    );
  }

  void _selectEmptyClearance() {
    _clearanceSelectionRecorded = true;
    _clearanceOwner = null;
  }

  Future<void> _remove(
    String revision,
    UserAccountAuthenticationOperation operation,
  ) async {
    _guard(operation);
    final removed = await _store.remove(
      profileId: profile.profileId,
      expectedRevision: revision,
    );
    _guard(operation);
    if (!removed) {
      throw const _SafeFailure(
        UserAccountAuthenticationFailure.serviceUnavailable,
      );
    }
  }

  @override
  Future<UserAccountLogoutResult> signOut({
    required UserAccountAuthenticationOperation operation,
  }) async {
    final active = _active;
    _active = null;
    _challenge = null;
    if (_closed || !operation.isCurrent || _busy || _pending != null) {
      return const UserAccountLogoutResult(
        localCleared: false,
        remoteRevocation: UserAccountRemoteRevocation.notAttempted,
      );
    }
    _busy = true;
    final done = Completer<void>();
    _workDone = done;
    var localCleared = false;
    var remote = UserAccountRemoteRevocation.notAttempted;
    try {
      try {
        final entry = await _read(operation);
        if (entry == null) {
          if (!_clearanceSelectionRecorded) {
            _selectEmptyClearance();
          }
          localCleared = true;
        } else {
          final record = _record(entry);
          if (!_clearanceSelectionRecorded) {
            _selectClearanceOwner(record, entry.revision);
          }
          final owner = _clearanceOwner;
          if (owner != null && owner.matches(entry.revision, record)) {
            await _remove(entry.revision, operation);
            localCleared = true;
          }
        }
      } catch (_) {
        // Remote revocation remains independent of a failed local CAS/read.
      }
      if (active != null && !_closed && operation.isCurrent) {
        try {
          final response = await _request(
            'logout',
            operation,
            access: active.record.pair.accessToken,
            body: {'userAccountId': active.record.pair.userAccountId},
          );
          _guard(operation);
          remote = response.status == 200 && response.bytes.isEmpty
              ? UserAccountRemoteRevocation.confirmed
              : UserAccountRemoteRevocation.failed;
        } on _SafeFailure catch (failure) {
          remote =
              failure.reason ==
                  UserAccountAuthenticationFailure.transportUnavailable
              ? UserAccountRemoteRevocation.unknown
              : UserAccountRemoteRevocation.failed;
        } catch (_) {
          remote = UserAccountRemoteRevocation.unknown;
        }
      }
      if (localCleared) _unresolvedCleanup = false;
      return UserAccountLogoutResult(
        localCleared: localCleared,
        remoteRevocation: remote,
      );
    } finally {
      _busy = false;
      _workDone = null;
      done.complete();
    }
  }

  Future<Object?> _json(
    String selector,
    UserAccountAuthenticationOperation operation, {
    Map<String, Object?>? body,
    String? access,
    required UserAccountAuthenticationFailure refusal,
  }) async {
    final response = await _request(
      selector,
      operation,
      body: body,
      access: access,
    );
    _guard(operation);
    _status(response.status, refusal);
    return _decode(response.bytes);
  }

  static Object? _decode(Uint8List bytes) {
    try {
      return jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } catch (_) {
      throw const _SafeFailure(
        UserAccountAuthenticationFailure.invalidResponse,
      );
    }
  }

  static void _status(int status, UserAccountAuthenticationFailure refusal) {
    if (status == 200) return;
    throw _SafeFailure(switch (status) {
      401 || 403 => refusal,
      429 ||
      >= 500 && <= 599 => UserAccountAuthenticationFailure.serviceUnavailable,
      _ => UserAccountAuthenticationFailure.invalidResponse,
    });
  }

  Future<_Reply> _request(
    String selector,
    UserAccountAuthenticationOperation operation, {
    Map<String, Object?>? body,
    String? access,
  }) async {
    _guard(operation);
    final abort = Completer<void>();
    final result = Completer<_Reply>();
    StreamSubscription<List<int>>? subscription;
    var size = 0;
    final bytes = BytesBuilder(copy: false);
    void abortRequest() {
      if (!abort.isCompleted) abort.complete();
      final listening = subscription;
      if (listening != null) _observe(listening.cancel());
    }

    void fail(UserAccountAuthenticationFailure reason) {
      if (result.isCompleted) return;
      result.completeError(_SafeFailure(reason));
      abortRequest();
    }

    final request = http.AbortableRequest(
      body == null ? 'GET' : 'POST',
      profile.serviceBaseUri.resolve(selector),
      abortTrigger: abort.future,
    )..followRedirects = false;
    request.headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    if (access != null) request.headers['Authorization'] = 'Bearer $access';
    final timer = Timer(profile.requestTimeout, () {
      fail(UserAccountAuthenticationFailure.transportUnavailable);
    });
    // Successful client completion also retires the operation. A completed
    // request is unaffected; no storage cleanup subscribes to this signal.
    operation.cancelled.then<void>((_) {
      fail(UserAccountAuthenticationFailure.transportUnavailable);
    });
    _closedSignal.future.then<void>((_) {
      fail(UserAccountAuthenticationFailure.transportUnavailable);
    });
    try {
      _guard(operation);
      final sending = _client.send(request);
      _observe(
        sending.then<void>(
          (response) {
            if (result.isCompleted || _closed || !operation.isCurrent) {
              _observe(
                response.stream.listen((_) {}, onError: (Object _) {}).cancel(),
              );
              fail(UserAccountAuthenticationFailure.transportUnavailable);
              return;
            }
            subscription = response.stream.listen(
              (chunk) {
                if (result.isCompleted) return;
                if (_closed || !operation.isCurrent) {
                  fail(UserAccountAuthenticationFailure.transportUnavailable);
                  return;
                }
                size += chunk.length;
                if (size > 65536) {
                  fail(UserAccountAuthenticationFailure.invalidResponse);
                } else {
                  bytes.add(chunk);
                }
              },
              onError: (Object _) {
                fail(UserAccountAuthenticationFailure.transportUnavailable);
              },
              onDone: () {
                if (!result.isCompleted) {
                  if (_closed || !operation.isCurrent) {
                    fail(UserAccountAuthenticationFailure.transportUnavailable);
                  } else {
                    result.complete(
                      _Reply(response.statusCode, bytes.takeBytes()),
                    );
                  }
                }
              },
              cancelOnError: true,
            );
          },
          onError: (Object _) {
            fail(UserAccountAuthenticationFailure.transportUnavailable);
          },
        ),
      );
      return await result.future;
    } on _SafeFailure {
      rethrow;
    } catch (_) {
      abortRequest();
      throw const _SafeFailure(
        UserAccountAuthenticationFailure.transportUnavailable,
      );
    } finally {
      timer.cancel();
    }
  }

  @override
  Future<void> close() {
    if (_closing case final closing?) return closing;
    _closed = true;
    _active = null;
    _clearanceSelectionRecorded = false;
    _clearanceOwner = null;
    _challenge = null;
    _closedSignal.complete();
    final done = Completer<void>();
    _closing = done.future;
    _observe(done.future);
    final work = _workDone?.future;
    () async {
      var failed = false;
      try {
        if (work != null) await work;
        await _pending?.discard();
      } catch (_) {
        failed = true;
      }
      if (_unresolvedCleanup) failed = true;
      if (_ownsClient) {
        try {
          _client.close();
        } catch (_) {
          failed = true;
        }
      }
      if (_ownsStore) {
        try {
          await _store.close();
        } catch (_) {
          failed = true;
        }
      }
      if (failed) {
        done.completeError(
          const _SafeFailure(
            UserAccountAuthenticationFailure.serviceUnavailable,
          ),
        );
      } else {
        done.complete();
      }
    }();
    return done.future;
  }

  @override
  String toString() => 'UserAccountHttpAuthenticationBackend';
}

final class _SessionCommit implements UserAccountAuthenticationSessionCommit {
  _SessionCommit(this.backend, this.record, this.operation, this.baseline);
  final UserAccountHttpAuthenticationBackend backend;
  final _Record record;
  final UserAccountAuthenticationOperation operation;
  final String? baseline;
  Future<void>? _persisting;
  Future<void>? _discarding;
  Future<void>? _rollingBack;
  String? _writtenRevision;
  bool _persisted = false;
  bool _accepted = false;
  bool _discarded = false;
  bool _indeterminate = false;

  @override
  Future<void> persist({
    required UserAccountAuthenticationOperation operation,
  }) {
    if (!identical(operation, this.operation) || _discarded) {
      return Future.error(
        const _SafeFailure(UserAccountAuthenticationFailure.serviceUnavailable),
      );
    }
    return _persisting ??= _persist();
  }

  Future<void> _persist() async {
    try {
      backend._guard(operation);
      if (baseline != null) {
        final entry = await backend._read(operation);
        if (entry == null ||
            entry.revision != baseline ||
            !backend._record(entry).same(record)) {
          throw const _SafeFailure(
            UserAccountAuthenticationFailure.serviceUnavailable,
          );
        }
      } else {
        backend._guard(operation);
        final bytes = record.encode();
        _indeterminate = true;
        final revision = await backend._store.replace(
          profileId: backend.profile.profileId,
          expectedRevision: null,
          value: bytes,
        );
        _indeterminate = false;
        _writtenRevision = revision;
        if (revision == null) {
          throw const _SafeFailure(
            UserAccountAuthenticationFailure.serviceUnavailable,
          );
        }
      }
      backend._guard(operation);
      if (_discarded) {
        throw const _SafeFailure(
          UserAccountAuthenticationFailure.serviceUnavailable,
        );
      }
      _persisted = true;
    } catch (_) {
      // Includes a write which completed after retirement. Only this candidate's
      // revision/writeId can be rolled back, never a baseline read by restore.
      try {
        await _rollback();
      } catch (_) {
        throw const _SafeFailure(
          UserAccountAuthenticationFailure.serviceUnavailable,
        );
      }
      throw const _SafeFailure(
        UserAccountAuthenticationFailure.serviceUnavailable,
      );
    }
  }

  @override
  void accept() {
    if (_accepted) return;
    backend._guard(operation);
    if (!_persisted || _discarded || !identical(backend._pending, this)) {
      throw const _SafeFailure(
        UserAccountAuthenticationFailure.serviceUnavailable,
      );
    }
    final revision = baseline ?? _writtenRevision;
    if (revision == null) {
      throw const _SafeFailure(
        UserAccountAuthenticationFailure.serviceUnavailable,
      );
    }
    backend._active = _OwnedSession(record, revision);
    backend._selectClearanceOwner(record, revision);
    _accepted = true;
    backend._pending = null;
  }

  Future<void> _rollback() => _rollingBack ??= _doRollback();

  Future<void> _doRollback() async {
    if (_accepted || baseline != null) return;
    var revision = _writtenRevision;
    try {
      if (revision == null && _indeterminate) {
        final entry = await backend._store.read(backend.profile.profileId);
        if (entry != null) {
          _Record? selected;
          try {
            selected = backend._record(entry);
          } catch (_) {
            /* Retain foreign data. */
          }
          if (selected != null && selected.same(record)) {
            revision = entry.revision;
          }
        }
        _indeterminate = false;
      }
      if (revision != null) {
        final removed = await backend._store.remove(
          profileId: backend.profile.profileId,
          expectedRevision: revision,
        );
        if (!removed) {
          // A new owner must survive. A read distinguishes that owner from an
          // unresolved own write, without another remove or overwrite attempt.
          final entry = await backend._store.read(backend.profile.profileId);
          if (entry != null && entry.revision == revision) {
            throw const _SafeFailure(
              UserAccountAuthenticationFailure.serviceUnavailable,
            );
          }
        }
        _writtenRevision = null;
      }
    } catch (_) {
      if (revision != null || _indeterminate) {
        // Retain only a local clearance witness, never the unaccepted pair.
        backend._unresolvedCleanup = true;
        backend._active = null;
        backend._challenge = null;
        backend._clearanceSelectionRecorded = true;
        backend._clearanceOwner = _ClearanceOwner(
          revision,
          record.writeId,
          record.pair.userAccountId,
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> discard() {
    if (_accepted) return Future.value();
    return _discarding ??= _discard();
  }

  Future<void> _discard() async {
    _discarded = true;
    try {
      final persisting = _persisting;
      if (persisting != null) {
        try {
          await persisting;
        } catch (_) {
          /* Cleanup below observes IO. */
        }
      }
      await _rollback();
    } catch (_) {
      backend._active = null;
      throw const _SafeFailure(
        UserAccountAuthenticationFailure.serviceUnavailable,
      );
    } finally {
      if (identical(backend._pending, this)) backend._pending = null;
    }
  }

  @override
  String toString() => 'UserAccountAuthenticationSessionCommit';
}

final class _Pair {
  const _Pair(
    this.userAccountId,
    this.accessSessionId,
    this.accessToken,
    this.refreshSessionId,
    this.refreshToken,
  );
  factory _Pair.login(UserAccountHttpWireSessionPair pair) => _Pair(
    pair.userAccountId,
    pair.accessSessionId,
    pair.accessToken,
    pair.refreshSessionId,
    pair.refreshToken,
  );
  factory _Pair.refresh(UserAccountHttpWireRefreshPair pair) => _Pair(
    pair.userAccountId,
    pair.accessSessionId,
    pair.accessToken,
    pair.refreshSessionId,
    pair.refreshToken,
  );
  final String userAccountId;
  final String accessSessionId;
  final String accessToken;
  final String refreshSessionId;
  final String refreshToken;
  @override
  String toString() => 'UserAccountSessionPair';
}

final class _Record {
  const _Record(this.profileId, this.authorityBaseUri, this.pair, this.writeId);
  factory _Record.fresh(UserAccountHttpProfile profile, _Pair pair) {
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return _Record(
      profile.profileId,
      profile.serviceBaseUri.toString(),
      pair,
      id,
    );
  }
  factory _Record.decode(Uint8List bytes, UserAccountHttpProfile profile) {
    try {
      if (bytes.isEmpty || bytes.length > 65536) throw const FormatException();
      final document = jsonDecode(utf8.decode(bytes, allowMalformed: false));
      const keys = {
        'schemaVersion',
        'profileId',
        'authorityBaseUri',
        'userAccountId',
        'accessSessionId',
        'accessToken',
        'refreshSessionId',
        'refreshToken',
        'writeId',
      };
      if (document is! Map<String, dynamic> ||
          document.length != keys.length ||
          !keys.every(document.containsKey) ||
          document['schemaVersion'] is! int ||
          document['schemaVersion'] != 1 ||
          document['profileId'] != profile.profileId ||
          document['authorityBaseUri'] != profile.serviceBaseUri.toString() ||
          document['writeId'] is! String ||
          !_matches(RegExp(r'^[0-9a-f]{32}$'), document['writeId'] as String)) {
        throw const FormatException();
      }
      final decoded = decodeUserAccountHttpRefresh({
        'user_account_id': document['userAccountId'],
        'access_session_id': document['accessSessionId'],
        'access_token': document['accessToken'],
        'refresh_session_id': document['refreshSessionId'],
        'refresh_token': document['refreshToken'],
        'authenticated': true,
      });
      return _Record(
        profile.profileId,
        profile.serviceBaseUri.toString(),
        _Pair.refresh(decoded),
        document['writeId'] as String,
      );
    } catch (_) {
      throw const _SafeFailure(
        UserAccountAuthenticationFailure.invalidResponse,
      );
    }
  }
  final String profileId;
  final String authorityBaseUri;
  final _Pair pair;
  final String writeId;
  Uint8List encode() {
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'schemaVersion': 1,
          'profileId': profileId,
          'authorityBaseUri': authorityBaseUri,
          'userAccountId': pair.userAccountId,
          'accessSessionId': pair.accessSessionId,
          'accessToken': pair.accessToken,
          'refreshSessionId': pair.refreshSessionId,
          'refreshToken': pair.refreshToken,
          'writeId': writeId,
        }),
      ),
    );
    if (bytes.length > 65536) {
      throw const _SafeFailure(
        UserAccountAuthenticationFailure.invalidResponse,
      );
    }
    return bytes;
  }

  bool same(_Record other) =>
      profileId == other.profileId &&
      authorityBaseUri == other.authorityBaseUri &&
      writeId == other.writeId &&
      pair.userAccountId == other.pair.userAccountId &&
      pair.accessSessionId == other.pair.accessSessionId &&
      pair.accessToken == other.pair.accessToken &&
      pair.refreshSessionId == other.pair.refreshSessionId &&
      pair.refreshToken == other.pair.refreshToken;
  @override
  String toString() => 'UserAccountCredentialRecord';
}

/// Local CAS ownership only; this selection never retains usable credentials.
final class _ClearanceOwner {
  const _ClearanceOwner(this.revision, this.writeId, this.userAccountId);
  final String? revision;
  final String writeId;
  final String userAccountId;

  bool matches(String revision, _Record record) =>
      (this.revision == null || this.revision == revision) &&
      writeId == record.writeId &&
      userAccountId == record.pair.userAccountId;

  @override
  String toString() => 'UserAccountClearanceOwner';
}

final class _OwnedSession {
  const _OwnedSession(this.record, this.revision);
  final _Record record;
  final String revision;
  @override
  String toString() => 'UserAccountOwnedSession';
}

final class _Reply {
  const _Reply(this.status, this.bytes);
  final int status;
  final Uint8List bytes;
  @override
  String toString() => 'UserAccountHttpReply';
}

final class _SafeFailure implements Exception {
  const _SafeFailure(this.reason);
  final UserAccountAuthenticationFailure reason;
  @override
  String toString() => 'UserAccountAuthenticationFailure(${reason.name})';
}

bool _matches(RegExp pattern, String value) =>
    pattern.firstMatch(value)?.group(0) == value;
ArgumentError _invalidProfile() =>
    ArgumentError('Invalid authentication profile');
void _observe(Future<void> future) {
  unawaited(future.then<void>((_) {}, onError: (Object _) {}));
}
