import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  group('strict content verification projection', () {
    for (final camelCase in [false, true]) {
      test('complete ${camelCase ? 'native camelCase' : 'adapter snake_case'} proof exposes verified resources', () async {
        // Given the server's closed tuple with an actual verified placed original.
        final raw = _integritySnapshot(camelCase: camelCase);
        final client = MockClient((_) async => _response(raw));
        addTearDown(client.close);
        // When normal HTTP decoding reads that server observation.
        final result = await _client(client).get('delivery-1');
        // Then typed proof and attempt counts survive without inventing MaterialRef.
        expect(result.state, TklMaterialDeliveryState.readyToRegister);
        expect(result.resources.single.contentDigest, _checkedDigest());
        expect(result.resources.single.verificationState, TklOriginalVerificationState.verified);
        expect(result.resources.single.verificationAttempts, 1);
        expect(result.materialRef, isNull);
        expect(result.toString(), isNot(contains(_checkedDigest().value)));
      });
    }
    final mutations = <void Function(Map<String, Object?>)>[
      (r) { r['content_digest'] = null; },
      (r) { r['content_digest'] = {'algorithm': 'sha256', 'value': 'short'}; },
      (r) { r['content_digest'] = {..._checkedDigest().toJson(), 'extra': null}; },
      (r) { r['content_digest'] = {'Algorithm': 'sha256', 'value': _checkedDigest().value}; },
      (r) { r.remove('content_digest'); },
      (r) { r.remove('verification_state'); },
      (r) { r.remove('verification_attempts'); },
      (r) { r['verification_state'] = null; },
      (r) { r['verification_state'] = 'accepted'; },
      (r) { r['verification_attempts'] = null; },
      (r) { r['verification_attempts'] = -1; },
      (r) { r['verification_attempts'] = 4; },
      (r) { r['verification_attempts'] = 1.0; },
      (r) { r['verification_attempts'] = 0; },
      (r) { r['verification_reason'] = null; },
      (r) { r['verification_reason'] = 'provider-session-secret'; },
      (r) { r['verification_reason'] = 'integrityMismatch'; },
      (r) { r['contentDigest'] = _checkedDigest().toJson(); },
      (r) { r['verificationState'] = 'verified'; },
      (r) { r['verificationAttempts'] = 1; },
      (r) { r['verification_state'] = 'pending'; r['verification_attempts'] = 0; },
      (r) { r['verification_state'] = 'verifying'; },
      (r) { r['verification_state'] = 'failed'; r['verification_reason'] = 'integrityMismatch'; },
    ];
    for (var i = 0; i < mutations.length; i++) {
      test('malformed ambiguous or insufficient ready proof case $i never registers', () async {
        // Given a ready projection with a malformed tuple or nonverified original.
        final raw = _integritySnapshot();
        mutations[i]((raw['resources'] as List).single as Map<String, Object?>);
        final client = MockClient((_) async => _response(raw));
        addTearDown(client.close);
        // When the ordinary HTTP client decodes the claimed ready state.
        await expectLater(_client(client).get('delivery-1'), throwsA(
          isA<TklMaterialDeliveryHttpException>().having((e) => e.code, 'code', 'invalidResponse')));
        // Then the raw expected digest or provider secret cannot escape as success.
      });
    }
    test('destination SHA capability accepts both closed aliases and rejects null ambiguity or unsupported algorithms', () async {
      // Given the two supported projections and malformed capability observations.
      for (final field in ['content_integrity', 'contentIntegrity']) {
        final client = MockClient((_) async => _response({
          'availability': 'available', 'destinationId': 'selected', 'label': 'Selected',
          'transferMethod': 'googleDriveResumable', field: 'sha256',
        }));
        addTearDown(client.close);
        // When discovery decodes the actual advertised capability.
        final destination = await _client(client).getDestination();
        // Then only explicit supported SHA advertisement enables local preparation.
        expect(destination.contentIntegrity, 'sha256');
      }
      for (final fields in [
        {'contentIntegrity': null}, {'contentIntegrity': 'md5'},
        {'contentIntegrity': 'sha256', 'content_integrity': 'sha256'},
      ]) {
        // Given malformed or ambiguous presence on an otherwise valid destination.
        final client = MockClient((_) async => _response({
          'availability': 'available', 'destinationId': 'selected', 'label': 'Selected',
          'transferMethod': 'googleDriveResumable', ...fields,
        }));
        addTearDown(client.close);
        // When discovery receives that response, Then no capability is inferred.
        await expectLater(_client(client).getDestination(), throwsA(isA<TklMaterialDeliveryHttpException>()));
      }
    });
    test('failed proof is explicit while legacy Registered has no fabricated SHA', () async {
      // Given a server failure with the fixed safe reason and a legacy Registered observation.
      final failure = _integritySnapshot()..['state'] = 'verificationFailed'
        ..['action_required'] = 'integrityMismatch';
      final resource = (failure['resources'] as List).single as Map<String, Object?>;
      resource['verification_state'] = 'failed';
      resource['verification_reason'] = 'integrityMismatch';
      var call = 0;
      final client = MockClient((_) async => _response(call++ == 0 ? failure :
        _snapshot(state: 'registered', uploaded: true, materialRef: 'urn:legacy')));
      addTearDown(client.close);
      // When the real client reads both independent observations.
      final failed = await _client(client).get('delivery-1');
      final legacy = await _client(client).get('delivery-1');
      // Then failure is not acceptance, and historical registration is readable without SHA proof.
      expect(failed.materialRef, isNull);
      expect(failed.resources.single.verificationReason, 'integrityMismatch');
      expect(legacy.materialRef, 'urn:legacy');
      expect(legacy.resources.single.contentDigest, isNull);
      expect(legacy.resources.single.verificationState, isNull);
    });
  });

  test('native TKL direct instruction retains its narrow session only in the ephemeral preparation result', () async {
    // Given a native preparation response with a delivery and narrow resumable instruction.
    final client = MockClient((request) async {
      // Then preparation requests only the retained delivery and resource.
      expect(request.url.path.endsWith('/prepareOriginalTransfer'), isTrue);
      expect(jsonDecode(request.body), {
        'deliveryRef': 'delivery-1',
        'resourceId': 'cover',
      });
      return _response({
        'delivery': {
          'deliveryRef': 'delivery-1',
          'requestId': 'book-1',
          'revision': 3,
          'destinationId': 'selected',
          'destinationLabel': 'Library',
          'transferMethod': 'googleDriveResumable',
          'state': 'prepared',
          'resources': [
            {
              'resourceId': 'cover',
              'mediaType': 'image/png',
              'byteLength': 5,
              'state': 'pending',
            },
          ],
        },
        'instruction': {
          'transferRef': 'transfer-1',
          'resourceId': 'cover',
          'method': 'googleDriveResumable',
          'uploadSessionUri': 'https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=session-marker',
          'mediaType': 'image/png',
          'byteLength': 5,
          'nextOffset': 2,
        },
      });
    });
    addTearDown(client.close);
    // When the client prepares the original transfer for that delivery and resource.
    final result = await _client(
      client,
    ).prepareOriginalTransfer(deliveryRef: 'delivery-1', resourceId: 'cover');
    // Then the ephemeral instruction retains its offset and transfer identity without exposing the session in diagnostics.
    expect(result.instruction!.nextOffset, 2);
    expect(result.instruction!.transferRef, 'transfer-1');
    expect(result.instruction.toString(), isNot(contains('session-marker')));
    expect(result.delivery.toString(), isNot(contains('session-marker')));
  });
  test(
    'native Record response keys decode without renaming opaque request JSON',
    () async {
      // Given native Record response keys for a prepared direct delivery and pending original.
      final client = MockClient(
        (request) async => _response({
          'deliveryRef': 'delivery-1',
          'requestId': 'book-1',
          'revision': 1,
          'destinationId': 'selected',
          'destinationLabel': 'Library',
          'transferMethod': 'googleDriveResumable',
          'state': 'prepared',
          'resources': [
            {
              'resourceId': 'cover',
              'mediaType': 'image/png',
              'byteLength': 5,
              'state': 'pending',
            },
          ],
        }),
      );
      addTearDown(client.close);
      // When the retained delivery is read through the HTTP client.
      final result = await _client(client).get('delivery-1');
      // Then native aliases decode to the same delivery, transfer method and resource identity.
      expect(result.deliveryRef, 'delivery-1');
      expect(
        result.transferMethod,
        TklMaterialTransferMethod.googleDriveResumable,
      );
      expect(result.resources.single.resourceId, 'cover');
    },
  );

  test(
    'ambiguous native and generated projection aliases are rejected',
    () async {
      // Given a response with conflicting native and generated delivery-reference aliases.
      final client = MockClient(
        (request) async =>
            _response({..._snapshot(), 'deliveryRef': 'other-delivery'}),
      );
      addTearDown(client.close);
      // When the client reads the retained delivery.
      await expectLater(
        _client(client).get('delivery-1'),
        // Then ambiguous aliases fail as invalidResponse.
        throwsA(
          isA<TklMaterialDeliveryHttpException>().having(
            (error) => error.code,
            'code',
            'invalidResponse',
          ),
        ),
      );
    },
  );
  test('discovery calls TKL without physical storage configuration', () async {
    // Given explicitly injected service bootstrap and borrowed credentials.
    final credentials = _Credentials();
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.method, 'GET');
      expect(
        request.url.toString(),
        'https://tkl.example/rest/v1/lake/material-delivery/getDestination',
      );
      expect(request.headers['Authorization'], 'Bearer test-application-token');
      expect(request.followRedirects, isFalse);
      return _response({
        'availability': 'available',
        'destination_id': 'mobile-materials',
        'label': 'Mobile Materials',
        'transfer_method': 'tklMultipart',
        'max_resource_bytes': 1000000,
      });
    });
    addTearDown(client.close);
    final delivery = _client(client, credentials);
    expect(requests, 0);
    expect(credentials.calls, isEmpty);
    // When production discovery runs through the supplied HTTPS service.
    final destination = await delivery.getDestination();
    // Then only TKL's logical projection is exposed; no local folder is supplied.
    expect(destination.destinationId, 'mobile-materials');
    expect(destination.transferMethod, TklMaterialTransferMethod.tklMultipart);
    expect(requests, 1);
    expect(credentials.calls, ['tkl-service']);
  });

  test(
    'prepare preserves structured JSON, Unicode and explicit null',
    () async {
      // Given an immutable generic commit carrying uninterpreted document/context.
      final contribution = {
        'schema': 'textus.material-contribution/1',
        'title': '窯変源氏物語 7',
        'provenance': {
          'executionContext': {'arm': 2, 'other': null},
        },
        'documents': [
          {
            'body': null,
            'derivedFrom': ['cover'],
          },
        ],
      };
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), {
          'requestId': 'book-1',
          'contribution': contribution,
        });
        return _response(_snapshot(), status: 201);
      });
      addTearDown(client.close);
      // When the real client encodes the committed contribution.
      final result = await _client(client).prepare(
        TklMaterialDeliveryRequest(
          requestId: 'book-1',
          contribution: contribution,
        ),
      );
      // Then remote Prepared is not an uploaded or registered receipt.
      expect(result.state, TklMaterialDeliveryState.prepared);
      expect(result.materialRef, isNull);
    },
  );

  test('only confirmed lookup absence returns null', () async {
    // Given one actual absence, followed by an unavailable service.
    var count = 0;
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.queryParameters, {'requestId': 'book-1'});
      count++;
      return count == 1
          ? _response({'found': false})
          : _response({'private': 'must not escape'}, status: 503);
    });
    addTearDown(client.close);
    final delivery = _client(client);
    // When the same correlation is queried in both conditions.
    expect(await delivery.findForRequest('book-1'), isNull);
    // Then service failure cannot be treated as absence or a local destination.
    await expectLater(
      delivery.findForRequest('book-1'),
      throwsA(
        isA<TklMaterialDeliveryHttpException>()
            .having((error) => error.code, 'code', 'serviceUnavailable')
            .having((error) => error.outcomeUnknown, 'query mutation', isFalse),
      ),
    );
    expect(count, 2);
  });

  test('multipart retains original bytes and MIME without JSON encoding', () async {
    // Given an original containing bytes that are not UTF-8 text.
    final bytes = Uint8List.fromList([0, 255, 128, 10, 0]);
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path.endsWith('/uploadOriginal'), isTrue);
      expect(
        request.headers['content-type'],
        startsWith('multipart/form-data;'),
      );
      // Lossless Latin-1 comparison checks the serialized binary part exactly.
      final wire = latin1.decode(request.bodyBytes);
      expect(wire, contains('name="deliveryRef"\r\n\r\ndelivery-1\r\n'));
      expect(wire, contains('name="resourceId"\r\n\r\ncover\r\n'));
      expect(wire, contains('name="content"; filename="original"'));
      expect(wire, contains('content-type: image/png\r\n'));
      expect(wire, contains('\r\n\r\n${latin1.decode(bytes)}\r\n'));
      return _response(_snapshot(state: 'readyToRegister', uploaded: true));
    });
    addTearDown(client.close);
    // When the client sends the exact retained original declaration.
    final result = await _client(client).uploadOriginal(
      deliveryRef: 'delivery-1',
      resourceId: 'cover',
      mediaType: 'image/png',
      content: bytes,
    );
    // Then uploaded bytes still do not imply Material registration.
    expect(result.resources.single.state, TklOriginalTransferState.uploaded);
    expect(result.materialRef, isNull);
  });

  test('lost finalize result can be queried without replaying the mutation', () async {
    // Given an uncertain finalization reply and a later confirmed registration.
    final operations = <String>[];
    final client = MockClient((request) async {
      operations.add('${request.method} ${request.url.path.split('/').last}');
      if (request.method == 'POST') {
        expect(jsonDecode(request.body), {'deliveryRef': 'delivery-1'});
        return _response({}, status: 503);
      }
      expect(request.url.queryParameters, {'deliveryRef': 'delivery-1'});
      return _response(
        _snapshot(
          state: 'registered',
          uploaded: true,
          materialRef: 'urn:textus:klake:test:material:book-1',
        ),
      );
    });
    addTearDown(client.close);
    final delivery = _client(client);
    // When finalization fails after a possible remote effect.
    await expectLater(
      delivery.finalize('delivery-1'),
      throwsA(
        isA<TklMaterialDeliveryHttpException>().having(
          (error) => error.outcomeUnknown,
          'unknown outcome',
          isTrue,
        ),
      ),
    );
    final result = await delivery.get('delivery-1');
    // Then the caller can reconcile the same reference; no automatic POST occurs.
    expect(result.materialRef, 'urn:textus:klake:test:material:book-1');
    expect(operations, ['POST finalize', 'GET get']);
  });

  for (final status in [401, 403, 503]) {
    test('mutation HTTP $status has truthful uncertainty and safe errors', () async {
      // Given a refusal or uncertain service response containing private text.
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return _response({
          'private': 'credential-folder-secret',
        }, status: status);
      });
      addTearDown(client.close);
      // When the client observes that response after submitting finalization.
      try {
        await _client(client).finalize('delivery-1');
        fail('Expected explicit failure');
      } on TklMaterialDeliveryHttpException catch (error) {
        // Then only auth refusal is known; the response body never becomes UI text.
        expect(error.outcomeUnknown, status == 503);
        expect(error.toString(), isNot(contains('credential-folder-secret')));
      }
      expect(requests, 1);
    });
  }

  test(
    'mismatched or falsely registered results never become receipts',
    () async {
      // Given a different reference, then a planned reference before registration.
      final variants = [
        {..._snapshot(), 'delivery_ref': 'other-delivery'},
        {..._snapshot(), 'material_ref': 'urn:planned'},
        {..._snapshot(state: 'registered'), 'material_ref': 'urn:incomplete'},
      ];
      for (final response in variants) {
        final client = MockClient((_) async => _response(response));
        addTearDown(client.close);
        // When status decoding sees a result outside the retained delivery contract.
        await expectLater(
          _client(client).get('delivery-1'),
          // Then mismatched identity or an unearned registration fails as invalidResponse.
          throwsA(
            isA<TklMaterialDeliveryHttpException>().having(
              (error) => error.code,
              'code',
              'invalidResponse',
            ),
          ),
        );
      }
    },
  );

  test(
    'missing authorization sends nothing and has no unknown remote effect',
    () async {
      // Given a configured service without a usable platform application credential.
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return _response(_snapshot());
      });
      addTearDown(client.close);
      final credentials = _Credentials(token: null);
      // When finalization requests the exact configured connection credential.
      await expectLater(
        _client(client, credentials).finalize('delivery-1'),
        throwsA(
          isA<TklMaterialDeliveryHttpException>()
              .having((error) => error.code, 'code', 'authRequired')
              .having(
                (error) => error.outcomeUnknown,
                'unknown outcome',
                isFalse,
              ),
        ),
      );
      // Then there is no anonymous request, consent action or alternate target.
      expect(requests, 0);
      expect(credentials.calls, ['tkl-service']);
    },
  );
}

