import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:textus_flutter_core/src/authentication/native_authentication_credential_store.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

const _channel = MethodChannel(
  'org.textus.flutter.core/authentication_credentials',
);
const _base = 'https://scope.example.test/user-account/';
const _account = ' synthetic/account:α ';
const _access = 'SYNTHETIC.scope-access-v1=';
const _refresh = 'SYNTHETIC.scope-refresh-v1==';
const _otherRevision = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _marker = 'synthetic-private-marker';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _NativeCas native;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    native = _NativeCas();
    messenger.setMockMethodCallHandler(_channel, native.handle);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(_channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  _Harness harness({bool ownedDefaults = false}) {
    final h = _Harness(native, ownedDefaults: ownedDefaults);
    addTearDown(h.dispose);
    return h;
  }

  group('accepted account and explicit recipient admission', () {
    for (final state in ['signed out', 'challenge', 'closed']) {
      test('$state cannot construct a scope', () async {
        // Given a real backend without an accepted authenticated owner.
        final h = harness();
        if (state == 'challenge') {
          h.http.json({
            'user_account_id': _account,
            'credential_id': 'synthetic/credential',
            'two_factor_required': true,
            'challenge_id': 'synthetic/challenge',
            'channel': 'email',
            'authenticated': false,
          });
          await h.signIn();
        } else if (state == 'closed') {
          await h.backend.close();
        }
        var callbacks = 0;
        final calls = List<String>.of(native.calls);
        final requests = h.http.requests.length;
        // When explicit recipient admission is requested in that state.
        final error = _capture(
          () => h.scope(
            isCurrent: () {
              callbacks++;
              return true;
            },
          ),
        );
        // Then the fixed safe error precedes callback, native and HTTP work.
        _expectUnavailable(error);
        expect(callbacks, 0);
        expect(native.calls, calls);
        expect(h.http.requests, hasLength(requests));
      });
    }

    test('accepted login snapshots exact identity and recipient definitions', () async {
      // Given an actual login, a mutable recipient list and a counting run fence.
      final h = harness();
      await h.login();
      final target = _target();
      final targets = [target];
      var callbacks = 0;
      final calls = List<String>.of(native.calls);
      final requests = h.http.requests.length;
      // When a scope is constructed and the caller replaces its list contents.
      final scope = h.backend.createSubmissionScope(
        trustedTargets: targets,
        isRunCurrent: () {
          callbacks++;
          return true;
        },
      );
      targets
        ..clear()
        ..add(_target(id: 'replacement'));
      // Then construction is inert and exposes exact token-free local identity.
      expect(callbacks, 0);
      expect(native.calls, calls);
      expect(h.http.requests, hasLength(requests));
      expect(scope.binding.authorityProfileId, h.backend.profile.profileId);
      expect(scope.binding.authorityBaseUri, Uri.parse(_base));
      expect(scope.binding.userAccountId, _account);
      expect(scope.context.binding, same(scope.binding));
      expect('$scope', 'UserAccountSubmissionScope');
      expect('${scope.context}', 'SubmissionAuthenticationContext');
      expect('${scope.binding}', 'SubmissionAuthenticationBinding');
      // When the advanced port borrows the original exact recipient.
      final token = await scope.bearerTokenFor(
        binding: scope.binding,
        connection: target,
      );
      // Then one readonly native call returns only ACCESS, with no new HTTP/CAS.
      expect(token, _access);
      expect(token, isNot(_refresh));
      expect(native.calls, [...calls, 'read']);
      expect(h.http.requests, hasLength(requests));
      expect(callbacks, greaterThan(0));
    });

    for (final invalid in [
      'empty',
      'duplicate',
      'anonymous',
      'iteration',
      '129',
    ]) {
      test('invalid $invalid recipient list is safely rejected', () async {
        // Given an accepted login and an invalid explicitly supplied recipient set.
        final h = harness();
        await h.login();
        final Iterable<HttpSubmissionConnection> targets = switch (invalid) {
          'empty' => [],
          'duplicate' => [
            _target(),
            _target(endpoint: 'https://other.test/path'),
          ],
          'anonymous' => [_target(authenticated: false)],
          'iteration' => _IteratedTargets(() => throw StateError(_marker)),
          _ => List.generate(129, (index) => _target(id: 'target-$index')),
        };
        var callbacks = 0;
        final calls = List<String>.of(native.calls);
        final requests = h.http.requests.length;
        // When the real backend validates that recipient declaration.
        final error = _capture(
          () => h.backend.createSubmissionScope(
            trustedTargets: targets,
            isRunCurrent: () {
              callbacks++;
              return true;
            },
          ),
        );
        // Then no input/cause, callback or extra IO escapes validation.
        expect(
          error,
          isA<ArgumentError>().having(
            (error) => error.message,
            'safe message',
            'Invalid authenticated submission targets',
          ),
        );
        expect('$error', isNot(contains(_marker)));
        expect(callbacks, 0);
        expect(native.calls, calls);
        expect(h.http.requests, hasLength(requests));
      });
    }

    test(
      '128 unique recipients are admitted without implicit recipient inference',
      () async {
        // Given an accepted account and the maximum explicit recipient set.
        final h = harness();
        await h.login();
        final targets = List.generate(
          128,
          (index) => _target(id: 'target-$index'),
        );
        // When the final declared recipient is used and a same-origin outsider probed.
        final scope = h.backend.createSubmissionScope(
          trustedTargets: targets,
          isRunCurrent: () => true,
        );
        final outside = await scope.bearerTokenFor(
          binding: scope.binding,
          connection: _target(id: 'outside'),
        );
        final accepted = await scope.bearerTokenFor(
          binding: scope.binding,
          connection: targets.last,
        );
        // Then only the explicitly declared id receives the accepted ACCESS token.
        expect(outside, isNull);
        expect(accepted, _access);
        expect(native.calls.where((call) => call == 'read'), hasLength(2));
      },
    );

    test('recipient iteration cannot reentrantly escape backend retirement', () async {
      // Given an accepted owner and caller iteration that closes it synchronously.
      final h = harness();
      await h.login();
      Future<void>? closing;
      var callbacks = 0;
      final targets = _IteratedTargets(() {
        closing = h.backend.close();
        return [_target()].iterator;
      });
      final calls = List<String>.of(native.calls);
      // When target iteration withdraws the backend during scope construction.
      final error = _capture(
        () => h.backend.createSubmissionScope(
          trustedTargets: targets,
          isRunCurrent: () {
            callbacks++;
            return true;
          },
        ),
      );
      await closing;
      // Then the post-iteration owner check rejects without invoking the fence.
      _expectUnavailable(error);
      expect(callbacks, 0);
      expect(native.calls, calls);
    });

    test('busy refresh denies construction before any extra work', () async {
      // Given a real accepted login and a refresh held at its HTTP response.
      final h = harness();
      await h.login();
      final started = Completer<void>();
      final release = Completer<http.StreamedResponse>();
      h.http.respond((_) {
        started.complete();
        return release.future;
      });
      final refreshing = h.client.refresh();
      await started.future;
      final calls = List<String>.of(native.calls);
      var callbacks = 0;
      // When construction is attempted before the admitted refresh completes.
      final error = _capture(
        () => h.scope(
          isCurrent: () {
            callbacks++;
            return true;
          },
        ),
      );
      // Then the busy owner is unavailable and admission adds no IO/callback.
      _expectUnavailable(error);
      expect(callbacks, 0);
      expect(native.calls, calls);
      expect(h.http.requests, hasLength(3));
      release.complete(_reply({}, status: 401));
      await refreshing;
    });

    test('unaccepted candidate cannot issue a scope', () async {
      // Given the real backend whose real candidate is held before client persist.
      final h = harness();
      h.loginReplies();
      final bridge = _CandidateBridge(h.backend);
      final client = UserAccountAuthenticationClient(backend: bridge);
      addTearDown(client.close);
      final signingIn = client.signIn(
        identifier: 'synthetic',
        password: 'synthetic',
      );
      await bridge.ready.future;
      final calls = List<String>.of(native.calls);
      var callbacks = 0;
      // When a scope is requested while the genuine session commit is pending.
      final error = _capture(
        () => h.scope(
          isCurrent: () {
            callbacks++;
            return true;
          },
        ),
      );
      // Then no unaccepted candidate can become a credential authority.
      _expectUnavailable(error);
      expect(callbacks, 0);
      expect(native.calls, calls);
      expect(native.value, isNull);
      bridge.release.complete();
      await signingIn;
      expect(client.snapshot.isAuthenticated, isTrue);
    });

    test(
      'unresolved staged cleanup denies a scope until explicit recovery',
      () async {
        // Given a real candidate write held while its own rollback will fail.
        final h = harness();
        h.loginReplies();
        final started = Completer<void>();
        final release = Completer<void>();
        native.onReplace = (args) async {
          started.complete();
          await release.future;
          return native.replace(args);
        };
        native.onRemove = (_) async =>
            throw PlatformException(code: 'unavailable');
        final signingIn = h.signIn();
        await started.future;
        final cancelling = _captureAsync(h.client.cancel);
        release.complete();
        await signingIn;
        final cancelError = await cancelling;
        final calls = List<String>.of(native.calls);
        var callbacks = 0;
        // When unresolved rollback is followed by attempted scope admission.
        final error = _capture(
          () => h.scope(
            isCurrent: () {
              callbacks++;
              return true;
            },
          ),
        );
        // Then the honest cleanup barrier remains and no new work is admitted.
        expect(
          cancelError,
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Authentication cleanup failed',
          ),
        );
        _expectUnavailable(error);
        expect(callbacks, 0);
        expect(native.calls, calls);
        expect(native.value, isNotNull);
        native.onRemove = null;
        await h.client.signOut();
        expect(native.value, isNull);
      },
    );
  });

  group('exact binding, target and protected owner checks', () {
    test('mismatches and legacy probes precede IO without retiring valid scope', () async {
      // Given an accepted scope and mismatches on every binding/recipient edge.
      final h = harness();
      await h.login();
      var callbacks = 0;
      final scope = h.scope(
        isCurrent: () {
          callbacks++;
          return true;
        },
      );
      final bindings = [
        _binding(account: 'other-account'),
        _binding(profile: 'other-profile'),
        _binding(base: 'https://other.test/account/'),
      ];
      final targets = [
        _target(id: 'other-id'),
        _target(endpoint: 'https://recipient.example.test/other'),
        _target(authenticated: false),
      ];
      final calls = List<String>.of(native.calls);
      // When mismatching requests and the legacy id-only method probe the scope.
      final results = <String?>[];
      for (final binding in bindings) {
        results.add(
          await scope.bearerTokenFor(binding: binding, connection: _target()),
        );
      }
      for (final target in targets) {
        results.add(
          await scope.bearerTokenFor(
            binding: scope.binding,
            connection: target,
          ),
        );
      }
      results.add(await scope.bearerToken('recipient'));
      // Then none calls the borrowed fence or native storage, and every probe denies.
      expect(results, everyElement(isNull));
      expect(callbacks, 0);
      expect(native.calls, calls);
      expect(h.http.requests, hasLength(2));
      // When the same scope subsequently receives an exact request.
      final token = await _lookup(scope);
      // Then target probing has not withdrawn valid accepted ownership.
      expect(token, _access);
      expect(native.calls, [...calls, 'read']);
    });

    for (final change in ['missing', 'owner B', 'pair', 'writeId']) {
      test('native $change cannot be adopted or erased', () async {
        // Given an accepted A scope followed by a changed protected slot.
        final h = harness();
        await h.login();
        final scope = h.scope();
        final originalBinding = scope.binding;
        final document = native.document();
        if (change == 'missing') {
          native.value = null;
          native.revision = null;
        } else {
          if (change == 'owner B') document['userAccountId'] = 'synthetic/B';
          if (change == 'pair' || change == 'owner B') {
            document['accessToken'] = 'SYNTHETIC.other-access=';
            document['refreshToken'] = 'SYNTHETIC.other-refresh=';
            document['accessSessionId'] = 'synthetic/other-access-session';
          }
          if (change == 'writeId') document['writeId'] = _otherRevision;
          native.value = _bytes(document);
          if (change == 'owner B') native.revision = _otherRevision;
        }
        final retained = native.read();
        final calls = List<String>.of(native.calls);
        // When the advanced port rechecks the protected owner once.
        final token = await _lookup(scope);
        // Then no foreign or changed token is returned, adopted, written or removed.
        expect(token, isNull);
        expect(scope.binding, same(originalBinding));
        expect(scope.binding.userAccountId, _account);
        expect(native.read(), retained);
        expect(native.calls, [...calls, 'read']);
        expect(h.http.requests, hasLength(2));
        expect(h.client.snapshot.account!.userAccountId, _account);
      });
    }

    test(
      'explicit same-record restore retires an unobserved old scope',
      () async {
        // Given accepted A and another real client borrowing exactly the same backend.
        final h = harness();
        await h.login();
        final old = h.scope();
        final saved = native.read();
        final other = UserAccountAuthenticationClient(backend: h.backend);
        addTearDown(other.close);
        h.http.json(_accountBody());
        // When restore accepts the identical record without observing the old scope.
        await other.restore();
        final calls = List<String>.of(native.calls);
        final oldToken = await _lookup(old);
        final fresh = h.scope();
        final newToken = await _lookup(fresh);
        // Then auth epoch prevents revival while the same queue binding can resume.
        expect(other.snapshot.isAuthenticated, isTrue);
        expect(native.read(), saved);
        expect(oldToken, isNull);
        expect(old.context.isCurrent, isFalse);
        expect(fresh.binding, old.binding);
        expect(newToken, _access);
        expect(native.calls, [...calls, 'read']);
        expect(h.http.requests, hasLength(3));
      },
    );

    for (final action in ['refresh', 'same-account relogin']) {
      test('$action cannot revive an unobserved scope', () async {
        // Given a real accepted account and a scope never polled during auth change.
        final h = harness();
        await h.login();
        final old = h.scope();
        // When explicit authentication accepts the same account again.
        if (action == 'refresh') {
          h.http.json(_rotated());
          h.http.json(_accountBody());
          await h.client.refresh();
        } else {
          h.http.raw([]);
          await h.client.signOut();
          await h.login();
        }
        final calls = List<String>.of(native.calls);
        final oldToken = await _lookup(old);
        final fresh = h.scope();
        final token = await _lookup(fresh);
        // Then only a fresh scope resumes the identical immutable account binding.
        expect(h.client.snapshot.isAuthenticated, isTrue);
        expect(oldToken, isNull);
        expect(fresh.binding, old.binding);
        expect(
          token,
          action == 'refresh' ? 'SYNTHETIC.scope-access-v2=' : _access,
        );
        expect(native.calls, [...calls, 'read']);
      });
    }
  });

  group('borrowed lifetime and readonly operation retirement', () {
    for (final failure in ['false', 'error']) {
      test('caller $failure latches permanent withdrawal', () async {
        // Given a real accepted scope whose caller can withdraw or fail.
        final h = harness();
        await h.login();
        var current = false;
        bool runCurrent() {
          if (!current && failure == 'error') throw StateError(_marker);
          return current;
        }

        final scope = h.scope(isCurrent: runCurrent);
        final calls = List<String>.of(native.calls);
        // When false/error is observed and the same callback later becomes true.
        final first = await _lookup(scope);
        current = true;
        final second = await _lookup(scope);
        final stillCurrent = scope.context.isCurrent;
        // Then the retired scope cannot revive or perform native work.
        expect(first, isNull);
        expect(second, isNull);
        expect(stillCurrent, isFalse);
        expect(native.calls, calls);
        // When a new scope borrows the now-current caller fence.
        final token = await _lookup(h.scope(isCurrent: runCurrent));
        // Then explicit fresh admission can use the still-accepted account.
        expect(token, _access);
      });
    }

    for (final action in ['close', 'logout', 'refresh']) {
      test('callback $action returning true cannot authorize a token', () async {
        // Given an accepted owner and a callback that synchronously changes auth.
        final h = harness();
        await h.login();
        if (action == 'logout') h.http.raw([]);
        if (action == 'refresh') {
          h.http.json(_rotated());
          h.http.json(_accountBody());
        }
        Future<void>? changing;
        Future<UserAccountLogoutResult>? signingOut;
        final scope = h.scope(
          isCurrent: () {
            if (action == 'logout') {
              signingOut = h.client.signOut();
            } else {
              changing = action == 'close'
                  ? h.backend.close()
                  : h.client.refresh();
            }
            return true;
          },
        );
        final readCount = native.calls.where((call) => call == 'read').length;
        // When the scope checks that callback immediately before credential IO.
        final token = await _lookup(scope);
        await changing;
        await signingOut;
        // Then the post-callback internal check denies the withdrawn epoch.
        expect(token, isNull);
        expect(scope.context.isCurrent, isFalse);
        expect(
          native.calls.where((call) => call == 'read'),
          hasLength(readCount + (action == 'close' ? 0 : 1)),
        );
      });
    }

    for (final action in ['logout', 'refresh']) {
      test('held readonly lookup yields to $action without overwriting auth', () async {
        // Given a scope lookup held after its accepted native read begins.
        final h = harness();
        await h.login();
        final scope = h.scope();
        final started = Completer<void>();
        final release = Completer<Object?>();
        final saved = native.read();
        native.onRead = (_) {
          native.onRead = null;
          started.complete();
          return release.future;
        };
        final lookup = _lookup(scope);
        await started.future;
        // When a newer explicit auth action completes before that read returns.
        if (action == 'logout') {
          h.http.raw([]);
          await h.client.signOut();
        } else {
          h.http.json(_rotated());
          h.http.json(_accountBody());
          await h.client.refresh();
        }
        final calls = List<String>.of(native.calls);
        final retained = native.read();
        release.complete(saved);
        final token = await lookup;
        // Then the late result cannot publish a token or write/erase newer state.
        expect(token, isNull);
        expect(scope.context.isCurrent, isFalse);
        expect(native.calls, calls);
        expect(native.read(), retained);
        expect(h.client.snapshot.isAuthenticated, action == 'refresh');
        if (action == 'refresh') {
          expect(await _lookup(h.scope()), 'SYNTHETIC.scope-access-v2=');
        }
      });
    }

    for (final invalid in ['native error', 'invalid record']) {
      test('$invalid is safe and permits explicit readonly retry', () async {
        // Given accepted ownership and one native failure carrying a private marker.
        final h = harness();
        await h.login();
        final scope = h.scope();
        native.onRead = (_) async {
          if (invalid == 'native error') {
            throw PlatformException(code: 'unavailable', message: _marker);
          }
          return {
            'revision': native.revision,
            'value': _bytes({'private': _marker}),
          };
        };
        final calls = List<String>.of(native.calls);
        // When credential lookup executes and its actual failure is captured.
        final error = await _captureAsync(() => _lookup(scope));
        // Then only the fixed safe failure escapes; no CAS or auth HTTP occurs.
        expect(
          error,
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Submission credentials are unavailable',
          ),
        );
        expect('$error', isNot(contains(_marker)));
        expect(native.calls, [...calls, 'read']);
        expect(h.http.requests, hasLength(2));
        // When native reads explicitly recover and the same scope is retried.
        native.onRead = null;
        final token = await _lookup(scope);
        // Then readonly failure alone did not retire the still-current owner.
        expect(token, _access);
        expect(scope.context.isCurrent, isTrue);
      });
    }
  });

  group('owned and borrowed readonly drain', () {
    for (final count in [1, 2]) {
      test('owned close retires native before draining $count held reads', () async {
        // Given actual default-owned handles with one or two accepted held reads.
        final h = harness(ownedDefaults: true);
        await h.login();
        final scope = h.scope();
        final saved = native.read();
        final allStarted = Completer<void>();
        final releases = List.generate(count, (_) => Completer<Object?>());
        var started = 0;
        native.onRead = (_) {
          final result = releases[started++].future;
          if (started == count) allStarted.complete();
          return result;
        };
        final lookups = List.generate(count, (_) => _lookup(scope));
        await allStarted.future;
        final nativeClosed = Completer<void>();
        native.onClose = (_) async {
          nativeClosed.complete();
          return null;
        };
        var completed = false;
        // When backend close starts while every readonly native result is held.
        final closing = h.backend.close();
        final observed = closing.then<void>((_) {
          completed = true;
        });
        await nativeClosed.future;
        // Then native retirement and HTTP cleanup precede the unresolved drain.
        expect(completed, isFalse);
        expect(h.http.closeCalls, 1);
        expect(native.calls.where((call) => call == 'close'), hasLength(1));
        expect(identical(h.backend.close(), closing), isTrue);
        expect(scope.context.isCurrent, isFalse);
        expect(await _lookup(scope), isNull);
        expect(native.read(), saved);
        if (count == 2) {
          releases.first.complete(saved);
          expect(await lookups.first, isNull);
          expect(completed, isFalse);
        }
        // When all remaining accepted native calls finally finish.
        releases.last.complete(saved);
        final tokens = await Future.wait(lookups);
        await observed;
        // Then close joins every read without late tokens, erasure or revival.
        expect(tokens, everyElement(isNull));
        expect(completed, isTrue);
        expect(native.read(), saved);
        expect(native.calls.where((call) => call == 'remove'), isEmpty);
        expect(native.calls.where((call) => call == 'clear'), isEmpty);
        expect(h.http.closeCalls, 1);
        expect(native.calls.where((call) => call == 'close'), hasLength(1));
      });
    }

    test('borrowed handles remain open while backend close joins accepted lookup', () async {
      // Given borrowed HTTP/native handles and a held accepted readonly lookup.
      final h = harness();
      await h.login();
      final scope = h.scope();
      final started = Completer<void>();
      final release = Completer<Object?>();
      final saved = native.read();
      native.onRead = (_) {
        started.complete();
        return release.future;
      };
      final lookup = _lookup(scope);
      await started.future;
      var completed = false;
      // When backend close withdraws auth without owning either borrowed handle.
      final closing = h.backend.close();
      final observed = closing.then<void>((_) {
        completed = true;
      });
      final retired = scope.context.isCurrent;
      // Then close cannot finish early, close borrowed handles or admit more reads.
      expect(completed, isFalse);
      expect(retired, isFalse);
      expect(h.http.closeCalls, 0);
      expect(native.calls.where((call) => call == 'close'), isEmpty);
      expect(identical(h.backend.close(), closing), isTrue);
      // When the owner releases its read and explicitly uses/cleans borrowed handles.
      release.complete(saved);
      final token = await lookup;
      await observed;
      native.onRead = null;
      final retained = await h.store!.read('scope-profile');
      h.http.close();
      await h.store!.close();
      // Then backend drain preserved borrowing and protected persistent ownership.
      expect(token, isNull);
      expect(completed, isTrue);
      expect(retained!.value, native.value);
      expect(h.http.closeCalls, 1);
      expect(native.calls.where((call) => call == 'close'), hasLength(1));
      expect(native.calls.where((call) => call == 'remove'), isEmpty);
    });

    test('native dispatch reentrantly closing backend still reserves its lookup', () async {
      // Given a borrowed scope whose native handler synchronously starts close.
      final h = harness();
      await h.login();
      final scope = h.scope();
      final closingStarted = Completer<void>();
      final release = Completer<Object?>();
      Future<void>? closing;
      var completed = false;
      native.onRead = (_) {
        closing = h.backend.close();
        closing!.then<void>((_) {
          completed = true;
        });
        closingStarted.complete();
        return release.future;
      };
      // When native dispatch reenters close before returning the protected read.
      final lookup = _lookup(scope);
      await closingStarted.future;
      // Then close sees the already-reserved readonly drain.
      expect(completed, isFalse);
      expect(native.calls.where((call) => call == 'close'), isEmpty);
      release.complete(native.read());
      final token = await lookup;
      await closing;
      expect(token, isNull);
      expect(completed, isTrue);
    });

    test('native close failure stays honest while all owned cleanup is attempted', () async {
      // Given owned defaults, accepted A and a held read plus native close failure.
      final h = harness(ownedDefaults: true);
      await h.login();
      final scope = h.scope();
      final started = Completer<void>();
      final release = Completer<Object?>();
      final closed = Completer<void>();
      native.onRead = (_) {
        started.complete();
        return release.future;
      };
      native.onClose = (_) async {
        closed.complete();
        throw PlatformException(code: 'unavailable', message: _marker);
      };
      final lookup = _lookup(scope);
      await started.future;
      h.expectsCloseFailure = true;
      // When close executes, with its actual error observed before releasing IO.
      final closing = h.backend.close();
      final outcome = _captureAsync(() => closing);
      await closed.future;
      expect(h.http.closeCalls, 1);
      release.complete(native.read());
      final token = await lookup;
      final error = await outcome;
      // Then failure is safe and repeated close keeps the same honest outcome.
      _expectBackendCloseFailure(error);
      expect('$error', isNot(contains(_marker)));
      expect(token, isNull);
      expect(identical(h.backend.close(), closing), isTrue);
      expect(h.http.closeCalls, 1);
      expect(native.calls.where((call) => call == 'close'), hasLength(1));
      expect(native.calls.where((call) => call == 'remove'), isEmpty);
      expect(native.value, isNotNull);
    });

    test(
      'abandoned readonly failure is observed without changing awaiter outcome',
      () async {
        // Given a real accepted scope and native read failures with private markers.
        final h = harness();
        await h.login();
        var errorReleased = false;
        final failureObserved = Completer<void>();
        final scope = h.scope(
          isCurrent: () {
            if (errorReleased && !failureObserved.isCompleted) {
              failureObserved.complete();
            }
            return true;
          },
        );
        final started = Completer<void>();
        final release = Completer<Object?>();
        native.onRead = (_) {
          started.complete();
          return release.future;
        };
        // When the caller abandons one lookup before its native read fails.
        unawaited(_lookup(scope));
        await started.future;
        errorReleased = true;
        release.completeError(
          PlatformException(code: 'unavailable', message: _marker),
        );
        await failureObserved.future;
        await h.backend.close();
        // Then readonly retirement drains normally and is not staged-write failure.
        expect(scope.context.isCurrent, isFalse);
        expect(native.value, isNotNull);
        expect(native.calls.where((call) => call == 'remove'), isEmpty);
        expect(h.http.closeCalls, 0);
      },
    );
  });
}

