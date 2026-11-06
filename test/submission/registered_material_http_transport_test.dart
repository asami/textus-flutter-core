import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:textus_flutter_core/textus_flutter_core.dart';

import '../support/submission_http_fixture.dart';
import 'registered_material_submission_test.dart' show registeredTestPacket, registeredTestRequest;

const _studioCases = [
  (400, 10899020100, 'argument', 'invalid', 'studioInputInvalid'),
  (401, 91599020100, 'security', 'authentication-required', 'studioAuthenticationRequired'),
  (403, 91699020100, 'security', 'permission-denied', 'studioPermissionDenied'),
  (404, 61099020100, 'resource', 'not-found', 'studioNotFound'),
  (409, 81299020100, 'state', 'conflict', 'studioConflict'),
];

Map<String, Object?> _studioBody(
  (int, int, String, String, String) value, {
  String variant = 'matching',
}) {
  final status = <String, Object?>{'detailCode': value.$2, 'webCode': value.$1};
  final taxonomy = <String, Object?>{'category': value.$3, 'symptom': value.$4};
  final conclusion = <String, Object?>{
    'status': status,
    'observation': <String, Object?>{'taxonomy': taxonomy},
    'cause': 'hostile-diagnostic-owner-token',
    'facets': {'url': 'https://private.invalid/token'},
  };
  final error = <String, Object?>{
    'status': value.$1,
    'detailCode': value.$2,
    'conclusion': conclusion,
    'message': 'hostile-diagnostic-owner-token: update someone else',
    'debug': 'https://private.invalid/token',
    'owner': 'hostile-diagnostic-owner-token',
  };
  switch (variant) {
    case 'absentStatus':
      conclusion.remove('status');
      error.remove('status');
    case 'emptyStatus':
      status.clear();
    case 'wrongInteger':
      error['detailCode'] = 1;
    case 'stringCode':
      error['detailCode'] = '${value.$2}';
    case 'doubleCode':
      error['detailCode'] = value.$2.toDouble();
    case 'nullCode':
      error['detailCode'] = null;
    case 'missingCode':
      error.remove('detailCode');
    case 'missingTaxonomy':
      conclusion['observation'] = <String, Object?>{};
    case 'wrongTuple':
      taxonomy['symptom'] = 'unknown';
    case 'unequalNestedCode':
      status['detailCode'] = 1;
    case 'stringNestedCode':
      status['detailCode'] = '${value.$2}';
    case 'doubleNestedCode':
      status['detailCode'] = value.$2.toDouble();
    case 'nullNestedCode':
      status['detailCode'] = null;
    case 'nullNestedStatus':
      conclusion['status'] = null;
    case 'nonObjectNestedStatus':
      conclusion['status'] = value.$1;
    case 'wrongHttpStatus':
      error['status'] = 500;
    case 'stringHttpStatus':
      error['status'] = '${value.$1}';
    case 'nullHttpStatus':
      error['status'] = null;
    case 'wrongWebCode':
      status['webCode'] = 500;
    case 'stringWebCode':
      status['webCode'] = '${value.$1}';
    case 'nullWebCode':
      status['webCode'] = null;
  }
  return {'error': error};
}

