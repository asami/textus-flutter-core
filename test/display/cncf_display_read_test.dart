import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

Map<String, Object?> fixture(String name) => Map<String, Object?>.from(
  jsonDecode(
    File('test/fixtures/cncf_display_reference_v1/$name.json')
        .readAsStringSync(),
  ) as Map,
);

final trusted = fixture('list-initial');
CncfDisplayReadProfile profile() => CncfDisplayReadProfile(
  componentId: 'org.simplemodeling.textus.EditingStudio',
  resourceType: 'collecting-reference',
  listScreenId: 'collecting-resources',
  detailScreenId: 'capture-detail',
  definitionRevision: 'ess-reference-definition-1',
  semanticContract: Map<String, Object?>.from(
    trusted['semanticContract']! as Map,
  ),
  provenance: Map<String, Object?>.from(trusted['provenance']! as Map),
);
http.Response reply(Object? data) => http.Response(
  jsonEncode({'data': data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
CncfDisplayReadClient client(
  http.Client transport, {
  Future<String?> Function()? token,
  Duration timeout = const Duration(seconds: 2),
}) => CncfDisplayReadClient(
  profile: profile(),
  endpoint: Uri.parse('https://studio.test/rest/v1/editing-studio/'),
  client: transport,
  bearerToken: token ?? () async => 'test-only-token',
  timeout: timeout,
);
Matcher failure(String code) =>
    isA<CncfDisplayReadException>().having((e) => e.code, 'code', code);

void main() {
  test('should preserve Unicode context over successive real HTTP reads with ASCII headers', () async {
    // Given a controlled socket peer serving unchanged producer-authored goldens.
    // This tests actual client byte transport, not a native CNCF server deployment.
    final peer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final paths = <String>[];
    final headers = <String>[];
    final context = fixture('context-variant-ja');
    final families = context['families']! as List;
    (families[1]['data'] as Map)['variant'] = '参照・標準';
    (families[2]['data'] as Map)['displayInstance'] = '流れ-é-日本';
    (families[2]['data'] as Map)['correlation'] = '相関-😀';
    final serving = peer.listen((request) async {
      paths.add(request.uri.path);
      headers.add(request.headers.value('x-cncf-presentation-context')!);
      if (request.headers.value('authorization') !=
          'Bearer owned-loopback-token') {
        request.response.statusCode = 401;
      } else {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': fixture(
              request.uri.path.endsWith('query.json')
                  ? 'list-initial'
                  : 'detail-initial',
            )..['presentationContext'] = context,
          }),
        );
      }
      await request.response.close();
    });
    final transport = http.Client();
    final service = CncfDisplayReadClient(
      profile: profile(),
      endpoint: Uri.parse(
        'http://127.0.0.1:${peer.port}/rest/v1/editing-studio/',
      ),
      client: transport,
      bearerToken: () async => 'owned-loopback-token',
      allowLoopbackHttp: true,
    );
    try {
      // When the public client performs query followed by selected Detail over TCP.
      final list = await service.query();
      final detail = await service.read(list.resources.first.entityId);
      // Then exact mounted routes and semantic text survive real UTF8/JSON bytes.
      expect(detail.resources.single.text('title'), '日本の民話');
      expect(paths, [
        '/rest/v1/editing-studio/display/query.json',
        '/rest/v1/editing-studio/display/read.json',
      ]);
      expect(headers.last.codeUnits.every((unit) => unit < 128), isTrue);
      expect(jsonDecode(headers.last), context);
      expect(headers.last, contains(r'\u53c2'));
    } finally {
      service.dispose();
      transport.close();
      await peer.close(force: true);
      await serving.cancel();
    }
  });

  test(
    'should reject malformed surrogate text in supported context before reuse',
    () async {
      // Given malformed UTF16 in either the server variant or an opaque flow reference.
      for (final item in [
        (1, 'variant', '\uD800'),
        (2, 'correlation', '\uDC00'),
      ]) {
        final context = fixture('context-variant-ja');
        (((context['families']! as List)[item.$1] as Map)['data']
                as Map)[item.$2] =
            item.$3;
        final data = fixture('list-initial')..['presentationContext'] = context;
        var calls = 0;
        final transport = MockClient((_) async {
          calls++;
          return reply(data);
        });
        final service = client(transport);
        // When the first response is admitted for possible continuation.
        final read = service.query();
        // Then admission fails and performs no follow-up request or lossy replacement.
        await expectLater(read, throwsA(failure('contextValueInvalid')));
        expect(calls, 1);
        service.dispose();
        transport.close();
      }
    },
  );

  test('should cancel a stalled response subscription on timeout and flow disposal', () async {
    // Given a response body that never completes, even after headers arrived.
    for (final dispose in [false, true]) {
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
        },
      );
      final headers = Completer<void>();
      final transport = MockClient.streaming((request, stream) async {
        headers.complete();
        return http.StreamedResponse(
          body.stream,
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = client(
        transport,
        timeout: const Duration(milliseconds: 30),
      );
      // When the read times out or its owner explicitly retires.
      final result = service.query();
      final expectation = expectLater(
        result,
        throwsA(isA<CncfDisplayReadException>()),
      );
      await headers.future;
      await Future<void>.delayed(Duration.zero);
      if (dispose) service.dispose();
      await expectation;
      await Future<void>.delayed(Duration.zero);
      // Then the actual stream subscription is cancelled, with no retry.
      expect(cancelled, isTrue);
      service.dispose();
      transport.close();
      await body.close();
    }
  });

  test('should read producer goldens without inventing a snapshot or merging revisions', () async {
    // Given the independently authored accepted server read fixtures.
    final requests = <http.Request>[];
    final transport = MockClient((request) async {
      requests.add(request);
      return reply(
        fixture(
          request.url.path.endsWith('query.json')
              ? 'list-initial'
              : 'detail-initial',
        ),
      );
    });
    final service = client(transport);
    // When query is followed by an explicit selected-resource read.
    final list = await service.query();
    final id = list.resources.first.entityId;
    final detail = await service.read(id);
    // Then original text/order/string revisions and independent provenance survive.
    expect(list.resources.map((r) => r.text('title')), ['日本の民話', '地域資料目録']);
    expect(list.snapshotReference, isNull);
    expect(detail.resources.single.revision, '1');
    expect(detail.wire['provenance'], trusted['provenance']);
    expect(detail.resources.single.text('description'), '地域に伝わる物語を集めた資料。');
    expect(requests.first.method, 'GET');
    expect(requests.last.url.queryParameters['resourceId'], id);
    expect(
      requests.first.url.queryParameters['screenId'],
      'collecting-resources',
    );
    expect(requests.last.url.queryParameters['screenId'], 'capture-detail');
    expect(requests.every((r) => r.body.isEmpty && !r.followRedirects), isTrue);
    expect(requests.first.headers['Authorization'], 'Bearer test-only-token');
    service.dispose();
    transport.close();
  });

  test('should carry supplied context opaquely then clear it when the server omits it', () async {
    // Given a fresh server context with exact opaque references and an inert extension.
    final context = fixture('context-variant-ja');
    (context['families']! as List).add({
      'name': 'vendor.optional',
      'version': 2,
      'data': {'secret': 'inert'},
    });
    final requests = <http.Request>[];
    final transport = MockClient((request) async {
      requests.add(request);
      final data = fixture('list-initial');
      if (requests.length == 1) data['presentationContext'] = context;
      return reply(data);
    });
    final service = client(transport);
    // When three explicit reads cross a context-producing then context-free response.
    await service.query();
    await service.query();
    await service.query();
    // Then only supported supplied families are returned; no local arm allocation occurs.
    final carried =
        jsonDecode(requests[1].headers['X-CNCF-Presentation-Context']!) as Map;
    expect((carried['families'] as List).map((f) => f['name']), [
      'cncf.locale',
      'cncf.presentation',
      'cncf.display-flow',
    ]);
    expect(
      (carried['families'] as List).last['data'],
      (context['families'] as List)[2]['data'],
    );
    expect(jsonDecode(requests[2].headers['X-CNCF-Presentation-Context']!), {
      'version': 1,
      'families': [],
    });
    service.dispose();
    transport.close();
  });

  test('should preserve Long maximum revision as a string', () async {
    // Given a native server revision beyond JavaScript integer precision.
    final data = fixture('detail-initial');
    ((data['model'] as Map)['resource'] as Map)['revision'] =
        '9223372036854775807';
    final transport = MockClient((_) async => reply(data));
    final service = client(transport);
    // When the exact resource is read, Then no floating-point conversion occurs.
    final id =
        ((data['model'] as Map)['resource'] as Map)['entityId'] as String;
    expect(
      (await service.read(id)).resources.single.revision,
      '9223372036854775807',
    );
    service.dispose();
    transport.close();
  });

  for (final mutation in <String, void Function(Map<String, Object?>)>{
    'source': (v) => v['componentId'] = 'foreign',
    'ABI': (v) => (v['abi'] as Map)['version'] = 2,
    'contract': (v) => (v['semanticContract'] as Map)['assurance'] = 'foreign',
    'provenance': (v) => (v['provenance'] as Map)['revision'] = 'foreign',
    'definition': (v) => (v['definition'] as Map)['revision'] = 'foreign',
    'extra member': (v) => v['surprise'] = true,
    'null snapshot': (v) => (v['model'] as Map)['snapshot'] = null,
    'noncanonical revision': (v) =>
        (((v['model'] as Map)['items'] as List).first['resource']
                as Map)['revision'] =
            '01',
    'malformed known context': (v) => v['presentationContext'] = {
      'version': 1,
      'families': [
        {
          'name': 'cncf.presentation',
          'version': 1,
          'data': {'variant': null},
        },
      ],
    },
  }.entries) {
    test(
      'should reject ${mutation.key} without adopting received metadata',
      () async {
        // Given a response differing from the separately selected trusted profile.
        final data = fixture('list-initial');
        mutation.value(data);
        final transport = MockClient((_) async => reply(data));
        final service = client(transport);
        // When read admission runs, Then the whole read fails without partial projection.
        await expectLater(
          service.query(),
          throwsA(isA<CncfDisplayReadException>()),
        );
        service.dispose();
        transport.close();
      },
    );
  }

  test(
    'should reject duplicate nested JSON keys and mismatched Detail identity',
    () async {
      // Given repeated decoded members that dart:convert would otherwise collapse.
      final response = jsonEncode({'data': fixture('list-initial')})
          .replaceFirst(
            '"title":"Collecting Resources"',
            '"title":"wrong","title":"Collecting Resources"',
          );
      final transport = MockClient(
        (_) async => http.Response(
          response,
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      final service = client(transport);
      // When raw wire is parsed, Then duplicate members fail before decoded admission.
      await expectLater(
        service.query(),
        throwsA(failure('duplicateJsonMember')),
      );
      service.dispose();
      transport.close();
      // Given a separate Detail response for a different selected resource.
      final other = MockClient((_) async => reply(fixture('detail-initial')));
      final selected = client(other);
      // When the caller reads its explicit selection, Then the mismatched identity rejects.
      await expectLater(
        selected.read('another-resource'),
        throwsA(failure('resourceMismatch')),
      );
      selected.dispose();
      other.close();
    },
  );

  test('should reject redirects and credentials before any unauthorized follow-up', () async {
    // Given a cross-origin redirect containing attacker-controlled failure details.
    var calls = 0;
    final transport = MockClient((_) async {
      calls++;
      return http.Response(
        'secret-token',
        302,
        headers: {'location': 'https://other.test/steal'},
      );
    });
    final service = client(transport);
    // When a read is sent, Then there is one request and only a redacted status failure.
    await expectLater(service.query(), throwsA(failure('httpRejected')));
    expect(calls, 1);
    // Given a separate client whose credentials require explicit authorization.
    final missing = client(transport, token: () async => null);
    // When that client attempts a read, Then no new HTTP request is dispatched.
    await expectLater(
      missing.query(),
      throwsA(failure('authenticationRequired')),
    );
    expect(calls, 1);
    service.dispose();
    missing.dispose();
    transport.close();
  });

  test('should never dispatch after a credential wait times out or the flow is disposed', () async {
    // Given credential callbacks that finish after their owner has retired.
    final token = Completer<String?>();
    var calls = 0;
    final transport = MockClient((_) async {
      calls++;
      return reply(fixture('list-initial'));
    });
    final service = client(
      transport,
      token: () => token.future,
      timeout: const Duration(milliseconds: 10),
    );
    // When the bounded read times out and credentials arrive later.
    await expectLater(service.query(), throwsA(failure('timeout')));
    token.complete('late-token');
    await Future<void>.delayed(Duration.zero);
    // Then no request is dispatched and the error contains no secret data.
    expect(calls, 0);
    service.dispose();
    transport.close();
  });

  test(
    'should reject remote cleartext and never close a borrowed HTTP client',
    () {
      // Given a non-loopback HTTP endpoint, even with the development opt-in.
      final transport = MockClient((_) async => reply(trusted));
      // When configuration is admitted, Then cleartext to remote hosts is rejected.
      expect(
        () => CncfDisplayReadClient(
          profile: profile(),
          endpoint: Uri.parse('http://remote.test/'),
          client: transport,
          bearerToken: () async => 'token',
          allowLoopbackHttp: true,
        ),
        throwsArgumentError,
      );
      final service = client(transport);
      service.dispose();
      // Then the borrowed transport remains callable by its actual owner.
      expect(transport.get(Uri.parse('https://owner.test')), completes);
      transport.close();
    },
  );
}