HttpSubmissionConnection _target({
  String id = 'recipient',
  String endpoint = 'https://recipient.example.test/submission',
  bool authenticated = true,
}) => HttpSubmissionConnection(
  id: id,
  endpoint: Uri.parse(endpoint),
  requiresBearerToken: authenticated,
);

SubmissionAuthenticationBinding _binding({
  String account = _account,
  String profile = 'scope-profile',
  String base = _base,
}) => SubmissionAuthenticationBinding(
  authority: UserAccountHttpProfile(
    profileId: profile,
    serviceBaseUri: Uri.parse(base),
  ),
  userAccountId: account,
);

Future<String?> _lookup(UserAccountSubmissionScope scope) =>
    scope.bearerTokenFor(binding: scope.binding, connection: _target());

Object? _capture(void Function() action) {
  try {
    action();
    return null;
  } catch (error) {
    return error;
  }
}

Future<Object?> _captureAsync<T>(Future<T> Function() action) async {
  try {
    await action();
    return null;
  } catch (error) {
    return error;
  }
}

void _expectUnavailable(Object? error) => expect(
  error,
  isA<StateError>().having(
    (error) => error.message,
    'message',
    'Authenticated submission is unavailable',
  ),
);

void _expectBackendCloseFailure(Object? error) =>
    expect('$error', 'UserAccountAuthenticationFailure(serviceUnavailable)');

