import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

import '../support/submission_fixture.dart';
import '../support/submission_http_fixture.dart';

void main() {
  late SubmissionFixture f;
  setUp(() async {
    // Given a scenario requiring real originals and independently owned SQLite.
    f = await SubmissionFixture.create();
    // When this scenario receives the isolated fixture's actual disk lifetime.
    final owned = f.directory;
    // Then every later handle and original remains confined to that directory.
    expect(await owned.exists(), isTrue);
  });
  tearDown(() async {
    // Given services and independent queue handles retained by this fixture.
    final owned = f.directory;
    // When fixture cleanup drains work, closes handles and removes its own files.
    await f.dispose();
    // Then the actual temporary directory no longer exists.
    expect(await owned.exists(), isFalse);
  });

  test('DR1', () async {
    // Given real file photo/audio originals and a complete durable upload stage.
    var queue = await f.openQueue();
    var service = f.service(queue);
    final request = await f.request();
    await service.commit(request);
    await _uploadAll(service);
    final uploaded = (await queue.find(request.id))!;
    final raw = await _raw(f);
    await raw.execute(
      "CREATE TRIGGER reject_acceptance BEFORE UPDATE ON submission_jobs "
      "WHEN json_extract(NEW.body, '\$.state') = 'submitted' "
      "BEGIN SELECT RAISE(ABORT, 'controlled acceptance write failure'); END",
    );
    // When fake server acceptance is followed by a real SQLite complete-write failure.
    await expectLater(
      service.processNext(networkAllowed: true),
      throwsA(isA<DatabaseException>()),
    );
    final uncertain = (await queue.find(request.id))!;
    // Then earliest potentially dispatched claim is durable without local acceptance.
    expect(f.transport.remote[request.id], isNotNull);
    expect(uncertain.state, SubmissionState.submitting);
    expect(uncertain.transportCheckpoint!.claimCount, 5);
    expect(uncertain.transportCheckpoint!.startedAt, f.now);
    expect(uncertain.transportCheckpoint!.isLegacyUnknown, isFalse);
    expect(uncertain.acknowledgement, isNull);
    expect(uncertain.receipts, uploaded.receipts);
    expect(uncertain.reservations, uploaded.reservations);
    expect(f.storage.uploads, 2);
    final firstPacket = f.transport.packets.single;
    final firstWire = SubmissionCodec.packetToJson(firstPacket);
    await raw.execute('DROP TRIGGER reject_acceptance');
    await raw.close();
    await service.close();
    await queue.close();

    // Given a distinct service and real queue handle after released owner shutdown.
    queue = await f.openQueue();
    service = f.service(queue);
    final restarted = (await queue.find(request.id))!;
    // When the restarted record is projected and existing intent requests a wake.
    final status = SubmissionTransferStatus.fromRecord(
      restarted,
      observedAt: f.now,
    );
    final wake = await service.requestRun(request.id);
    // Then presentation preserves uncertainty and wake changes no queue identity/facts.
    expect(restarted.state, SubmissionState.readyToSubmit);
    expect(
      status.submission.state,
      SubmissionTransferOperationState.outcomeUnknown,
    );
    expect(status.submission.leaseExpiresAt, isNull);
    expect(status.actions, {SubmissionTransferAction.requestRun});
    expect(wake.record, restarted);
    expect(await queue.find(request.id), restarted);
    expect(restarted.transportCheckpoint, uncertain.transportCheckpoint);
    expect(restarted.request, request);
    // When the same idempotent packet POST recovers the matching fake acknowledgement.
    final recovered = await service.processNext(networkAllowed: true);
    await service.close();
    await queue.close();
    final finalQueue = await f.openQueue();
    final submitted = (await finalQueue.find(request.id))!;
    // Then no upload repeats, exact provenance/whitespace survives and only ack clears.
    expect(recovered.outcome, SubmissionRunOutcome.submitted);
    expect(submitted, recovered.record);
    expect(submitted.transportCheckpoint, isNull);
    expect(submitted.acknowledgement, f.transport.remote[request.id]);
    expect(submitted.request.id, request.id);
    expect(submitted.request.subjectId, request.subjectId);
    expect(submitted.request.kind, request.kind);
    expect(submitted.request, request);
    expect(submitted.reservations, uploaded.reservations);
    expect(submitted.receipts, uploaded.receipts);
    expect(f.transport.submits, 2);
    expect(f.transport.packets.last, firstPacket);
    expect(SubmissionCodec.packetToJson(f.transport.packets.last), firstWire);
    expect(f.storage.prepares, 2);
    expect(f.storage.uploads, 2);
    expect(f.storage.uploadedBytes, [
      SubmissionFixture.photoBytes,
      SubmissionFixture.audioBytes,
    ]);
    expect(request.payload['transcript'], '  手入力\n原文  ');
    for (final material in request.materials) {
      // Given each real original referenced by both identical accepted packets.
      final wire = (firstWire['materials']! as List).cast<Map>().singleWhere(
        (value) => value['key'] == material.key,
      );
      // When the real original is reread independently after queue/server recovery.
      final bytes = await f.materials.readMaterial(material.original);
      // Then exact original bytes, full reference and provenance remain unchanged.
      expect(
        bytes,
        material.key == 'photo'
            ? SubmissionFixture.photoBytes
            : SubmissionFixture.audioBytes,
      );
      expect(wire['original'], material.original.toJson());
      expect(wire['provenance'], material.provenance);
    }
  });

  group('DR2 dispatch checkpoint, ownership and retirement fences', () {
    test('actual checkpoint write failure prevents transport', () async {
      // Given no-upload intent and a real SQLite fault restricted to checkpoint writes.
      final queue = await f.openQueue();
      final service = f.service(queue);
      final request = await f.request(withMaterials: false);
      await service.commit(request);
      final raw = await _raw(f);
      await raw.execute(
        "CREATE TRIGGER reject_dispatch BEFORE UPDATE ON submission_jobs "
        "WHEN json_extract(NEW.body, '\$.transportCheckpoint') IS NOT NULL "
        "BEGIN SELECT RAISE(ABORT, 'controlled dispatch write failure'); END",
      );
      // When the service attempts durable dispatch before calling any transport.
      await expectLater(
        service.processNext(networkAllowed: true),
        throwsA(isA<DatabaseException>()),
      );
      // Then the real failed transaction preserves the lease but has no checkpoint/POST.
      final record = (await queue.find(request.id))!;
      expect(record.state, SubmissionState.submitting);
      expect(record.transportCheckpoint, isNull);
      expect(f.transport.submits, 0);
      await raw.execute('DROP TRIGGER reject_dispatch');
      await raw.close();
    });

    test('competing handle steals expired lease after awaited checkpoint', () async {
      // Given two independent real handles and an awaited dispatch checkpoint barrier.
      final queue = await f.openQueue();
      final other = await f.openQueue();
      final controlled = ControlledQueue(queue);
      final service = f.service(controlled);
      final request = await f.request(withMaterials: false);
      await service.commit(request);
      final entered = Completer<void>();
      final release = Completer<void>();
      controlled.after = (name) async {
        // Given the actual durable checkpoint has finished on the first handle.
        if (name != 'markTransportDispatch') return;
        entered.complete();
        // When checkpoint return is held under a bounded test-owned release signal.
        await release.future.timeout(const Duration(seconds: 2));
        // Then the service must renew ownership after this real awaited boundary.
      };
      final running = service.processNext(networkAllowed: true);
      try {
        await submissionEntered(entered);
        final earliest = (await other.find(request.id))!.transportCheckpoint;
        // When wall time expires and the competing real handle claims this same intent.
        f.now = f.now.add(const Duration(minutes: 6));
        final stolen = await other.claimNext(
          now: f.now,
          leaseToken: 'newOwner',
          leaseDuration: const Duration(minutes: 5),
        );
        release.complete();
        final result = await running.timeout(const Duration(seconds: 2));
        // Then old-owner renewal prevents submit and cannot erase the new claim/checkpoint.
        expect(result.outcome, SubmissionRunOutcome.leaseLost);
        expect(f.transport.submits, 0);
        expect(await other.find(request.id), stolen);
        expect(stolen!.transportCheckpoint, earliest);
      } finally {
        if (!release.isCompleted) release.complete();
        await running.timeout(const Duration(seconds: 2));
      }
    });

    for (final closeOwner in [false, true]) {
      test(
        '${closeOwner ? 'close' : 'cancel'} after checkpoint prevents submit',
        () async {
          // Given no-upload intent and a barrier after its actual checkpoint commit.
          final queue = await f.openQueue();
          final controlled = ControlledQueue(queue);
          final service = f.service(controlled);
          final request = await f.request(withMaterials: false);
          await service.commit(request);
          var current = true;
          final entered = Completer<void>();
          final release = Completer<void>();
          controlled.after = (name) async {
            // Given the real dispatch checkpoint, before final lease renewal.
            if (name != 'markTransportDispatch') return;
            entered.complete();
            // When this callback holds the awaited return for owner retirement.
            await release.future.timeout(const Duration(seconds: 2));
            // Then the next current-owner check observes the actual retired lifetime.
          };
          final running = service.processNext(
            networkAllowed: true,
            isRunCurrent: () => current,
          );
          Future<void>? closing;
          try {
            await submissionEntered(entered);
            final pending = (await queue.find(request.id))!.transportCheckpoint;
            // When the owner cancels or closes while durable checkpoint return is held.
            if (closeOwner) {
              closing = service.close();
            } else {
              current = false;
            }
            release.complete();
            final result = await running.timeout(const Duration(seconds: 2));
            await closing;
            // Then release preserves uncertainty even though this owner never submits.
            expect(result.outcome, SubmissionRunOutcome.cancelled);
            expect(result.record!.state, SubmissionState.readyToSubmit);
            expect(result.record!.transportCheckpoint, pending);
            expect(f.transport.submits, 0);
            expect(await queue.find(request.id), result.record);
          } finally {
            if (!release.isCompleted) release.complete();
            await running.timeout(const Duration(seconds: 2));
            await closing;
          }
        },
      );
    }

    test(
      'late fake acknowledgement cannot complete a cancelled owner',
      () async {
        // Given an actual entered transport, complete dispatch checkpoint and held ack.
        final queue = await f.openQueue();
        final service = f.service(queue);
        final request = await f.request(withMaterials: false);
        await service.commit(request);
        final entered = Completer<void>();
        final release = Completer<void>();
        var current = true;
        f.transport.onSubmit = (packet) async {
          // Given the controlled server has actually entered submit for this packet.
          entered.complete();
          // When acknowledgement is held until after the caller retires.
          await release.future.timeout(const Duration(seconds: 2));
          final ack = f.transport.acknowledgement(packet.request);
          // Then only Core's still-current owner could checkpoint this late result.
          return ack;
        };
        final running = service.processNext(
          networkAllowed: true,
          isRunCurrent: () => current,
        );
        try {
          await submissionEntered(entered);
          final earliest = (await queue.find(request.id))!.transportCheckpoint;
          // When this owner is invalidated before the matching acknowledgement arrives.
          current = false;
          release.complete();
          final result = await running.timeout(const Duration(seconds: 2));
          // Then ready uncertainty survives and no matching late ack becomes submitted.
          expect(result.outcome, SubmissionRunOutcome.cancelled);
          expect(result.record!.transportCheckpoint, earliest);
          expect(result.record!.acknowledgement, isNull);
          expect(result.record!.state, SubmissionState.readyToSubmit);
          expect(f.transport.remote[request.id], isNotNull);
        } finally {
          if (!release.isCompleted) release.complete();
          await running.timeout(const Duration(seconds: 2));
        }
      },
    );
  });

  group('DR3 safe attempt outcome and identity-preserving actions', () {
    for (final outcome in [
      SubmissionTransportFailureOutcome.notSent,
      SubmissionTransportFailureOutcome.rejected,
    ]) {
      test(
        'first ${outcome.name} clears only this claim and retains uploaded originals',
        () async {
          // Given real fully uploaded originals and a trusted first transport refusal.
          final queue = await f.openQueue();
          final service = f.service(queue);
          final request = await f.request();
          await service.commit(request);
          await _uploadAll(service);
          final uploaded = (await queue.find(request.id))!;
          f.transport.onSubmit = (_) async {
            // Given this current attempt has conclusively not accepted the packet.
            final failure = _adapterFailure(outcome);
            // When the trusted port attributes its actual no-send/refusal result.
            throw failure;
            // Then Core may clear only the exact current-claim checkpoint.
          };
          // When that exact first dispatch fails, then explicit retry reuses the intent.
          final failed = await service.processNext(networkAllowed: true);
          final retried = await service.retry(request.id);
          // Then uncertainty clears while every original/receipt/reservation/history remains.
          expect(failed.record!.transportCheckpoint, isNull);
          expect(failed.record!.failureHistory.length, 1);
          expect(failed.record!.receipts, uploaded.receipts);
          expect(failed.record!.reservations, uploaded.reservations);
          expect(retried.record.request, request);
          expect(retried.record.failureHistory, failed.record!.failureHistory);
          f.transport.onSubmit = null;
          final submitted = await service.processNext(networkAllowed: true);
          expect(submitted.outcome, SubmissionRunOutcome.submitted);
          expect(f.storage.uploads, 2);
          expect(f.transport.packets.last, f.transport.packets.first);
        },
      );

      test(
        'earlier unknown survives later ${outcome.name}, configuration and reopen',
        () async {
          // Given a first unclassified result whose server outcome cannot be proven.
          final queue = await f.openQueue();
          final service = f.service(queue);
          final request = await f.request();
          await service.commit(request);
          await _uploadAll(service);
          f.transport.onSubmit = (_) async {
            // Given an untrusted/unclassified current-attempt transport result.
            final failure = _adapterFailure(
              SubmissionTransportFailureOutcome.unknown,
            );
            // When that port fails, acceptance remains unconfirmed.
            throw failure;
            // Then the earliest potentially dispatched claim must remain durable.
          };
          final unknown = await service.processNext(networkAllowed: true);
          final earliest = unknown.record!.transportCheckpoint;
          await service.retry(request.id);
          f.transport.onSubmit = (_) async {
            // Given a later attempt conclusively refused before acceptance.
            final failure = _adapterFailure(outcome);
            // When this later attempt fails independently of the first.
            throw failure;
            // Then it cannot establish whether the older packet was accepted.
          };
          // When the later attributed attempt fails and a missing transport is retried.
          final refused = await service.processNext(networkAllowed: true);
          await service.retry(request.id);
          final missing = f.service(queue, transports: {});
          final configuration = await missing.processNext(networkAllowed: true);
          await missing.retry(request.id);
          final cancelledQueue = ControlledQueue(queue);
          var current = true;
          cancelledQueue.after = (name) async {
            // Given a later claim has returned its actual existing dispatch checkpoint.
            if (name != 'markTransportDispatch') return;
            // When the caller retires after that awaited boundary.
            current = false;
            // Then cancellation must preserve the earlier potentially accepted dispatch.
          };
          final cancelledService = f.service(cancelledQueue);
          // When this later owner cancels after observing the earliest checkpoint.
          final cancelled = await cancelledService.processNext(
            networkAllowed: true,
            isRunCurrent: () => current,
          );
          // Then it releases ready without erasing historical uncertainty.
          expect(cancelled.outcome, SubmissionRunOutcome.cancelled);
          expect(cancelled.record!.transportCheckpoint, earliest);
          await service.close();
          await missing.close();
          await cancelledService.close();
          await queue.close();
          final reopened = await f.openQueue();
          final retained = (await reopened.find(request.id))!;
          // Then earlier uncertainty/history/receipts survive both failures and restart.
          expect(refused.record!.transportCheckpoint, earliest);
          expect(configuration.record!.lastFailure!.code, 'transportMissing');
          expect(retained.transportCheckpoint, earliest);
          expect(retained.failureHistory.length, 3);
          expect(retained.receipts, unknown.record!.receipts);
          expect(retained.reservations, unknown.record!.reservations);
          expect(retained.request, request);
          expect(f.storage.uploads, 2);
          expect(f.transport.submits, 2);
        },
      );
    }

    for (final kind in ['raw', 'mismatch', 'timeout', 'unknownAdapter']) {
      test('$kind never clears possible dispatch', () async {
        // Given complete no-upload intent and one unclassified remote failure form.
        final queue = await f.openQueue();
        final service = f.service(
          queue,
          operationTimeout: const Duration(milliseconds: 20),
          leaseDuration: const Duration(seconds: 1),
        );
        final request = await f.request(withMaterials: false);
        await service.commit(request);
        final entered = Completer<void>();
        final released = Completer<SubmissionAcknowledgement>();
        f.transport.onSubmit = (packet) async {
          // Given actual entry to the transport after the durable dispatch checkpoint.
          entered.complete();
          // When the selected remote failure/late result occurs.
          if (kind == 'raw') throw StateError('private-raw-marker');
          if (kind == 'unknownAdapter') {
            throw _adapterFailure(SubmissionTransportFailureOutcome.unknown);
          }
          if (kind == 'mismatch') {
            return SubmissionAcknowledgement(
              requestId: 'other',
              subjectId: packet.request.subjectId,
              serverId: 'fake/other',
              receivedAt: f.now,
            );
          }
          // Then the held timeout result is released by the scenario's owned cleanup.
          return released.future.timeout(const Duration(seconds: 2));
        };
        final running = service.processNext(networkAllowed: true);
        try {
          await submissionEntered(entered);
          // When Core records the selected error, independently from any late ack.
          final result = await running.timeout(const Duration(seconds: 2));
          // Then safe failure retains earliest uncertainty without raw exception data.
          expect(result.outcome, SubmissionRunOutcome.failed);
          expect(result.record!.transportCheckpoint, isNotNull);
          expect(result.record!.acknowledgement, isNull);
          expect(
            jsonEncode(SubmissionCodec.recordToJson(result.record!)),
            isNot(contains('private-raw-marker')),
          );
          if (!released.isCompleted) {
            released.complete(f.transport.acknowledgement(request));
          }
          expect(await queue.find(request.id), result.record);
        } finally {
          if (!released.isCompleted) {
            released.complete(f.transport.acknowledgement(request));
          }
          await running.timeout(const Duration(seconds: 2));
        }
      });
    }

    test('requestRun reads freshly without queue mutation and submitted never wakes', () async {
      // Given existing ready no-upload intent and an independent queue owner.
      final queue = await f.openQueue();
      final service = f.service(queue);
      final request = await f.request(withMaterials: false);
      final ready = (await service.commit(request)).record;
      // When existing intent requests wake and a missing id attempts the same action.
      final wake = await service.requestRun(request.id);
      final calls = f.scheduler.calls;
      await expectLater(service.requestRun('missing'), throwsStateError);
      // Then wake changes no queue state/claim, while missing intent cannot schedule.
      expect(wake.record, ready);
      expect(await queue.find(request.id), ready);
      expect(f.scheduler.calls, calls);
      expect(f.transport.submits, 0);
      final active = (await queue.claimNext(
        now: f.now,
        leaseToken: 'external',
        leaseDuration: const Duration(minutes: 5),
      ))!;
      // When a fresh service read observes another active claim and retry is attempted.
      final activeWake = await service.requestRun(request.id);
      await expectLater(service.retry(request.id), throwsStateError);
      // Then wake can schedule existing work but cannot requeue or steal ownership.
      expect(activeWake.record, active);
      expect(await queue.find(request.id), active);
      final failed = await queue.fail(
        id: request.id,
        leaseToken: 'external',
        now: f.now,
        failure: _failure(active, f.now),
      );
      // When wake is requested for failed intent before explicit retry transitions it.
      final failedWake = await service.requestRun(request.id);
      // Then failed wake retains failure history and produces no fresh intent/dispatch.
      expect(failedWake.record, failed);
      expect(await queue.find(request.id), failed);
      await service.retry(request.id);
      final expired = (await queue.claimNext(
        now: f.now,
        leaseToken: 'expired',
        leaseDuration: const Duration(minutes: 5),
      ))!;
      f.now = f.now.add(const Duration(minutes: 6));
      // When an expired current claim requests wake, it is still a read plus schedule.
      final expiredWake = await service.requestRun(request.id);
      // Then expiry presentation does not itself claim or replace existing intent.
      expect(expiredWake.record, expired);
      expect(await queue.find(request.id), expired);
      final submitted = await service.processNext(networkAllowed: true);
      final before = f.scheduler.calls;
      // When submitted intent requests run or retry again, or service closes.
      final noWake = await service.requestRun(request.id);
      final noRetry = await service.retry(request.id);
      await service.close();
      // Then the matching accepted record remains unchanged and borrowed queue stays open.
      expect(noWake.record, submitted.record);
      expect(noRetry.record, submitted.record);
      expect(f.scheduler.calls, before);
      expect(await queue.find(request.id), submitted.record);
      expect(f.transport.submits, 1);
      expect(f.storage.uploads, 0);
      await expectLater(service.requestRun(request.id), throwsStateError);
    });
  });

  group('DR4 actual HTTP transport with controlled streams', () {
    test('missing local grant is notSent and sends zero POSTs', () async {
      // Given public HTTP transport with a controlled missing account grant.
      final fixture = _httpFixture();
      fixture.credentials.handler = (_) {
        // Given this actual credential callback is invoked before HTTP send.
        const String? missing = null;
        // When the account grant is unavailable.
        final result = missing;
        // Then no submit side effect has started.
        return result;
      };
      // When the public transport attempts a packet under that missing grant.
      final submitting = fixture.transport().submit(
        fixture.packet(fixture.request()),
      );
      // Then safe authorization failure explicitly reports no-send and borrows the client.
      await expectLater(
        submitting,
        throwsA(
          _httpFailure(
            'authRequired',
            SubmissionTransportFailureOutcome.notSent,
            stage: SubmissionFailureStage.configuration,
          ),
        ),
      );
      expect(fixture.client.requests, isEmpty);
      expect(fixture.client.closed, isFalse);
    });

    final responses = [
      (
        401,
        'authRequired',
        SubmissionTransportFailureOutcome.rejected,
        SubmissionFailureStage.configuration,
        false,
      ),
      (
        403,
        'permissionDenied',
        SubmissionTransportFailureOutcome.rejected,
        SubmissionFailureStage.transport,
        false,
      ),
      (
        409,
        'requestRejected',
        SubmissionTransportFailureOutcome.unknown,
        SubmissionFailureStage.transport,
        false,
      ),
      (
        302,
        'redirectRejected',
        SubmissionTransportFailureOutcome.unknown,
        SubmissionFailureStage.transport,
        false,
      ),
      (
        408,
        'serviceUnavailable',
        SubmissionTransportFailureOutcome.unknown,
        SubmissionFailureStage.transport,
        true,
      ),
      (
        429,
        'serviceUnavailable',
        SubmissionTransportFailureOutcome.unknown,
        SubmissionFailureStage.transport,
        true,
      ),
      (
        503,
        'serviceUnavailable',
        SubmissionTransportFailureOutcome.unknown,
        SubmissionFailureStage.transport,
        true,
      ),
      (
        202,
        'acknowledgementMissing',
        SubmissionTransportFailureOutcome.unknown,
        SubmissionFailureStage.transport,
        false,
      ),
    ];
    for (final scenario in responses) {
      test(
        '${scenario.$1} current attempt has ${scenario.$3.name} outcome',
        () async {
          // Given an actual configured packet and sensitive controlled error response.
          final fixture = _httpFixture();
          final packet = fixture.packet(fixture.request());
          fixture.client.respond(
            submissionJsonResponse({
              'private': ControlledSubmissionCredentials.secret,
            }, status: scenario.$1),
          );
          // When the public transport sends and classifies that exact response.
          final submitting = fixture.transport().submit(packet);
          // Then only explicit auth refusals are rejected, preserving exact wire identity.
          await expectLater(
            submitting,
            throwsA(
              _httpFailure(
                scenario.$2,
                scenario.$3,
                stage: scenario.$4,
                retryable: scenario.$5,
              ),
            ),
          );
          expect(
            fixture.client.requests.single.headers['idempotency-key'],
            packet.request.id,
          );
          expect(
            fixture.client.requests.single.json,
            SubmissionCodec.packetToJson(packet),
          );
          expect(fixture.client.closed, isFalse);
        },
      );
    }

    for (final kind in ['malformed', 'mismatched', 'missing', 'raw']) {
      test('$kind after send remains unknown', () async {
        // Given one controlled 200 acknowledgement or a private connection failure.
        final fixture = _httpFixture();
        final request = fixture.request();
        fixture.client.handler = (_) {
          // Given the actual request has reached the borrowed controlled HTTP client.
          final ack = fixture.acknowledgement(request);
          // When that response is malformed, mismatched, absent or loses connection.
          if (kind == 'raw') {
            throw StateError(ControlledSubmissionCredentials.secret);
          }
          if (kind == 'mismatched') ack['requestId'] = 'another';
          // Then only matching strict JSON could establish acceptance.
          return kind == 'malformed'
              ? http.StreamedResponse(
                  Stream<List<int>>.value(utf8.encode('{bad')),
                  200,
                  headers: {'content-type': 'application/json'},
                )
              : submissionJsonResponse(kind == 'missing' ? {} : ack);
        };
        // When submit observes that actual response/failure after its send boundary.
        final submitting = fixture.transport().submit(fixture.packet(request));
        // Then a safe error retains unknown server outcome and no sensitive cause/body.
        await expectLater(
          submitting,
          throwsA(
            _httpFailure(
              kind == 'raw' ? 'connectionFailed' : 'invalidAcknowledgement',
              SubmissionTransportFailureOutcome.unknown,
              retryable: kind == 'raw',
            ),
          ),
        );
        expect(fixture.client.requests.length, 1);
        expect(fixture.client.closed, isFalse);
      });
    }

    test('held sent request cancellation remains unknown and owned cleanup releases it', () async {
      // Given an actual entered HTTP send and a test-owned held response.
      final fixture = _httpFixture();
      final request = fixture.request();
      final entered = Completer<void>();
      final response = Completer<http.StreamedResponse>();
      final cancellation = Completer<void>();
      fixture.client.handler = (_) {
        // Given the borrowed client has captured the actual packet POST.
        entered.complete();
        // When this controlled response is held until explicit cleanup releases it.
        final pending = response.future.timeout(const Duration(seconds: 2));
        // Then cancellation must retire this operation without closing the client.
        return pending;
      };
      final submitting = fixture
          .transport(cancellation: cancellation.future)
          .submit(fixture.packet(request));
      final observed = expectLater(
        submitting,
        throwsA(
          _httpFailure(
            'operationCancelled',
            SubmissionTransportFailureOutcome.unknown,
            retryable: true,
          ),
        ),
      );
      try {
        await submissionEntered(entered);
        // When an explicit owner cancellation fires after actual send entry.
        cancellation.complete();
        await observed.timeout(const Duration(seconds: 2));
        // Then the sent outcome is unknown and the borrowed client remains usable.
        expect(fixture.client.requests.length, 1);
        expect(fixture.client.closed, isFalse);
      } finally {
        if (!cancellation.isCompleted) cancellation.complete();
        if (!response.isCompleted) {
          response.complete(
            submissionJsonResponse(fixture.acknowledgement(request)),
          );
        }
        await observed.timeout(const Duration(seconds: 2));
        await response.future;
      }
    });

    test(
      'valid matching acknowledgement returns acceptance with unchanged packet',
      () async {
        // Given exact server acceptance and a complete packet with edited whitespace.
        final fixture = _httpFixture();
        final request = fixture.request();
        final packet = fixture.packet(request);
        fixture.client.respond(
          submissionJsonResponse(fixture.acknowledgement(request)),
        );
        // When the actual public HTTP transport sends the idempotent packet.
        final ack = await fixture.transport().submit(packet);
        // Then strict matching identities alone establish this actual controlled acceptance.
        expect(
          ack,
          SubmissionCodec.acknowledgementFromJson(
            fixture.acknowledgement(request),
          ),
        );
        expect(
          fixture.client.requests.single.headers['idempotency-key'],
          request.id,
        );
        expect(
          fixture.client.requests.single.json,
          SubmissionCodec.packetToJson(packet),
        );
        expect(fixture.client.requests.single.json['payload'], request.payload);
        expect(request.payload['transcript'], '  手入力\n原文  ');
        expect(fixture.client.requests.single.followsRedirects, isFalse);
        expect(fixture.client.closed, isFalse);
      },
    );
  });

  group('DR5 literal legacy compatibility and fenced v2 transitions', () {
    for (final scenario in [
      'initial',
      'partial',
      'ready',
      'submitting',
      'failed',
      'submitted',
      'empty',
    ]) {
      test(
        'literal $scenario row reads/reopens without rewrite and transitions to v2',
        () async {
          // Given an independently authored exact old record, never new-encoder output.
          var queue = await f.openQueue();
          final legacy = _legacy(scenario);
          final raw = await _raw(f);
          final body = jsonEncode(legacy);
          await raw.insert('submission_jobs', {
            'request_id': 'legacyCommit',
            'kind': 'bookMaterial',
            'subject_id': 'legacySubject',
            'body': body,
          });
          final schema = await raw.query(
            'sqlite_master',
            where: "type IN ('table', 'index')",
            orderBy: 'name',
          );
          // When public codec and distinct real handles decode without any transition.
          final decoded = SubmissionCodec.recordFromJson(legacy);
          final first = (await queue.find('legacyCommit'))!;
          await queue.close();
          queue = await f.openQueue();
          final reopened = (await queue.find('legacyCommit'))!;
          // Then every old value remains exact and read never rewrites indexed persistence.
          expect(first, decoded);
          expect(reopened, decoded);
          expect((await raw.query('submission_jobs')).single['body'], body);
          final encoded = SubmissionCodec.recordToJson(decoded);
          final oldFields = {...encoded}..remove('transportCheckpoint');
          oldFields['version'] = 1;
          expect(oldFields, legacy);
          final ambiguous = ![
            'initial',
            'partial',
            'submitted',
          ].contains(scenario);
          expect(
            decoded.transportCheckpoint?.isLegacyUnknown ?? false,
            ambiguous,
          );
          expect(decoded.transportCheckpoint?.claimCount, isNull);
          expect(decoded.transportCheckpoint?.startedAt, isNull);
          expect(decoded.request.payload['transcript'], '  legacy\n text  ');
          if (scenario == 'submitted') {
            expect(decoded.acknowledgement!.requestId, 'legacyCommit');
            await raw.close();
            return;
          }
          // When the first real fenced claim writes the unchanged intent using record v2.
          f.now = f.now.add(const Duration(minutes: 6));
          final claimed = await queue.claimNext(
            now: f.now,
            leaseToken: 'migratedOwner',
            leaseDuration: const Duration(minutes: 5),
          );
          final row = (await raw.query('submission_jobs')).single;
          final persisted = Map<String, Object?>.from(
            jsonDecode(row['body']! as String) as Map,
          );
          // Then actual transition preserves identity/history and the additive database v2
          // schema established by public open, while old record-v1 values stay exact.
          expect(claimed!.request, decoded.request);
          expect(claimed.failureHistory, decoded.failureHistory);
          expect(claimed.receipts, decoded.receipts);
          expect(claimed.reservations, decoded.reservations);
          expect(claimed.transportCheckpoint, decoded.transportCheckpoint);
          expect(persisted['version'], 2);
          expect(persisted.containsKey('transportCheckpoint'), isTrue);
          expect(SubmissionCodec.recordFromJson(persisted), claimed);
          expect(await raw.rawQuery('PRAGMA user_version'), [
            {'user_version': 2},
          ]);
          expect(
            await raw.query(
              'sqlite_master',
              where: "type IN ('table', 'index')",
              orderBy: 'name',
            ),
            schema,
          );
          await queue.close();
          queue = await f.openQueue();
          expect(await queue.find('legacyCommit'), claimed);
          await raw.close();
        },
      );
    }

    for (final outcome in [
      SubmissionTransportFailureOutcome.notSent,
      SubmissionTransportFailureOutcome.rejected,
    ]) {
      test(
        'legacy ambiguity survives ${outcome.name}, cancellation and matching-ack recovery',
        () async {
          // Given a literal old complete-reference ready row and real independent handles.
          final queue = await f.openQueue();
          final raw = await _raw(f);
          await raw.insert('submission_jobs', {
            'request_id': 'legacyCommit',
            'kind': 'bookMaterial',
            'subject_id': 'legacySubject',
            'body': jsonEncode(_legacy('ready')),
          });
          final service = f.service(queue);
          f.transport.onSubmit = (_) async {
            // Given a trusted refusal of this new attempt on legacy-uncertain intent.
            final failure = _adapterFailure(outcome);
            // When that current attempt is conclusively refused.
            throw failure;
            // Then legacy uncertainty cannot gain a fabricated dispatch attribution.
          };
          // When processing/retrying that intent then releasing another owned claim.
          final failed = await service.processNext(networkAllowed: true);
          await service.retry('legacyCommit');
          final claimed = await queue.claimNext(
            now: f.now,
            leaseToken: 'cancelLegacy',
            leaseDuration: const Duration(minutes: 5),
          );
          await queue.markTransportDispatch(
            id: 'legacyCommit',
            leaseToken: 'cancelLegacy',
            now: f.now,
          );
          await queue.release(
            id: 'legacyCommit',
            leaseToken: 'cancelLegacy',
            now: f.now,
          );
          await service.close();
          await queue.close();
          final reopened = await f.openQueue();
          final retained = (await reopened.find('legacyCommit'))!;
          // Then no-send/refusal/cancellation/reopen leaves original unknown attribution intact.
          expect(failed.record!.transportCheckpoint!.isLegacyUnknown, isTrue);
          expect(retained.transportCheckpoint, claimed!.transportCheckpoint);
          expect(retained.transportCheckpoint!.claimCount, isNull);
          expect(retained.transportCheckpoint!.startedAt, isNull);
          expect(retained.failureHistory.length, 1);
          expect(retained.receipts.length, 1);
          expect(f.storage.uploads, 0);
          f.transport.onSubmit = null;
          // When the same request recovers a matching fake server acknowledgement.
          final recovered = await f
              .service(reopened)
              .processNext(networkAllowed: true);
          // Then matching acknowledgement alone clears legacy uncertainty.
          expect(recovered.outcome, SubmissionRunOutcome.submitted);
          expect(recovered.record!.transportCheckpoint, isNull);
          expect(recovered.record!.request, retained.request);
          expect(f.storage.uploads, 0);
          await raw.close();
        },
      );
    }

    test(
      'exact checkpoint keys/types/time/relationships and value equality',
      () {
        // Given literal valid legacy intent and a real semantic v2 pending checkpoint.
        final legacy = _legacy('ready');
        final pending = <String, Object?>{
          ...legacy,
          'version': 2,
          'transportCheckpoint': {
            'claimCount': 1,
            'startedAt': '2026-10-10T10:00:00+09:00',
            'isLegacyUnknown': false,
          },
        };
        // When the strict public record decoder reconstructs pending/legacy values.
        final value = SubmissionCodec.recordFromJson(pending);
        final same = SubmissionCodec.recordFromJson({...pending});
        final unknown = SubmissionCodec.recordFromJson(legacy);
        // Then checkpoints normalize UTC, compare by value and never invent legacy time/count.
        expect(value, same);
        expect(value.hashCode, same.hashCode);
        expect(
          value.transportCheckpoint,
          SubmissionTransportCheckpoint.pending(
            claimCount: 1,
            startedAt: DateTime.utc(2026, 10, 10, 1),
          ),
        );
        expect(
          value.transportCheckpoint!.hashCode,
          same.transportCheckpoint!.hashCode,
        );
        expect(value, isNot(unknown));
        expect(value.transportCheckpoint, isNot(unknown.transportCheckpoint));
        // Given independently constructed checkpoints differing in count or UTC time.
        final later = SubmissionTransportCheckpoint.pending(
          claimCount: 1,
          startedAt: DateTime.utc(2026, 10, 10, 1, 0, 1),
        );
        final anotherClaim = SubmissionTransportCheckpoint.pending(
          claimCount: 2,
          startedAt: DateTime.utc(2026, 10, 10, 1),
        );
        // When their ordinary value equality is compared with the earliest checkpoint.
        final earliest = value.transportCheckpoint!;
        // Then every attribution field distinguishes the actual pending value.
        expect(later, isNot(earliest));
        expect(anotherClaim, isNot(earliest));
        expect(
          unknown.transportCheckpoint,
          const SubmissionTransportCheckpoint.legacyUnknown(),
        );
        final c = Map<String, Object?>.from(
          pending['transportCheckpoint']! as Map,
        );
        final malformed = <Map<String, Object?>>[
          {...pending}..remove('transportCheckpoint'),
          {...pending, 'version': 3},
          {...pending, 'version': 2.0},
          {...pending, 'extra': true},
          for (final key in c.keys)
            {
              ...pending,
              'transportCheckpoint': {...c}..remove(key),
            },
          {
            ...pending,
            'transportCheckpoint': {...c, 'extra': true},
          },
          for (final count in [0, -1, 1.0, null, 3])
            {
              ...pending,
              'transportCheckpoint': {...c, 'claimCount': count},
            },
          for (final time in [
            null,
            '2026-10-10T01:00:00',
            '2026-02-30T01:00:00Z',
            '2026-10-10T02:00:00Z',
          ])
            {
              ...pending,
              'transportCheckpoint': {...c, 'startedAt': time},
            },
          {
            ...pending,
            'transportCheckpoint': {...c, 'isLegacyUnknown': 'false'},
          },
          {
            ...pending,
            'transportCheckpoint': {...c, 'isLegacyUnknown': true},
          },
          {
            ...pending,
            'transportCheckpoint': {
              'claimCount': null,
              'startedAt': null,
              'isLegacyUnknown': false,
            },
          },
          {...pending, 'claimCount': 0},
          {...pending, 'receipts': {}},
          {..._legacy('submitted'), 'version': 2, 'transportCheckpoint': c},
          {...legacy, 'transportCheckpoint': null},
        ];
        // When malformed schema or impossible checkpoint/state relationships are decoded.
        for (final row in malformed) {
          // Then they fail observably rather than repairing uncertainty or accepted intent.
          expect(
            () => SubmissionCodec.recordFromJson(row),
            throwsFormatException,
          );
        }
        expect(
          () => SubmissionTransportCheckpoint.pending(
            claimCount: 0,
            startedAt: DateTime.utc(2026),
          ),
          throwsArgumentError,
        );
        expect(
          SubmissionCodec.recordFromJson({
            ...pending,
            'transportCheckpoint': null,
          }).transportCheckpoint,
          isNull,
        );
      },
    );

    test('dispatch/clear fences, incomplete references and current-claim ownership', () async {
      // Given real queue intent and two handles with one positive current claim.
      final queue = await f.openQueue();
      final other = await f.openQueue();
      final request = await f.request();
      await queue.enqueue(request);
      final claimed = (await queue.claimNext(
        now: f.now,
        leaseToken: 'first',
        leaseDuration: const Duration(minutes: 5),
      ))!;
      // When incomplete references or incompatible clear attribution are presented.
      await expectLater(
        queue.markTransportDispatch(
          id: request.id,
          leaseToken: 'first',
          now: f.now,
        ),
        throwsStateError,
      );
      await expectLater(
        queue.fail(
          id: request.id,
          leaseToken: 'first',
          now: f.now,
          failure: _failure(
            claimed,
            f.now,
            stage: SubmissionFailureStage.storage,
          ),
          transportFailureOutcome: SubmissionTransportFailureOutcome.notSent,
        ),
        throwsArgumentError,
      );
      // Then neither rejected transaction changes claim or material checkpoints.
      expect(await other.find(request.id), claimed);
      await queue.release(id: request.id, leaseToken: 'first', now: f.now);
      final service = f.service(queue);
      await _uploadAll(service);
      final current = (await queue.claimNext(
        now: f.now,
        leaseToken: 'dispatch',
        leaseDuration: const Duration(minutes: 5),
      ))!;
      // When current ownership checkpoints twice, then another handle steals expiry.
      final marked = await queue.markTransportDispatch(
        id: request.id,
        leaseToken: 'dispatch',
        now: f.now,
      );
      final repeated = await queue.markTransportDispatch(
        id: request.id,
        leaseToken: 'dispatch',
        now: f.now.add(const Duration(seconds: 1)),
      );
      f.now = f.now.add(const Duration(minutes: 6));
      final stolen = (await other.claimNext(
        now: f.now,
        leaseToken: 'stolen',
        leaseDuration: const Duration(minutes: 5),
      ))!;
      await expectLater(
        queue.markTransportDispatch(
          id: request.id,
          leaseToken: 'dispatch',
          now: f.now,
        ),
        throwsA(isA<SubmissionLeaseLostException>()),
      );
      await expectLater(
        queue.fail(
          id: request.id,
          leaseToken: 'dispatch',
          now: f.now,
          failure: _failure(current, f.now),
          transportFailureOutcome: SubmissionTransportFailureOutcome.rejected,
        ),
        throwsA(isA<SubmissionLeaseLostException>()),
      );
      // Then stale ownership never clears and idempotent mark retains earliest claim/time.
      expect(repeated, marked);
      expect(stolen.transportCheckpoint, marked.transportCheckpoint);
      expect(await other.find(request.id), stolen);
      final refused = await other.fail(
        id: request.id,
        leaseToken: 'stolen',
        now: f.now,
        failure: _failure(stolen, f.now),
        transportFailureOutcome: SubmissionTransportFailureOutcome.rejected,
      );
      expect(refused.transportCheckpoint, marked.transportCheckpoint);
      expect(refused.receipts, marked.receipts);
    });
  });
}

