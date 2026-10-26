import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

import '../support/submission_http_fixture.dart';
import 'registered_material_submission_test.dart' show registeredTestPacket, registeredTestRequest;

void main() {
  late SubmissionHttpFixture f;
  setUp(() { f = SubmissionHttpFixture(); });
  tearDown(() { f.dispose(); });

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