Map<String, Object?> _login() => {
  'user_account_id': _account,
  'credential_id': 'synthetic/credential',
  'access_session_id': 'synthetic/access-session-v1',
  'access_token': _access,
  'refresh_session_id': 'synthetic/refresh-session-v1',
  'refresh_token': _refresh,
  'authenticated': true,
};

Map<String, Object?> _rotated() => {
  'user_account_id': _account,
  'access_session_id': 'synthetic/access-session-v2',
  'access_token': 'SYNTHETIC.scope-access-v2=',
  'refresh_session_id': 'synthetic/refresh-session-v2',
  'refresh_token': 'SYNTHETIC.scope-refresh-v2==',
  'authenticated': true,
};

Map<String, Object?> _accountBody() => {
  'id': _account,
  'handle': 'Synthetic label',
};
Uint8List _bytes(Object? value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));
http.StreamedResponse _reply(Object? value, {int status = 200}) =>
    http.StreamedResponse(Stream.value(_bytes(value)), status);

final class _Harness {
  _Harness(this.native, {required this.ownedDefaults}) {
    http = _ControlledHttp();
    final profile = UserAccountHttpProfile(
      profileId: 'scope-profile',
      serviceBaseUri: Uri.parse(_base),
    );
    if (ownedDefaults) {
      backend = _backendWithDefaults(profile, http);
    } else {
      store = NativeAuthenticationCredentialStore();
      backend = UserAccountHttpAuthenticationBackend(
        profile: profile,
        client: http,
        credentialStore: store,
      );
    }
    client = UserAccountAuthenticationClient(backend: backend);
  }