TklMaterialDeliveryHttpClient _client(
  http.Client client, [
  _Credentials? credentials,
]) => TklMaterialDeliveryHttpClient(
  connection: HttpSubmissionConnection(
    id: 'tkl-service',
    endpoint: Uri.parse('https://tkl.example/rest/v1/lake/material-delivery/'),
  ),
  client: client,
  credentials: credentials ?? _Credentials(),
);

http.Response _response(Object value, {int status = 200}) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(value)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, Object?> _snapshot({
  String state = 'prepared',
  bool uploaded = false,
  String? materialRef,
}) => {
  'delivery_ref': 'delivery-1',
  'request_id': 'book-1',
  'revision': 1,
  'destination_id': 'mobile-materials',
  'destination_label': 'Mobile Materials',
  'state': state,
  'resources': [
    <String, Object?>{
      'resource_id': 'cover',
      'media_type': 'image/png',
      'byte_length': 5,
      'state': uploaded ? 'uploaded' : 'pending',
    },
  ],
  'material_ref': ?materialRef,
};

final class _Credentials implements SubmissionCredentialProvider {
  _Credentials({this.token = 'test-application-token'});
  final String? token;
  final List<String> calls = [];
  @override
  Future<String?> bearerToken(String connectionId) async {
    calls.add(connectionId);
    return token;
  }
}

TklContentDigest _checkedDigest() => TklContentDigest(algorithm: 'sha256',
  value: List.filled(64, 'a').join());
Map<String, Object?> _integritySnapshot({bool camelCase = false}) {
  final raw = _snapshot(state: 'readyToRegister', uploaded: true);
  final resource = (raw['resources'] as List).single as Map<String, Object?>;
  resource.addAll({
    'content_digest': _checkedDigest().toJson(), 'verification_state': 'verified',
    'verification_attempts': 1,
  });
  if (!camelCase) return raw;
  Map<String, Object?> native(Map<String, Object?> fields) => {
    for (final entry in fields.entries)
      entry.key.replaceAllMapped(RegExp(r'_([a-z])'), (m) => m[1]!.toUpperCase()): entry.value,
  };
  raw['resources'] = [native(resource)];
  return native(raw);
}
