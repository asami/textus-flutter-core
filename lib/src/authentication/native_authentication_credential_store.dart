import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

final _profilePattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');
final _revisionPattern = RegExp(r'^[0-9a-f]{32}$');

bool _exactMatch(RegExp pattern, String value) =>
    pattern.firstMatch(value)?.group(0) == value;

void _profile(String value) {
  if (!_exactMatch(_profilePattern, value)) {
    throw ArgumentError('Invalid credential profile');
  }
}

void _revision(String value) {
  if (!_exactMatch(_revisionPattern, value)) {
    throw ArgumentError('Invalid credential revision');
  }
}

void _value(Uint8List value) {
  if (value.isEmpty || value.length > 65536) {
    throw ArgumentError('Invalid credential value');
  }
}

/// Internal storage failures contain only a closed safe category.
enum NativeAuthenticationCredentialStoreErrorCode {
  closed,
  unavailable,
  invalidResponse,
}

final class NativeAuthenticationCredentialStoreException implements Exception {
  const NativeAuthenticationCredentialStoreException(this.code);

  final NativeAuthenticationCredentialStoreErrorCode code;

  @override
  String toString() =>
      'NativeAuthenticationCredentialStoreException(${code.name})';
}

/// An opaque storage snapshot, unrelated to account/session authority.
final class NativeAuthenticationCredentialEntry {
  NativeAuthenticationCredentialEntry({
    required this.revision,
    required Uint8List value,
  }) : _bytes = _copy(revision, value);

  final String revision;
  final Uint8List _bytes;
  Uint8List get value => Uint8List.fromList(_bytes);

  static Uint8List _copy(String revision, Uint8List value) {
    _revision(revision);
    _value(value);
    return Uint8List.fromList(value);
  }

  @override
  String toString() => 'NativeAuthenticationCredentialEntry';
}

/// Internal mobile storage only: no login, codec, restore, network or issuer.
/// Construction generates a local handle and performs no channel/storage IO.
final class NativeAuthenticationCredentialStore {
  NativeAuthenticationCredentialStore({MethodChannel? channel})
    : _channel =
          channel ??
          const MethodChannel(
            'org.textus.flutter.core/authentication_credentials',
          ),
      _handleId = _newHandle();

  final MethodChannel _channel;
  final String _handleId;
  final Set<Future<bool>> _accepted = {};
  bool _closed = false;
  Future<void>? _closing;

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static String _newHandle() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  static Never _fail(NativeAuthenticationCredentialStoreErrorCode code) =>
      throw NativeAuthenticationCredentialStoreException(code);

  void _requireOpen() {
    if (_closed) _fail(NativeAuthenticationCredentialStoreErrorCode.closed);
    if (!isSupported) {
      _fail(NativeAuthenticationCredentialStoreErrorCode.unavailable);
    }
  }

  Future<NativeAuthenticationCredentialEntry?> read(String profileId) {
    _requireOpen();
    _profile(profileId);
    return _dispatch('read', {'profileId': profileId}, (reply) {
      if (reply == null) return null;
      if (reply is! Map ||
          reply.length != 2 ||
          !reply.containsKey('revision') ||
          !reply.containsKey('value')) {
        _fail(NativeAuthenticationCredentialStoreErrorCode.invalidResponse);
      }
      final revision = reply['revision'];
      final value = reply['value'];
      if (revision is! String ||
          !_exactMatch(_revisionPattern, revision) ||
          value is! Uint8List ||
          value.isEmpty ||
          value.length > 65536) {
        _fail(NativeAuthenticationCredentialStoreErrorCode.invalidResponse);
      }
      return NativeAuthenticationCredentialEntry(
        revision: revision,
        value: value,
      );
    });
  }

  Future<String?> replace({
    required String profileId,
    required String? expectedRevision,
    required Uint8List value,
  }) {
    _requireOpen();
    _profile(profileId);
    if (expectedRevision != null) _revision(expectedRevision);
    _value(value);
    final ownedValue = Uint8List.fromList(value);
    return _dispatch(
      'replace',
      {
        'profileId': profileId,
        'expectedRevision': expectedRevision,
        'value': ownedValue,
      },
      (reply) {
        if (reply == null) return null;
        if (reply is! String || !_exactMatch(_revisionPattern, reply)) {
          _fail(NativeAuthenticationCredentialStoreErrorCode.invalidResponse);
        }
        return reply;
      },
    );
  }

