import 'dart:async';
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
const _base = 'https://account.example.test/rest/v1/user-account/user/';
const _account = ' synthetic/account:α ';
const _credential = 'synthetic/credential';
const _access = 'SYNTHETIC.access-v1=';
const _refresh = 'SYNTHETIC.refresh-v1==';
const _revision = '11111111111111111111111111111111';
const _newOwnerRevision = '22222222222222222222222222222222';

// Independently authored synthetic authority fixtures; no execution captures.
Map<String, Object?> _login({String account = _account}) => {
  'user_account_id': account,
  'credential_id': _credential,
  'access_session_id': 'synthetic/access-session-v1',
  'access_token': _access,
  'refresh_session_id': 'synthetic/refresh-session-v1',
  'refresh_token': _refresh,
  'authenticated': true,
};
Map<String, Object?> _rotated({String account = _account}) => {
  'user_account_id': account,
  'access_session_id': 'synthetic/access-session-v2',
  'access_token': 'SYNTHETIC.access-v2=',
  'refresh_session_id': 'synthetic/refresh-session-v2',
  'refresh_token': 'SYNTHETIC.refresh-v2==',
  'authenticated': true,
};
Map<String, Object?> _challenge() => {
  'user_account_id': _account,
  'credential_id': _credential,
  'two_factor_required': true,
  'challenge_id': 'synthetic/challenge',
  'channel': 'email',
  'authenticated': false,
};
Map<String, Object?> _accountBody({String id = _account}) => {
  'id': id,
  'handle': 'Authoritative synthetic handle',
  'owner_id': 'unrelated-owner',
  'publicPrincipalId': 'unrelated-principal',
  'email': 'unrelated@example.test',
};
Map<String, Object?> _record({
  String profile = 'test-profile',
  String authority = _base,
  String writeId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
}) => {
  'schemaVersion': 1,
  'profileId': profile,
  'authorityBaseUri': authority,
  'userAccountId': _account,
  'accessSessionId': 'synthetic/access-session-v1',
  'accessToken': _access,
  'refreshSessionId': 'synthetic/refresh-session-v1',
  'refreshToken': _refresh,
  'writeId': writeId,
};
Uint8List _bytes(Object? value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));
http.StreamedResponse _reply(Object? value, {int status = 200}) =>
    http.StreamedResponse(Stream.value(_bytes(value)), status);