  final _NativeCas native;
  final bool ownedDefaults;
  late final _ControlledHttp http;
  NativeAuthenticationCredentialStore? store;
  late final UserAccountHttpAuthenticationBackend backend;
  late final UserAccountAuthenticationClient client;
  bool expectsCloseFailure = false;

  void loginReplies() {
    http.json(_login());
    http.json(_accountBody());
  }

  Future<void> signIn() =>
      client.signIn(identifier: 'synthetic', password: 'synthetic');
  Future<void> login() async {
    loginReplies();
    await signIn();
    expect(client.snapshot.isAuthenticated, isTrue);
  }

  UserAccountSubmissionScope scope({bool Function()? isCurrent}) =>
      backend.createSubmissionScope(
        trustedTargets: [_target()],
        isRunCurrent: isCurrent ?? () => true,
      );

  Future<void> dispose() async {
    await client.close();
    if (expectsCloseFailure) {
      _expectBackendCloseFailure(await _captureAsync(backend.close));
    } else {
      await backend.close();
    }
    if (!ownedDefaults) {
      await store!.close();
      if (http.closeCalls == 0) http.close();
    }
  }
}

UserAccountHttpAuthenticationBackend _backendWithDefaults(
  UserAccountHttpProfile profile,
  _ControlledHttp transport,
) => http.runWithClient(
  () => UserAccountHttpAuthenticationBackend(profile: profile),
  () => transport,
);

