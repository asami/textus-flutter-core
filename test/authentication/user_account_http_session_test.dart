import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

const _base = 'https://studio.example.test/';
const _access = 'SYNTHETIC.http.access';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<
    (UserAccountHttpAuthenticationBackend, UserAccountAuthenticationClient)
  >
  login(Future<http.Response> Function(http.Request) service) async {
    final wire = MockClient((request) async {
      switch (request.url.pathSegments.last) {
        case 'login':
          return http.Response(
            jsonEncode({
              'user_account_id': 'synthetic/participant',
              'credential_id': 'synthetic/credential',
              'access_session_id': 'synthetic/access-session',
              'access_token': _access,
              'refresh_session_id': 'synthetic/refresh-session',
              'refresh_token': 'SYNTHETIC.http.refresh',
              'authenticated': true,
            }),
            200,
          );
        case 'get-my-account':
          return http.Response('{"id":"synthetic/participant"}', 200);
        case 'logout':
          return http.Response('', 200);
        default:
          return service(request);
      }
    });
    final backend = UserAccountHttpAuthenticationBackend.browser(
      profile: UserAccountHttpProfile.fromString(
        profileId: 'test',
        serviceBaseUri: '${_base}user/',
      ),
      client: wire,
    );
    final client = UserAccountAuthenticationClient(
      backend: backend,
      ownsBackend: true,
    );
    addTearDown(wire.close);
    addTearDown(client.close);
    await client.signIn(identifier: 'synthetic', password: 'synthetic');
    expect(client.snapshot.isAuthenticated, isTrue);
    return (backend, client);
  }

  test('delivery access isolates capability bytes from account credentials and retires with the session', () async {
    // Given an accepted account, a scoped control API and a borrowed direct-transfer client.
    final (backend, _) = await login((request) async {
      expect(request.headers['authorization'], 'Bearer $_access');
      return http.Response('null', 200);
    });
    var transfers = 0;
    final direct = MockClient((request) async {
      transfers++;
      expect(request.method, 'PUT');
      expect(request.url.host, 'www.googleapis.com');
      expect(
        request.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
      expect(
        request.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('cookie')),
      );
      expect(request.bodyBytes, [1, 2, 3, 4]);
      expect(request.followRedirects, isFalse);
      return http.Response('{}', 200);
    });
    addTearDown(direct.close);
    final control = MockClient((request) async {
      expect(request.headers['authorization'], 'Bearer $_access');
      expect(
        request.url.path,
        '/knowledge-lake/material-delivery/findForRequest',
      );
      return http.Response(
        '{"found":false}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    addTearDown(control.close);
    final session = backend.createHttpSession(
      serviceBaseUri: Uri.parse(_base),
      client: control,
    );
    addTearDown(session.close);
    final access = session.createMaterialDeliveryAccess(
      directTransferClient: direct,
    );
    expect(await access.delivery.findForRequest('synthetic-request'), isNull);
    final instruction = TklDirectTransferInstruction(
      transferRef: 'synthetic-transfer',
      resourceId: 'cover',
      mediaType: 'image/png',
      byteLength: 4,
      nextOffset: 0,
      uploadUri: Uri.parse(
        'https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=synthetic',
      ),
    );
    // When the existing delivery port transfers declared content to the provider capability.
    await access.delivery.uploadDirect(
      instruction: instruction,
      content: Uint8List.fromList([1, 2, 3, 4]),
    );
    // Then only exact bytes go to that client; retirement prevents another dispatch.
    expect(transfers, 1);
    session.close();
    expect(access.authentication.isCurrent, isFalse);
    await expectLater(
      access.delivery.uploadDirect(
        instruction: instruction,
        content: Uint8List.fromList([1, 2, 3, 4]),
      ),
      throwsA(isA<TklMaterialDeliveryHttpException>()),
    );
    expect(transfers, 1);
    access.close();
  });

  test('run retirement aborts pending delivery without retiring the accepted account', () async {
    // Given a delivery GET waiting for headers under a borrowed foreground run.
    final (backend, account) = await login(
      (_) async => throw StateError('Unexpected account request'),
    );
    final wire = _HeldDeliveryClient();
    addTearDown(wire.close);
    final session = backend.createHttpSession(
      serviceBaseUri: Uri.parse(_base),
      client: wire,
    );
    addTearDown(session.close);
    final lifetime = SubmissionRunLifetime(id: 'synthetic-foreground');
    final access = session.createMaterialDeliveryAccess(lifetime: lifetime);
    final pending = expectLater(
      access.delivery.getDestination(),
      throwsA(isA<TklMaterialDeliveryHttpException>()),
    );
    await wire.dispatched.future.timeout(const Duration(seconds: 2));

    // When the run retires before the server responds.
    lifetime.retire();
    expect(access.authentication.isCurrent, isFalse);
    await wire.aborted.future.timeout(const Duration(seconds: 2));
    await pending.timeout(const Duration(seconds: 2));

    // Then the pending operation drains, further dispatch is refused, and a
    // new run can still borrow the accepted session without another login.
    await expectLater(
      access.delivery.getDestination(),
      throwsA(isA<TklMaterialDeliveryHttpException>()),
    );
    expect(wire.sends, 1);
    expect(session.isClosed, isFalse);
    expect(account.snapshot.isAuthenticated, isTrue);
    expect(
      () => session.createMaterialDeliveryAccess(lifetime: lifetime),
      throwsStateError,
    );
    final replacement = session.createMaterialDeliveryAccess();
    expect(replacement.authentication.isCurrent, isTrue);
    replacement.close();
    access.close();
  });

  test('accepted account sends exact scoped JSON and If-Match while safe replies exclude credentials', () async {
    // Given an accepted participant session and an observed service transport.
    final requests = <http.Request>[];
    final (backend, _) = await login(
      (_) async => throw StateError('Unexpected'),
    );
    final wire = MockClient((request) async {
      requests.add(request);
      expect(request.headers['authorization'], 'Bearer $_access');
      expect(request.headers['if-match'], '"revision-4"');
      expect(request.followRedirects, isFalse);
      expect(jsonDecode(request.body), {
        'resourceId': 'synthetic/book',
        'patch': {'version': 1},
      });
      return http.Response(
        '{"saved":true}',
        200,
        headers: {
          'etag': '"revision-5"',
          'content-type': 'application/json',
          'set-cookie': 'SYNTHETIC.cookie',
          'authorization': 'SYNTHETIC.header',
        },
      );
    });
    addTearDown(wire.close);
    final session = backend.createHttpSession(
      serviceBaseUri: Uri.parse('${_base}rest/v1/'),
      client: wire,
    );
    addTearDown(session.close);
    // When a conditional business mutation is sent through the scoped capability.
    final response = await session.post(
      'editing-studio/book-material-editor/save',
      body: {
        'resourceId': 'synthetic/book',
        'patch': {'version': 1},
      },
      ifMatch: '"revision-4"',
    );
    // Then its wire/body match the operation and only safe response headers escape.
    expect(response.json(), {'saved': true});
    expect(response.headers, {
      'etag': '"revision-5"',
      'content-type': 'application/json',
    });
    expect(
      requests.single.url.toString(),
      '${_base}rest/v1/editing-studio/book-material-editor/save',
    );
    expect('$session $response', isNot(contains(_access)));
    expect(
      () => backend.createHttpSession(
        serviceBaseUri: Uri.parse('https://foreign.example.test/rest/'),
        client: wire,
      ),
      throwsArgumentError,
    );
    for (final selector in [
      '../escape',
      '/escape',
      'https://foreign.example.test/',
      'editor/%2e%2e',
    ]) {
      await expectLater(session.get(selector), throwsArgumentError);
    }
    expect(requests, hasLength(1));
  });

  test(
    'logout retires in-flight mutations without claiming rejection or retrying',
    () async {
      // Given a dispatched POST whose server reply has not arrived.
      final dispatched = Completer<void>();
      final reply = Completer<http.Response>();
      var sends = 0;
      final (backend, client) = await login(
        (_) async => throw StateError('Unexpected'),
      );
      final wire = MockClient((_) {
        sends++;
        dispatched.complete();
        return reply.future;
      });
      addTearDown(wire.close);
      final session = backend.createHttpSession(
        serviceBaseUri: Uri.parse('${_base}rest/v1/'),
        client: wire,
      );
      final saving = session.post(
        'editor/save',
        body: {'resourceId': 'synthetic/book'},
      );
      final rejected = expectLater(
        saving,
        throwsA(
          isA<UserAccountHttpException>()
              .having(
                (e) => e.failure,
                'failure',
                UserAccountHttpFailure.retired,
              )
              .having(
                (e) => e.mutationMayHaveCompleted,
                'uncertain mutation',
                isTrue,
              ),
        ),
      );
      await dispatched.future;
      // When the account logs out before that reply.
      await client.signOut();
      await rejected;
      // Then the lease retires, the mutation remains uncertain and it is not replayed.
      expect(session.isClosed, isTrue);
      reply.complete(http.Response('{"saved":true}', 200));
      await expectLater(
        session.get('editor/get'),
        throwsA(
          isA<UserAccountHttpException>().having(
            (e) => e.mutationMayHaveCompleted,
            'no new mutation',
            isFalse,
          ),
        ),
      );
      expect(sends, 1);
    },
  );

  test(
    'bounded replies retain complete HTTP conflict without automatic replay',
    () async {
      // Given a service returning an oversized reply followed by HTTP409.
      final (backend, _) = await login(
        (_) async => throw StateError('Unexpected'),
      );
      var sends = 0;
      final wire = MockClient((_) async {
        sends++;
        return http.Response(
          'a response longer than the selected bound',
          sends == 1 ? 200 : 409,
        );
      });
      addTearDown(wire.close);
      final session = backend.createHttpSession(
        serviceBaseUri: Uri.parse('${_base}rest/v1/'),
        client: wire,
      );
      addTearDown(session.close);
      // When the selected byte bound is exceeded, then read fails safely.
      await expectLater(
        session.get('editor/get', maximumResponseBytes: 4),
        throwsA(
          isA<UserAccountHttpException>().having(
            (e) => e.failure,
            'overflow',
            UserAccountHttpFailure.invalidResponse,
          ),
        ),
      );
      // When a later mutation returns a complete conflict, then its status is preserved without retry.
      final conflict = await session.post(
        'editor/save',
        body: {'patch': {}},
        ifMatch: '"revision-1"',
      );
      expect(conflict.statusCode, 409);
      expect(sends, 2);
    },
  );
}

final class _HeldDeliveryClient extends http.BaseClient {
  final dispatched = Completer<void>();
  final aborted = Completer<void>();
  int sends = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sends++;
    expect(
      request.url.path,
      '/knowledge-lake/material-delivery/getDestination',
    );
    final abort = (request as http.AbortableRequest).abortTrigger;
    expect(abort, isNotNull);
    dispatched.complete();
    await abort;
    aborted.complete();
    throw http.RequestAbortedException(request.url);
  }
}