void main() {
  late SubmissionHttpFixture f;
  setUp(() { f = SubmissionHttpFixture(); });
  tearDown(() { f.dispose(); });

  for (final value in _studioCases) {
    for (final variant in [
      'matching', 'absentStatus', 'emptyStatus', 'wrongInteger', 'stringCode',
      'doubleCode', 'nullCode', 'missingCode', 'missingTaxonomy', 'wrongTuple',
      'unequalNestedCode', 'stringNestedCode', 'doubleNestedCode',
      'nullNestedCode', 'nullNestedStatus', 'nonObjectNestedStatus',
      'wrongHttpStatus', 'stringHttpStatus', 'nullHttpStatus', 'wrongWebCode',
      'stringWebCode', 'nullWebCode', 'badJson', 'wrongContentType',
    ]) {
      test('should classify Studio ${value.$1} $variant safely after one unchanged v2 POST', () async {
        // Given a server-shaped response with hostile diagnostics and one selected contract variation.
        final packet = registeredTestPacket(target: f.httpConnection);
        final known = ['matching', 'absentStatus', 'emptyStatus'].contains(variant);
        final code = known ? value.$5 : 'studioHttp${value.$1}';
        f.client.respond(variant == 'badJson'
            ? http.StreamedResponse(Stream.value(utf8.encode('{bad')), value.$1,
                headers: {'content-type': 'application/json'})
            : submissionJsonResponse(_studioBody(value, variant: variant),
                status: value.$1,
                headers: variant == 'wrongContentType'
                    ? {'content-type': 'text/plain'} : const {}));
        // When the actual bounded HTTP v2 transport consumes that response.
        final pending = f.transport().submitRegisteredMaterial(packet);
        // Then only the exact tuple is known; fallback preserves status/outcome without diagnostics or replay.
        await expectLater(pending, throwsA(allOf(
          submissionFailure(code,
            stage: value.$1 == 401 ? SubmissionFailureStage.configuration
                : SubmissionFailureStage.transport),
          isA<SubmissionAdapterException>()
          .having((e) => e.transportFailureOutcome, 'outcome',
            value.$1 == 401 || value.$1 == 403
                ? SubmissionTransportFailureOutcome.rejected
                : SubmissionTransportFailureOutcome.unknown)
          .having((e) => e.message, 'fixed message',
            'Submission operation could not be completed.'))));
        final sent = f.client.requests.single;
        expect(sent.method, 'POST');
        expect(sent.uri, packet.target.endpoint);
        expect(sent.headers['idempotency-key'], packet.sourceRequest.id);
        expect(sent.json, RegisteredMaterialSubmissionCodec.packetToJson(packet));
        expect(f.credentials.calls, [f.httpConnection.id]);
      });
    }
  }

  for (final status in [402, 408, 418, 429, 500, 503]) {
    test('should retain uncertainty and retryability for unclassified Studio HTTP $status', () async {
      // Given an unclassified HTTP failure whose body contains no trusted tuple.
      final packet = registeredTestPacket(target: f.httpConnection);
      f.client.respond(submissionJsonResponse({'message': 'hostile-token'}, status: status));
      // When the participant transport observes its actual response stream.
      final pending = f.transport().submitRegisteredMaterial(packet);
      // Then a fixed unknown code carries existing retryability and one unchanged dispatch.
      await expectLater(pending, throwsA(allOf(
        submissionFailure('studioHttpUnknown',
        stage: SubmissionFailureStage.transport,
        retryable: status == 408 || status == 429 || status >= 500),
        isA<SubmissionAdapterException>()
        .having((e) => e.transportFailureOutcome, 'outcome', SubmissionTransportFailureOutcome.unknown))));
      expect(f.client.requests.single.json, RegisteredMaterialSubmissionCodec.packetToJson(packet));
      expect(f.client.requests.single.headers['idempotency-key'], packet.sourceRequest.id);
    });
  }

  for (final status in [302, 304]) {
    test('should retain generic redirect refusal for v2 HTTP $status without following it', () async {
      // Given a redirect response outside Studio error classification.
      f.client.respond(submissionEmptyResponse(status));
      // When v2 receives the redirect after dispatch.
      final pending = f.transport().submitRegisteredMaterial(registeredTestPacket(target: f.httpConnection));
      // Then existing redirect policy and uncertain outcome remain unchanged.
      await expectLater(pending, throwsA(allOf(
        submissionFailure('redirectRejected',
          stage: SubmissionFailureStage.transport),
        isA<SubmissionAdapterException>()
        .having((e) => e.transportFailureOutcome, 'outcome', SubmissionTransportFailureOutcome.unknown))));
      expect(f.client.requests.single.followsRedirects, isFalse);
    });
  }

  for (final value in _studioCases) {
    test('should retain generic v1 failure code for Studio-shaped HTTP ${value.$1}', () async {
      // Given an ordinary v1 packet and an otherwise recognized Studio response.
      final request = f.request();
      f.client.respond(submissionJsonResponse(_studioBody(value), status: value.$1));
      final code = switch (value.$1) {
        401 => 'authRequired',
        403 => 'permissionDenied',
        _ => 'requestRejected',
      };
      // When legacy submit receives the same HTTP error.
      final pending = f.transport().submit(f.packet(request));
      // Then v1 keeps its generic vocabulary, outcome and exact wire packet.
      await expectLater(pending, throwsA(allOf(
        submissionFailure(code,
          stage: value.$1 == 401 ? SubmissionFailureStage.configuration
              : SubmissionFailureStage.transport),
        isA<SubmissionAdapterException>()
        .having((e) => e.transportFailureOutcome, 'outcome',
          value.$1 == 401 || value.$1 == 403
              ? SubmissionTransportFailureOutcome.rejected
              : SubmissionTransportFailureOutcome.unknown))));
      expect(f.client.requests.single.json, SubmissionCodec.packetToJson(f.packet(request)));
    });
  }

  for (final status in [401, 403]) {
    for (final retirement in ['cancelled', 'timedOut']) {
      test('should keep $retirement after HTTP $status headers unknown until a complete refusal', () async {
        // Given refusal headers with a response body held open after potential dispatch.
        final entered = Completer<void>();
        final cancelled = Completer<void>();
        final body = StreamController<List<int>>();
        f.client.handler = (_) {
          entered.complete();
          return http.StreamedResponse(body.stream, status,
            headers: {'content-type': 'application/json'});
        };
        final adapter = f.transport(cancellation: cancelled.future,
          operationTimeout: retirement == 'timedOut'
              ? const Duration(milliseconds: 100) : const Duration(seconds: 2));
        // When cancellation or the total deadline wins before the body can establish refusal.
        final pending = adapter.submitRegisteredMaterial(registeredTestPacket(target: f.httpConnection));
        final assertion = expectLater(pending, throwsA(allOf(
          submissionFailure(
          retirement == 'cancelled' ? 'operationCancelled' : 'operationTimeout',
            stage: SubmissionFailureStage.transport, retryable: true),
          isA<SubmissionAdapterException>()
          .having((e) => e.transportFailureOutcome, 'outcome', SubmissionTransportFailureOutcome.unknown))));
        await submissionEntered(entered);
        if (retirement == 'cancelled') cancelled.complete();
        try {
          await assertion;
          // Then headers alone do not reject, retry or close the borrowed client.
          expect(f.client.requests.length, 1);
          expect(f.client.closed, isFalse);
        } finally {
          await body.close();
        }
      });
    }
  }

  test('should send v2 to the same endpoint with original key and target credentials and matching ACK', () async {
    // Given an original TKL request whose transport ID differs from the Studio target.
    final source = registeredTestRequest();
    final packet = registeredTestPacket(source: source, target: f.httpConnection);
    final expected = SubmissionCodec.acknowledgementFromJson(f.acknowledgement(source));
    f.client.respond(submissionJsonResponse(SubmissionCodec.acknowledgementToJson(expected)));
    // When the public typed v2 capability sends through the actual HTTP adapter.
    final result = await f.transport().submitRegisteredMaterial(packet);
    // Then the original intent/key and exact target headers/endpoint produce that real response ACK.
    final sent = f.client.requests.single;
    expect(sent.uri, f.httpConnection.endpoint);
    expect(sent.method, 'POST');
    expect(sent.followsRedirects, isFalse);
    expect(sent.headers['content-type'], 'application/json');
    expect(sent.headers['idempotency-key'], source.id);
    expect(sent.headers['authorization'], 'Bearer ${ControlledSubmissionCredentials.secret}');
    expect(f.credentials.calls, [f.httpConnection.id]);
    expect(sent.json, RegisteredMaterialSubmissionCodec.packetToJson(packet));
    expect(sent.json.length, 9);
    expect(result, expected);
    expect(source.transportConnectionId, 'lake');
    expect(f.client.closed, isFalse);
  });

  for (final mismatch in ['identity', 'endpoint', 'authorization']) {
    test('should reject pinned target $mismatch mismatch before credentials or send', () async {
      // Given the same packet destination except for one frozen target field.
      final actual = f.httpConnection;
      final target = HttpSubmissionConnection(
        id: mismatch == 'identity' ? 'another' : actual.id,
        endpoint: mismatch == 'endpoint' ? Uri.parse('https://other.example.test/submit') : actual.endpoint,
        requiresBearerToken: mismatch != 'authorization',
      );
      final packet = registeredTestPacket(target: target);
      // When the actual adapter is asked to send that differently pinned packet.
      final pending = f.transport().submitRegisteredMaterial(packet);
      // Then no credential or HTTP operation occurs and the outcome is conclusively notSent.
      await expectLater(pending, throwsA(isA<SubmissionAdapterException>()
        .having((e) => e.code, 'code', 'connectionMismatch')
        .having((e) => e.transportFailureOutcome, 'outcome', SubmissionTransportFailureOutcome.notSent)));
      expect(f.credentials.calls, isEmpty);
      expect(f.client.requests, isEmpty);
    });
  }

  for (final fault in ['missing', 'null', 'unknown', 'requestMismatch', 'subjectMismatch', 'badTime', 'wrongContentType']) {
    test('should retain postdispatch uncertainty for $fault ACK with no internal retry', () async {
      // Given an actual POST and a deliberately malformed or mismatched server response.
      final source = registeredTestRequest();
      final ack = f.acknowledgement(source);
      switch (fault) {
        case 'missing': ack.remove('serverId');
        case 'null': ack['serverId'] = null;
        case 'unknown': ack['extra'] = null;
        case 'requestMismatch': ack['requestId'] = 'other';
        case 'subjectMismatch': ack['subjectId'] = 'other';
        case 'badTime': ack['receivedAt'] = '2026-02-30T00:00:00Z';
        case 'wrongContentType': break;
      }
      f.client.respond(submissionJsonResponse(ack,
        headers: fault == 'wrongContentType' ? {'content-type': 'text/plain'} : const {}));
      // When the concrete adapter parses its actual bounded response stream.
      final pending = f.transport().submitRegisteredMaterial(
        registeredTestPacket(source: source, target: f.httpConnection));
      // Then no malformed response accepts or causes an internal resend.
      await expectLater(pending, throwsA(isA<SubmissionAdapterException>()
        .having((e) => e.code, 'code', 'invalidAcknowledgement')
        .having((e) => e.transportFailureOutcome, 'outcome', SubmissionTransportFailureOutcome.unknown)));
      expect(f.client.requests.length, 1);
    });
  }

  for (final status in [204, 400, 409, 500]) {
    test('should keep HTTP $status uncertain after one v2 POST', () async {
      // Given a response status that supplies no matching durable acknowledgement.
      f.client.respond(submissionEmptyResponse(status));
      final packet = registeredTestPacket(target: f.httpConnection);
      // When the actual HTTP transport sends the v2 packet.
      final pending = f.transport().submitRegisteredMaterial(packet);
      // Then the potentially accepted result is unknown with exactly one attempt.
      await expectLater(pending, throwsA(isA<SubmissionAdapterException>()
        .having((e) => e.transportFailureOutcome, 'outcome', SubmissionTransportFailureOutcome.unknown)));
      expect(f.client.requests.length, 1);
    });
  }

  test('should abort a postdispatch retired v2 operation and discard its late ACK', () async {
    // Given a held HTTP response and the same lifetime cancellation as legacy transport.
    final entered = Completer<void>();
    final response = Completer<SubmissionAcknowledgement>();
    final cancelled = Completer<void>();
    final source = registeredTestRequest();
    f.client.handler = (_) async {
      entered.complete();
      return submissionJsonResponse(SubmissionCodec.acknowledgementToJson(await response.future));
    };
    final adapter = f.transport(cancellation: cancelled.future);
    final pending = adapter.submitRegisteredMaterial(registeredTestPacket(source: source, target: f.httpConnection));
    final assertion = expectLater(pending, throwsA(isA<SubmissionAdapterException>()
      .having((e) => e.transportFailureOutcome, 'outcome', SubmissionTransportFailureOutcome.unknown)));
    await submissionEntered(entered);
    // When cancellation retires potential IO before the remote ACK arrives.
    cancelled.complete();
    await assertion;
    response.complete(SubmissionCodec.acknowledgementFromJson(f.acknowledgement(source)));
    // Then the abort signal completes and no internal retry or borrower close occurs.
    await f.client.requests.single.abort;
    expect(f.client.requests.length, 1);
    expect(f.client.closed, isFalse);
  });

  test('should classify a v2 credential failure as notSent without HTTP work', () async {
    // Given credentials unavailable before any POST can be attempted.
    f.credentials.handler = (_) => null;
    final packet = registeredTestPacket(target: f.httpConnection);
    // When the typed v2 operation requests the target grant.
    final pending = f.transport().submitRegisteredMaterial(packet);
    // Then the safe notSent result never reaches HTTP or retries internally.
    await expectLater(pending, throwsA(isA<SubmissionAdapterException>()
      .having((e) => e.transportFailureOutcome, 'outcome', SubmissionTransportFailureOutcome.notSent)));
    expect(f.client.requests, isEmpty);
    expect(f.credentials.calls, [f.httpConnection.id]);
  });

  test('should leave legacy v1 body headers receipts and ACK behavior unchanged', () async {
    // Given an ordinary legacy packet with its complete physical receipts.
    final request = f.request();
    final packet = f.packet(request);
    f.client.respond(submissionJsonResponse(f.acknowledgement(request), status: 201));
    // When the existing submit method uses the shared private HTTP mechanics.
    final ack = await f.transport().submit(packet);
    // Then all eight fields, receipt semantics and original transport identity remain v1.
    final sent = f.client.requests.single;
    expect(sent.json, SubmissionCodec.packetToJson(packet));
    expect(sent.json.length, 8);
    expect(sent.json['version'], 1);
    expect(((sent.json['materials'] as List).single as Map).containsKey('receipt'), isTrue);
    expect(sent.json.containsKey('registeredMaterial'), isFalse);
    expect(sent.headers['idempotency-key'], request.id);
    expect(ack.requestId, request.id);
  });
}
