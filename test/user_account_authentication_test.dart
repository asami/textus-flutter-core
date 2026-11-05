import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  group('backend-owned publication completion and explicit restore', () {
    test('persist precedes publication and accepted work survives retirement', () async {
      // Given a staged result whose persistence is externally controlled.
      final completion = _ControlledCommit();
      final backend = _ControlledBackend()..onSignIn = () =>
          UserAccountSignedIn(_signedIn().account, sessionCommit: completion);
      final client = UserAccountAuthenticationClient(backend: backend);
      final work = client.signIn(identifier: 'id', password: 'pw');
      await completion.started.future;
      // When protected persistence finishes for the still-current operation.
      expect(client.snapshot.isAuthenticated, isFalse);
      completion.persisted.complete();
      await work;
      // Then acceptance happens once before observers see the account.
      expect(completion.events, ['persist', 'accept']);
      expect(client.snapshot.isAuthenticated, isTrue);
      await client.close();
      expect(completion.events, ['persist', 'accept']);
    });

    test('late results are discarded before cancellation finishes', () async {
      // Given a backend response delayed until after cancellation.
      final result = Completer<UserAccountSignInResult>();
      final completion = _ControlledCommit()..holdDiscard = true;
      final backend = _ControlledBackend()..onSignIn = () => result.future;
      final client = UserAccountAuthenticationClient(backend: backend);
      final work = client.signIn(identifier: 'id', password: 'pw');
      final cancelling = client.cancel();
      // When a late staged success arrives, cleanup remains outstanding.
      result.complete(UserAccountSignedIn(
        _signedIn().account, sessionCommit: completion,
      ));
      await completion.discardStarted.future;
      await expectLater(client.signIn(identifier: 'next', password: 'pw'), throwsStateError);
      expect(client.busy, isTrue);
      completion.discarded.complete();
      await work;
      await cancelling;
      // Then cleanup drained before idle and persistence never began.
      expect(completion.events, ['discard']);
      expect(client.snapshot.status, UserAccountAuthenticationStatus.signedOut);
      await client.close();
    });

    test('mismatched refresh account is discarded before persistence', () async {
      // Given a signed-in client and a staged refresh for another account.
      final backend = _ControlledBackend();
      final client = await _authenticated(backend);
      final completion = _ControlledCommit();
      backend.onRefresh = () => UserAccountSignedIn(
        AuthenticatedUserAccount(userAccountId: 'different-account'),
        sessionCommit: completion,
      );
      // When refresh reaches the publication boundary.
      await client.refresh();
      // Then account ownership is rejected before any protected write.
      expect(completion.events, ['discard']);
      expect(client.snapshot.failure, UserAccountAuthenticationFailure.invalidResponse);
      await client.close();
    });

    for (final command in ['cancel', 'logout', 'close']) {
      test('authenticated publication listener handles $command safely', () async {
        // Given a completion already persisted and a synchronous publication listener.
        final completion = _ControlledCommit()..persisted.complete();
        final backend = _ControlledBackend()..onSignIn = () =>
            UserAccountSignedIn(_signedIn().account, sessionCommit: completion);
        final client = UserAccountAuthenticationClient(backend: backend);
        Future<Object?>? listenerWork;
        client.addListener(() {
          if (client.snapshot.isAuthenticated && listenerWork == null) {
            listenerWork = switch (command) {
              'cancel' => expectLater(client.cancel(), throwsStateError),
              'logout' => client.signOut(),
              _ => client.close(),
            };
          }
        });
        // When the accepted result publishes synchronously.
        await client.signIn(identifier: 'id', password: 'pw');
        await listenerWork;
        // Then cancellation cannot withdraw success; logout and close retain their meaning.
        expect(completion.events, ['persist', 'accept']);
        expect(client.snapshot.status, switch (command) {
          'cancel' => UserAccountAuthenticationStatus.authenticated,
          'logout' => UserAccountAuthenticationStatus.signedOut,
          _ => UserAccountAuthenticationStatus.closed,
        });
        await client.close();
      });
    }

    test('cleanup failure is observed and never publishes authentication', () async {
      // Given a persist failure followed by an unsuccessful candidate cleanup.
      final completion = _ControlledCommit()..failPersist = true..failDiscard = true;
      final backend = _RestorableBackend()..onSignIn = () =>
          UserAccountSignedIn(_signedIn().account, sessionCommit: completion);
      final client = UserAccountAuthenticationClient(backend: backend);
      // When the client handles that completion.
      await client.signIn(identifier: 'id', password: 'pw');
      // Then it fails closed with only a fixed safe category and drains cleanup.
      expect(completion.events, ['persist', 'discard']);
      expect(client.snapshot.failure, UserAccountAuthenticationFailure.serviceUnavailable);
      expect(client.snapshot.isAuthenticated, isFalse);
      expect(client.busy, isFalse);
      expect(client.snapshot.lastLogoutResult?.localCleared, isFalse);
      expect(client.snapshot.lastLogoutResult?.remoteRevocation,
          UserAccountRemoteRevocation.notAttempted);
      expect(client.canRestore, isFalse);
      // When a caller attempts to restore or sign in before explicit cleanup.
      await expectLater(client.restore(), throwsStateError);
      await expectLater(client.signIn(identifier: 'next', password: 'pw'), throwsStateError);
      // Then neither command reaches the backend or hides the cleanup failure.
      expect(backend.calls, ['signIn']);
      expect(backend.restores, 0);
      // When explicit logout successfully resolves the failed local cleanup.
      final cleanup = await client.signOut();
      // Then the client admits restoration again and ordinary close succeeds.
      expect(cleanup.localCleared, isTrue);
      expect(client.canRestore, isTrue);
      await client.close();
    });

    test('retired cleanup failure reaches cancellation without an unobserved join error', () async {
      // Given a late staged result with a failing discard and a restorable backend.
      final result = Completer<UserAccountSignInResult>();
      final completion = _ControlledCommit()..failDiscard = true;
      final backend = _RestorableBackend()..onSignIn = () => result.future;
      final client = UserAccountAuthenticationClient(backend: backend);
      addTearDown(() async {
        await expectLater(client.close(), _authenticationCloseFailure());
      });
      final work = client.signIn(identifier: 'id', password: 'pw');
      final statuses = <UserAccountAuthenticationStatus>[];
      client.addListener(() => statuses.add(client.snapshot.status));
      // When cancellation joins a late completion whose cleanup fails.
      final cancelling = expectLater(client.cancel(), _authenticationCleanupFailure());
      result.complete(UserAccountSignedIn(_signedIn().account, sessionCommit: completion));
      await work;
      await cancelling;
      // Then the origin drains normally, but the retiring caller receives a safe failure.
      expect(completion.events, ['discard']);
      expect(client.busy, isFalse);
      expect(client.snapshot.status, UserAccountAuthenticationStatus.failure);
      expect(client.snapshot.failure, UserAccountAuthenticationFailure.serviceUnavailable);
      expect(client.snapshot.account, isNull);
      expect(client.snapshot.lastLogoutResult?.localCleared, isFalse);
      expect(client.snapshot.lastLogoutResult?.remoteRevocation,
          UserAccountRemoteRevocation.notAttempted);
      expect(client.canRestore, isFalse);
      expect(statuses, isNot(contains(UserAccountAuthenticationStatus.signedOut)));
      expect('$client', isNot(contains('synthetic private cleanup failure')));
      // When direct authentication is requested again.
      await expectLater(client.signIn(identifier: 'next', password: 'pw'), throwsStateError);
      await expectLater(client.restore(), throwsStateError);
      // Then failed staged cleanup prevents any new backend IO.
      expect(backend.calls, ['signIn']);
      expect(backend.restores, 0);
    });

    for (final owned in [false, true]) {
      test('retired cleanup failure is joined by close with owned=$owned', () async {
        // Given persistence already accepted and a discard held until after close.
        final completion = _ControlledCommit()
          ..holdDiscard = true
          ..failDiscard = true;
        final backend = _ControlledBackend()..onSignIn = () =>
            UserAccountSignedIn(_signedIn().account, sessionCommit: completion);
        final client = UserAccountAuthenticationClient(backend: backend, ownsBackend: owned);
        addTearDown(() async {
          await expectLater(client.close(), _authenticationCloseFailure());
          if (!owned) await backend.close();
        });
        final work = client.signIn(identifier: 'id', password: 'pw');
        await completion.started.future;
        // When cancellation starts draining and close supersedes its presentation.
        final cancelling = expectLater(client.cancel(), _authenticationCleanupFailure());
        completion.persisted.complete();
        await completion.discardStarted.future;
        final closing = client.close();
        final failedClose = expectLater(closing, _authenticationCloseFailure());
        final closedRevision = client.snapshot.revision;
        var notifications = 0;
        client.addListener(() { notifications++; });
        completion.discarded.complete();
        await work;
        await cancelling;
        await failedClose;
        // Then both owners receive their fixed failures after all owned close work.
        expect(completion.events, ['persist', 'discard']);
        expect(backend.calls, owned ? ['signIn', 'close'] : ['signIn']);
        expect(client.snapshot.status, UserAccountAuthenticationStatus.closed);
        expect(client.snapshot.account, isNull);
        expect(client.snapshot.revision, closedRevision);
        expect(notifications, 0);
        expect(client.canRestore, isFalse);
        expect(client.close(), same(closing));
      });
    }

    for (final owned in [false, true]) {
      test('current cleanup failure remains observable on later idle close with owned=$owned', () async {
        // Given current authentication whose persistence and discard both fail.
        final completion = _ControlledCommit()..failPersist = true..failDiscard = true;
        final backend = _ControlledBackend()..onSignIn = () =>
            UserAccountSignedIn(_signedIn().account, sessionCommit: completion);
        final client = UserAccountAuthenticationClient(backend: backend, ownsBackend: owned);
        await client.signIn(identifier: 'id', password: 'pw');
        // When close runs after the failed action has already become idle.
        final closing = client.close();
        await expectLater(closing, _authenticationCloseFailure());
        // Then remembered cleanup failure is retained and only an owned backend closes.
        expect(client.snapshot.status, UserAccountAuthenticationStatus.closed);
        expect(client.snapshot.account, isNull);
        expect(backend.calls, owned ? ['signIn', 'close'] : ['signIn']);
        expect(client.close(), same(closing));
        if (!owned) await backend.close();
      });
    }

    for (final throwsCleanup in [false, true]) {
      test('logout joining cleanup failure retains barriers until successful retry throws=$throwsCleanup', () async {
        // Given a deferred staged login and an unsuccessful first explicit cleanup.
        final result = Completer<UserAccountSignInResult>();
        final completion = _ControlledCommit()..failDiscard = true;
        final backend = _RestorableBackend()
          ..onSignIn = (() => result.future)
          ..onSignOut = () {
            if (throwsCleanup) throw StateError('synthetic private logout failure');
            return const UserAccountLogoutResult(
              localCleared: false,
              remoteRevocation: UserAccountRemoteRevocation.notAttempted,
            );
          };
        final client = UserAccountAuthenticationClient(backend: backend);
        final work = client.signIn(identifier: 'id', password: 'pw');
        // When explicit logout joins the failed discard and still invokes backend cleanup.
        final loggingOut = client.signOut();
        result.complete(UserAccountSignedIn(_signedIn().account, sessionCommit: completion));
        await work;
        final failed = await loggingOut;
        // Then unsuccessful cleanup retains both admission barriers with safe logout facts.
        expect(backend.calls, ['signIn', 'signOut']);
        expect(failed.localCleared, isFalse);
        expect(failed.remoteRevocation, throwsCleanup
            ? UserAccountRemoteRevocation.unknown
            : UserAccountRemoteRevocation.notAttempted);
        expect(client.snapshot.status, UserAccountAuthenticationStatus.failure);
        expect(client.snapshot.account, isNull);
        expect(client.canRestore, isFalse);
        await expectLater(client.signIn(identifier: 'next', password: 'pw'), throwsStateError);
        await expectLater(client.restore(), throwsStateError);
        // Given a successful explicit local cleanup is now available.
        backend.onSignOut = () => const UserAccountLogoutResult(
          localCleared: true,
          remoteRevocation: UserAccountRemoteRevocation.notAttempted,
        );
        // When logout is explicitly retried.
        final retry = await client.signOut();
        // Then both barriers clear without reviving the discarded account.
        expect(retry.localCleared, isTrue);
        expect(client.snapshot.status, UserAccountAuthenticationStatus.signedOut);
        expect(client.snapshot.account, isNull);
        expect(client.canRestore, isTrue);
        backend.onSignIn = _signedIn;
        // When sign-in is explicitly requested after successful cleanup.
        await client.signIn(identifier: 'next', password: 'pw');
        // Then normal authentication admission and borrowed close remain compatible.
        expect(client.snapshot.isAuthenticated, isTrue);
        await client.close();
      });
    }

    test('only an explicit restorable idle port admits restoration', () async {
      // Given restorable, legacy and unavailable clients with inert constructors.
      final backend = _RestorableBackend();
      final client = UserAccountAuthenticationClient(backend: backend);
      final legacy = UserAccountAuthenticationClient(backend: _ControlledBackend());
      final unavailable = UserAccountAuthenticationClient.unavailable();
      expect(backend.restores, 0);
      expect(client.canRestore, isTrue);
      expect(legacy.canRestore, isFalse);
      expect(unavailable.canRestore, isFalse);
      // When explicit restoration reports no stored candidate.
      await client.restore();
      // Then null means ordinary signed-out only for this call.
      expect(backend.restores, 1);
      expect(client.snapshot.status, UserAccountAuthenticationStatus.signedOut);
      expect(client.snapshot.failure, isNull);
      await expectLater(legacy.restore(), throwsStateError);
      backend.result = _signedIn();
      await client.restore();
      expect(client.snapshot.isAuthenticated, isTrue);
      expect(client.canRestore, isFalse);
      backend.onSignOut = () => const UserAccountLogoutResult(
        localCleared: false, remoteRevocation: UserAccountRemoteRevocation.unknown,
      );
      await client.signOut();
      expect(client.canRestore, isFalse);
      await expectLater(client.restore(), throwsStateError);
      await client.close();
      await legacy.close();
      await unavailable.close();
    });
  });

  group('authentication construction and structural admission', () {
    test('should expose configured and unavailable states without IO', () async {
      // Given a backend and an explicitly unavailable client.
      final backend = _ControlledBackend();
      final client = UserAccountAuthenticationClient(backend: backend);
      final unavailable = UserAccountAuthenticationClient.unavailable();
      // When construction state is read and unavailable commands are attempted.
      expect(client.snapshot.status, UserAccountAuthenticationStatus.signedOut);
      expect(client.snapshot.revision, 0);
      expect(client.busy, isFalse);
      expect(
        unavailable.snapshot.status,
        UserAccountAuthenticationStatus.unavailable,
      );
      expect(
        unavailable.snapshot.failure,
        UserAccountAuthenticationFailure.notConfigured,
      );
      await expectLater(
        unavailable.signIn(identifier: 'id', password: 'pw'),
        throwsStateError,
      );
      await expectLater(unavailable.verifyChallenge('code'), throwsStateError);
      await expectLater(unavailable.refresh(), throwsStateError);
      await expectLater(unavailable.cancel(), throwsStateError);
      await expectLater(unavailable.signOut(), throwsStateError);
      // Then neither construction nor unsupported commands contact a backend.
      expect(client.snapshot.isAuthenticated, isFalse);
      expect(unavailable.snapshot.account, isNull);
      expect(backend.calls, isEmpty);
      await client.close();
      await unavailable.close();
    });

    test(
      'should reject invalid inputs and sequences before backend IO',
      () async {
        // Given an idle configured client and structural input variants.
        final backend = _ControlledBackend();
        final client = UserAccountAuthenticationClient(backend: backend);
        // When blank identifiers, empty passwords and out-of-order actions arrive.
        await expectLater(
          client.signIn(identifier: ' \n', password: 'pw'),
          throwsArgumentError,
        );
        await expectLater(
          client.signIn(identifier: 'id', password: ''),
          throwsArgumentError,
        );
        await expectLater(client.verifyChallenge('code'), throwsStateError);
        await expectLater(client.refresh(), throwsStateError);
        await expectLater(client.cancel(), throwsStateError);
        // Then no backend operation starts or revision changes.
        expect(backend.calls, isEmpty);
        expect(client.snapshot.revision, 0);
        expect(
          () => AuthenticatedUserAccount(userAccountId: ' \t'),
          throwsArgumentError,
        );
        await client.close();
        await expectLater(
          client.signIn(identifier: 'id', password: 'pw'),
          throwsStateError,
        );
        await expectLater(client.signOut(), throwsStateError);
        expect(backend.calls, isEmpty);
      },
    );
  });

  group('authoritative account and challenge sign-in', () {
    test('should preserve exact credentials and use the authoritative account', () async {
      // Given exact whitespace-bearing input and an unrelated account identity.
      final pending = Completer<UserAccountSignInResult>();
      final account = AuthenticatedUserAccount(
        userAccountId: ' urn:account:opaque ',
        displayName: ' Authority Name ',
      );
      final backend = _ControlledBackend()..onSignIn = () => pending.future;
      final client = UserAccountAuthenticationClient(backend: backend);
      final revisions = <int>[];
      client.addListener(() => revisions.add(client.snapshot.revision));
      // When sign-in is accepted and later resolves from the backend.
      final work = client.signIn(
        identifier: ' entered-id ',
        password: ' pw \n',
      );
      expect(client.snapshot.status, UserAccountAuthenticationStatus.signingIn);
      expect(client.snapshot.account, isNull);
      expect(client.busy, isTrue);
      expect(backend.identifier, ' entered-id ');
      expect(backend.password, ' pw \n');
      final operation = backend.operations.single;
      expect(operation.isCurrent, isTrue);
      pending.complete(UserAccountSignedIn(account));
      await work;
      // Then only the exact authoritative projection establishes authentication.
      expect(client.snapshot.isAuthenticated, isTrue);
      expect(client.snapshot.account, same(account));
      expect(client.snapshot.account!.userAccountId, ' urn:account:opaque ');
      expect(client.snapshot.account!.displayName, ' Authority Name ');
      expect(revisions, [1, 2, 3]);
      expect(client.busy, isFalse);
      expect(operation.isCurrent, isFalse);
      await operation.cancelled;
      await expectLater(
        client.signIn(identifier: 'other', password: 'other'),
        throwsStateError,
      );
      expect(backend.calls, ['signIn']);
      await client.close();
    });

    test('should keep a challenge private and complete its exact reference', () async {
      // Given an email challenge and an authoritative verification result.
      final backend = _ControlledBackend()
        ..onSignIn = () =>
            const UserAccountChallengePending(' ref: exact ', 'email');
      final client = UserAccountAuthenticationClient(backend: backend);
      await client.signIn(identifier: 'id', password: 'pw');
      final challengeSnapshot = client.snapshot;
      // When blank verification is refused and the exact supplied code is used.
      await expectLater(client.verifyChallenge(' \n'), throwsArgumentError);
      expect(backend.calls, ['signIn']);
      expect(client.snapshot, same(challengeSnapshot));
      await client.verifyChallenge(' 123 456 ');
      // Then challenge state is unauthenticated and only verification signs in.
      expect(
        challengeSnapshot.status,
        UserAccountAuthenticationStatus.challengeRequired,
      );
      expect(challengeSnapshot.isAuthenticated, isFalse);
      expect(challengeSnapshot.account, isNull);
      expect(challengeSnapshot.challengeChannel, 'email');
      expect(challengeSnapshot.toString(), isNot(contains('ref: exact')));
      expect(backend.challengeId, ' ref: exact ');
      expect(backend.code, ' 123 456 ');
      expect(backend.operations, hasLength(2));
      expect(backend.operations[0], isNot(same(backend.operations[1])));
      expect(client.snapshot.isAuthenticated, isTrue);
      expect(client.snapshot.challengeChannel, isNull);
      await client.close();
    });

    for (final challenge in const [
      UserAccountChallengePending(' ', 'email'),
      UserAccountChallengePending('reference', 'sms'),
      UserAccountChallengePending('reference', ' email '),
    ]) {
      test(
        'should reject malformed challenge ${challenge.channel}/${challenge.challengeId}',
        () async {
          // Given a backend-normalized result with an invalid reference or channel.
          final backend = _ControlledBackend()..onSignIn = () => challenge;
          final client = UserAccountAuthenticationClient(backend: backend);
          // When that result reaches the current sign-in operation.
          await client.signIn(identifier: 'id', password: 'pw');
          // Then it is a safe invalid response and cannot be verified or authenticated.
          expect(
            client.snapshot.failure,
            UserAccountAuthenticationFailure.invalidResponse,
          );
          expect(client.snapshot.account, isNull);
          expect(client.snapshot.challengeChannel, isNull);
          await expectLater(client.verifyChallenge('code'), throwsStateError);
          expect(backend.calls, ['signIn']);
          await client.close();
        },
      );
    }

    test('should reject a challenge without establishing an account', () async {
      // Given a pending challenge whose backend rejects verification.
      final backend = _ControlledBackend()
        ..onSignIn = (() =>
            const UserAccountChallengePending('reference', 'email'))
        ..onVerify = () => const UserAccountSignInRejected(
          UserAccountAuthenticationFailure.challengeRejected,
        );
      final client = UserAccountAuthenticationClient(backend: backend);
      await client.signIn(identifier: 'id', password: 'pw');
      // When the supplied challenge code is rejected.
      await client.verifyChallenge('wrong');
      // Then no challenge or account remains and another verification is refused.
      expect(
        client.snapshot.failure,
        UserAccountAuthenticationFailure.challengeRejected,
      );
      expect(client.snapshot.isAuthenticated, isFalse);
      expect(client.snapshot.challengeChannel, isNull);
      await expectLater(client.verifyChallenge('retry'), throwsStateError);
      await client.close();
    });

    test(
      'should sanitize rejections exceptions and invalid authoritative IDs',
      () async {
        // Given safe rejection followed by exceptions containing private data.
        final backend = _ControlledBackend()
          ..onSignIn = () => const UserAccountSignInRejected(
            UserAccountAuthenticationFailure.invalidCredentials,
          );
        final client = UserAccountAuthenticationClient(backend: backend);
        // When rejected sign-in is retried through throwing and malformed results.
        await client.signIn(
          identifier: 'private-id',
          password: 'private-password',
        );
        expect(
          client.snapshot.failure,
          UserAccountAuthenticationFailure.invalidCredentials,
        );
        backend.onSignIn = () => throw StateError('secret-backend-body');
        await client.signIn(
          identifier: 'private-id',
          password: 'private-password',
        );
        final sanitized = client.snapshot;
        backend.onSignIn = () =>
            UserAccountSignedIn(AuthenticatedUserAccount(userAccountId: ' '));
        await client.signIn(
          identifier: 'private-id',
          password: 'private-password',
        );
        // Then no exception or input leaks into snapshots or usable authentication.
        expect(
          sanitized.failure,
          UserAccountAuthenticationFailure.serviceUnavailable,
        );
        expect(sanitized.toString(), isNot(contains('secret-backend-body')));
        expect(sanitized.toString(), isNot(contains('private-id')));
        expect(sanitized.toString(), isNot(contains('private-password')));
        expect(client.snapshot.status, UserAccountAuthenticationStatus.failure);
        expect(client.snapshot.account, isNull);
        expect(client.snapshot.isAuthenticated, isFalse);
        await client.close();
      },
    );
  });

  group('terminal idle notification and reentrant admission', () {
    test('should notify idle challenge verification refresh and logout synchronously', () async {
      // Given deferred authority actions and a listener recording callback state.
      final signIn = Completer<UserAccountSignInResult>();
      final verification = Completer<UserAccountSignInResult>();
      final refresh = Completer<UserAccountSignInResult>();
      final logout = Completer<UserAccountLogoutResult>();
      final backend = _ControlledBackend();
      backend.onSignIn = () => signIn.future;
      backend.onVerify = () => verification.future;
      backend.onRefresh = () => refresh.future;
      backend.onSignOut = () => logout.future;
      final client = UserAccountAuthenticationClient(backend: backend);
      final observations = <(UserAccountAuthenticationSnapshot, bool)>[];
      client.addListener(() {
        observations.add((client.snapshot, client.busy));
      });
      // When direct sign-in completes with a private email challenge.
      final signingIn = client.signIn(identifier: 'id', password: 'pw');
      signIn.complete(
        const UserAccountChallengePending('private-reference', 'email'),
      );
      await signingIn;
      // Then the listener receives the safe challenge again after ownership is idle.
      expect(
        observations.map(
          (entry) => (entry.$1.status, entry.$2, entry.$1.revision),
        ),
        [
          (UserAccountAuthenticationStatus.signingIn, true, 1),
          (UserAccountAuthenticationStatus.challengeRequired, true, 2),
          (UserAccountAuthenticationStatus.challengeRequired, false, 3),
        ],
      );
      final challenge = observations.last.$1;
      expect(challenge.account, isNull);
      expect(challenge.challengeChannel, 'email');
      expect(challenge.toString(), isNot(contains('private-reference')));
      // When direct verification establishes the authoritative account.
      final verifying = client.verifyChallenge('code');
      final account = _signedIn().account;
      verification.complete(UserAccountSignedIn(account));
      await verifying;
      // Then synchronous observers see authenticated idle state and the exact account.
      expect(
        observations.last.$1.status,
        UserAccountAuthenticationStatus.authenticated,
      );
      expect(observations.last.$1.account, same(account));
      expect(observations.last.$1.challengeChannel, isNull);
      expect(observations.last.$2, isFalse);
      // When direct refresh supplies the same account with an updated label.
      final refreshing = client.refresh();
      final refreshed = AuthenticatedUserAccount(
        userAccountId: account.userAccountId,
        displayName: 'Refreshed authority',
      );
      refresh.complete(UserAccountSignedIn(refreshed));
      await refreshing;
      // Then the idle callback preserves the new authoritative projection.
      expect(observations.last.$1.account, same(refreshed));
      expect(observations.last.$2, isFalse);
      // When direct logout reports local clearance and failed remote revocation.
      final signingOut = client.signOut();
      const result = UserAccountLogoutResult(
        localCleared: true,
        remoteRevocation: UserAccountRemoteRevocation.failed,
      );
      logout.complete(result);
      await signingOut;
      // Then every completed action has an idle revision and logout facts stay exact.
      expect(
        observations.map(
          (entry) => (entry.$1.status, entry.$2, entry.$1.revision),
        ),
        [
          (UserAccountAuthenticationStatus.signingIn, true, 1),
          (UserAccountAuthenticationStatus.challengeRequired, true, 2),
          (UserAccountAuthenticationStatus.challengeRequired, false, 3),
          (UserAccountAuthenticationStatus.signingIn, true, 4),
          (UserAccountAuthenticationStatus.authenticated, true, 5),
          (UserAccountAuthenticationStatus.authenticated, false, 6),
          (UserAccountAuthenticationStatus.refreshing, true, 7),
          (UserAccountAuthenticationStatus.authenticated, true, 8),
          (UserAccountAuthenticationStatus.authenticated, false, 9),
          (UserAccountAuthenticationStatus.signingOut, true, 10),
          (UserAccountAuthenticationStatus.signedOut, true, 11),
          (UserAccountAuthenticationStatus.signedOut, false, 12),
        ],
      );
      expect(observations.last.$1.account, isNull);
      expect(observations.last.$1.challengeChannel, isNull);
      expect(observations.last.$1.lastLogoutResult, same(result));
      expect(backend.calls, [
        'signIn',
        'verifyChallenge',
        'refresh',
        'signOut',
      ]);
      await client.close();
    });

    test(
      'should notify safe idle failure after rejected direct sign-in',
      () async {
        // Given a deferred rejection and a listener capturing snapshot and busy state.
        final pending = Completer<UserAccountSignInResult>();
        final backend = _ControlledBackend()..onSignIn = () => pending.future;
        final client = UserAccountAuthenticationClient(backend: backend);
        final observations = <(UserAccountAuthenticationSnapshot, bool)>[];
        client.addListener(() {
          observations.add((client.snapshot, client.busy));
        });
        // When the backend rejects the direct credential attempt.
        final work = client.signIn(
          identifier: 'private-id',
          password: 'private-pw',
        );
        pending.complete(
          const UserAccountSignInRejected(
            UserAccountAuthenticationFailure.invalidCredentials,
          ),
        );
        await work;
        // Then callback-time failure is safe and the last revision is visibly idle.
        expect(
          observations.map(
            (entry) => (entry.$1.status, entry.$2, entry.$1.revision),
          ),
          [
            (UserAccountAuthenticationStatus.signingIn, true, 1),
            (UserAccountAuthenticationStatus.failure, true, 2),
            (UserAccountAuthenticationStatus.failure, false, 3),
          ],
        );
        final failure = observations.last.$1;
        expect(
          failure.failure,
          UserAccountAuthenticationFailure.invalidCredentials,
        );
        expect(failure.account, isNull);
        expect(failure.challengeChannel, isNull);
        expect(failure.toString(), isNot(contains('private-')));
        expect(backend.calls, ['signIn']);
        await client.close();
      },
    );

    test(
      'should notify idle cancellation only after retired work drains',
      () async {
        // Given deferred sign-in and a synchronous listener on the real client.
        final pending = Completer<UserAccountSignInResult>();
        final backend = _ControlledBackend()..onSignIn = () => pending.future;
        final client = UserAccountAuthenticationClient(backend: backend);
        final observations = <(UserAccountAuthenticationSnapshot, bool)>[];
        client.addListener(() {
          observations.add((client.snapshot, client.busy));
        });
        final work = client.signIn(identifier: 'id', password: 'pw');
        // When cancellation supersedes sign-in before its late success drains.
        final cancellation = client.cancel();
        expect(
          observations.last.$1.status,
          UserAccountAuthenticationStatus.cancelling,
        );
        expect(observations.last.$2, isTrue);
        expect(backend.operations.single.isCurrent, isFalse);
        pending.complete(_signedIn());
        await work;
        await cancellation;
        // Then no superseded success publishes and cancellation finally admits idle work.
        expect(
          observations.map(
            (entry) => (entry.$1.status, entry.$2, entry.$1.revision),
          ),
          [
            (UserAccountAuthenticationStatus.signingIn, true, 1),
            (UserAccountAuthenticationStatus.cancelling, true, 2),
            (UserAccountAuthenticationStatus.signedOut, true, 3),
            (UserAccountAuthenticationStatus.signedOut, false, 4),
          ],
        );
        expect(
          observations.last.$1.failure,
          UserAccountAuthenticationFailure.cancelled,
        );
        expect(observations.last.$1.account, isNull);
        expect(observations.last.$1.challengeChannel, isNull);
        expect(backend.calls, ['signIn']);
        await client.close();
      },
    );

    test(
      'should retain verification reserved reentrantly by the idle listener',
      () async {
        // Given deferred challenge and verification results with a one-shot listener.
        final signIn = Completer<UserAccountSignInResult>();
        final verification = Completer<UserAccountSignInResult>();
        final backend = _ControlledBackend();
        backend.onSignIn = () => signIn.future;
        backend.onVerify = () => verification.future;
        final client = UserAccountAuthenticationClient(backend: backend);
        Future<void>? verifying;
        var started = false;
        var starts = 0;
        client.addListener(() {
          if (!started &&
              !client.busy &&
              client.snapshot.status ==
                  UserAccountAuthenticationStatus.challengeRequired) {
            started = true;
            starts++;
            expect(backend.operations.single.isCurrent, isFalse);
            verifying = client.verifyChallenge('exact-code');
          }
        });
        // When final challenge publication synchronously reserves the next legitimate action.
        final signingIn = client.signIn(identifier: 'id', password: 'pw');
        signIn.complete(
          const UserAccountChallengePending('exact-reference', 'email'),
        );
        await signingIn;
        // Then old completion cannot clear new ownership or admit overlapping backend work.
        expect(starts, 1);
        expect(verifying, isNotNull);
        expect(client.busy, isTrue);
        expect(
          client.snapshot.status,
          UserAccountAuthenticationStatus.signingIn,
        );
        expect(backend.operations, hasLength(2));
        expect(backend.operations.last.isCurrent, isTrue);
        expect(backend.calls, ['signIn', 'verifyChallenge']);
        expect(backend.challengeId, 'exact-reference');
        expect(backend.code, 'exact-code');
        await expectLater(client.refresh(), throwsStateError);
        await expectLater(client.verifyChallenge('overlap'), throwsStateError);
        expect(backend.calls, ['signIn', 'verifyChallenge']);
        // When the reentrantly reserved verification completes.
        verification.complete(_signedIn());
        await verifying;
        // Then its own final idle publication preserves authoritative authentication.
        expect(client.snapshot.isAuthenticated, isTrue);
        expect(client.busy, isFalse);
        expect(backend.operations.last.isCurrent, isFalse);
        expect(starts, 1);
        await client.close();
      },
    );

    for (final dispose in [false, true]) {
      test(
        'should allow terminal idle listener cleanup with dispose=$dispose',
        () async {
          // Given an owned backend and a listener that closes only on final idle success.
          final pending = Completer<UserAccountSignInResult>();
          final backend = _ControlledBackend()..onSignIn = () => pending.future;
          final client = UserAccountAuthenticationClient(
            backend: backend,
            ownsBackend: true,
          );
          var idleNotifications = 0;
          var notifications = 0;
          client.addListener(() {
            notifications++;
            if (client.snapshot.isAuthenticated && !client.busy) {
              idleNotifications++;
              if (dispose) {
                client.dispose();
              } else {
                unawaited(client.close());
              }
            }
          });
          // When deferred sign-in reaches the idle callback and cleanup reenters it.
          final work = client.signIn(identifier: 'id', password: 'pw');
          pending.complete(_signedIn());
          await work;
          await client.close();
          // Then cleanup finishes once without waiting on old unfinished bookkeeping.
          expect(idleNotifications, 1);
          expect(notifications, dispose ? 3 : 4);
          expect(client.isClosed, isTrue);
          expect(client.busy, isFalse);
          expect(client.snapshot.account, isNull);
          expect(backend.calls, ['signIn', 'close']);
          client.dispose();
        },
      );
    }
  });

  group('same-account refresh and fail-closed refusal', () {
    test(
      'should withdraw presentation while refreshing the exact same account',
      () async {
        // Given an authenticated opaque account and a deferred refresh.
        final pending = Completer<UserAccountSignInResult>();
        final backend = _ControlledBackend()..onRefresh = () => pending.future;
        final client = await _authenticated(backend);
        // When refresh starts and later supplies the same exact ID with a new label.
        final work = client.refresh();
        expect(
          client.snapshot.status,
          UserAccountAuthenticationStatus.refreshing,
        );
        expect(client.snapshot.isAuthenticated, isFalse);
        expect(client.snapshot.account, isNull);
        pending.complete(
          UserAccountSignedIn(
            AuthenticatedUserAccount(
              userAccountId: 'account:1',
              displayName: 'Updated',
            ),
          ),
        );
        await work;
        // Then authoritative refresh restores only the same account.
        expect(client.snapshot.isAuthenticated, isTrue);
        expect(client.snapshot.account!.userAccountId, 'account:1');
        expect(client.snapshot.account!.displayName, 'Updated');
        expect(backend.calls, ['signIn', 'refresh']);
        await client.close();
      },
    );

    for (final result in <UserAccountSignInResult>[
      UserAccountSignedIn(AuthenticatedUserAccount(userAccountId: 'account:2')),
      UserAccountSignedIn(
        AuthenticatedUserAccount(userAccountId: ' account:1 '),
      ),
      const UserAccountChallengePending('refresh-challenge', 'email'),
      const UserAccountSignInRejected(
        UserAccountAuthenticationFailure.authorizationRequired,
      ),
    ]) {
      test(
        'should fail closed for refresh ${result.runtimeType} ${result is UserAccountSignedIn ? result.account.userAccountId : ''}',
        () async {
          // Given an authenticated client and a switch, challenge or refusal result.
          final backend = _ControlledBackend()..onRefresh = () => result;
          final client = await _authenticated(backend);
          // When refresh receives the incompatible or rejected authority outcome.
          await client.refresh();
          // Then the account is withdrawn and refresh requires a fresh sign-in.
          expect(
            client.snapshot.status,
            UserAccountAuthenticationStatus.failure,
          );
          expect(client.snapshot.account, isNull);
          expect(client.snapshot.challengeChannel, isNull);
          expect(
            client.snapshot.failure,
            result is UserAccountSignInRejected
                ? UserAccountAuthenticationFailure.authorizationRequired
                : UserAccountAuthenticationFailure.invalidResponse,
          );
          await expectLater(client.refresh(), throwsStateError);
          expect(backend.calls, ['signIn', 'refresh']);
          await client.close();
        },
      );
    }

    test(
      'should fail closed when refresh throws without leaking its cause',
      () async {
        // Given an authenticated client whose refresh transport throws private text.
        final backend = _ControlledBackend()
          ..onRefresh = () => throw StateError('private-refresh-body');
        final client = await _authenticated(backend);
        // When refresh fails unexpectedly.
        await client.refresh();
        // Then only a safe failure remains and refresh cannot continue.
        expect(
          client.snapshot.failure,
          UserAccountAuthenticationFailure.serviceUnavailable,
        );
        expect(client.snapshot.account, isNull);
        expect(
          client.snapshot.toString(),
          isNot(contains('private-refresh-body')),
        );
        await expectLater(client.refresh(), throwsStateError);
        await client.close();
      },
    );
  });

  group('current-session logout facts and ordering', () {
    test(
      'should withdraw immediately and preserve local success remote failure',
      () async {
        // Given an authenticated client with deferred current-session logout.
        final pending = Completer<UserAccountLogoutResult>();
        final backend = _ControlledBackend()..onSignOut = () => pending.future;
        final client = await _authenticated(backend);
        // When logout begins before its remote/local outcome is available.
        final work = client.signOut();
        expect(
          client.snapshot.status,
          UserAccountAuthenticationStatus.signingOut,
        );
        expect(client.snapshot.account, isNull);
        expect(client.snapshot.isAuthenticated, isFalse);
        await expectLater(
          client.signIn(identifier: 'id', password: 'pw'),
          throwsStateError,
        );
        await expectLater(client.signOut(), throwsStateError);
        const result = UserAccountLogoutResult(
          localCleared: true,
          remoteRevocation: UserAccountRemoteRevocation.failed,
        );
        pending.complete(result);
        final actual = await work;
        // Then local success signs out without claiming that remote revoke worked.
        expect(actual, same(result));
        expect(client.snapshot.lastLogoutResult, same(result));
        expect(
          client.snapshot.status,
          UserAccountAuthenticationStatus.signedOut,
        );
        expect(actual.localCleared, isTrue);
        expect(actual.remoteRevocation, UserAccountRemoteRevocation.failed);
        await client.close();
      },
    );

    test('should fail closed for local-clear failure and unexpected logout error', () async {
      // Given a backend that cannot clear local credentials.
      const failed = UserAccountLogoutResult(
        localCleared: false,
        remoteRevocation: UserAccountRemoteRevocation.confirmed,
      );
      final backend = _ControlledBackend()..onSignOut = () => failed;
      final client = await _authenticated(backend);
      // When local clearance fails and a subsequent logout throws private text.
      expect(await client.signOut(), same(failed));
      expect(client.snapshot.status, UserAccountAuthenticationStatus.failure);
      expect(client.snapshot.account, isNull);
      backend.onSignOut = () => throw StateError('private-logout-body');
      final unexpected = await client.signOut();
      // Then the throw becomes fixed unknown revocation and no usable account.
      expect(unexpected.localCleared, isFalse);
      expect(unexpected.remoteRevocation, UserAccountRemoteRevocation.unknown);
      expect(client.snapshot.lastLogoutResult, same(unexpected));
      expect(client.snapshot.status, UserAccountAuthenticationStatus.failure);
      expect(client.snapshot.isAuthenticated, isFalse);
      expect(
        client.snapshot.toString(),
        isNot(contains('private-logout-body')),
      );
      await client.close();
    });

    test('should drain deferred sign-in before invoking logout', () async {
      // Given accepted sign-in work that has not returned.
      final pending = Completer<UserAccountSignInResult>();
      final backend = _ControlledBackend()..onSignIn = () => pending.future;
      final client = UserAccountAuthenticationClient(backend: backend);
      final signIn = client.signIn(identifier: 'id', password: 'pw');
      final operation = backend.operations.single;
      // When logout retires sign-in and its late result eventually arrives.
      final logout = client.signOut();
      expect(operation.isCurrent, isFalse);
      expect(
        client.snapshot.status,
        UserAccountAuthenticationStatus.signingOut,
      );
      expect(backend.calls, ['signIn']);
      await expectLater(
        client.signIn(identifier: 'other', password: 'pw'),
        throwsStateError,
      );
      pending.complete(_signedIn());
      await signIn;
      final result = await logout;
      // Then logout starts only after drain and the retired account never appears.
      expect(backend.calls, ['signIn', 'signOut']);
      expect(backend.operations.last, isNot(same(operation)));
      expect(result.localCleared, isTrue);
      expect(client.snapshot.status, UserAccountAuthenticationStatus.signedOut);
      expect(client.snapshot.account, isNull);
      await client.close();
    });
  });

  group('cancellation and serial ownership', () {
    for (final lateError in [false, true]) {
      test(
        'should retire sign-in and block new work until drain error=$lateError',
        () async {
          // Given deferred sign-in and an observer of operation cancellation.
          final pending = Completer<UserAccountSignInResult>();
          final backend = _ControlledBackend()..onSignIn = () => pending.future;
          final client = UserAccountAuthenticationClient(backend: backend);
          final signIn = client.signIn(identifier: 'id', password: 'pw');
          final operation = backend.operations.single;
          var cancellationCount = 0;
          unawaited(operation.cancelled.then((_) => cancellationCount++));
          // When cancel retires synchronously but the old backend is still pending.
          final cancel = client.cancel();
          expect(operation.isCurrent, isFalse);
          expect(
            client.snapshot.status,
            UserAccountAuthenticationStatus.cancelling,
          );
          expect(client.snapshot.account, isNull);
          expect(client.busy, isTrue);
          await operation.cancelled;
          await expectLater(
            client.signIn(identifier: 'new', password: 'pw'),
            throwsStateError,
          );
          await expectLater(client.cancel(), throwsStateError);
          if (lateError) {
            pending.completeError(StateError('private-late-body'));
          } else {
            pending.complete(_signedIn());
          }
          await signIn;
          await cancel;
          // Then late outcomes are suppressed and new sign-in waits for drain.
          expect(
            client.snapshot.status,
            UserAccountAuthenticationStatus.signedOut,
          );
          expect(
            client.snapshot.failure,
            UserAccountAuthenticationFailure.cancelled,
          );
          expect(client.snapshot.account, isNull);
          expect(cancellationCount, 1);
          backend.onSignIn = _signedIn;
          await client.signIn(identifier: 'new', password: 'pw');
          expect(client.snapshot.isAuthenticated, isTrue);
          expect(backend.calls, ['signIn', 'signIn']);
          await client.close();
        },
      );
    }

    test(
      'should cancel an idle challenge without additional backend IO',
      () async {
        // Given a completed sign-in requiring an email challenge.
        final backend = _ControlledBackend()
          ..onSignIn = () =>
              const UserAccountChallengePending('private-ref', 'email');
        final client = UserAccountAuthenticationClient(backend: backend);
        await client.signIn(identifier: 'id', password: 'pw');
        // When the user cancels before submitting a code.
        await client.cancel();
        // Then private challenge state is gone and no remote revoke is claimed.
        expect(
          client.snapshot.status,
          UserAccountAuthenticationStatus.signedOut,
        );
        expect(client.snapshot.challengeChannel, isNull);
        expect(client.snapshot.lastLogoutResult, isNull);
        await expectLater(client.verifyChallenge('code'), throwsStateError);
        expect(backend.calls, ['signIn']);
        await client.close();
      },
    );

    for (final verifying in [true, false]) {
      test('should cancel deferred ${verifying ? 'verification' : 'refresh'}', () async {
        // Given an authenticated or challenged client with deferred next work.
        final pending = Completer<UserAccountSignInResult>();
        final backend = _ControlledBackend();
        if (verifying) {
          backend.onSignIn = () =>
              const UserAccountChallengePending('reference', 'email');
          backend.onVerify = () => pending.future;
        } else {
          backend.onRefresh = () => pending.future;
        }
        final client = UserAccountAuthenticationClient(backend: backend);
        await client.signIn(identifier: 'id', password: 'pw');
        // When accepted verification/refresh is cancelled before late success.
        final work = verifying
            ? client.verifyChallenge('code')
            : client.refresh();
        final operation = backend.operations.last;
        final cancel = client.cancel();
        expect(operation.isCurrent, isFalse);
        expect(client.snapshot.isAuthenticated, isFalse);
        pending.complete(_signedIn());
        await work;
        await cancel;
        // Then the late account cannot return and the challenge stays cleared.
        expect(
          client.snapshot.status,
          UserAccountAuthenticationStatus.signedOut,
        );
        expect(client.snapshot.account, isNull);
        expect(client.snapshot.challengeChannel, isNull);
        await client.close();
      });
    }

    test('should reserve before listeners and reject concurrent backend reentry', () async {
      // Given a listener and backend that attempt a second command synchronously.
      final pending = Completer<UserAccountSignInResult>();
      final backend = _ControlledBackend();
      final client = UserAccountAuthenticationClient(backend: backend);
      Future<void>? listenerAttempt;
      Future<void>? backendAttempt;
      client.addListener(() {
        if (client.snapshot.status ==
            UserAccountAuthenticationStatus.signingIn) {
          listenerAttempt = expectLater(
            client.signIn(identifier: 'listener-private', password: 'pw'),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'safe message',
                'Authentication command is not available',
              ),
            ),
          );
        }
      });
      backend.onSignIn = () {
        backendAttempt = expectLater(client.refresh(), throwsStateError);
        return pending.future;
      };
      // When the first action publishes state and invokes external backend code.
      final work = client.signIn(identifier: 'id', password: 'pw');
      await expectLater(
        client.signIn(identifier: 'concurrent', password: 'pw'),
        throwsStateError,
      );
      await expectLater(client.verifyChallenge('code'), throwsStateError);
      await listenerAttempt;
      await backendAttempt;
      pending.complete(_signedIn());
      await work;
      // Then every reentrant/concurrent attempt is safe and only one IO starts.
      expect(backend.calls, ['signIn']);
      expect(client.snapshot.isAuthenticated, isTrue);
      await client.close();
    });

    test(
      'should suppress IO when a listener cancels before backend invocation',
      () async {
        // Given a listener that cancels the newly reserved sign-in generation.
        final backend = _ControlledBackend();
        final client = UserAccountAuthenticationClient(backend: backend);
        Future<void>? cancelled;
        client.addListener(() {
          if (client.snapshot.status ==
              UserAccountAuthenticationStatus.signingIn) {
            cancelled = client.cancel();
          }
        });
        // When sign-in publishes its initial state to that listener.
        await client.signIn(identifier: 'id', password: 'pw');
        await cancelled;
        // Then the retired generation cannot invoke or publish backend work.
        expect(backend.calls, isEmpty);
        expect(
          client.snapshot.status,
          UserAccountAuthenticationStatus.signedOut,
        );
        expect(client.snapshot.isAuthenticated, isFalse);
        await client.close();
      },
    );
  });

  group('close disposal and backend ownership', () {
    for (final owned in [false, true]) {
      test(
        'should close idempotently after late work with owned=$owned',
        () async {
          // Given accepted sign-in, an ownership choice and a notification observer.
          final pending = Completer<UserAccountSignInResult>();
          final backend = _ControlledBackend()..onSignIn = () => pending.future;
          final client = UserAccountAuthenticationClient(
            backend: backend,
            ownsBackend: owned,
          );
          var notifications = 0;
          client.addListener(() => notifications++);
          final work = client.signIn(identifier: 'id', password: 'pw');
          final operation = backend.operations.single;
          // When close retires synchronously and is requested repeatedly before drain.
          final closing = client.close();
          expect(client.close(), same(closing));
          expect(client.isClosed, isTrue);
          expect(client.snapshot.account, isNull);
          expect(client.busy, isFalse);
          expect(operation.isCurrent, isFalse);
          final closedRevision = client.snapshot.revision;
          expect(backend.calls, ['signIn']);
          pending.complete(_signedIn());
          await work;
          await closing;
          await client.close();
          // Then no late state publishes and only an owned backend closes once.
          expect(
            client.snapshot.status,
            UserAccountAuthenticationStatus.closed,
          );
          expect(client.snapshot.revision, closedRevision);
          expect(notifications, 2);
          expect(backend.calls, owned ? ['signIn', 'close'] : ['signIn']);
          client.dispose();
          client.dispose();
        },
      );
    }

    test('should drain logout before owned close without late publication', () async {
      // Given an owned backend whose logout has not finished.
      final pending = Completer<UserAccountLogoutResult>();
      final backend = _ControlledBackend()..onSignOut = () => pending.future;
      final client = UserAccountAuthenticationClient(
        backend: backend,
        ownsBackend: true,
      );
      await client.signIn(identifier: 'id', password: 'pw');
      final logout = client.signOut();
      // When close retires the logout lifetime before its response arrives.
      final closing = client.close();
      final revision = client.snapshot.revision;
      expect(backend.operations.last.isCurrent, isFalse);
      expect(backend.calls, ['signIn', 'signOut']);
      pending.complete(
        const UserAccountLogoutResult(
          localCleared: true,
          remoteRevocation: UserAccountRemoteRevocation.unknown,
        ),
      );
      await logout;
      await closing;
      // Then close follows drain and the closed presentation remains unchanged.
      expect(backend.calls, ['signIn', 'signOut', 'close']);
      expect(client.snapshot.status, UserAccountAuthenticationStatus.closed);
      expect(client.snapshot.revision, revision);
      expect(client.snapshot.lastLogoutResult, isNull);
      client.dispose();
    });

    test(
      'should retire disposal immediately and observe late errors silently',
      () async {
        // Given deferred work and an owned backend with a failing close handle.
        final pending = Completer<UserAccountSignInResult>();
        final backend = _ControlledBackend()
          ..onSignIn = (() => pending.future)
          ..onClose = () => throw StateError('private-close-body');
        final client = UserAccountAuthenticationClient(
          backend: backend,
          ownsBackend: true,
        );
        var notifications = 0;
        client.addListener(() => notifications++);
        final work = client.signIn(identifier: 'id', password: 'pw');
        // When dispose runs before a late backend error and cleanup failure.
        client.dispose();
        client.dispose();
        expect(client.isClosed, isTrue);
        expect(backend.operations.single.isCurrent, isFalse);
        final closedRevision = client.snapshot.revision;
        pending.completeError(StateError('private-late-body'));
        await work;
        await expectLater(
          client.close(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'safe message',
              'Authentication close failed',
            ),
          ),
        );
        // Then cleanup runs once with no post-disposal state notification or leak.
        expect(notifications, 1);
        expect(client.snapshot.revision, closedRevision);
        expect(client.snapshot.toString(), isNot(contains('private-')));
        expect(backend.calls, ['signIn', 'close']);
      },
    );

    test('should return a safe close error and never implicitly log out', () async {
      // Given an authenticated client that owns a failing backend handle.
      final backend = _ControlledBackend()
        ..onClose = () => throw StateError('private-backend-close');
      final client = UserAccountAuthenticationClient(
        backend: backend,
        ownsBackend: true,
      );
      await client.signIn(identifier: 'id', password: 'pw');
      // When asynchronous close is awaited more than once.
      final closing = client.close();
      await expectLater(
        closing,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'safe message',
            'Authentication close failed',
          ),
        ),
      );
      await expectLater(client.close(), throwsStateError);
      // Then cleanup does not logout, retry close or expose the backend cause.
      expect(backend.calls, ['signIn', 'close']);
      expect(client.snapshot.account, isNull);
      expect(client.snapshot.status, UserAccountAuthenticationStatus.closed);
      client.dispose();
    });

    test(
      'should tolerate listener disposal before backend invocation',
      () async {
        // Given a listener that disposes synchronously during initial notification.
        final backend = _ControlledBackend();
        final client = UserAccountAuthenticationClient(
          backend: backend,
          ownsBackend: true,
        );
        var notifications = 0;
        client.addListener(() {
          notifications++;
          client.dispose();
        });
        // When sign-in publishes its reserved generation to the listener.
        await client.signIn(identifier: 'id', password: 'pw');
        await client.close();
        // Then notifier disposal is safe and no retired sign-in reaches the backend.
        expect(notifications, 1);
        expect(client.isClosed, isTrue);
        expect(backend.calls, ['close']);
      },
    );
  });
}