Future<void> _uploadAll(SubmissionService service) async {
  // Given the real fixture's two originals require two prepares and two uploads.
  const steps = 4;
  // When four bounded invocations perform their actual one-operation stages.
  for (var index = 0; index < steps; index++) {
    final result = await service.processNext(networkAllowed: true);
    // Then each actual checkpoint returns progress without remote server dispatch.
    expect(result.outcome, SubmissionRunOutcome.progress);
    expect(result.record!.transportCheckpoint, isNull);
  }
}

Future<Database> _raw(SubmissionFixture fixture) async {
  // Given the exact fixture-owned path used by public real SQLite queue handles.
  final path = fixture.databasePath;
  // When a distinct raw handle is opened solely for controlled legacy/fault setup.
  final database = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  addTearDown(() async {
    // Given the scenario-owned raw handle, including early exceptional exits.
    final owned = database;
    // When that owner closes its handle after all held work is released.
    await owned.close();
    // Then the fixture's borrowed public queue handles retain their own lifetimes.
  });
  // Then the caller can inject actual database rows/faults without global state swaps.
  return database;
}

SubmissionAdapterException _adapterFailure(
  SubmissionTransportFailureOutcome outcome,
) {
  // Given a frozen trusted attempt outcome supplied by a controlled transport.
  final attribution = outcome;
  // When the public safe adapter error is constructed without a raw cause/token.
  final error = SubmissionAdapterException(
    stage: SubmissionFailureStage.transport,
    code: 'controlledRefusal',
    message: 'Safe controlled transport failure.',
    retryable: false,
    transportFailureOutcome: attribution,
  );
  // Then service specifications inspect this actual error's durable attribution.
  return error;
}

