import 'dart:async';

import 'package:flutter/foundation.dart';

/// An authoritative account projection, without credentials or session IDs.
final class AuthenticatedUserAccount {
  AuthenticatedUserAccount({required String userAccountId, this.displayName})
    : userAccountId = _nonblankAccountId(userAccountId);

  /// Opaque, exact identity supplied by the account authority.
  final String userAccountId;
  final String? displayName;
}

enum UserAccountAuthenticationStatus {
  unavailable,
  signedOut,
  signingIn,
  challengeRequired,
  authenticated,
  refreshing,
  cancelling,
  signingOut,
  failure,
  closed,
}

/// Safe client categories; these do not prescribe HTTP status mappings.
enum UserAccountAuthenticationFailure {
  notConfigured,
  invalidCredentials,
  authorizationRequired,
  challengeRejected,
  serviceUnavailable,
  transportUnavailable,
  invalidResponse,
  cancelled,
}

enum UserAccountRemoteRevocation { confirmed, failed, notAttempted, unknown }

/// Local clearance and remote revocation are independent facts.
final class UserAccountLogoutResult {
  const UserAccountLogoutResult({
    required this.localCleared,
    required this.remoteRevocation,
  });

  final bool localCleared;
  final UserAccountRemoteRevocation remoteRevocation;
}

/// Presentation evidence only; this snapshot does not authorize server work.
final class UserAccountAuthenticationSnapshot {
  const UserAccountAuthenticationSnapshot({
    required this.status,
    required this.revision,
    this.account,
    this.challengeChannel,
    this.failure,
    this.lastLogoutResult,
  });

  final UserAccountAuthenticationStatus status;
  final AuthenticatedUserAccount? account;
  final String? challengeChannel;
  final UserAccountAuthenticationFailure? failure;
  final UserAccountLogoutResult? lastLogoutResult;
  final int revision;

  bool get isAuthenticated =>
      status == UserAccountAuthenticationStatus.authenticated &&
      account != null;

  @override
  String toString() =>
      'UserAccountAuthenticationSnapshot(status: ${status.name}, '
      'revision: $revision)';
}

/// A client-owned lifetime. Backends may observe, but cannot retire or renew it.
final class UserAccountAuthenticationOperation {
  UserAccountAuthenticationOperation._();

  final Completer<void> _cancelled = Completer<void>();
  bool _current = true;

  bool get isCurrent => _current;
  Future<void> get cancelled => _cancelled.future;

  void _retire() {
    if (!_current) return;
    _current = false;
    _cancelled.complete();
  }
}

/// Normalized backend outcomes, independent of any HTTP wire representation.
sealed class UserAccountSignInResult {
  const UserAccountSignInResult();
}

final class UserAccountSignedIn extends UserAccountSignInResult {
  const UserAccountSignedIn(this.account);

  final AuthenticatedUserAccount account;
}

/// The opaque reference is private to the backend and Core client.
final class UserAccountChallengePending extends UserAccountSignInResult {
  const UserAccountChallengePending(this.challengeId, this.channel);

  final String challengeId;
  final String channel;
}

final class UserAccountSignInRejected extends UserAccountSignInResult {
  const UserAccountSignInRejected(this.reason);

  final UserAccountAuthenticationFailure reason;
}

/// Authority communication and protected credential storage owned by Core.
///
/// Implementations must honor retirement before persisting or publishing
/// credentials, drain cancellation in bounded time, normalize authority results,
/// and never issue a substitute application session. App/Framework consumers
/// must not implement a credential verifier or token issuer as this port.
/// [close] releases handles without logging out or deleting retained user work.
abstract interface class UserAccountAuthenticationBackend {
  Future<UserAccountSignInResult> signIn({
    required String identifier,
    required String password,
    required UserAccountAuthenticationOperation operation,
  });

  Future<UserAccountSignInResult> verifyChallenge({
    required String challengeId,
    required String code,
    required UserAccountAuthenticationOperation operation,
  });

  Future<UserAccountSignInResult> refresh({
    required UserAccountAuthenticationOperation operation,
  });

  Future<UserAccountLogoutResult> signOut({
    required UserAccountAuthenticationOperation operation,
  });

  Future<void> close();
}

/// Safe observable authentication state with serialized, cancellable actions.
///
/// Construction performs no IO. No credential inputs are retained as fields.
/// Real HTTP, native protected storage and authenticated submission adapters
/// remain separate required integrations of [UserAccountAuthenticationBackend].
final class UserAccountAuthenticationClient extends ChangeNotifier {
  UserAccountAuthenticationClient({
    required UserAccountAuthenticationBackend backend,
    this.ownsBackend = false,
    // Preserve the public backend argument while storing it privately.
    // ignore: prefer_initializing_formals
  }) : _backend = backend,
       _snapshot = const UserAccountAuthenticationSnapshot(
         status: UserAccountAuthenticationStatus.signedOut,
         revision: 0,
       );

  UserAccountAuthenticationClient.unavailable()
    : _backend = null,
      ownsBackend = false,
      _snapshot = const UserAccountAuthenticationSnapshot(
        status: UserAccountAuthenticationStatus.unavailable,
        failure: UserAccountAuthenticationFailure.notConfigured,
        revision: 0,
      );