  Future<bool> remove({
    required String profileId,
    required String expectedRevision,
  }) {
    _requireOpen();
    _profile(profileId);
    _revision(expectedRevision);
    return _dispatch(
      'remove',
      {'profileId': profileId, 'expectedRevision': expectedRevision},
      (reply) {
        if (reply is! bool) {
          _fail(NativeAuthenticationCredentialStoreErrorCode.invalidResponse);
        }
        return reply;
      },
    );
  }

  Future<void> clear(String profileId) {
    _requireOpen();
    _profile(profileId);
    return _dispatch<void>('clear', {'profileId': profileId}, _emptyReply);
  }

  static void _emptyReply(Object? reply) {
    if (reply != null) {
      _fail(NativeAuthenticationCredentialStoreErrorCode.invalidResponse);
    }
  }

  Future<Object?> _invoke(String method, Map<String, Object?> arguments) async {
    try {
      return await _channel.invokeMethod<Object?>(method, arguments);
    } on PlatformException catch (error) {
      final code = switch (error.code) {
        'credentialStoreClosed' =>
          NativeAuthenticationCredentialStoreErrorCode.closed,
        'credentialStoreInvalidArguments' =>
          NativeAuthenticationCredentialStoreErrorCode.invalidResponse,
        _ => NativeAuthenticationCredentialStoreErrorCode.unavailable,
      };
      _fail(code);
    } catch (_) {
      _fail(NativeAuthenticationCredentialStoreErrorCode.unavailable);
    }
  }

  Future<T> _dispatch<T>(
    String method,
    Map<String, Object?> arguments,
    T Function(Object?) decode,
  ) {
    final result = Completer<T>();
    final drained = Completer<bool>();
    final drain = drained.future;
    _accepted.add(drain);
    // Observe the returned future even if its caller retires or abandons it.
    result.future.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _invoke(method, {'handleId': _handleId, ...arguments}).then<void>(
      (reply) {
        try {
          final decoded = decode(reply);
          if (_closed) {
            _fail(NativeAuthenticationCredentialStoreErrorCode.closed);
          }
          result.complete(decoded);
          drained.complete(true);
        } catch (error) {
          result.completeError(
            _closed
                ? const NativeAuthenticationCredentialStoreException(
                    NativeAuthenticationCredentialStoreErrorCode.closed,
                  )
                : error,
          );
          // Withdrawal of a valid late result is normal retirement, not IO failure.
          drained.complete(
            error is NativeAuthenticationCredentialStoreException &&
                error.code ==
                    NativeAuthenticationCredentialStoreErrorCode.closed,
          );
        } finally {
          _accepted.remove(drain);
        }
      },
      onError: (Object error, StackTrace _) {
        result.completeError(
          _closed
              ? const NativeAuthenticationCredentialStoreException(
                  NativeAuthenticationCredentialStoreErrorCode.closed,
                )
              : error,
        );
        drained.complete(false);
        _accepted.remove(drain);
      },
    );
    return result.future;
  }

  /// Retires immediately and drains every accepted call. Persistent records stay.
  /// An already-issued native write can finish; close is never rollback/logout.
  Future<void> close() {
    if (_closing case final closing?) return closing;
    _closed = true;
    final completion = Completer<void>();
    _closing = completion.future;
    completion.future.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    if (!isSupported) {
      completion.complete();
      return completion.future;
    }
    final pending = List<Future<bool>>.of(_accepted);
    // Dispatch native retirement now, before waiting for accepted work.
    final nativeClose = _invoke('close', {'handleId': _handleId}).then<bool>((
      reply,
    ) {
      try {
        _emptyReply(reply);
        return true;
      } catch (_) {
        return false;
      }
    }, onError: (Object _, StackTrace _) => false);
    Future.wait<bool>([nativeClose, ...pending]).then<void>((outcomes) {
      if (outcomes.every((ok) => ok)) {
        completion.complete();
      } else {
        completion.completeError(
          const NativeAuthenticationCredentialStoreException(
            NativeAuthenticationCredentialStoreErrorCode.unavailable,
          ),
        );
      }
    });
    return completion.future;
  }
}