SubmissionFailure _failure(
  SubmissionRecord claim,
  DateTime now, {
  SubmissionFailureStage stage = SubmissionFailureStage.transport,
}) {
  // Given the actual executing claim/time and a safe aggregate failure stage.
  final count = claim.claimCount;
  // When the public historical value records that exact current attempt.
  final failure = SubmissionFailure(
    stage: stage,
    code: 'controlledFailure',
    message: 'Safe controlled failure.',
    retryable: false,
    occurredAt: now,
    claimCount: count,
  );
  // Then real queue ownership/clear tests use the exact value without forged history.
  return failure;
}

SubmissionHttpFixture _httpFixture() {
  // Given test-owned controlled HTTP/credential ports without real networking.
  final fixture = SubmissionHttpFixture();
  // When its owning scenario installs guaranteed client cleanup.
  addTearDown(() {
    // Given held work has been explicitly released by each scenario's finally block.
    final client = fixture.client;
    // When only the fixture owner closes its borrowed HTTP client.
    fixture.dispose();
    // Then the actual controlled lifetime confirms cleanup.
    expect(client.closed, isTrue);
  });
  // Then all actual public transport operations remain scoped to controlled ports.
  return fixture;
}

Matcher _httpFailure(
  String code,
  SubmissionTransportFailureOutcome outcome, {
  SubmissionFailureStage stage = SubmissionFailureStage.transport,
  bool retryable = false,
}) {
  // Given fixed safe error expectations and one trusted current-attempt outcome.
  final safe = submissionFailure(code, stage: stage, retryable: retryable);
  // When the matcher checks the actual public exception, including secret exclusion.
  final matcher = allOf(
    safe,
    isA<SubmissionAdapterException>().having(
      (value) => value.transportFailureOutcome,
      'transport outcome',
      outcome,
    ),
  );
  // Then observable exception assertions remain stronger than plain type checks.
  return matcher;
}

