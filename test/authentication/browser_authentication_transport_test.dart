@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:textus_flutter_core/src/authentication/browser_authentication_http_web.dart';
import 'package:web/web.dart' as web;

@JS('window.fetch')
external JSFunction get _fetch;
@JS('window.fetch')
external set _fetch(JSFunction value);

void main() {
  group('browser response lifecycle', () {
    late Uri base;
    late http.Client client;
    late web.Response fetchResponse;
    late web.AbortSignal signal;
    void Function()? onAbort;

    setUp(() {
      final original = _fetch;
      addTearDown(() => _fetch = original);
      base = Uri.base.replace(
        path: '/rest/v1/user-account/user/',
        query: '',
        fragment: '',
      );
      onAbort = null;
      _fetch = ((JSAny url, web.RequestInit options) {
        signal = options.signal!;
        if (onAbort != null) {
          signal.addEventListener(
            'abort',
            ((web.Event event) => onAbort!()).toJS,
          );
        }
        return Future<web.Response>.value(fetchResponse).toJS;
      }).toJS;
      client = createBrowserAuthenticationHttpClient(base);
      addTearDown(client.close);
    });

    test(
      'should preserve the response and leave Fetch un-aborted after EOF',
      () async {
        // Given a real browser response containing a complete JSON body.
        const body = '{"synthetic":true}';
        fetchResponse = web.Response(
          body.toJS,
          web.ResponseInit(
            status: 200,
            headers:
                {'content-type': 'application/json'}.jsify()!
                    as web.HeadersInit,
          ),
        );

        // When the complete response body reaches normal EOF.
        final response = await client.get(base.resolve('login'));

        // Then body, status and headers survive without aborting Fetch.
        expect(response.body, body);
        expect(response.statusCode, 200);
        expect(response.headers['content-type'], 'application/json');
        expect(signal.aborted, isFalse);

        // When the client closes after completion.
        client.close();

        // Then the completed request has already retired from pending work.
        expect(signal.aborted, isFalse);
      },
    );

    test(
      'should ignore an abort trigger completed after response EOF',
      () async {
        // Given an abortable request whose real browser response can complete.
        final abortTrigger = Completer<void>();
        fetchResponse = web.Response('completed'.toJS);
        final request = http.AbortableRequest(
          'GET',
          base.resolve('login'),
          abortTrigger: abortTrigger.future,
        );
        final response = await http.Response.fromStream(
          await client.send(request),
        );

        // When its abort trigger completes after the entire body was consumed.
        abortTrigger.complete();
        await abortTrigger.future;

        // Then the completed response remains intact and Fetch is not aborted.
        expect(response.body, 'completed');
        expect(signal.aborted, isFalse);
      },
    );

    for (final nullBody in [true, false]) {
      test(
        'should complete a ${nullBody ? 'null' : 'empty'} body without aborting Fetch',
        () async {
          // Given a real browser response with no body or an empty body stream.
          fetchResponse = web.Response(
            nullBody ? null : ''.toJS,
            web.ResponseInit(status: 200),
          );

          // When its response is fully consumed.
          final response = await client.get(base.resolve('login'));

          // Then the empty payload completes normally without aborting Fetch.
          expect(response.bodyBytes, isEmpty);
          expect(response.statusCode, 200);
          expect(signal.aborted, isFalse);
        },
      );
    }

    test(
      'should abort an active response when its abort trigger completes',
      () async {
        // Given an abortable request with an unfinished real browser body.
        final abortTrigger = Completer<void>();
        late web.ReadableStreamDefaultController controller;
        fetchResponse = web.Response(
          web.ReadableStream(
            {
                  'start': ((web.ReadableStreamDefaultController value) {
                    controller = value;
                    value.enqueue(Uint8List.fromList([1, 2, 3]).toJS);
                  }).toJS,
                }.jsify()!
                as JSObject,
          ),
        );
        onAbort = () =>
            controller.error(web.DOMException('Aborted', 'AbortError'));
        final response = await client.send(
          http.AbortableRequest(
            'GET',
            base.resolve('login'),
            abortTrigger: abortTrigger.future,
          ),
        );
        final body = StreamIterator<List<int>>(response.stream);
        addTearDown(body.cancel);
        expect(await body.moveNext(), isTrue);
        expect(body.current, [1, 2, 3]);
        expect(signal.aborted, isFalse);
        final interrupted = expectLater(
          body.moveNext(),
          throwsA(isA<http.ClientException>()),
        );

        // When the abort trigger completes while the next body read is pending.
        abortTrigger.complete();
        await interrupted;

        // Then Fetch is aborted and the unfinished body fails rather than completing.
        expect(signal.aborted, isTrue);
      },
    );

    test('should abort Fetch and cancel its reader on early stream cancellation', () async {
      // Given an unfinished browser body with an observable cancellation hook.
      var cancellations = 0;
      fetchResponse = web.Response(
        web.ReadableStream(
          {
                'start': ((web.ReadableStreamDefaultController controller) {
                  controller.enqueue(Uint8List.fromList([1, 2, 3]).toJS);
                }).toJS,
                'cancel': ((JSAny? reason) {
                  cancellations++;
                }).toJS,
              }.jsify()!
              as JSObject,
        ),
      );
      final response = await client.send(
        http.Request('GET', base.resolve('login')),
      );
      final body = StreamIterator<List<int>>(response.stream);
      addTearDown(body.cancel);
      expect(await body.moveNext(), isTrue);
      expect(body.current, [1, 2, 3]);
      expect(signal.aborted, isFalse);

      // When the consumer cancels before the browser body reaches EOF.
      await body.cancel();

      // Then the active Fetch and its reader are both cancelled.
      expect(signal.aborted, isTrue);
      expect(cancellations, 1);
    });

    test('should abort an outstanding response when the client closes', () async {
      // Given a response whose browser body remains unfinished after one chunk.
      var cancellations = 0;
      fetchResponse = web.Response(
        web.ReadableStream(
          {
                'start': ((web.ReadableStreamDefaultController controller) {
                  controller.enqueue(Uint8List.fromList([1, 2, 3]).toJS);
                }).toJS,
                'cancel': ((JSAny? reason) {
                  cancellations++;
                }).toJS,
              }.jsify()!
              as JSObject,
        ),
      );
      final response = await client.send(
        http.Request('GET', base.resolve('login')),
      );
      final body = StreamIterator<List<int>>(response.stream);
      addTearDown(body.cancel);
      expect(await body.moveNext(), isTrue);
      expect(body.current, [1, 2, 3]);
      expect(signal.aborted, isFalse);

      // When the client closes with that response still outstanding.
      client.close();

      // Then the pending Fetch is aborted and its reader can still be cancelled.
      expect(signal.aborted, isTrue);
      await body.cancel();
      expect(cancellations, 1);
    });
  });

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