http.StreamedResponse _raw(List<int> value, {int status = 200}) =>
    http.StreamedResponse(Stream.value(value), status);

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

  _Harness harness({Duration? timeout, bool registerCleanup = true}) {
    final h = _Harness(native, timeout: timeout);
    if (registerCleanup) {
      addTearDown(() async {
        await h.client.close();
        await h.backend.close();
        await h.store.close();
      });
    }
    return h;
  }

  group('explicit authority profile and inert ownership', () {
    test('constructors have no HTTP or native IO and safe diagnostics', () async {
      // Given the real backend and real native-store port with borrowed handles.
      final h = harness();
      // When construction state and diagnostic values are observed.
      expect(h.client.canRestore, isTrue);
      expect(h.backend.profile.requestTimeout, const Duration(seconds: 15));
      // Then no network/storage action occurs or sensitive binding is printed.
      expect(native.calls, isEmpty);
      expect(h.http.requests, isEmpty);
      expect('${h.backend}', 'UserAccountHttpAuthenticationBackend');
      expect('${h.backend.profile}', 'UserAccountHttpProfile');
      await h.client.close();
      expect(h.http.closed, isFalse);
      expect(native.calls, isEmpty);
    });

    for (final host in [
      'localhost',
      '127.0.0.1',
      '127.42.1.9',
      '[::1]',
      '10.20.30.40',
      '172.16.0.1',
      '172.31.255.254',
      '192.168.1.2',
    ]) {
      test('development HTTP explicitly admits literal $host', () {
        // Given an explicit development-only loopback or private authority.
        final uri = Uri.parse('http://$host:8080/rest/user');
        // When HTTP is opted in and the base is normalized.
        final profile = UserAccountHttpProfile(
          profileId: 'test-profile',
          serviceBaseUri: uri,
          allowDevelopmentHttp: true,
        );
        // Then the binding adds one trailing slash without contacting it.
        expect(
          profile.serviceBaseUri.toString(),
          'http://$host:8080/rest/user/',
        );
        expect(native.calls, isEmpty);
      });
    }

    for (final uri in [
      'http://account.example.test/user/',
      'http://10.example.test/user/',
      'http://8.8.8.8/user/',
      'http://172.15.0.1/user/',
      'http://172.32.0.1/user/',
      'http://192.169.0.1/user/',
      'http://100.64.0.1/user/',
      'http://0.0.0.0/user/',
      'https://user:synthetic-secret@account.example.test/user/',
      'https://account.example.test/user/?token=synthetic-secret',
      'https://account.example.test/user/#synthetic-secret',
      'https://account.example.test/user/./',
      'https://account.example.test/user/../',
      'https://account.example.test/user/%2e/',
      'https://account.example.test/user/%2e%2e/',
      'https://account.example.test/user/.%2e/',
      'https://account.example.test/user/%2E./',
      'https://account.example.test/user/%2fsecret/',
      'https://account.example.test/user/%5csecret/',
      'https://account.example.test/user/%00/',
      'https://account.example.test/user/%1f/',
      'https://account.example.test/user/%7f/',
      'https://account.example.test/user/\\secret/',
      'https://account.example.test/user/\u0000/',
      'https://account.example.test/user/\u007f/',
      'ftp://account.example.test/user/',
      '/relative/user/',
    ]) {
      test('unsafe authority binding is rejected safely ($uri)', () {
        // Given an insecure, traversing or credential-bearing binding.
        // When the profile is constructed even with development HTTP enabled.
        Object? failure;
        try {
          UserAccountHttpProfile.fromString(
            profileId: 'test-profile',
            serviceBaseUri: uri,
            allowDevelopmentHttp: true,
          );
        } catch (error) {
          failure = error;
        }
        // Then only the fixed safe argument diagnostic is exposed, with no IO.
        expect(failure, isArgumentError);
        expect(
          '$failure',
          'Invalid argument(s): Invalid authentication profile',
        );
        expect(native.calls, isEmpty);
      });
    }

    test('raw HTTPS configuration normalizes safe paths without IO', () {
      // Given safe raw bindings with a port, escaped path colon and a root base.
      const raw = 'https://account.example.test:8443/rest/user%3Aaccount///';
      // When raw configuration is admitted before URI normalization.
      final profile = UserAccountHttpProfile.fromString(
        profileId: 'test-profile',
        serviceBaseUri: raw,
      );
      final root = UserAccountHttpProfile.fromString(
        profileId: 'test-profile',
        serviceBaseUri: 'https://account.example.test',
      );
      // Then safe escaped characters survive with one trailing slash and no IO.
      expect(
        profile.serviceBaseUri.toString(),
        'https://account.example.test:8443/rest/user%3Aaccount/',
      );
      expect(profile.requestTimeout, const Duration(seconds: 15));
      expect(root.serviceBaseUri.toString(), 'https://account.example.test/');
      expect(native.calls, isEmpty);
    });

    test('explicit canonical Uri binding accepts already normalized input', () {
      // Given a trusted caller's Uri whose original traversal syntax was erased.
      final canonical = Uri.parse('https://account.example.test/user/%2e%2e/');
      // When that already-parsed canonical binding uses the original entry point.
      final profile = UserAccountHttpProfile(
        profileId: 'test-profile',
        serviceBaseUri: canonical,
      );
      // Then only the supplied canonical URI is bound, without recovering raw syntax.
      expect(canonical.path, '/');
      expect(profile.serviceBaseUri, canonical);
      expect(native.calls, isEmpty);
    });

    test('default HTTP, slot syntax and timeout bounds fail before IO', () {
      // Given otherwise valid profiles with one invalid configuration value.
      final actions = <void Function()>[
        () {
          UserAccountHttpProfile(
            profileId: 'test-profile',
            serviceBaseUri: Uri.parse('http://127.0.0.1/user/'),
          );
        },
        for (final id in ['', '.slot', 'slot/secret', 'slot\n', 'é', 'a' * 129])
          () {
            UserAccountHttpProfile(
              profileId: id,
              serviceBaseUri: Uri.parse(_base),
            );
          },
        for (final timeout in [
          Duration.zero,
          const Duration(microseconds: -1),
          const Duration(seconds: 61),
        ])
          () {
            UserAccountHttpProfile(
              profileId: 'test-profile',
              serviceBaseUri: Uri.parse(_base),
              requestTimeout: timeout,
            );
          },
      ];
      // When each invalid configuration is constructed.
      for (final action in actions) {
        expect(action, throwsArgumentError);
      }
      // Then no native call has been accepted.
      expect(native.calls, isEmpty);
    });
  });

  group('real login, account proof and native publication', () {
    test(
      'login account proof precedes CAS and authenticated publication',
      () async {
        // Given synthetic login and authoritative account responses.
        final h = harness()..loginReplies();
        final observations = <UserAccountAuthenticationSnapshot>[];
        h.client.addListener(() {
          observations.add(h.client.snapshot);
          if (h.client.snapshot.isAuthenticated) {
            expect(native.value, isNotNull);
            native.events.add('published');
          }
        });
        // When the real client signs in using exact supplied input bytes.
        await h.client.signIn(
          identifier: ' identifier \n',
          password: ' password \t',
        );
        // Then the requests use the selected base, fixed selectors and ACCESS only.
        expect(h.http.requests, hasLength(2));
        final login = h.http.requests[0];
        expect(login.url.toString(), '${_base}login');
        expect(login.method, 'POST');
        expect(jsonDecode(login.body), {
          'identifier': ' identifier \n',
          'password': ' password \t',
        });
        _unprotected(login);
        final get = h.http.requests[1];
        expect(get.url.toString(), '${_base}get-my-account');
        expect(get.method, 'GET');
        expect(get.bodyBytes, isEmpty);
        expect(get.headers['Authorization'], 'Bearer $_access');
        expect(get.headers.containsKey('Cookie'), isFalse);
        expect(h.client.snapshot.account!.userAccountId, _account);
        expect(
          h.client.snapshot.account!.displayName,
          'Authoritative synthetic handle',
        );
        expect(
          native.events.indexOf('http:get-my-account'),
          lessThan(native.events.indexOf('native:replace')),
        );
        expect(
          native.events.indexOf('native:replace'),
          lessThan(native.events.indexOf('published')),
        );
        final stored =
            jsonDecode(utf8.decode(native.value!)) as Map<String, dynamic>;
        expect(stored.keys.toSet(), {
          'schemaVersion',
          'profileId',
          'authorityBaseUri',
          'userAccountId',
          'accessSessionId',
          'accessToken',
          'refreshSessionId',
          'refreshToken',
          'writeId',
        });
        expect(stored['authorityBaseUri'], _base);
        expect(stored['writeId'], matches(RegExp(r'^[0-9a-f]{32}$')));
        expect(stored.containsKey('credentialId'), isFalse);
        for (final snapshot in observations) {
          for (final secret in [_access, _refresh, _credential, ' password ']) {
            expect('$snapshot', isNot(contains(secret)));
          }
        }
        // Normal operation retirement and close preserve accepted credentials.
        final saved = native.value;
        await h.client.close();
        expect(native.value, saved);
        expect(native.calls.where((c) => c == 'remove'), isEmpty);
      },
    );

    test(
      'account handle is optional and no other attribute supplies a label',
      () async {
        // Given a valid pair and an account root containing only unrelated labels.
        final h = harness();
        h.http.json(_login());
        h.http.json({
          'id': _account,
          'name': 'ignore',
          'email': 'ignore@example.test',
        });
        // When that account is verified through its ACCESS token.
        await h.signIn();
        // Then identity stays exact and displayName has no request/email fallback.
        expect(h.client.snapshot.account!.userAccountId, _account);
        expect(h.client.snapshot.account!.displayName, isNull);
      },
    );

    test(
      'a rejected replacement cannot restore the former cached login',
      () async {
        // Given a matching old protected record and a refused explicit replacement.
        native.seed(_record());
        final h = harness();
        h.http.json({'ignored': 'private error body'}, status: 401);
        // When new credentials are submitted.
        await h.signIn();
        // Then only the read revision was removed before login and no old login remains.
        expect(native.value, isNull);
        expect(
          native.events.indexOf('native:remove'),
          lessThan(native.events.indexOf('http:login')),
        );
        expect(
          h.client.snapshot.failure,
          UserAccountAuthenticationFailure.invalidCredentials,
        );
        expect(native.calls.where((c) => c == 'replace'), isEmpty);
        await h.client.restore();
        expect(
          h.client.snapshot.status,
          UserAccountAuthenticationStatus.signedOut,
        );
        expect(h.http.requests, hasLength(1));
      },
    );

    test(
      'new slot owner prevents explicit replacement before credential send',
      () async {
        // Given an old record whose CAS ownership changes at removal.
        native.seed(_record());
        native.onRemove = (arguments) async {
          native.seed(
            _record(writeId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
            revision: _newOwnerRevision,
          );
          return false;
        };
        final h = harness();
        // When explicit login attempts to withdraw the old revision.
        await h.signIn();
        // Then the new owner is retained and no password leaves the client.
        expect(native.revision, _newOwnerRevision);
        expect(h.http.requests, isEmpty);
        expect(
          h.client.snapshot.failure,
          UserAccountAuthenticationFailure.serviceUnavailable,
        );
      },
    );
  });

  group('private email challenge binding', () {
    test(
      'challenge performs no account lookup or write before exact verification',
      () async {
        // Given an email challenge followed by a seven-key verification pair.
        final h = harness();
        h.http.json(_challenge());
        await h.signIn();
        expect(
          h.client.snapshot.status,
          UserAccountAuthenticationStatus.challengeRequired,
        );
        expect(native.calls, ['read']);
        expect(h.http.requests, hasLength(1));
        h.loginReplies();
        // When the exact challenge reference and supplied code are verified.
        await h.client.verifyChallenge(' 123 456 ');
        // Then verification is unprotected, account proof precedes the only write.
        expect(h.client.snapshot.isAuthenticated, isTrue);
        final verify = h.http.requests[1];
        expect(verify.url.toString(), '${_base}verify-two-factor-login');
        expect(jsonDecode(verify.body), {
          'challengeId': 'synthetic/challenge',
          'code': ' 123 456 ',
        });
        _unprotected(verify);
        expect(native.calls.where((c) => c == 'replace'), hasLength(1));
      },
    );

    for (final variation in [
      'account',
      'credential',
      'challenge',
      'missing',
      'extra',
    ]) {
      test(
        'verification refuses incompatible $variation response before account IO',
        () async {
          // Given a retained expected account, credential and challenge reference.
          final h = harness();
          h.http.json(_challenge());
          await h.signIn();
          final document = switch (variation) {
            'account' => _login(account: 'synthetic/different-account'),
            'credential' =>
              _login()..['credential_id'] = 'synthetic/different-credential',
            'challenge' => _challenge(),
            'missing' => _login()..remove('credential_id'),
            _ => _login()..['extra'] = 'synthetic',
          };
          h.http.json(document);
          // When the one-use verification result is consumed.
          await h.client.verifyChallenge('code');
          // Then no account request or credential write is admitted.
          expect(
            h.client.snapshot.failure,
            UserAccountAuthenticationFailure.invalidResponse,
          );
          expect(h.http.requests, hasLength(2));
          expect(native.value, isNull);
          await expectLater(
            h.client.verifyChallenge('again'),
            throwsStateError,
          );
        },
      );
    }

    test(
      'backend rejects a wrong challenge ID and consumes its pending challenge',
      () async {
        // Given a real client challenge and its operation captured at the port boundary.
        final h = harness();
        final bridge = _OperationBridge(h.backend);
        final client = UserAccountAuthenticationClient(backend: bridge);
        addTearDown(client.close);
        h.http.json(_challenge());
        await client.signIn(identifier: 'id', password: 'pw');
        bridge.replaceChallenge = true;
        // When verification is presented with a different opaque challenge ID.
        await client.verifyChallenge('code');
        // Then no verification HTTP or write is attempted.
        expect(
          client.snapshot.failure,
          UserAccountAuthenticationFailure.challengeRejected,
        );
        expect(h.http.requests, hasLength(1));
        expect(native.value, isNull);
      },
    );
  });

  group('rotation and explicit restart restoration', () {
    test(
      'explicit refresh removes own record before body-only refresh rotation',
      () async {
        // Given a genuinely accepted pair in protected storage.
        final h = harness()..loginReplies();
        await h.signIn();
        final originalRevision = native.revision;
        h.http.json(_rotated());
        h.http.json(_accountBody());
        // When explicit refresh rotates that exact owned pair.
        await h.client.refresh();
        // Then the old refresh token is body-only and the new ACCESS proves the same account.
        final refresh = h.http.requests[2];
        expect(refresh.url.toString(), '${_base}refresh-access-token');
        expect(jsonDecode(refresh.body), {'refreshToken': _refresh});
        _unprotected(refresh);
        expect(
          native.events.indexOf('native:remove'),
          lessThan(native.events.indexOf('http:refresh-access-token')),
        );
        expect(
          h.http.requests[3].headers['Authorization'],
          'Bearer SYNTHETIC.access-v2=',
        );
        expect(native.revision, isNot(originalRevision));
        expect(h.client.snapshot.isAuthenticated, isTrue);
        expect(h.client.snapshot.account!.userAccountId, _account);
      },
    );

    for (final refusal in ['401', '403', 'account', 'credential-extra']) {
      test('refresh $refusal never reactivates the old pair', () async {
        // Given an accepted old pair and a rejected or mismatched rotation.
        final h = harness()..loginReplies();
        await h.signIn();
        if (refusal == '401' || refusal == '403') {
          h.http.json({
            'private': 'synthetic refusal',
          }, status: int.parse(refusal));
        } else if (refusal == 'account') {
          h.http.json(_rotated(account: 'synthetic/other-account'));
        } else {
          h.http.json({..._rotated(), 'credential_id': _credential});
        }
        // When refresh withdraws the old record and consumes that response.
        await h.client.refresh();
        // Then no old credentials remain usable or restorable and logout has no active pair.
        expect(h.client.snapshot.isAuthenticated, isFalse);
        expect(native.value, isNull);
        final result = await h.client.signOut();
        expect(
          result.remoteRevocation,
          UserAccountRemoteRevocation.notAttempted,
        );
        expect(h.http.requests, hasLength(3));
      });
    }

    test(
      'absent restore is explicit, signed-out and performs no HTTP/write',
      () async {
        // Given an empty native slot and an inert real client/backend.
        final h = harness();
        // When restoration is explicitly requested.
        await h.client.restore();
        // Then disk absence means ordinary signed-out, not successful authentication.
        expect(
          h.client.snapshot.status,
          UserAccountAuthenticationStatus.signedOut,
        );
        expect(h.client.snapshot.failure, isNull);
        expect(native.calls, ['read']);
        expect(h.http.requests, isEmpty);
      },
    );

    test('restart restores only after actual account proof without rewriting baseline', () async {
      // Given a retained accepted record and a new client/backend lifetime.
      final first = harness()..loginReplies();
      await first.signIn();
      final retainedRevision = native.revision;
      await first.client.close();
      native.calls.clear();
      final second = harness();
      second.http.json({'id': _account, 'handle': 'Fresh server label'});
      // When the restarted client explicitly restores.
      await second.client.restore();
      // Then ACCESS proves the account and persist rereads the unchanged original revision.
      expect(
        second.http.requests.single.url.toString(),
        '${_base}get-my-account',
      );
      expect(
        second.http.requests.single.headers['Authorization'],
        'Bearer $_access',
      );
      expect(second.client.snapshot.account!.displayName, 'Fresh server label');
      expect(native.calls, ['read', 'read']);
      expect(native.revision, retainedRevision);
    });

    test(
      'restore access 401 conditionally withdraws old pair then refreshes once',
      () async {
        // Given a matching stored pair whose access session is refused.
        native.seed(_record());
        final h = harness();
        h.http.json(null, status: 401);
        h.http.json(_rotated());
        h.http.json(_accountBody());
        // When explicit restore encounters the expired access session.
        await h.client.restore();
        // Then only one refresh occurs after old-record removal and new access proof.
        expect(h.http.requests.map((r) => r.url.pathSegments.last), [
          'get-my-account',
          'refresh-access-token',
          'get-my-account',
        ]);
        expect(
          native.events.indexOf('native:remove'),
          lessThan(native.events.indexOf('http:refresh-access-token')),
        );
        expect(h.client.snapshot.isAuthenticated, isTrue);
        expect(native.revision, isNot(_revision));
      },
    );

    for (final failure in ['503', 'transport', '403', 'changed-account']) {
      test(
        'restore $failure fails closed with truthful record retention',
        () async {
          // Given a matching record and an authority/transport refusal.
          native.seed(_record());
          final h = harness();
          switch (failure) {
            case 'transport':
              h.http.respond(
                (_) => throw StateError('synthetic private transport'),
              );
            case 'changed-account':
              h.http.json(_accountBody(id: 'synthetic/other-account'));
            default:
              h.http.json({
                'private': 'synthetic body',
              }, status: int.parse(failure));
          }
          // When restoration validates the stored ACCESS against the server.
          await h.client.restore();
          // Then no account is published; only an identified invalid own 403 is removed.
          expect(h.client.snapshot.isAuthenticated, isFalse);
          expect(h.http.requests, hasLength(1));
          expect(native.value == null, failure == '403');
          expect(native.calls.where((c) => c == 'replace'), isEmpty);
        },
      );
    }

    for (final variant in [
      'profile',
      'authority',
      'extra',
      'version',
      'bad-token',
      'malformed-json',
    ]) {
      test(
        'foreign or malformed $variant record is retained without HTTP',
        () async {
          // Given bytes that cannot be adopted under the explicit profile authority.
          final document = switch (variant) {
            'profile' => _record(profile: 'foreign-profile'),
            'authority' => _record(
              authority: 'https://foreign.example.test/user/',
            ),
            'extra' => _record()..['displayName'] = 'untrusted',
            'version' => _record()..['schemaVersion'] = 2,
            'bad-token' => _record()..['accessToken'] = 'synthetic token',
            _ => _record(),
          };
          native.seed(document);
          if (variant == 'malformed-json') {
            native.value = Uint8List.fromList([123]);
          }
          final saved = native.value;
          final h = harness();
          // When restoration and then local logout inspect those bytes.
          await h.client.restore();
          final logout = await h.client.signOut();
          // Then neither HTTP nor removal trusts those records as an account or owner.
          expect(h.http.requests, isEmpty);
          expect(native.value, saved);
          expect(logout.localCleared, isFalse);
          expect(
            logout.remoteRevocation,
            UserAccountRemoteRevocation.notAttempted,
          );
          expect(
            native.calls.where((c) => c == 'remove' || c == 'replace'),
            isEmpty,
          );
        },
      );
    }
  });

  group('retirement, staged publication and CAS ownership', () {
    for (final command in ['cancel', 'close']) {
      test('$command before invoke prevents all IO', () async {
        // Given a listener retiring the client on its initial signing-in notification.
        final h = harness();
        Future<void>? retirement;
        h.client.addListener(() {
          if (h.client.snapshot.status ==
              UserAccountAuthenticationStatus.signingIn) {
            retirement = command == 'cancel'
                ? h.client.cancel()
                : h.client.close();
          }
        });
        // When sign-in reserves ownership before invoking the real backend.
        await h.signIn();
        await retirement;
        // Then retired work never reaches HTTP or native storage.
        expect(h.http.requests, isEmpty);
        expect(native.calls, isEmpty);
        expect(h.client.snapshot.isAuthenticated, isFalse);
      });

      test(
        '$command during account lookup aborts and ignores a late injected reply',
        () async {
          // Given a transport which deliberately ignores the account request abort.
          final h = harness();
          final late = Completer<http.StreamedResponse>();
          final cancelledBody = Completer<void>();
          final body = StreamController<List<int>>(
            onCancel: () {
              cancelledBody.complete();
            },
          );
          h.http.json(_login());
          h.http.respond((_) => late.future);
          final signingIn = h.signIn();
          final accountRequest = await h.http.requestAt(1);
          // When retirement happens before that response arrives.
          final retiring = command == 'cancel'
              ? h.client.cancel()
              : h.client.close();
          await accountRequest.abortTrigger;
          await signingIn;
          await retiring;
          late.complete(http.StreamedResponse(body.stream, 200));
          await cancelledBody.future;
          await body.close();
          // Then the late stream is observed/cancelled with no write/publication/next request.
          expect(native.calls.where((c) => c == 'replace'), isEmpty);
          expect(h.http.requests, hasLength(2));
          expect(h.client.snapshot.isAuthenticated, isFalse);
        },
      );

      test(
        '$command during native replace drains own late-write rollback',
        () async {
          // Given a native CAS which has been accepted but not yet returned.
          final h = harness()..loginReplies();
          final writeStarted = Completer<void>();
          final releaseWrite = Completer<void>();
          native.onReplace = (args) async {
            writeStarted.complete();
            await releaseWrite.future;
            return native.replace(args);
          };
          final signingIn = h.signIn();
          await writeStarted.future;
          // When retirement occurs while the write is in flight.
          final retiring = command == 'cancel'
              ? h.client.cancel()
              : h.client.close();
          var drained = false;
          retiring.then((_) {
            drained = true;
          });
          await expectLater(h.signIn(), throwsStateError);
          expect(drained, isFalse);
          releaseWrite.complete();
          await signingIn;
          await retiring;
          // Then its returned revision is conditionally removed before retirement completes.
          expect(native.value, isNull);
          expect(native.calls.where((c) => c == 'remove'), hasLength(1));
          expect(h.client.snapshot.isAuthenticated, isFalse);
          expect(native.calls, isNot(contains('clear')));
        },
      );
    }

    test(
      'retired cleanup failure blocks cancellation until exact logout recovery',
      () async {
        // Given a real login held in native replace and an unavailable own rollback.
        final h = harness(registerCleanup: false)..loginReplies();
        var recovered = false;
        addTearDown(h.http.close);
        addTearDown(h.store.close);
        addTearDown(() async {
          if (recovered) {
            await h.backend.close();
          } else {
            await expectLater(h.backend.close(), _backendCleanupFailure());
          }
        });
        addTearDown(() async {
          if (recovered) {
            await h.client.close();
          } else {
            await expectLater(h.client.close(), _closeFailure());
          }
        });
        final started = Completer<void>();
        final release = Completer<void>();
        native.onReplace = (args) async {
          started.complete();
          await release.future;
          return native.replace(args);
        };
        native.onRemove = (_) async => throw PlatformException(
          code: 'unavailable',
          message: 'synthetic private rollback failure',
        );
        final signingIn = h.signIn();
        await started.future;
        // When cancellation joins the late write, with its error observed before release.
        final cancelling = expectLater(h.client.cancel(), _cleanupFailure());
        expect(h.client.snapshot.account, isNull);
        release.complete();
        await signingIn;
        await cancelling;
        // Then unresolved cleanup is observable and neither entry point can revive it.
        expect(
          h.client.snapshot.status,
          UserAccountAuthenticationStatus.failure,
        );
        expect(
          h.client.snapshot.failure,
          UserAccountAuthenticationFailure.serviceUnavailable,
        );
        expect(h.client.snapshot.account, isNull);
        expect(h.client.snapshot.lastLogoutResult?.localCleared, isFalse);
        expect(
          h.client.snapshot.lastLogoutResult?.remoteRevocation,
          UserAccountRemoteRevocation.notAttempted,
        );
        expect(h.client.canRestore, isFalse);
        final ownBytes = Uint8List.fromList(native.value!);
        final ownRevision = native.revision;
        final callsBeforeBlocked = List<String>.of(native.calls);
        await expectLater(h.signIn(), throwsStateError);
        await expectLater(h.client.restore(), throwsStateError);
        expect(native.calls, callsBeforeBlocked);
        expect(native.value, ownBytes);
        expect(native.calls.where((call) => call == 'remove'), hasLength(1));
        expect(native.calls, isNot(contains('clear')));
        expect(h.http.requests, hasLength(2));

        // Given another client with no presentation barrier borrowing the same backend.
        final probe = UserAccountAuthenticationClient(backend: h.backend);
        addTearDown(probe.close);
        // When direct login and restoration reach that unresolved real backend.
        await probe.signIn(
          identifier: 'synthetic-id',
          password: 'synthetic-password',
        );
        await probe.restore();
        // Then the backend rejects both before storage or account HTTP.
        expect(
          probe.snapshot.failure,
          UserAccountAuthenticationFailure.serviceUnavailable,
        );
        expect(probe.snapshot.account, isNull);
        expect(native.calls, callsBeforeBlocked);
        expect(h.http.requests, hasLength(2));

        // Given native removal has recovered without replacing the owned bytes.
        Object? retryRevision;
        native.onRemove = (args) async {
          retryRevision = args['expectedRevision'];
          return native.remove(args);
        };
        // When explicit logout retries the retained exact ownership witness.
        final retry = await h.client.signOut();
        recovered = retry.localCleared;
        // Then only that revision is removed, barriers clear and no remote logout is sent.
        expect(retry.localCleared, isTrue);
        expect(
          retry.remoteRevocation,
          UserAccountRemoteRevocation.notAttempted,
        );
        expect(retryRevision, ownRevision);
        expect(native.value, isNull);
        expect(native.revision, isNull);
        expect(native.calls.where((call) => call == 'remove'), hasLength(2));
        expect(native.calls, isNot(contains('clear')));
        expect(
          h.client.snapshot.status,
          UserAccountAuthenticationStatus.signedOut,
        );
        expect(h.client.canRestore, isTrue);
        expect(
          h.http.requests.map((request) => request.url.pathSegments.last),
          ['login', 'get-my-account'],
        );
        // When the recovered client closes normally.
        await h.client.close();
        // Then successful explicit cleanup leaves no delayed close failure.
        expect(h.client.isClosed, isTrue);
      },
    );

    test(
      'retired cleanup failure closes default owned handles exactly once',
      () async {
        // Given omitted HTTP/store dependencies, controlled at their actual default seams.
        final transport = _ControlledHttp(native.events)
          ..json(_login())
          ..json(_accountBody());
        final backend = http.runWithClient(
          () => UserAccountHttpAuthenticationBackend(
            profile: UserAccountHttpProfile(
              profileId: 'test-profile',
              serviceBaseUri: Uri.parse(_base),
            ),
          ),
          () => transport,
        );
        final client = UserAccountAuthenticationClient(
          backend: backend,
          ownsBackend: true,
        );
        addTearDown(() async {
          await expectLater(backend.close(), _backendCleanupFailure());
        });
        addTearDown(() async {
          await expectLater(client.close(), _closeFailure());
        });
        final started = Completer<void>();
        final release = Completer<void>();
        native.onReplace = (args) async {
          started.complete();
          await release.future;
          return native.replace(args);
        };
        native.onRemove = (_) async =>
            throw PlatformException(code: 'unavailable');
        final signingIn = client.signIn(
          identifier: 'synthetic-id',
          password: 'synthetic-password',
        );
        await started.future;
        // When owned close retires authentication before the late write fails cleanup.
        final closing = client.close();
        final failedClose = expectLater(closing, _closeFailure());
        final closedRevision = client.snapshot.revision;
        var lateNotifications = 0;
        client.addListener(() {
          lateNotifications++;
        });
        expect(client.snapshot.status, UserAccountAuthenticationStatus.closed);
        release.complete();
        await signingIn;
        await failedClose;
        // Then the safe close failure still releases each owned handle once.
        expect(transport.closeCalls, 1);
        expect(native.calls.where((call) => call == 'close'), hasLength(1));
        expect(native.calls.where((call) => call == 'remove'), hasLength(1));
        expect(native.value, isNotNull);
        final retained = Uint8List.fromList(native.value!);
        final callsAfterClose = List<String>.of(native.calls);
        expect(client.snapshot.account, isNull);
        expect(client.canRestore, isFalse);
        expect(client.snapshot.revision, closedRevision);
        expect(lateNotifications, 0);
        // When the same close outcome and closed commands are requested again.
        expect(identical(client.close(), closing), isTrue);
        await expectLater(client.close(), _closeFailure());
        await expectLater(client.restore(), throwsStateError);
        await expectLater(
          client.signIn(identifier: 'id', password: 'pw'),
          throwsStateError,
        );
        // Then retained bytes are reported honestly without extra cleanup or revocation.
        expect(native.calls, callsAfterClose);
        expect(native.value, retained);
        expect(transport.closeCalls, 1);
        expect(native.calls, isNot(contains('clear')));
        expect(
          transport.requests.map((request) => request.url.pathSegments.last),
          ['login', 'get-my-account'],
        );
        expect(client.snapshot.status, UserAccountAuthenticationStatus.closed);
        expect(client.snapshot.revision, closedRevision);
        expect(lateNotifications, 0);
      },
    );

    test('retired cleanup failure retry preserves a competing owner installed during removal', () async {
      // Given a deferred own write and owner B arriving during its failing rollback.
      final h = harness(registerCleanup: false)..loginReplies();
      addTearDown(h.http.close);
      addTearDown(h.store.close);
      addTearDown(() async {
        await expectLater(h.backend.close(), _backendCleanupFailure());
      });
      addTearDown(() async {
        await expectLater(h.client.close(), _closeFailure());
      });
      final replacement = {
        ..._record(writeId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
        'userAccountId': 'synthetic/replacement-account',
      };
      final started = Completer<void>();
      final release = Completer<void>();
      native.onReplace = (args) async {
        started.complete();
        await release.future;
        return native.replace(args);
      };
      Object? rollbackRevision;
      native.onRemove = (args) async {
        rollbackRevision = args['expectedRevision'];
        native.seed(replacement, revision: _newOwnerRevision);
        throw PlatformException(code: 'unavailable');
      };
      final signingIn = h.signIn();
      await started.future;
      // When cancellation drains that failed rollback and explicitly reports its failure.
      final cancelling = expectLater(h.client.cancel(), _cleanupFailure());
      release.complete();
      await signingIn;
      await cancelling;
      // Then A remains withdrawn and the known failure does not authenticate B.
      expect(rollbackRevision, isNot(_newOwnerRevision));
      expect(rollbackRevision, isNotNull);
      expect(h.client.snapshot.status, UserAccountAuthenticationStatus.failure);
      expect(
        h.client.snapshot.failure,
        UserAccountAuthenticationFailure.serviceUnavailable,
      );
      expect(h.client.snapshot.lastLogoutResult?.localCleared, isFalse);
      expect(h.client.snapshot.account, isNull);
      expect(h.client.canRestore, isFalse);
      native.onRemove = null;
      // When removal recovers and explicit logout retries A's exact witness.
      final retry = await h.client.signOut();
      // Then B survives with no CAS attempt against B and no Bearer revocation request.
      expect(retry.localCleared, isFalse);
      expect(retry.remoteRevocation, UserAccountRemoteRevocation.notAttempted);
      expect(native.value, _bytes(replacement));
      expect(native.revision, _newOwnerRevision);
      expect(native.calls.where((call) => call == 'remove'), hasLength(1));
      final callsBeforeBlocked = List<String>.of(native.calls);
      await expectLater(h.signIn(), throwsStateError);
      await expectLater(h.client.restore(), throwsStateError);
      expect(native.calls, callsBeforeBlocked);
      expect(native.calls, isNot(contains('clear')));
      expect(h.http.requests.map((request) => request.url.pathSegments.last), [
        'login',
        'get-my-account',
      ]);
      expect(h.client.snapshot.account, isNull);
    });

    for (final owner in ['same', 'newer']) {
      test(
        'retired cleanup failure retains indeterminate write ownership for $owner owner retry',
        () async {
          // Given a real deferred write that mutates disk, then loses both its reply and rollback read.
          final h = harness(registerCleanup: false)..loginReplies();
          var recovered = false;
          addTearDown(h.http.close);
          addTearDown(h.store.close);
          addTearDown(() async {
            if (recovered) {
              await h.backend.close();
            } else {
              await expectLater(h.backend.close(), _backendCleanupFailure());
            }
          });
          addTearDown(() async {
            if (recovered) {
              await h.client.close();
            } else {
              await expectLater(h.client.close(), _closeFailure());
            }
          });
          final started = Completer<void>();
          final release = Completer<void>();
          String? ownRevision;
          native.onReplace = (args) async {
            started.complete();
            await release.future;
            ownRevision = native.replace(args) as String;
            native.onRead = (_) async =>
                throw PlatformException(code: 'unavailable');
            throw PlatformException(code: 'unavailable');
          };
          final signingIn = h.signIn();
          await started.future;
          // When cancellation retires the operation before the indeterminate write settles.
          final cancelling = expectLater(h.client.cancel(), _cleanupFailure());
          release.complete();
          await signingIn;
          await cancelling;
          // Then failed observation retains bytes and blocks all implicit reactivation.
          expect(native.value, isNotNull);
          expect(native.revision, ownRevision);
          expect(native.calls.where((call) => call == 'read'), hasLength(2));
          expect(native.calls.where((call) => call == 'remove'), isEmpty);
          expect(
            h.client.snapshot.failure,
            UserAccountAuthenticationFailure.serviceUnavailable,
          );
          expect(h.client.snapshot.lastLogoutResult?.localCleared, isFalse);
          expect(h.client.snapshot.account, isNull);
          expect(h.client.canRestore, isFalse);
          final callsBeforeBlocked = List<String>.of(native.calls);
          await expectLater(h.signIn(), throwsStateError);
          await expectLater(h.client.restore(), throwsStateError);
          expect(native.calls, callsBeforeBlocked);

          // Given native IO recovers, with either the exact product owner or a new owner B.
          native.onRead = null;
          final replacement = {
            ..._record(writeId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
            'userAccountId': 'synthetic/replacement-account',
          };
          if (owner == 'newer') {
            native.seed(replacement, revision: _newOwnerRevision);
          }
          Object? retryRevision;
          native.onRemove = (args) async {
            retryRevision = args['expectedRevision'];
            return native.remove(args);
          };
          // When explicit logout uses only the retained writeId/account witness and current CAS revision.
          final retry = await h.client.signOut();
          recovered = retry.localCleared;
          // Then only the own record can be erased; B is retained without remote authentication.
          expect(retry.localCleared, owner == 'same');
          expect(
            retry.remoteRevocation,
            UserAccountRemoteRevocation.notAttempted,
          );
          expect(
            native.calls.where((call) => call == 'remove').length,
            owner == 'same' ? 1 : 0,
          );
          expect(retryRevision, owner == 'same' ? ownRevision : isNull);
          expect(native.value, owner == 'same' ? isNull : _bytes(replacement));
          expect(native.revision, owner == 'same' ? isNull : _newOwnerRevision);
          expect(h.client.canRestore, owner == 'same');
          expect(h.client.snapshot.account, isNull);
          expect(native.calls, isNot(contains('clear')));
          expect(
            h.http.requests.map((request) => request.url.pathSegments.last),
            ['login', 'get-my-account'],
          );
        },
      );
    }

    test('late own write rollback cannot delete a newer CAS owner', () async {
      // Given a pending native write whose returned revision is superseded immediately.
      final h = harness()..loginReplies();
      final started = Completer<void>();
      final release = Completer<void>();
      native.onReplace = (args) async {
        started.complete();
        await release.future;
        final ownRevision = native.replace(args);
        native.seed(
          _record(writeId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
          revision: _newOwnerRevision,
        );
        return ownRevision;
      };
      final work = h.signIn();
      await started.future;
      // When cancellation joins that write and observes a changed slot owner.
      final cancelled = h.client.cancel();
      release.complete();
      await work;
      await cancelled;
      // Then conditional rollback retains the new record without retry or clear.
      expect(native.revision, _newOwnerRevision);
      expect(native.calls.where((c) => c == 'remove'), hasLength(1));
      expect(native.calls.where((c) => c == 'replace'), hasLength(1));
      expect(native.calls, isNot(contains('clear')));
    });

    test('retirement after backend result still discards the real staged completion', () async {
      // Given a real backend whose normalized result is held before the client consumes it.
      final h = harness()..loginReplies();
      final bridge = _OperationBridge(h.backend)..holdResult = true;
      final client = UserAccountAuthenticationClient(backend: bridge);
      addTearDown(client.close);
      final work = client.signIn(identifier: 'id', password: 'pw');
      await bridge.resultReady.future;
      // When cancellation retires the operation before the held result is forwarded.
      final cancelling = client.cancel();
      bridge.releaseResult.complete();
      await work;
      await cancelling;
      // Then no staged write is made, and the backend is free for another real login.
      expect(native.value, isNull);
      bridge.holdResult = false;
      h.loginReplies();
      await client.signIn(identifier: 'id', password: 'pw');
      expect(client.snapshot.isAuthenticated, isTrue);
    });

    test('restoration cancellation never deletes a baseline record', () async {
      // Given a matching baseline and a deferred reread in the staged persist phase.
      native.seed(_record());
      final h = harness();
      h.http.json(_accountBody());
      final started = Completer<void>();
      final release = Completer<void>();
      var reads = 0;
      native.onRead = (_) async {
        if (++reads == 2) {
          started.complete();
          await release.future;
        }
        return native.read();
      };
      final restoring = h.client.restore();
      await started.future;
      // When cancellation arrives after account proof but before baseline confirmation.
      final cancelling = h.client.cancel();
      release.complete();
      await restoring;
      await cancelling;
      // Then discard releases the candidate without deleting the record it only read.
      expect(native.revision, _revision);
      expect(
        native.calls.where((c) => c == 'remove' || c == 'replace'),
        isEmpty,
      );
      expect(h.client.snapshot.isAuthenticated, isFalse);
    });

    for (final owner in ['same', 'newer']) {
      test(
        'indeterminate native replace resolves only its $owner product owner',
        () async {
          // Given a native write which mutates disk but reports a platform failure.
          final h = harness()..loginReplies();
          native.onReplace = (args) async {
            native.replace(args);
            if (owner == 'newer') {
              native.seed(
                _record(writeId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
                revision: _newOwnerRevision,
              );
            }
            throw PlatformException(
              code: 'unavailable',
              message: 'synthetic private native failure',
            );
          };
          // When persistence encounters that indeterminate result.
          await h.signIn();
          // Then one bounded read identifies writeId; only its own record is removed.
          expect(
            h.client.snapshot.failure,
            UserAccountAuthenticationFailure.serviceUnavailable,
          );
          expect(h.client.snapshot.isAuthenticated, isFalse);
          expect(native.calls.where((c) => c == 'replace'), hasLength(1));
          expect(native.value == null, owner == 'same');
          expect(
            native.calls.where((c) => c == 'remove').length,
            owner == 'same' ? 1 : 0,
          );
          expect(native.calls, isNot(contains('clear')));
        },
      );
    }

    test('CAS conflict never overwrites the competing owner', () async {
      // Given another owner appearing between initial read and candidate write.
      final h = harness()..loginReplies();
      native.onReplace = (args) async {
        native.seed(
          _record(writeId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
          revision: _newOwnerRevision,
        );
        return native.replace(args);
      };
      // When the candidate uses expectedRevision:null.
      await h.signIn();
      // Then the conflict is safe failure with no overwrite or recursive retry.
      expect(native.revision, _newOwnerRevision);
      expect(
        h.client.snapshot.failure,
        UserAccountAuthenticationFailure.serviceUnavailable,
      );
      expect(native.calls.where((c) => c == 'replace'), hasLength(1));
      expect(native.calls.where((c) => c == 'remove'), isEmpty);
    });

    for (final method in ['read', 'remove']) {
      test(
        'native $method failure is safe and does not claim local clearance',
        () async {
          // Given a selected record and an unavailable native read/removal operation.
          native.seed(_record());
          final h = harness();
          Future<Object?> fail(Map args) async => throw PlatformException(
            code: 'unavailable',
            message: 'synthetic private store failure',
          );
          if (method == 'read') {
            native.onRead = fail;
          } else {
            native.onRemove = fail;
          }
          // When explicit login attempts to withdraw that slot, then logout is requested.
          await h.signIn();
          final logout = await h.client.signOut();
          // Then storage failure remains local-not-cleared with no credential HTTP.
          expect(logout.localCleared, isFalse);
          expect(native.value, isNotNull);
          expect(h.http.requests, isEmpty);
          expect(
            h.client.snapshot.failure,
            UserAccountAuthenticationFailure.serviceUnavailable,
          );
        },
      );
    }

    test(
      'failed own rollback remains observable and is never retried as clear',
      () async {
        // Given indeterminate persistence of this candidate and an unavailable removal.
        final h = harness(registerCleanup: false)..loginReplies();
        var recovered = false;
        addTearDown(h.http.close);
        addTearDown(h.store.close);
        addTearDown(() async {
          if (recovered) {
            await h.backend.close();
          } else {
            await expectLater(h.backend.close(), _backendCleanupFailure());
          }
        });
        addTearDown(() async {
          if (recovered) {
            await h.client.close();
          } else {
            await expectLater(h.client.close(), _closeFailure());
          }
        });
        native.onReplace = (args) async {
          native.replace(args);
          throw PlatformException(code: 'unavailable');
        };
        native.onRemove = (_) async =>
            throw PlatformException(code: 'unavailable');
        // When persist and discard observe that unresolved IO fact.
        await h.signIn();
        // Then no authenticated state or false clearance is published, and cleanup is not repeated.
        expect(
          h.client.snapshot.failure,
          UserAccountAuthenticationFailure.serviceUnavailable,
        );
        expect(native.value, isNotNull);
        expect(native.calls.where((c) => c == 'remove'), hasLength(1));
        expect(native.calls, isNot(contains('clear')));
        expect(h.client.snapshot.account, isNull);
        expect(h.client.snapshot.lastLogoutResult?.localCleared, isFalse);
        expect(
          h.client.snapshot.lastLogoutResult?.remoteRevocation,
          UserAccountRemoteRevocation.notAttempted,
        );
        expect(h.client.canRestore, isFalse);
        // When authentication is attempted before the unresolved rollback is cleared.
        await expectLater(h.signIn(), throwsStateError);
        await expectLater(h.client.restore(), throwsStateError);
        // Then the rejected attempts do not reuse the retained unaccepted pair.
        expect(h.http.requests, hasLength(2));
        native.onRemove = null;
        // When explicit logout retries after native removal recovers.
        final retry = await h.client.signOut();
        recovered = retry.localCleared;
        // Then only own residual bytes are cleared without remote revocation.
        expect(retry.localCleared, isTrue);
        expect(
          retry.remoteRevocation,
          UserAccountRemoteRevocation.notAttempted,
        );
        expect(native.value, isNull);
        expect(native.calls.where((c) => c == 'remove'), hasLength(2));
        expect(native.calls, isNot(contains('clear')));
        expect(h.client.canRestore, isTrue);
        expect(h.http.requests, hasLength(2));
      },
    );

    for (final command in ['cancel', 'logout', 'close']) {
      test('publication listener $command respects accepted native ownership', () async {
        // Given a listener invoked exactly as a real staged result is accepted.
        final h = harness()..loginReplies();
        Future<Object?>? action;
        var fired = false;
        h.client.addListener(() {
          if (!fired && h.client.snapshot.isAuthenticated) {
            fired = true;
            action = switch (command) {
              'cancel' => expectLater(h.client.cancel(), throwsStateError),
              'logout' => h.client.signOut(),
              _ => h.client.close(),
            };
          }
        });
        if (command == 'logout') h.http.respond((_) => _raw([]));
        // When successful authentication publishes and the listener reenters.
        await h.signIn();
        await action;
        // Then direct cancel refuses, logout clears, and close preserves the accepted record.
        expect(native.value == null, command == 'logout');
        expect(h.client.snapshot.isAuthenticated, command == 'cancel');
        expect(h.http.requests.length, command == 'logout' ? 3 : 2);
      });
    }
  });

  group('independent local logout and remote current-session revocation', () {
    Map<String, Object?> replacementRecord() => {
      ..._record(writeId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
      'userAccountId': 'synthetic/replacement-account',
      'accessSessionId': 'synthetic/replacement-access-session',
      'accessToken': 'SYNTHETIC.replacement-access=',
      'refreshSessionId': 'synthetic/replacement-refresh-session',
      'refreshToken': 'SYNTHETIC.replacement-refresh==',
    };

    for (final body in ['empty', 'null', 'object', 'nonempty', 'redirect']) {
      test('logout distinguishes exact zero bytes from $body', () async {
        // Given an accepted active pair and a selected logout response body.
        final h = harness()..loginReplies();
        await h.signIn();
        h.http.respond(
          (_) => switch (body) {
            'empty' => _raw([]),
            'null' => _reply(null),
            'object' => _reply({}),
            'redirect' => _raw([], status: 302),
            _ => _raw([32]),
          },
        );
        // When ordinary signOut withdraws the local pair and revokes only this session.
        final result = await h.client.signOut();
        // Then local clearance is independent of exact remote response confirmation.
        expect(result.localCleared, isTrue);
        expect(
          result.remoteRevocation,
          body == 'empty'
              ? UserAccountRemoteRevocation.confirmed
              : UserAccountRemoteRevocation.failed,
        );
        expect(native.value, isNull);
        final logout = h.http.requests.last;
        expect(logout.url.toString(), '${_base}logout');
        expect(logout.method, 'POST');
        expect(jsonDecode(logout.body), {'userAccountId': _account});
        expect(logout.headers['Authorization'], 'Bearer $_access');
        expect(logout.headers.containsKey('Cookie'), isFalse);
        expect(logout.followRedirects, isFalse);
        expect(
          h.http.requests.any((r) => r.url.path.contains('logout-all')),
          isFalse,
        );
      });
    }

    test(
      'unreachable remote logout is unknown while local clearance succeeds',
      () async {
        // Given accepted local credentials and a failing remote transport.
        final h = harness()..loginReplies();
        await h.signIn();
        h.http.respond(
          (_) => throw StateError('synthetic private connection error'),
        );
        // When signOut attempts local CAS removal and remote revocation independently.
        final result = await h.client.signOut();
        // Then usable credentials are gone without a false claim of remote confirmation.
        expect(result.localCleared, isTrue);
        expect(result.remoteRevocation, UserAccountRemoteRevocation.unknown);
        expect(
          h.client.snapshot.status,
          UserAccountAuthenticationStatus.signedOut,
        );
        expect(native.value, isNull);
      },
    );

    test(
      'newer stored owner is not cleared by an older active session logout',
      () async {
        // Given an accepted pair followed by another transaction's slot ownership.
        final h = harness()..loginReplies();
        await h.signIn();
        native.seed(
          _record(writeId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
          revision: _newOwnerRevision,
        );
        h.http.respond((_) => _raw([]));
        // When the older accepted session logs out.
        final result = await h.client.signOut();
        // Then its own remote session can be revoked but the newer local owner survives.
        expect(result.localCleared, isFalse);
        expect(result.remoteRevocation, UserAccountRemoteRevocation.confirmed);
        expect(native.revision, _newOwnerRevision);
        expect(h.client.canRestore, isFalse);
      },
    );

    test('unverified stored bytes never authorize remote logout', () async {
      // Given a matching protected record never validated in this backend lifetime.
      native.seed(_record());
      final h = harness();
      // When signOut is requested before explicit restore.
      final result = await h.client.signOut();
      // Then local conditional removal is allowed, with no remote credential request.
      expect(result.localCleared, isTrue);
      expect(result.remoteRevocation, UserAccountRemoteRevocation.notAttempted);
      expect(h.http.requests, isEmpty);
    });

    test('logout retry retains a newer accepted slot owner', () async {
      // Given genuinely accepted account A followed by a distinct valid owner B.
      final h = harness()..loginReplies();
      await h.signIn();
      expect(h.client.snapshot.isAuthenticated, isTrue);
      final replacement = replacementRecord();
      native.seed(replacement, revision: _newOwnerRevision);
      h.http.respond((_) => _raw([]));
      // When A logs out and retries after its usable credentials are withdrawn.
      final first = await h.client.signOut();
      // Then the first call revokes only A and leaves B's local ownership intact.
      expect(first.localCleared, isFalse);
      expect(first.remoteRevocation, UserAccountRemoteRevocation.confirmed);
      expect(native.value, _bytes(replacement));
      expect(native.revision, _newOwnerRevision);
      // When local clearance is retried on the same backend lifetime.
      final retry = await h.client.signOut();
      // Then the retry cannot adopt, remove or remotely use B's credentials.
      expect(retry.localCleared, isFalse);
      expect(retry.remoteRevocation, UserAccountRemoteRevocation.notAttempted);
      expect(native.value, _bytes(replacement));
      expect(native.revision, _newOwnerRevision);
      expect(native.calls.where((call) => call == 'remove'), isEmpty);
      expect(h.http.requests.map((request) => request.url.pathSegments.last), [
        'login',
        'get-my-account',
        'logout',
      ]);
      expect(jsonDecode(h.http.requests.last.body), {
        'userAccountId': _account,
      });
      expect(h.http.requests.last.headers['Authorization'], 'Bearer $_access');
      expect(h.client.snapshot.isAuthenticated, isFalse);
    });

    test('logout retry clears only the previously selected own revision', () async {
      // Given accepted A and a first removal that fails without changing its slot.
      final h = harness()..loginReplies();
      await h.signIn();
      expect(h.client.snapshot.isAuthenticated, isTrue);
      final ownRevision = native.revision;
      final ownBytes = Uint8List.fromList(native.value!);
      Object? attemptedRevision;
      native.onRemove = (args) async {
        attemptedRevision = args['expectedRevision'];
        throw PlatformException(code: 'unavailable');
      };
      h.http.respond((_) => _raw([]));
      // When logout encounters local IO failure while remote A revocation succeeds.
      final first = await h.client.signOut();
      // Then its exact selected own record remains available for legitimate cleanup.
      expect(first.localCleared, isFalse);
      expect(first.remoteRevocation, UserAccountRemoteRevocation.confirmed);
      expect(attemptedRevision, ownRevision);
      expect(native.value, ownBytes);
      expect(native.revision, ownRevision);
      native.onRemove = null;
      // When native removal recovers and local clearance is retried.
      final retry = await h.client.signOut();
      // Then the same own revision is cleared with no repeated remote request.
      expect(retry.localCleared, isTrue);
      expect(retry.remoteRevocation, UserAccountRemoteRevocation.notAttempted);
      expect(native.value, isNull);
      expect(native.revision, isNull);
      expect(native.calls.where((call) => call == 'remove'), hasLength(2));
      expect(h.http.requests.map((request) => request.url.pathSegments.last), [
        'login',
        'get-my-account',
        'logout',
      ]);
      expect(jsonDecode(h.http.requests.last.body), {
        'userAccountId': _account,
      });
      expect(h.http.requests.last.headers['Authorization'], 'Bearer $_access');
      expect(h.client.snapshot.isAuthenticated, isFalse);
    });

    test('unverified logout retry retains a replacement slot owner', () async {
      // Given unverified A and an atomic competing B write during its first CAS.
      native.seed(_record());
      final h = harness();
      final replacement = replacementRecord();
      Object? attemptedRevision;
      native.onRemove = (args) async {
        attemptedRevision = args['expectedRevision'];
        native.seed(replacement, revision: _newOwnerRevision);
        return false;
      };
      // When the initial unverified local logout loses ownership to B.
      final first = await h.client.signOut();
      // Then only the initially selected A revision was attempted and B survives.
      expect(first.localCleared, isFalse);
      expect(first.remoteRevocation, UserAccountRemoteRevocation.notAttempted);
      expect(attemptedRevision, _revision);
      expect(native.value, _bytes(replacement));
      expect(native.revision, _newOwnerRevision);
      native.onRemove = null;
      // When the same backend retries with ordinary native removal restored.
      final retry = await h.client.signOut();
      // Then B is neither adopted nor removed, authenticated or used remotely.
      expect(retry.localCleared, isFalse);
      expect(retry.remoteRevocation, UserAccountRemoteRevocation.notAttempted);
      expect(native.value, _bytes(replacement));
      expect(native.revision, _newOwnerRevision);
      expect(native.calls.where((call) => call == 'remove'), hasLength(1));
      expect(h.http.requests, isEmpty);
      expect(h.client.snapshot.isAuthenticated, isFalse);
    });

    test('empty logout selection cannot adopt a later slot owner', () async {
      // Given a fresh real backend whose selected profile initially has no record.
      final h = harness();
      // When the first local logout observes that empty slot.
      final first = await h.client.signOut();
      // Then empty selection is locally cleared without credentials or HTTP.
      expect(first.localCleared, isTrue);
      expect(first.remoteRevocation, UserAccountRemoteRevocation.notAttempted);
      expect(native.value, isNull);
      final replacement = replacementRecord();
      native.seed(replacement, revision: _newOwnerRevision);
      // When another owner B arrives before a same-lifetime logout retry.
      final retry = await h.client.signOut();
      // Then known-empty selection gives no authority to remove or remotely use B.
      expect(retry.localCleared, isFalse);
      expect(retry.remoteRevocation, UserAccountRemoteRevocation.notAttempted);
      expect(native.value, _bytes(replacement));
      expect(native.revision, _newOwnerRevision);
      expect(native.calls.where((call) => call == 'remove'), isEmpty);
      expect(h.http.requests, isEmpty);
      expect(h.client.snapshot.isAuthenticated, isFalse);
    });
  });

  group('bounded HTTP and closed safe failures', () {
    for (final (stage, status, expected) in [
      ('login', 401, UserAccountAuthenticationFailure.invalidCredentials),
      ('login', 403, UserAccountAuthenticationFailure.invalidCredentials),
      ('verify', 401, UserAccountAuthenticationFailure.challengeRejected),
      ('verify', 403, UserAccountAuthenticationFailure.challengeRejected),
      ('account', 401, UserAccountAuthenticationFailure.authorizationRequired),
      ('account', 403, UserAccountAuthenticationFailure.authorizationRequired),
      ('login', 429, UserAccountAuthenticationFailure.serviceUnavailable),
      ('login', 500, UserAccountAuthenticationFailure.serviceUnavailable),
      ('login', 503, UserAccountAuthenticationFailure.serviceUnavailable),
      ('login', 302, UserAccountAuthenticationFailure.invalidResponse),
      ('login', 201, UserAccountAuthenticationFailure.invalidResponse),
      ('login', 404, UserAccountAuthenticationFailure.invalidResponse),
    ]) {
      test('$stage HTTP $status exposes only $expected', () async {
        // Given a synthetic authority status and deliberately non-JSON private error bytes.
        final h = harness();
        if (stage == 'verify') {
          h.http.json(_challenge());
          await h.signIn();
        }
        if (stage == 'account') h.http.json(_login());
        h.http.respond(
          (_) =>
              _raw(utf8.encode('synthetic private error body'), status: status),
        );
        // When that response reaches the actual transport/backend decoder.
        if (stage == 'verify') {
          await h.client.verifyChallenge('code');
        } else {
          await h.signIn();
        }
        // Then status determines the safe category without parsing/echoing the body.
        expect(h.client.snapshot.failure, expected);
        expect(h.client.snapshot.isAuthenticated, isFalse);
        expect('${h.client.snapshot}', isNot(contains('synthetic private')));
        expect(native.value, isNull);
        for (final request in h.http.requests) {
          expect(request.followRedirects, isFalse);
        }
      });
    }

    for (final shape in ['utf8', 'json', 'overflow', 'root', 'missing-seven']) {
      test(
        'malformed HTTP $shape cannot reach protected persistence',
        () async {
          // Given malformed expected-success bytes or an oversized body stream.
          final h = harness();
          h.http.respond(
            (_) => switch (shape) {
              'utf8' => _raw([0xc3, 0x28]),
              'json' => _raw(utf8.encode('{private')),
              'overflow' => http.StreamedResponse(
                Stream.fromIterable([
                  List<int>.filled(32768, 32),
                  List<int>.filled(32769, 32),
                ]),
                200,
              ),
              'root' => _reply({'data': _login()}),
              _ => _reply(_rotated()),
            },
          );
          // When sign-in consumes the whole bounded response.
          await h.signIn();
          // Then only safe invalidResponse is observable, with no account or write.
          expect(
            h.client.snapshot.failure,
            UserAccountAuthenticationFailure.invalidResponse,
          );
          expect(h.http.requests, hasLength(1));
          expect(native.value, isNull);
        },
      );
    }

    for (final phase in ['send', 'body']) {
      testWidgets(
        'one deadline bounds deferred $phase and observes ignored abort',
        (tester) async {
          // Given a request with a short fake-clock deadline and a noncooperative transport.
          final h = harness(
            timeout: const Duration(seconds: 2),
            registerCleanup: false,
          );
          final late = Completer<http.StreamedResponse>();
          final body = StreamController<List<int>>();
          var bodyClosed = false;
          // Observe done before cancellation so completion belongs to this fake clock.
          body.done.then<void>((_) {
            bodyClosed = true;
          });
          var bodyCancelled = false;
          body.onCancel = () {
            bodyCancelled = true;
          };
          var abortTriggered = false;
          h.http.respond((request) {
            request.abortTrigger!.then<void>((_) {
              abortTriggered = true;
            });
            return phase == 'send'
                ? late.future
                : http.StreamedResponse(body.stream, 200);
          });
          var workCompleted = false;
          final work = h.signIn();
          work.then<void>((_) {
            workCompleted = true;
          });
          var workCompletedAtDeadline = false;
          var abortTriggeredAtDeadline = false;
          UserAccountAuthenticationFailure? failureAtDeadline;
          var requestsAtDeadline = 0;
          var clientClosed = false;
          var backendClosed = false;
          var storeClosed = false;
          try {
            await tester.pump();
            // When the single whole-request deadline elapses on the controlled clock.
            await tester.pump(const Duration(seconds: 2));
            // Capture the deadline outcome before releasing any held headers.
            workCompletedAtDeadline = workCompleted;
            abortTriggeredAtDeadline = abortTriggered;
            failureAtDeadline = h.client.snapshot.failure;
            requestsAtDeadline = h.http.requests.length;
          } finally {
            // Release held sources even when an observation fails; never await an
            // unproven future while this test owns the fake clock.
            if (!late.isCompleted) {
              late.complete(http.StreamedResponse(body.stream, 200));
            }
            await tester.pump();
            body.close();
            await tester.pump();
            h.client.close().then<void>((_) {
              clientClosed = true;
            });
            await tester.pump();
            h.backend.close().then<void>((_) {
              backendClosed = true;
            });
            await tester.pump();
            h.store.close().then<void>((_) {
              storeClosed = true;
            });
            await tester.pump();
            debugDefaultTargetPlatformOverride = null;
          }
          // Then timeout is transportUnavailable and a late stream is cancelled without another request.
          expect(
            workCompletedAtDeadline,
            isTrue,
            reason: 'work completed at deadline',
          );
          expect(
            abortTriggeredAtDeadline,
            isTrue,
            reason: 'abort triggered at deadline',
          );
          expect(
            failureAtDeadline,
            UserAccountAuthenticationFailure.transportUnavailable,
          );
          expect(requestsAtDeadline, 1);
          expect(
            bodyCancelled,
            isTrue,
            reason: 'actual body onCancel observed',
          );
          expect(body.isClosed, isTrue);
          expect(bodyClosed, isTrue);
          expect(clientClosed, isTrue);
          expect(backendClosed, isTrue);
          expect(storeClosed, isTrue);
          expect(h.http.requests, hasLength(1));
          expect(native.value, isNull);
        },
        timeout: const Timeout(Duration(seconds: 20)),
      );
    }

    test('owned close drains without logout and borrowed handles remain usable', () async {
      // Given borrowed HTTP/store handles and a separately owned default native backend.
      final h = harness()..loginReplies();
      await h.signIn();
      final saved = native.value;
      // When close is repeated for borrowed and owned resource configurations.
      await h.backend.close();
      await h.backend.close();
      expect(h.http.closed, isFalse);
      expect(await h.store.read('test-profile'), isNotNull);
      final owned = UserAccountHttpAuthenticationBackend(
        profile: h.backend.profile,
      );
      await owned.close();
      await owned.close();
      // Then only owned native retirement is dispatched and retained data survives.
      expect(native.calls.where((c) => c == 'close'), hasLength(1));
      expect(native.value, saved);
      expect(h.http.requests, hasLength(2));
      expect(native.calls, isNot(contains('clear')));
    });
  });
}

void _unprotected(http.AbortableRequest request) {
  expect(request.headers.containsKey('Authorization'), isFalse);
  expect(request.headers.containsKey('Cookie'), isFalse);
  expect(request.headers['Accept'], 'application/json');
  expect(request.headers['Content-Type'], startsWith('application/json'));
  expect(request.followRedirects, isFalse);
}

Matcher _cleanupFailure() => throwsA(
  isA<StateError>().having(
    (error) => error.message,
    'message',
    'Authentication cleanup failed',
  ),
);

Matcher _closeFailure() => throwsA(
  isA<StateError>().having(
    (error) => error.message,
    'message',
    'Authentication close failed',
  ),
);

Matcher _backendCleanupFailure() => throwsA(
  predicate<Object>(
    (error) =>
        '$error' == 'UserAccountAuthenticationFailure(serviceUnavailable)',
    'the fixed safe backend cleanup failure',
  ),
);

final class _Harness {
  _Harness(this.native, {Duration? timeout}) {
    http = _ControlledHttp(native.events);
    store = NativeAuthenticationCredentialStore();
    backend = UserAccountHttpAuthenticationBackend(
      profile: UserAccountHttpProfile(
        profileId: 'test-profile',
        serviceBaseUri: Uri.parse(_base),
        requestTimeout: timeout ?? const Duration(seconds: 15),
      ),
      client: http,
      credentialStore: store,
    );
    client = UserAccountAuthenticationClient(
      backend: backend,
      ownsBackend: true,
    );
  }
  final _NativeCas native;
  late final _ControlledHttp http;
  late final NativeAuthenticationCredentialStore store;
  late final UserAccountHttpAuthenticationBackend backend;
  late final UserAccountAuthenticationClient client;
  void loginReplies() {
    http.json(_login());
    http.json(_accountBody());
  }

  Future<void> signIn() =>
      client.signIn(identifier: 'synthetic-id', password: 'synthetic-password');
}

final class _ControlledHttp extends http.BaseClient {
  _ControlledHttp(this.events);
  final List<String> events;
  final requests = <http.AbortableRequest>[];
  final _responses =
      <FutureOr<http.StreamedResponse> Function(http.AbortableRequest)>[];
  final _waiting = <int, Completer<http.AbortableRequest>>{};
  bool closed = false;
  int closeCalls = 0;
  void json(Object? body, {int status = 200}) =>
      respond((_) => _reply(body, status: status));
  void respond(
    FutureOr<http.StreamedResponse> Function(http.AbortableRequest) reply,
  ) {
    _responses.add(reply);
  }

  Future<http.AbortableRequest> requestAt(int index) {
    if (requests.length > index) return Future.value(requests[index]);
    return (_waiting[index] ??= Completer<http.AbortableRequest>()).future;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final actual = request as http.AbortableRequest;
    requests.add(actual);
    events.add('http:${request.url.pathSegments.last}');
    _waiting.remove(requests.length - 1)?.complete(actual);
    if (_responses.isEmpty) throw StateError('Unexpected synthetic request');
    return await _responses.removeAt(0)(actual);
  }

  @override
  void close() {
    closeCalls++;
    closed = true;
  }
}

final class _NativeCas {
  final calls = <String>[];
  final events = <String>[];
  Uint8List? value;
  String? revision;
  int sequence = 100;
  Future<Object?> Function(Map)? onRead;
  Future<Object?> Function(Map)? onReplace;
  Future<Object?> Function(Map)? onRemove;
  void seed(Object? record, {String revision = _revision}) {
    value = _bytes(record);
    this.revision = revision;
  }

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
    events.add('native:${call.method}');
    final args = call.arguments as Map;
    return switch (call.method) {
      'read' => onRead == null ? read() : await onRead!(args),
      'replace' => onReplace == null ? replace(args) : await onReplace!(args),
      'remove' => onRemove == null ? remove(args) : await onRemove!(args),
      'close' => null,
      'clear' => throw StateError('Authentication must use revision CAS'),
      _ => throw StateError('Unexpected native operation'),
    };
  }
}

/// A forwarding lifetime seam: all authority/HTTP/storage behavior stays real.
final class _OperationBridge
    implements UserAccountRestorableAuthenticationBackend {
  _OperationBridge(this.backend);
  final UserAccountHttpAuthenticationBackend backend;
  bool replaceChallenge = false;
  bool holdResult = false;
  final resultReady = Completer<void>();
  final releaseResult = Completer<void>();
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
    if (holdResult) {
      resultReady.complete();
      await releaseResult.future;
    }
    return result;
  }

  @override
  Future<UserAccountSignInResult> verifyChallenge({
    required String challengeId,
    required String code,
    required UserAccountAuthenticationOperation operation,
  }) => backend.verifyChallenge(
    challengeId: replaceChallenge ? 'synthetic/wrong-challenge' : challengeId,
    code: code,
    operation: operation,
  );
  @override
  Future<UserAccountSignInResult> refresh({
    required UserAccountAuthenticationOperation operation,
  }) => backend.refresh(operation: operation);
  @override
  Future<UserAccountSignInResult?> restore({
    required UserAccountAuthenticationOperation operation,
  }) => backend.restore(operation: operation);
  @override
  Future<UserAccountLogoutResult> signOut({
    required UserAccountAuthenticationOperation operation,
  }) => backend.signOut(operation: operation);
  @override
  Future<void> close() => backend.close();
}