final class _ControlledHttp extends http.BaseClient {
  final requests = <http.BaseRequest>[];
  final _responses =
      <FutureOr<http.StreamedResponse> Function(http.BaseRequest)>[];
  int closeCalls = 0;
  void json(Object? body) => respond((_) => _reply(body));
  void raw(List<int> body) =>
      respond((_) => http.StreamedResponse(Stream.value(body), 200));
  void respond(
    FutureOr<http.StreamedResponse> Function(http.BaseRequest) reply,
  ) {
    _responses.add(reply);
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (_responses.isEmpty) throw StateError('Unexpected synthetic request');
    return await _responses.removeAt(0)(request);
  }

  @override
  void close() {
    closeCalls++;
  }
}

final class _NativeCas {
  final calls = <String>[];
  Uint8List? value;
  String? revision;
  int sequence = 100;
  FutureOr<Object?> Function(Map)? onRead;
  FutureOr<Object?> Function(Map)? onReplace;
  FutureOr<Object?> Function(Map)? onRemove;
  FutureOr<Object?> Function(Map)? onClose;

  Map<String, dynamic> document() =>
      jsonDecode(utf8.decode(value!)) as Map<String, dynamic>;
  Object? read() => value == null
      ? null
      : {'revision': revision, 'value': Uint8List.fromList(value!)};
  Object? replace(Map args) {
    if (args['expectedRevision'] != revision) return null;
    value = Uint8List.fromList(args['value'] as Uint8List);
    revision = (++sequence).toRadixString(16).padLeft(32, '0');
    return revision;
  }