UserAccountSignedIn _signedIn() => UserAccountSignedIn(
  AuthenticatedUserAccount(
    userAccountId: 'account:1',
    displayName: 'Authority',
  ),
);

Future<UserAccountAuthenticationClient> _authenticated(
  _ControlledBackend backend,
) async {
  final client = UserAccountAuthenticationClient(backend: backend);
  await client.signIn(identifier: 'entered-id', password: 'pw');
  return client;
}

/// Test-only asynchronous port control; no credential verification or issuance.
class _ControlledBackend implements UserAccountAuthenticationBackend {
  final calls = <String>[];
  final operations = <UserAccountAuthenticationOperation>[];
  String? identifier;
  String? password;
  String? challengeId;
  String? code;
  FutureOr<UserAccountSignInResult> Function() onSignIn = _signedIn;
  FutureOr<UserAccountSignInResult> Function() onVerify = _signedIn;
  FutureOr<UserAccountSignInResult> Function() onRefresh = _signedIn;
  FutureOr<UserAccountLogoutResult> Function() onSignOut = () =>
      const UserAccountLogoutResult(
        localCleared: true,
        remoteRevocation: UserAccountRemoteRevocation.confirmed,
      );
  FutureOr<void> Function() onClose = () {};

  @override
  Future<UserAccountSignInResult> signIn({
    required String identifier,
    required String password,
    required UserAccountAuthenticationOperation operation,
  }) async {
    calls.add('signIn');
    operations.add(operation);
    this.identifier = identifier;
    this.password = password;
    return await onSignIn();
  }

