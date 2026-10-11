import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:textus_flutter_core/textus_flutter_core.dart';

import '../support/submission_fixture.dart';
import '../support/submission_http_fixture.dart';

void main() {
  late SubmissionHttpFixture fixture;
  setUp(() {
    // Given independently owned controlled HTTP/credential ports.
    fixture = SubmissionHttpFixture();
    // When the public transport is constructed without submitting a packet.
    fixture.transport();
    // Then construction performs no credential or network IO.
    expect(fixture.client.requests, isEmpty);
    expect(fixture.credentials.calls, isEmpty);
  });
  tearDown(() {
    // Given every operation in this scenario has completed or retired.
    final borrowed = fixture.client;
    // When the test owner disposes its client.
    fixture.dispose();
    // Then the controlled lifetime marker confirms owner cleanup.
    expect(borrowed.closed, isTrue);
  });

  group('HB6 exact encoded packet and explicit server acceptance', () {
    for (final anonymous in [false, true]) {
      for (final status in [200, 201]) {
        test(
          '${anonymous ? 'anonymous' : 'authenticated'} $status matching acknowledgement',
          () async {
            // Given exact original provenance, opaque context and manual whitespace.
            final request = fixture.request();
            final packet = fixture.packet(request);
            fixture.client.handler = (captured) {
              // Given the actual transport dispatches one configured JSON POST.
              expect(captured.method, 'POST');
              expect(
                captured.uri.toString(),
                fixture.httpConnection.endpoint.toString(),
              );
              expect(captured.followsRedirects, isFalse);
              expect(captured.headers['content-type'], 'application/json');
              expect(captured.headers['accept'], 'application/json');
              expect(captured.headers['idempotency-key'], request.id);
              expect(
                captured.headers['authorization'],
                anonymous
                    ? isNull
                    : 'Bearer ${ControlledSubmissionCredentials.secret}',
              );
              // When the controlled server returns a matching strict acceptance.
              final response = submissionJsonResponse(
                fixture.acknowledgement(request),
                status: status,
              );
              // Then receipt existence and bare HTTP status remain separate from acceptance.
              return response;
            };
            // When the public transport submits the complete immutable packet.
            final acknowledgement = await fixture
                .transport(anonymous: anonymous)
                .submit(packet);
            // Then wire data equals the A codec and preserves all opaque values exactly.
            final captured = fixture.client.requests.single;
            expect(captured.json, SubmissionCodec.packetToJson(packet));
            expect(captured.json['payload'], request.payload);
            expect(captured.json['extensions'], request.extensions);
            final materials = captured.json['materials']! as List;
            expect(
              (materials.single as Map)['provenance'],
              request.materials.single.provenance,
            );
            expect(
              (materials.single as Map)['receipt'],
              SubmissionCodec.receiptToJson(packet.receipts['photo']!),
            );
            expect(captured.json.containsKey('document'), isFalse);
            expect(
              utf8.decode(captured.bytes),
              allOf(
                isNot(contains('/private/editor/draft')),
                isNot(contains(ControlledSubmissionCredentials.secret)),
              ),
            );
            expect(
              acknowledgement,
              SubmissionCodec.acknowledgementFromJson(
                fixture.acknowledgement(request),
              ),
            );
            expect(fixture.credentials.calls, anonymous ? isEmpty : ['server']);
            expect(fixture.client.closed, isFalse);
          },
        );
      }
    }

    for (final mutation in [
      'requestId',
      'subjectId',
      'serverId',
      'receivedAt',
      'extra',
      'missing',
      'array',
      'invalidJson',
      'type',
      'contentType',
    ]) {
      test('$mutation cannot create server acceptance', () async {
        // Given an HTTP 200 with one malformed acknowledgement clause.
        final request = fixture.request();
        final acknowledgement = fixture.acknowledgement(request);
        switch (mutation) {
          case 'requestId':
            acknowledgement['requestId'] = 'other';
          case 'subjectId':
            acknowledgement['subjectId'] = 'other';
          case 'serverId':
            acknowledgement['serverId'] = '  ';
          case 'receivedAt':
            acknowledgement['receivedAt'] = '2026-02-30T00:00:00Z';
          case 'extra':
            acknowledgement['secret'] = ControlledSubmissionCredentials.secret;
          case 'missing':
            acknowledgement.remove('extensions');
          case 'type':
            acknowledgement['serverId'] = 7;
        }
        fixture.client.handler = (_) {
          // Given this controlled response uses the selected malformed body/type.
          final supplied = mutation;
          // When the concrete HTTP stream is returned to the transport.
          if (supplied == 'invalidJson') {
            return http.StreamedResponse(
              Stream<List<int>>.value(utf8.encode('{private invalid json')),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          // Then only a strict JSON acknowledgement could pass the public decoder.
          return submissionJsonResponse(
            supplied == 'array' ? [] : acknowledgement,
            headers: {
              if (supplied == 'contentType') 'content-type': 'text/plain',
            },
          );
        };
        // When the actual transport parses and independently matches both identities.
        final submitting = fixture.transport().submit(fixture.packet(request));
        // Then the safe nonretryable failure cannot mark a queue Submitted.
        await expectLater(
          submitting,
          throwsA(
            submissionFailure(
              'invalidAcknowledgement',
              stage: SubmissionFailureStage.transport,
            ),
          ),
        );
        expect(fixture.client.requests.length, 1);
      });
    }

    for (final status in [202, 204, 206, 299]) {
      test('$status has no explicit accepted acknowledgement', () async {
        // Given a success status other than the explicit 200/201 contract.
        final request = fixture.request();
        fixture.client.respond(
          submissionJsonResponse(
            fixture.acknowledgement(request),
            status: status,
          ),
        );
        // When submit receives the selected generic success status.
        final submitting = fixture.transport().submit(fixture.packet(request));
        // Then even a matching body cannot override the acceptance status contract.
        await expectLater(
          submitting,
          throwsA(
            submissionFailure(
              'acknowledgementMissing',
              stage: SubmissionFailureStage.transport,
            ),
          ),
        );
      });
    }

    test('connection mismatch fails before token retrieval or HTTP', () async {
      // Given a complete packet bound to another configured transport identity.
      final request = fixture.request(transportId: 'other');
      // When a direct call supplies it to this configured transport.
      final submitting = fixture.transport().submit(fixture.packet(request));
      // Then configuration rejection prevents all credential/network IO.
      await expectLater(
        submitting,
        throwsA(
          submissionFailure(
            'connectionMismatch',
            stage: SubmissionFailureStage.configuration,
          ),
        ),
      );
      expect(fixture.credentials.calls, isEmpty);
      expect(fixture.client.requests, isEmpty);
    });
  });

  group('HB7 fixed status attribution, privacy and durable failure', () {
    final cases = [
      (401, 'authRequired', false, SubmissionFailureStage.configuration),
      (403, 'permissionDenied', false, SubmissionFailureStage.transport),
      (408, 'serviceUnavailable', true, SubmissionFailureStage.transport),
      (429, 'serviceUnavailable', true, SubmissionFailureStage.transport),
      (500, 'serviceUnavailable', true, SubmissionFailureStage.transport),
      (503, 'serviceUnavailable', true, SubmissionFailureStage.transport),
      (400, 'requestRejected', false, SubmissionFailureStage.transport),
      (302, 'redirectRejected', false, SubmissionFailureStage.transport),
    ];
    for (final drive in [false, true]) {
      for (final scenario in cases) {
        test(
          '${drive ? 'Drive' : 'HTTP'} ${scenario.$1} safe status classification',
          () async {
            // Given a selected status with sensitive body/header markers.
            final request = fixture.request();
            fixture.client.respond(
              submissionJsonResponse(
                {
                  'error': {'message': ControlledSubmissionCredentials.secret},
                },
                status: scenario.$1,
                headers: {'location': 'https://secret.test/private-session'},
              ),
            );
            // When the actual adapter receives this controlled streamed response.
            final operation = drive
                ? fixture.drive().prepare(
                    request: request,
                    material: request.materials.single,
                  )
                : fixture.transport().submit(fixture.packet(request));
            // Then the stage and retry policy are fixed without leaking response data.
            await expectLater(
              operation,
              throwsA(
                submissionFailure(
                  scenario.$2,
                  stage: scenario.$4 == SubmissionFailureStage.configuration
                      ? scenario.$4
                      : drive
                      ? SubmissionFailureStage.storage
                      : scenario.$4,
                  retryable: scenario.$3,
                ),
              ),
            );
            expect(fixture.client.requests.length, 1);
            expect(fixture.client.closed, isFalse);
          },
        );
      }
    }

    for (final reason in [
      'rateLimitExceeded',
      'userRateLimitExceeded',
      'insufficientPermissions',
    ]) {
      for (final drive in [true, false]) {
        test(
          '${drive ? 'Drive' : 'HTTP'} 403 $reason only allowlisted Drive reasons retry',
          () async {
            // Given a sensitive error body with a documented or unrelated reason.
            final request = fixture.request();
            fixture.client.respond(
              submissionJsonResponse({
                'error': {
                  'message': ControlledSubmissionCredentials.secret,
                  'errors': [
                    {
                      'reason': reason,
                      'message': ControlledSubmissionCredentials.secret,
                    },
                  ],
                },
              }, status: 403),
            );
            // When a concrete adapter receives that 403 response.
            final operation = drive
                ? fixture.drive().prepare(
                    request: request,
                    material: request.materials.single,
                  )
                : fixture.transport().submit(fixture.packet(request));
            // Then only the two Google rate-limit reasons allow Drive retry.
            final limited = drive && reason != 'insufficientPermissions';
            await expectLater(
              operation,
              throwsA(
                submissionFailure(
                  limited ? 'rateLimited' : 'permissionDenied',
                  stage: drive
                      ? SubmissionFailureStage.storage
                      : SubmissionFailureStage.transport,
                  retryable: limited,
                ),
              ),
            );
            expect(fixture.client.requests.length, 1);
          },
        );
      }
    }

    for (final drive in [true, false]) {
      for (final location in ['send', 'stream']) {
        test(
          '${drive ? 'Drive' : 'HTTP'} $location exception has no raw public cause',
          () async {
            // Given an HTTP client/stream failure containing a sensitive marker.
            final request = fixture.request();
            fixture.client.handler = (_) {
              // Given a controlled failure at either send or body streaming.
              final error = StateError(ControlledSubmissionCredentials.secret);
              // When that stage throws its private exception.
              if (location == 'send') throw error;
              // Then stream errors are observed under the same safe failure policy.
              return http.StreamedResponse(Stream<List<int>>.error(error), 200);
            };
            // When the public adapter observes this private client exception.
            final operation = drive
                ? fixture.drive().prepare(
                    request: request,
                    material: request.materials.single,
                  )
                : fixture.transport().submit(fixture.packet(request));
            // Then a fixed retryable stage failure retains no body/URL/cause.
            await expectLater(
              operation,
              throwsA(
                submissionFailure(
                  'connectionFailed',
                  retryable: true,
                  stage: drive
                      ? SubmissionFailureStage.storage
                      : SubmissionFailureStage.transport,
                ),
              ),
            );
            expect(fixture.client.requests.length, 1);
            expect(fixture.client.closed, isFalse);
          },
        );
      }
    }

    test('raw client error never enters real SQLite failure history', () async {
      // Given real file SQLite intent with a concrete failing HTTP transport.
      final disk = await SubmissionFixture.create();
      addTearDown(disk.dispose);
      final queue = await disk.openQueue();
      final request = await disk.request(withMaterials: false);
      fixture.client.handler = (_) {
        // Given a private client exception that must not enter durable history.
        final error = StateError(ControlledSubmissionCredentials.secret);
        // When the concrete transport sends its actual request.
        throw error;
        // Then only the transport's fixed safe failure may reach real SQLite.
      };
      final service = disk.service(
        queue,
        transports: {'server': fixture.transport()},
      );
      await service.commit(request);
      // When the real queue driver records the adapter's safe retryable failure.
      final result = await service.processNext(networkAllowed: true);
      await service.close();
      await queue.close();
      final reopened = await disk.openQueue();
      final record = (await reopened.find(request.id))!;
      // Then a distinct SQLite handle retains safe failure, unchanged intent and no secret.
      expect(result.outcome, SubmissionRunOutcome.failed);
      expect(record.request, request);
      expect(record.state, SubmissionState.submissionFailed);
      expect(record.lastFailure!.stage, SubmissionFailureStage.transport);
      expect(record.lastFailure!.code, 'connectionFailed');
      expect(record.lastFailure!.retryable, isTrue);
      expect(
        jsonEncode(SubmissionCodec.recordToJson(record)),
        isNot(contains(ControlledSubmissionCredentials.secret)),
      );
      expect(fixture.client.requests.length, 1);
    });
  });

  group('HB8 transport retirement and response bounds', () {
    test('a completed response cannot acknowledge a retired run', () async {
      // Given an owner that retires as the actual acknowledgement body is read.
      var current = true;
      final request = fixture.request();
      fixture.client.handler = (_) {
        // Given valid server acceptance bytes ready on the response stream.
        final bytes = utf8.encode(jsonEncode(fixture.acknowledgement(request)));
        // When delivery retires the owning run before submit returns.
        final body = Stream<List<int>>.value(bytes).map((value) {
          // Given a valid completed response for this request.
          final captured = value;
          // When its owner is retired during delivery.
          current = false;
          // Then no acknowledgement may escape after the awaited body completes.
          return captured;
        });
        // Then the public transport must independently recheck current ownership.
        return http.StreamedResponse(
          body,
          200,
          headers: {'content-type': 'application/json'},
        );
      };
      // When submit observes the completed body under the retired owner.
      final submitting = fixture
          .transport(isRunCurrent: () => current)
          .submit(fixture.packet(request));
      // Then strict valid content does not defeat cancellation.
      await expectLater(
        submitting,
        throwsA(
          submissionFailure(
            'operationCancelled',
            stage: SubmissionFailureStage.transport,
            retryable: true,
          ),
        ),
      );
      expect(fixture.client.requests.length, 1);
    });

    test('oversized acknowledgement stream is aborted before decode', () async {
      // Given a response body larger than the shared 262144-byte bound.
      final request = fixture.request();
      final aborted = Completer<void>();
      fixture.client.handler = (captured) {
        // Given the operation-owned abort trigger on the real request.
        captured.abort.then((_) => aborted.complete());
        // When the controlled stream emits an oversized body.
        final body = Stream<List<int>>.value(Uint8List(262145));
        // Then the reader must bound/cancel it before schema decoding.
        return http.StreamedResponse(
          body,
          200,
          headers: {'content-type': 'application/json'},
        );
      };
      // When the transport reads the actual oversized response stream.
      final submitting = fixture.transport().submit(fixture.packet(request));
      // Then safe invalidResponse, abortion and no retry are observable.
      await expectLater(
        submitting,
        throwsA(
          submissionFailure(
            'invalidResponse',
            stage: SubmissionFailureStage.transport,
          ),
        ),
      );
      await submissionEntered(aborted);
      expect(fixture.client.requests.length, 1);
      expect(fixture.client.closed, isFalse);
    });
  });
}
