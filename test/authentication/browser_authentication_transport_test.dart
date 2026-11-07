@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:textus_flutter_core/src/authentication/browser_authentication_http_web.dart';
import 'package:web/web.dart' as web;

@JS('window.fetch')
external JSFunction get _fetch;
@JS('window.fetch')
external set _fetch(JSFunction value);

void main() {
  test('provider-capability browser transfer omits application credentials, referrer and redirects', () async {
    // Given the actual browser transfer transport and an observed synthetic Fetch response.
    final original = _fetch;
    addTearDown(() => _fetch = original);
    var calls = 0;
    _fetch = ((JSAny url, web.RequestInit options) {
      calls++;
      expect(options.mode, 'cors');
      expect(options.credentials, 'omit');
      expect(options.redirect, 'error');
      expect(options.cache, 'no-store');
      expect(options.referrerPolicy, 'no-referrer');
      final headers = options.headers.dartify() as Map;
      expect(
        headers.keys.map((v) => v.toString().toLowerCase()),
        isNot(contains('authorization')),
      );
      return Future<web.Response>.value(
        web.Response('{}'.toJS, web.ResponseInit(status: 200)),
      ).toJS;
    }).toJS;
    final client = createCapabilityTransferHttpClient();
    addTearDown(client.close);
    final uri = Uri.parse(
      'https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=synthetic',
    );
    // When a capability PUT is dispatched, then attempts carrying credentials or to another host are refused locally.
    await client.put(uri, body: [1, 2, 3]);
    expect(calls, 1);
    await expectLater(
      client.put(
        uri,
        headers: {'Authorization': 'SYNTHETIC.forbidden'},
        body: [1],
      ),
      throwsA(isA<http.ClientException>()),
    );
    await expectLater(
      client.put(Uri.parse('https://foreign.example.test/upload'), body: [1]),
      throwsA(isA<http.ClientException>()),
    );
    expect(calls, 1);
  });
  test(
    'browser transport omits cookies and rejects redirects and foreign origins',
    () async {
      // Given a same-origin browser transport and an observed Fetch boundary.
      final original = _fetch;
      addTearDown(() => _fetch = original);
      final base = Uri.base.replace(
        path: '/rest/v1/user-account/user/',
        query: '',
        fragment: '',
      );
      final requests = <web.RequestInit>[];
      _fetch = ((JSAny url, web.RequestInit options) {
        requests.add(options);
        expect(url.dartify(), base.resolve('login').toString());
        return Future<web.Response>.value(
          web.Response(
            '{"synthetic":true}'.toJS,
            web.ResponseInit(
              status: 200,
              headers:
                  {'content-type': 'application/json'}.jsify()!
                      as web.HeadersInit,
            ),
          ),
        ).toJS;
      }).toJS;
      final client = createBrowserAuthenticationHttpClient(base);
      addTearDown(client.close);
      // When one admitted login operation is dispatched.
      final response = await client.post(
        base.resolve('login'),
        body: 'synthetic-body',
      );
      // Then cookies/redirects/caching are excluded and foreign targets never dispatch.
      expect(response.body, '{"synthetic":true}');
      expect(response.headers['content-type'], 'application/json');
      expect(requests.single.credentials, 'omit');
      expect(requests.single.redirect, 'error');
      expect(requests.single.cache, 'no-store');
      expect(requests.single.mode, 'same-origin');
      final foreign = Uri.parse('https://foreign.example.test/rest/');
      expect(
        () => createBrowserAuthenticationHttpClient(foreign),
        throwsArgumentError,
      );
      await expectLater(
        client.get(foreign),
        throwsA(isA<http.ClientException>()),
      );
      expect(requests, hasLength(1));
      client.close();
      await expectLater(
        client.get(base.resolve('login')),
        throwsA(isA<http.ClientException>()),
      );
    },
  );
}
