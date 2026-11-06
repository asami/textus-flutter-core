import 'dart:async';

import '../authentication/user_account_authentication.dart';
import '../authentication/user_account_http_authentication_backend.dart';
import 'submission_authentication.dart';
import 'submission_configuration.dart';
import 'submission_connections.dart';
import 'submission_run_lifetime.dart';

/// Internal composition owner, without an account selector or credential cache.
final class SubmissionParticipantRuntime {
  SubmissionParticipantRuntime._({
    required this._lifetime,
    required this.requiresAuthentication,
    required this._legacyCredentials,
    required Map<String, HttpSubmissionConnection> targets,
    UserAccountSubmissionScope? authenticationScope,
  }) : _targets = Map.unmodifiable(targets),
       _scope = authenticationScope;

  final SubmissionRunLifetime _lifetime;
  final SubmissionCredentialProvider _legacyCredentials;
  final Map<String, HttpSubmissionConnection> _targets;
  UserAccountSubmissionScope? _scope;
  UserAccountHttpAuthenticationBackend? _ownedBackend;
  UserAccountAuthenticationClient? _ownedClient;
  bool _closed = false;
  Future<void>? _closeFuture;

  /// Explicit local policy or a configured participant declaration requires auth.
  final bool requiresAuthentication;

  SubmissionAuthenticationContext? get authenticationContext => _scope?.context;
  SubmissionAuthenticationBinding? get binding => _scope?.binding;
  SubmissionCredentialProvider get credentials => requiresAuthentication
      ? _scope ?? const _DenyingParticipantCredentials()
      : _legacyCredentials;

  bool get isCurrent =>
      !_closed &&
      _lifetime.isCurrent &&
      (!requiresAuthentication || (_scope?.context.isCurrent ?? false));

  /// Checks the complete operator definition, without probing a credential port.
  bool permits(HttpSubmissionConnection connection) {
    final target = _targets[connection.id];
    return target != null &&
        target.endpoint == connection.endpoint &&
        target.requiresBearerToken == connection.requiresBearerToken;
  }

  /// Opens inertly unless owned restoration is explicitly requested and declared.
  /// A borrowed scope is retained exactly, without invoking its current callback.
  static Future<SubmissionParticipantRuntime> open({
    required SubmissionConfigurationSnapshot snapshot,
    required SubmissionCredentialProvider legacyCredentials,
    required SubmissionRunLifetime lifetime,
    UserAccountSubmissionScope? authenticationScope,
    bool restoreParticipantAuthentication = false,
    bool requiresAuthentication = false,
  }) async {
    SubmissionParticipantRuntime? runtime;
    try {
      if (!lifetime.isCurrent) throw _unavailable();
      final declaration = snapshot.participantAuthentication;
      if (declaration == null && authenticationScope != null) {
        throw _unavailable();
      }
      if (declaration != null && authenticationScope != null) {
        final binding = authenticationScope.binding;
        if (binding.authorityProfileId != declaration.authorityProfileId ||
            binding.authorityBaseUri != declaration.authorityBaseUri) {
          throw _unavailable();
        }
      }
      final authenticationRequired =
          requiresAuthentication || declaration != null;
      final targets = <String, HttpSubmissionConnection>{};
      if (declaration != null) {
        for (final id in declaration.trustedConnectionIds) {
          // The snapshot validates membership. Never silently drop an unknown id.
          targets[id] = snapshot.httpConnections.singleWhere(
            (connection) => connection.id == id,
          );
        }
      } else if (!authenticationRequired) {
        for (final connection in snapshot.httpConnections) {
          targets[connection.id] = connection;
        }
      }
      final owner = runtime = SubmissionParticipantRuntime._(
        lifetime: lifetime,
        requiresAuthentication: authenticationRequired,
        legacyCredentials: legacyCredentials,
        targets: targets,
        authenticationScope: authenticationScope,
      );
      unawaited(lifetime.cancelled.then<void>((_) => unawaited(owner.close())));
      if (declaration == null ||
          authenticationScope != null ||
          !restoreParticipantAuthentication) {
        return owner;
      }

      // Capture every acquired owner before the first restoration await.
      final backend = owner._ownedBackend =
          UserAccountHttpAuthenticationBackend(profile: declaration.authority);
      final client = owner._ownedClient = UserAccountAuthenticationClient(
        backend: backend,
        ownsBackend: true,
      );
      await client.restore();
      if (owner._closed || !lifetime.isCurrent) throw _unavailable();
      if (client.snapshot.lastLogoutResult?.localCleared == false) {
        throw _unavailable();
      }
      if (client.snapshot.isAuthenticated) {
        owner._scope = backend.createSubmissionScope(
          trustedTargets: targets.values,
          isRunCurrent: () => !owner._closed && lifetime.isCurrent,
        );
      }
      if (owner._closed || !lifetime.isCurrent) throw _unavailable();
      return owner;
    } catch (_) {
      try {
        await runtime?.close();
      } catch (_) {
        // The public failure remains fixed even when owned cleanup also fails.
      }
      throw _unavailable();
    }
  }

  /// Retires synchronously and joins only authentication acquired by this owner.
  /// Borrowed scope, backend and legacy credentials are never closed or erased.
  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;
    final completion = Completer<void>();
    _closeFuture = completion.future;
    _closed = true;
    unawaited(completion.future.then<void>((_) {}, onError: (Object _) {}));
    Future<void> finish() async {
      try {
        if (_ownedClient != null) {
          await _ownedClient!.close();
        } else if (_ownedBackend != null) {
          // Covers partial client acquisition without closing a borrowed backend.
          await _ownedBackend!.close();
        }
        completion.complete();
      } catch (_) {
        completion.completeError(_unavailable());
      }
    }

    unawaited(finish());
    return completion.future;
  }

  static StateError _unavailable() =>
      StateError('Participant submission authentication is unavailable');

  @override
  String toString() => 'SubmissionParticipantRuntime';
}

final class _DenyingParticipantCredentials
    implements AuthenticatedSubmissionCredentialProvider {
  const _DenyingParticipantCredentials();

  @override
  Future<String?> bearerToken(String connectionId) => Future.value(null);

  @override
  Future<String?> bearerTokenFor({
    required SubmissionAuthenticationBinding binding,
    required HttpSubmissionConnection connection,
  }) => Future.value(null);
}