  final UserAccountAuthenticationBackend? _backend;
  final bool ownsBackend;
  UserAccountAuthenticationSnapshot _snapshot;
  _PendingAction? _active;
  String? _challengeId;
  Future<void>? _closeFuture;
  bool _disposeRequested = false;
  bool _notifierDisposed = false;
  int _notificationDepth = 0;

  UserAccountAuthenticationSnapshot get snapshot => _snapshot;
  bool get busy => _active != null && !isClosed;
  bool get isClosed =>
      _snapshot.status == UserAccountAuthenticationStatus.closed;

  Future<void> signIn({
    required String identifier,
    required String password,
  }) async {
    _requireIdle();
    if (_snapshot.status != UserAccountAuthenticationStatus.signedOut &&
        _snapshot.status != UserAccountAuthenticationStatus.failure) {
      throw _invalidCommand();
    }
    if (identifier.trim().isEmpty || password.isEmpty) {
      throw ArgumentError('Invalid authentication input');
    }
    final action = _reserve(_ActionKind.authentication);
    _challengeId = null;
    _publish(UserAccountAuthenticationStatus.signingIn);
    await _authenticate(
      action,
      () => _backend!.signIn(
        identifier: identifier,
        password: password,
        operation: action.operation,
      ),
    );
  }

  Future<void> verifyChallenge(String code) async {
    _requireIdle();
    final challengeId = _challengeId;
    if (_snapshot.status != UserAccountAuthenticationStatus.challengeRequired ||
        challengeId == null) {
      throw _invalidCommand();
    }
    if (code.trim().isEmpty) {
      throw ArgumentError('Invalid authentication input');
    }
    final action = _reserve(_ActionKind.authentication);
    _challengeId = null;
    _publish(UserAccountAuthenticationStatus.signingIn);
    await _authenticate(
      action,
      () => _backend!.verifyChallenge(
        challengeId: challengeId,
        code: code,
        operation: action.operation,
      ),
    );
  }

  Future<void> refresh() async {
    _requireIdle();
    final account = _snapshot.account;
    if (!_snapshot.isAuthenticated || account == null) {
      throw _invalidCommand();
    }
    final action = _reserve(_ActionKind.authentication);
    _publish(UserAccountAuthenticationStatus.refreshing);
    await _authenticate(
      action,
      () => _backend!.refresh(operation: action.operation),
      expectedAccountId: account.userAccountId,
    );
  }

  Future<void> _authenticate(
    _PendingAction action,
    Future<UserAccountSignInResult> Function() invoke, {
    String? expectedAccountId,
  }) async {
    try {
      // A listener may already have cancelled, logged out or closed the client.
      if (!_isCurrent(action)) return;
      final result = await invoke();
      if (!_isCurrent(action)) return;
      switch (result) {
        case UserAccountSignedIn(:final account):
          if (expectedAccountId != null &&
              account.userAccountId != expectedAccountId) {
            _fail(UserAccountAuthenticationFailure.invalidResponse);
          } else {
            _challengeId = null;
            _publish(
              UserAccountAuthenticationStatus.authenticated,
              account: account,
            );
          }
        case UserAccountChallengePending(:final challengeId, :final channel):
          if (expectedAccountId != null ||
              challengeId.trim().isEmpty ||
              channel != 'email') {
            _fail(UserAccountAuthenticationFailure.invalidResponse);
          } else {
            _challengeId = challengeId;
            _publish(
              UserAccountAuthenticationStatus.challengeRequired,
              challengeChannel: channel,
            );
          }
        case UserAccountSignInRejected(:final reason):
          _fail(reason);
      }
    } catch (_) {
      if (_isCurrent(action)) {
        _fail(UserAccountAuthenticationFailure.serviceUnavailable);
      }
    } finally {
      _finish(action);
    }
  }

  /// Retires accepted authentication work and waits for its backend to drain.
  Future<void> cancel() async {
    _requireConfigured();
    final previous = _active;
    if (previous?.kind != _ActionKind.authentication &&
        !(previous == null &&
            _snapshot.status ==
                UserAccountAuthenticationStatus.challengeRequired)) {
      throw _invalidCommand();
    }
    final action = _reserve(_ActionKind.cancelling);
    previous?.operation._retire();
    _challengeId = null;
    _publish(
      UserAccountAuthenticationStatus.cancelling,
      failure: UserAccountAuthenticationFailure.cancelled,
    );
    try {
      if (previous != null) await previous.done.future;
      if (_isCurrent(action)) {
        _publish(
          UserAccountAuthenticationStatus.signedOut,
          failure: UserAccountAuthenticationFailure.cancelled,
        );
      }
    } finally {
      _finish(action);
    }
  }

