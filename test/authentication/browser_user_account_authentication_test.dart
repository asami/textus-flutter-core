import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

const _account = 'user-account:synthetic/one';
const _access = 'SYNTHETIC.browser.access';
const _refresh = 'SYNTHETIC.browser.refresh';

Map<String, Object?> _pair({bool rotated = false}) => {
  'user_account_id': _account,
  if (!rotated) 'credential_id': 'synthetic/credential',
  'access_session_id': 'synthetic/access-session',
  'access_token': rotated ? '$_access.rotated' : _access,
  'refresh_session_id': 'synthetic/refresh-session',
  'refresh_token': rotated ? '$_refresh.rotated' : _refresh,
  'authenticated': true,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final profile = UserAccountHttpProfile.fromString(
    profileId: 'browser-test',
    serviceBaseUri: 'https://studio.example.test/rest/v1/user-account/user/',
  );

  test('volatile login, account, rotation and logout reuse common semantics without native storage', () async {
    // Given a browser backend with a synthetic authority and a forbidden native store.
    var nativeCalls = 0;
    const channel = MethodChannel(
      'org.textus.flutter.core/authentication_credentials',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          nativeCalls++;
          throw StateError('Browser must not call native storage');
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final requests = <http.Request>[];
    final wire = MockClient((request) async {
      requests.add(request);
      expect(request.followRedirects, isFalse);
      expect(
        request.headers.keys.map((v) => v.toLowerCase()),
        isNot(contains('cookie')),
      );
      switch (request.url.pathSegments.last) {
        case 'login':
          expect(request.headers['authorization'], isNull);
          expect(jsonDecode(request.body), {
            'identifier': 'synthetic-login',
            'password': 'synthetic-password',
          });
          return http.Response(jsonEncode(_pair()), 200);
        case 'get-my-account':
          expect(
            request.headers['authorization'],
            anyOf('Bearer $_access', 'Bearer $_access.rotated'),
          );
          return http.Response(
            jsonEncode({'id': _account, 'name': 'Synthetic participant'}),
            200,
          );
        case 'refresh-access-token':
          expect(request.headers['authorization'], isNull);
          expect(jsonDecode(request.body), {'refreshToken': _refresh});
          return http.Response(jsonEncode(_pair(rotated: true)), 200);
        case 'logout':
          expect(request.headers['authorization'], 'Bearer $_access.rotated');
          expect(jsonDecode(request.body), {'userAccountId': _account});
          return http.Response('', 200);
        default:
          throw StateError('Unexpected operation');
      }
    });
    final backend = UserAccountHttpAuthenticationBackend.browser(
      profile: profile,
      client: wire,
    );
    final client = UserAccountAuthenticationClient(
      backend: backend,
      ownsBackend: true,
    );
    addTearDown(client.close);
    addTearDown(wire.close);
    // A fresh tab has no persisted session and restore performs no HTTP.
    await client.restore();
    expect(client.snapshot.status, UserAccountAuthenticationStatus.signedOut);
    expect(requests, isEmpty);
    // When login, credential rotation and explicit logout use the common client.
    await client.signIn(
      identifier: 'synthetic-login',
      password: 'synthetic-password',
    );
    // Then accepted identity is retained without native storage or persisted browser credentials.
    expect(client.snapshot.isAuthenticated, isTrue);
    expect(client.snapshot.account?.userAccountId, _account);
    await client.refresh();
    expect(client.snapshot.isAuthenticated, isTrue);
    final result = await client.signOut();
    expect(result.localCleared, isTrue);
    expect(client.snapshot.status, UserAccountAuthenticationStatus.signedOut);
    expect(requests.map((r) => r.url.pathSegments.last), [
      'login',
      'get-my-account',
      'refresh-access-token',
      'get-my-account',
      'logout',
    ]);
    expect(nativeCalls, 0);

    // A different backend lifetime cannot restore the first one's credentials.
    final another = UserAccountAuthenticationClient(
      backend: UserAccountHttpAuthenticationBackend.browser(
        profile: profile,
        client: wire,
      ),
      ownsBackend: true,
    );
    addTearDown(another.close);
    await another.restore();
    expect(another.snapshot.status, UserAccountAuthenticationStatus.signedOut);
    expect(requests, hasLength(5));
  });

  test('retiring a pending browser login cannot publish a late authenticated account', () async {
    // Given a pending login response from the authority.
    final response = Completer<http.Response>();
    final requested = Completer<void>();
    final wire = MockClient((_) {
      requested.complete();
      return response.future;
    });
    final client = UserAccountAuthenticationClient(
      backend: UserAccountHttpAuthenticationBackend.browser(
        profile: profile,
        client: wire,
      ),
      ownsBackend: true,
    );
    addTearDown(wire.close);
    final signingIn = client.signIn(
      identifier: 'synthetic',
      password: 'synthetic',
    );
    await requested.future;
    // When the browser backend is retired before that response arrives.
    final closing = client.close();
    response.complete(http.Response(jsonEncode(_pair()), 200));
    await signingIn;
    await closing;
    // Then a late success cannot reopen or authenticate the retired client.
    expect(client.snapshot.status, UserAccountAuthenticationStatus.closed);
    expect(client.snapshot.isAuthenticated, isFalse);
  });
}