  @override
  Future<UserAccountSignInResult> verifyChallenge({
    required String challengeId,
    required String code,
    required UserAccountAuthenticationOperation operation,
  }) async {
    calls.add('verifyChallenge');
    operations.add(operation);
    this.challengeId = challengeId;
    this.code = code;
    return await onVerify();
  }

  @override
  Future<UserAccountSignInResult> refresh({
    required UserAccountAuthenticationOperation operation,
  }) async {
    calls.add('refresh');
    operations.add(operation);
    return await onRefresh();
  }

  @override
  Future<UserAccountLogoutResult> signOut({
    required UserAccountAuthenticationOperation operation,
  }) async {
    calls.add('signOut');
    operations.add(operation);
    return await onSignOut();
  }

  @override
  Future<void> close() async {
    calls.add('close');
    await onClose();
  }
}

final class _ControlledCommit implements UserAccountAuthenticationSessionCommit {
  final events = <String>[];
  final started = Completer<void>();
  final persisted = Completer<void>();
  final discardStarted = Completer<void>();
  final discarded = Completer<void>();
  bool holdDiscard = false;
  bool failPersist = false;
  bool failDiscard = false;
  @override
  Future<void> persist({required UserAccountAuthenticationOperation operation}) async {
    events.add('persist');
    started.complete();
    if (failPersist) throw StateError('synthetic private persist failure');
    await persisted.future;
  }
  @override
  void accept() => events.add('accept');
  @override
  Future<void> discard() async {
    events.add('discard');
    discardStarted.complete();
    if (holdDiscard) await discarded.future;
    if (failDiscard) throw StateError('synthetic private cleanup failure');
  }
}

Matcher _authenticationCleanupFailure() => throwsA(isA<StateError>().having(
  (error) => error.message, 'message', 'Authentication cleanup failed',
));

Matcher _authenticationCloseFailure() => throwsA(isA<StateError>().having(
  (error) => error.message, 'message', 'Authentication close failed',
));

final class _RestorableBackend extends _ControlledBackend
    implements UserAccountRestorableAuthenticationBackend {
  int restores = 0;
  UserAccountSignInResult? result;
  @override
  Future<UserAccountSignInResult?> restore({
    required UserAccountAuthenticationOperation operation,
  }) async {
    restores++;
    return result;
  }
}