  Object? remove(Map args) {
    if (value == null || args['expectedRevision'] != revision) return false;
    value = null;
    revision = null;
    return true;
  }

  Future<Object?> handle(MethodCall call) async {
    calls.add(call.method);
    final args = call.arguments as Map;
    return switch (call.method) {
      'read' => onRead == null ? read() : await onRead!(args),
      'replace' => onReplace == null ? replace(args) : await onReplace!(args),
      'remove' => onRemove == null ? remove(args) : await onRemove!(args),
      'close' => onClose == null ? null : await onClose!(args),
      _ => throw StateError('Unexpected synthetic native operation'),
    };
  }
}

final class _IteratedTargets extends IterableBase<HttpSubmissionConnection> {
  _IteratedTargets(this._iterator);
  final Iterator<HttpSubmissionConnection> Function() _iterator;
  @override
  Iterator<HttpSubmissionConnection> get iterator => _iterator();
}

/// Only delays a real backend candidate; it never issues identity or credentials.
final class _CandidateBridge implements UserAccountAuthenticationBackend {
  _CandidateBridge(this.backend);
  final UserAccountHttpAuthenticationBackend backend;
  final ready = Completer<void>();
  final release = Completer<void>();
  @override
  Future<UserAccountSignInResult> signIn({
    required String identifier,
    required String password,
    required UserAccountAuthenticationOperation operation,
  }) async {
    final result = await backend.signIn(
      identifier: identifier,
      password: password,
      operation: operation,
    );
    ready.complete();
    await release.future;
    return result;
  }

  @override
  Future<UserAccountSignInResult> verifyChallenge({
    required String challengeId,
    required String code,
    required UserAccountAuthenticationOperation operation,
  }) => backend.verifyChallenge(
    challengeId: challengeId,
    code: code,
    operation: operation,
  );
  @override
  Future<UserAccountSignInResult> refresh({
    required UserAccountAuthenticationOperation operation,
  }) => backend.refresh(operation: operation);
  @override
  Future<UserAccountLogoutResult> signOut({
    required UserAccountAuthenticationOperation operation,
  }) => backend.signOut(operation: operation);
  @override
  Future<void> close() => backend.close();
}