  /// Withdraws local presentation immediately and reports both logout facts.
  Future<UserAccountLogoutResult> signOut() async {
    _requireConfigured();
    final previous = _active;
    if (previous != null && previous.kind != _ActionKind.authentication) {
      throw _invalidCommand();
    }
    final action = _reserve(_ActionKind.signingOut);
    previous?.operation._retire();
    _challengeId = null;
    _publish(UserAccountAuthenticationStatus.signingOut);
    var result = _unknownLogout;
    try {
      if (previous != null) await previous.done.future;
      if (!_isCurrent(action)) return result;
      result = await _backend!.signOut(operation: action.operation);
      if (_isCurrent(action)) {
        _publish(
          result.localCleared
              ? UserAccountAuthenticationStatus.signedOut
              : UserAccountAuthenticationStatus.failure,
          failure: result.localCleared
              ? null
              : UserAccountAuthenticationFailure.serviceUnavailable,
          lastLogoutResult: result,
        );
      }
    } catch (_) {
      result = _unknownLogout;
      if (_isCurrent(action)) {
        _publish(
          UserAccountAuthenticationStatus.failure,
          failure: UserAccountAuthenticationFailure.serviceUnavailable,
          lastLogoutResult: result,
        );
      }
    } finally {
      _finish(action);
    }
    return result;
  }

  /// Retires synchronously, drains accepted work and closes an owned backend.
  Future<void> close() => _beginClose(notify: true);

  Future<void> _beginClose({required bool notify}) {
    final existing = _closeFuture;
    if (existing != null) return existing;
    final completion = Completer<void>();
    _closeFuture = completion.future;
    // Observe errors for disposal/fire-and-forget callers without changing the
    // safe error delivered to a caller explicitly awaiting close().
    unawaited(completion.future.then<void>((_) {}, onError: (Object _) {}));
    final previous = _active;
    previous?.operation._retire();
    _challengeId = null;
    _publish(UserAccountAuthenticationStatus.closed, notify: notify);
    unawaited(_drainAndClose(previous, completion));
    return completion.future;
  }

  Future<void> _drainAndClose(
    _PendingAction? previous,
    Completer<void> completion,
  ) async {
    try {
      if (previous != null) await previous.done.future;
      if (ownsBackend) await _backend!.close();
      completion.complete();
    } catch (_) {
      completion.completeError(StateError('Authentication close failed'));
    }
  }

  // _disposeNotifierWhenIdle calls super.dispose exactly once after active
  // notifyListeners calls finish, including disposal requested by a listener.
  @override
  // ignore: must_call_super
  void dispose() {
    if (_disposeRequested) return;
    _disposeRequested = true;
    unawaited(_beginClose(notify: false));
    _disposeNotifierWhenIdle();
  }

  void _disposeNotifierWhenIdle() {
    if (_disposeRequested && !_notifierDisposed && _notificationDepth == 0) {
      _notifierDisposed = true;
      super.dispose();
    }
  }

  void _requireConfigured() {
    if (isClosed || _backend == null) throw _invalidCommand();
  }

  void _requireIdle() {
    _requireConfigured();
    if (_active != null) throw _invalidCommand();
  }

  _PendingAction _reserve(_ActionKind kind) {
    final action = _PendingAction(kind);
    _active = action;
    return action;
  }

  bool _isCurrent(_PendingAction action) =>
      !isClosed && identical(_active, action) && action.operation.isCurrent;

  void _finish(_PendingAction action) {
    action.operation._retire();
    final wasActive = identical(_active, action);
    if (wasActive) _active = null;
    action.done.complete();
    if (wasActive && !isClosed) {
      _publish(
        _snapshot.status,
        account: _snapshot.account,
        challengeChannel: _snapshot.challengeChannel,
        failure: _snapshot.failure,
        lastLogoutResult: _snapshot.lastLogoutResult,
      );
    }
  }

  void _fail(UserAccountAuthenticationFailure failure) {
    _challengeId = null;
    _publish(UserAccountAuthenticationStatus.failure, failure: failure);
  }

  void _publish(
    UserAccountAuthenticationStatus status, {
    AuthenticatedUserAccount? account,
    String? challengeChannel,
    UserAccountAuthenticationFailure? failure,
    UserAccountLogoutResult? lastLogoutResult,
    bool notify = true,
  }) {
    _snapshot = UserAccountAuthenticationSnapshot(
      status: status,
      account: account,
      challengeChannel: challengeChannel,
      failure: failure,
      lastLogoutResult: lastLogoutResult ?? _snapshot.lastLogoutResult,
      revision: _snapshot.revision + 1,
    );
    if (!notify || _disposeRequested || _notifierDisposed) return;
    _notificationDepth++;
    try {
      notifyListeners();
    } finally {
      _notificationDepth--;
      _disposeNotifierWhenIdle();
    }
  }
}

enum _ActionKind { authentication, cancelling, signingOut }

final class _PendingAction {
  _PendingAction(this.kind);

  final _ActionKind kind;
  final UserAccountAuthenticationOperation operation =
      UserAccountAuthenticationOperation._();
  final Completer<void> done = Completer<void>();
}

const _unknownLogout = UserAccountLogoutResult(
  localCleared: false,
  remoteRevocation: UserAccountRemoteRevocation.unknown,
);

StateError _invalidCommand() =>
    StateError('Authentication command is not available');

String _nonblankAccountId(String value) {
  if (value.trim().isEmpty) throw ArgumentError('Invalid account identity');
  return value;
}