Map<String, Object?> _legacy(String scenario) {
  // Given independently written exact deployed v1 shapes, without any record encoder.
  const at = '2026-10-10T01:00:00.000Z';
  final initial = scenario == 'initial';
  final partial = scenario == 'partial';
  final empty = scenario == 'empty';
  final state = scenario == 'submitting'
      ? 'submitting'
      : scenario == 'failed'
      ? 'submissionFailed'
      : scenario == 'submitted'
      ? 'submitted'
      : 'readyToSubmit';
  final count = initial ? 0 : 2;
  // When the literal old row is assembled with exact local document/provenance/receipt.
  final row = <String, Object?>{
    'version': 1,
    'request': {
      'version': 1,
      'id': 'legacyCommit',
      'kind': 'bookMaterial',
      'subjectId': 'legacySubject',
      'createdAt': at,
      'document': {
        'local': {'draft': true},
      },
      'payload': {'transcript': '  legacy\n text  '},
      'materials': [
        if (!empty)
          {
            'key': 'photo',
            'original': {
              'id': 'legacyOriginal',
              'mediaType': 'image/jpeg',
              'byteLength': 6,
              'capturedAt': at,
              'originalName': 'legacy original.jpg',
              'extensions': {
                'source': [null, true],
              },
            },
            'provenance': {
              'capture': {'manual': false},
            },
          },
      ],
      'transportConnectionId': 'server',
      'storageConnectionId': empty ? null : 'drive',
      'extensions': {
        'opaque': [
          null,
          {'arm': 'uninterpreted/arm'},
        ],
      },
    },
    'state': state,
    'claimCount': count,
    'updatedAt': at,
    'leaseToken': state == 'submitting' ? 'legacyOwner' : null,
    'leaseExpiresAt': state == 'submitting' ? '2026-10-10T01:05:00.000Z' : null,
    'nextAttemptAt': state == 'submissionFailed'
        ? '2026-10-10T01:00:30.000Z'
        : null,
    'reservations': {
      if (!empty && !initial)
        'photo': {
          'key': 'photo',
          'providerId': 'controlledDrive',
          'data': {'remoteId': 'legacy/photo'},
        },
    },
    'receipts': {
      if (!empty && !initial && !partial)
        'photo': {
          'key': 'photo',
          'providerId': 'controlledDrive',
          'remoteId': 'legacy/photo',
          'accessConnectionId': 'drive',
          'storedAt': at,
          'metadata': {
            'opaque': [null, true],
          },
        },
    },
    'failureHistory': [
      if (state == 'submissionFailed')
        {
          'stage': 'transport',
          'code': 'legacyFailure',
          'message': 'Safe legacy failure.',
          'retryable': true,
          'occurredAt': at,
          'claimCount': count,
        },
    ],
    'acknowledgement': state == 'submitted'
        ? {
            'requestId': 'legacyCommit',
            'subjectId': 'legacySubject',
            'serverId': 'legacy/server',
            'receivedAt': at,
            'extensions': {
              'accepted': [null, true],
            },
          }
        : null,
  };
  // Then public codec/real SQLite scenarios exercise legacy behavior independently.
  return row;
}
