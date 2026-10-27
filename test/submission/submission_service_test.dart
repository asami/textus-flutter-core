import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

import '../support/submission_fixture.dart';

void main() {
  late SubmissionFixture f;
  setUp(() async {
    // Given a scenario needing real originals, a durable queue and controlled ports.
    // When a fresh isolated test-owned fixture is created and installed.
    f = await SubmissionFixture.create();
    // Then f holds the new fixture for this scenario to use and dispose.
  });
  tearDown(() async {
    // Given all services and handles opened by this scenario.
    // When fixture drains their owned work and closes the queue handles.
    await f.dispose();
    // Then only the temporary test artifacts are removed.
  });

  test('Q1 explicit offline Commit, reopen, global stage order and fake acceptance', () async {
    // Given actual original photo/audio bytes and opaque manual whitespace/context.
    var queue = await f.openQueue();
    var service = f.service(queue);
    final request = await f.request();
    await f.materials.saveDocument('consumer', request.subjectId, {
      'uncommitted': 'later editing remains independent',
    });
    // When explicit intent is committed while no processing/network is allowed.
    final committed = await service.commit(request);
    final offline = await service.processNext(networkAllowed: false);
    // Then intent is durable ready, with no prepare/upload/transport calls.
    expect(committed.record.state, SubmissionState.readyToSubmit);
    expect(offline.outcome, SubmissionRunOutcome.offline);
    expect(f.storage.prepares, 0);
    expect(f.storage.uploads, 0);
    expect(f.transport.submits, 0);
    expect(f.scheduler.calls, 1);
    expect(await queue.find(request.id), committed.record);
    await service.close();
    await queue.close();
    // Given a distinct store and service after every persisted stage.
    queue = await f.openQueue();
    service = f.service(queue);
    final stages = <(int, int)>[(1, 0), (2, 0), (2, 1), (2, 2)];
    for (final expected in stages) {
      // When one bounded invocation prepares all missing reservations before upload.
      final run = await service.processNext(networkAllowed: true);
      final persisted = await queue.find(request.id);
      // Then exactly one operation occurs and Ready checkpoints survive restart.
      expect(run.outcome, SubmissionRunOutcome.progress);
      expect(persisted, run.record);
      expect(persisted!.state, SubmissionState.readyToSubmit);
      expect(persisted.reservations.length, expected.$1);
      expect(persisted.receipts.length, expected.$2);
      expect(persisted.request, request);
      expect(persisted.leaseToken, isNull);
      expect(f.storage.prepares, expected.$1);
      expect(f.storage.uploads, expected.$2);
      expect(f.transport.submits, 0);
      await service.close();
      await queue.close();
      queue = await f.openQueue();
      service = f.service(queue);
      expect(await queue.find(request.id), persisted);
    }
    // When the final invocation sends only the complete immutable packet.
    final submitted = await service.processNext(networkAllowed: true);
    await service.close();
    await queue.close();
    final reopened = await f.openQueue();
    // Then only fake server acknowledgement produces Submitted and exact handoff.
    expect(submitted.outcome, SubmissionRunOutcome.submitted);
    expect(await reopened.find(request.id), submitted.record);
    expect(submitted.record!.acknowledgement!.serverId, 'fake-server/commit1');
    expect(f.transport.submits, 1);
    expect(f.storage.uploadedBytes, [
      SubmissionFixture.photoBytes,
      SubmissionFixture.audioBytes,
    ]);
    expect(f.transport.packets.single.request, request);
    final packet = SubmissionCodec.packetToJson(f.transport.packets.single);
    expect(packet['payload'], request.payload);
    expect(packet['extensions'], request.extensions);
    expect((packet['payload'] as Map)['transcript'], '  手入力\n原文  ');
    expect(packet.containsKey('document'), isFalse);
    for (final material in request.materials) {
      expect(
        await f.materials.readMaterial(material.original),
        material.key == 'photo'
            ? SubmissionFixture.photoBytes
            : SubmissionFixture.audioBytes,
      );
      final wire = (packet['materials'] as List).cast<Map>().singleWhere(
        (value) => value['key'] == material.key,
      );
      expect(wire['original'], material.original.toJson());
      expect(wire['provenance'], material.provenance);
    }
    expect(await f.materials.readDocument('consumer', request.subjectId), {
      'uncommitted': 'later editing remains independent',
    });
  });

  test('Q5 storage and transport failures preserve safe independent history and retry', () async {
    // Given a real queued two-material intent and independently failing storage.
    final queue = await f.openQueue();
    final service = f.service(queue);
    final request = await f.request();
    await service.commit(request);
    f.storage.onPrepare = (request, material) async {
      // Given a trusted safe expected storage failure.
      // When preparation is requested, report retryable storage attribution.
      throw SubmissionAdapterException(
        stage: SubmissionFailureStage.storage,
        code: 'driveUnavailable',
        message: 'Safe storage unavailable.',
        retryable: true,
      );
      // Then Core's observable failure must retain these safe structured fields.
    };
    // When one prepare fails and automatic retry is checked before/exactly due.
    final failure = await service.processNext(networkAllowed: true);
    // Then history is durable, safe and separate from transport acceptance.
    expect(failure.outcome, SubmissionRunOutcome.failed);
    expect(failure.record!.lastFailure!.stage, SubmissionFailureStage.storage);
    expect(failure.record!.lastFailure!.code, 'driveUnavailable');
    expect(failure.record!.lastFailure!.message, 'Safe storage unavailable.');
    expect(
      failure.record!.nextAttemptAt,
      f.now.add(const Duration(seconds: 30)),
    );
    expect(
      (await service.processNext(networkAllowed: true)).outcome,
      SubmissionRunOutcome.noWork,
    );
    f.now = f.now.add(const Duration(seconds: 30));
    f.storage.onPrepare = null;
    expect(
      (await service.processNext(networkAllowed: true)).outcome,
      SubmissionRunOutcome.progress,
    );
    await service.processNext(networkAllowed: true);
    await service.processNext(networkAllowed: true);
    final upload = await service.processNext(networkAllowed: true);
    expect(upload.record!.state, SubmissionState.readyToSubmit);
    expect(upload.record!.receipts.length, 2);
    expect(upload.record!.acknowledgement, isNull);
    f.transport.onSubmit = (packet) async {
      // Given storage is complete but the independent transport now fails.
      // When submit is requested, emit a nonretryable safe transport failure.
      throw SubmissionAdapterException(
        stage: SubmissionFailureStage.transport,
        code: 'serverRejected',
        message: 'Safe server rejection.',
        retryable: false,
      );
      // Then storage receipts must survive without a Submitted state.
    };
    final rejected = await service.processNext(networkAllowed: true);
    expect(
      rejected.record!.lastFailure!.stage,
      SubmissionFailureStage.transport,
    );
    expect(rejected.record!.nextAttemptAt, isNull);
    expect(rejected.record!.failureHistory.map((v) => v.stage), [
      SubmissionFailureStage.storage,
      SubmissionFailureStage.transport,
    ]);
    expect(rejected.record!.failureHistory.map((v) => v.claimCount), [1, 6]);
    expect(
      (await service.processNext(networkAllowed: true)).outcome,
      SubmissionRunOutcome.noWork,
    );
    // Given explicit retry of the rejected server packet, with completed originals.
    final wakeBefore = f.scheduler.calls;
    // When retry durably changes state and offline processing is requested.
    final retried = await service.retry(request.id);
    final offline = await service.processNext(networkAllowed: false);
    // Then receipts/history/originals remain exact and no upload is repeated.
    expect(retried.record.state, SubmissionState.readyToSubmit);
    expect(retried.record.receipts, rejected.record!.receipts);
    expect(retried.record.failureHistory, rejected.record!.failureHistory);
    expect(f.scheduler.calls, wakeBefore + 1);
    expect(offline.outcome, SubmissionRunOutcome.offline);
    f.transport.onSubmit = null;
    expect(
      (await service.processNext(networkAllowed: true)).outcome,
      SubmissionRunOutcome.submitted,
    );
    expect(f.storage.uploads, 2);
    expect(f.storage.prepares, 3);
    expect(
      await f.materials.readMaterial(request.materials.first.original),
      SubmissionFixture.photoBytes,
    );
  });

  for (final mismatch in [
    'reservationProvider',
    'reservationKey',
    'receiptProvider',
    'receiptKey',
    'acknowledgement',
    'missingStorage',
    'missingTransport',
  ]) {
    test('Q5 $mismatch is observable nonretryable configuration failure', () async {
      // Given an actual request plus one incorrect result/connection.
      final queue = await f.openQueue();
      final request = await f.request(
        withMaterials:
            mismatch != 'acknowledgement' && mismatch != 'missingTransport',
      );
      final service = f.service(
        queue,
        storageAdapters: mismatch == 'missingStorage' ? {} : null,
        transports: mismatch == 'missingTransport' ? {} : null,
      );
      await service.commit(request);
      if (mismatch.startsWith('reservation')) {
        f.storage.onPrepare = (request, material) async {
          // Given provider/key mismatch selected for this scenario.
          // When preparation returns, retain a valid value with incorrect identity.
          return SubmissionStorageReservation(
            key: mismatch == 'reservationKey' ? 'wrong' : material.key,
            providerId: mismatch == 'reservationProvider'
                ? 'wrong'
                : f.storage.providerId,
            data: {'file': 'remote'},
          );
          // Then service can reject the identity before any queue checkpoint.
        };
      }
      if (mismatch.startsWith('receipt')) {
        await service.processNext(networkAllowed: true);
        await service.processNext(networkAllowed: true);
        f.storage.onUpload = (request, material, reservation, bytes) async {
          // Given a stored reservation and selected receipt identity mismatch.
          // When upload acknowledges the wrong provider/key.
          return SubmissionMaterialReceipt(
            key: mismatch == 'receiptKey' ? 'wrong' : material.key,
            providerId: mismatch == 'receiptProvider'
                ? 'wrong'
                : f.storage.providerId,
            remoteId: 'remote',
            accessConnectionId: 'drive',
            storedAt: f.now,
          );
          // Then service must retain reservation but reject the receipt.
        };
      }
      if (mismatch == 'acknowledgement') {
        f.transport.onSubmit = (packet) async {
          // Given a complete empty-material packet.
          // When transport returns acceptance for a different subject.
          return SubmissionAcknowledgement(
            requestId: packet.request.id,
            subjectId: 'wrongSubject',
            serverId: 'fake',
            receivedAt: f.now,
          );
          // Then queue must never publish mismatched Submitted state.
        };
      }
      // When the selected operation/connection is used by one bounded run.
      final run = await service.processNext(networkAllowed: true);
      // Then safe nonretryable failure replaces no accepted checkpoint/ack.
      expect(run.outcome, SubmissionRunOutcome.failed);
      expect(
        run.record!.lastFailure!.stage,
        SubmissionFailureStage.configuration,
      );
      expect(run.record!.lastFailure!.retryable, isFalse);
      expect(run.record!.acknowledgement, isNull);
      expect(run.record!.receipts, isEmpty);
      expect(
        (await service.processNext(networkAllowed: true)).outcome,
        SubmissionRunOutcome.noWork,
      );
    });
  }

  test('Q5 empty-material request bypasses storage and unknown errors are safe', () async {
    // Given a domain-opaque empty-material request and no storage connections.
    final queue = await f.openQueue();
    final service = f.service(queue, storageAdapters: {});
    final request = await f.request(withMaterials: false);
    await service.commit(request);
    f.transport.onSubmit = (packet) async {
      // Given a raw exception containing unsafe diagnostic detail.
      // When transport throws, Core must replace it with fixed safe fields.
      throw StateError('SECRET header/body/token');
      // Then the raw text must never enter persisted failure history.
    };
    // When transport fails and explicit retry later gets fake acknowledgement.
    final failed = await service.processNext(networkAllowed: true);
    await service.retry(request.id);
    f.transport.onSubmit = null;
    final submitted = await service.processNext(networkAllowed: true);
    // Then storage is unused, safe history persists and server acceptance is explicit.
    expect(failed.record!.lastFailure!.code, 'operationFailed');
    expect(
      jsonEncode(SubmissionCodec.recordToJson(failed.record!)),
      isNot(contains('SECRET')),
    );
    expect(submitted.outcome, SubmissionRunOutcome.submitted);
    expect(submitted.record!.failureHistory, failed.record!.failureHistory);
    expect(f.storage.prepares, 0);
    expect(f.storage.uploads, 0);
  });

  test('Q6 upload success then checkpoint failure reuses persisted reservation on restart', () async {
    // Given both reservations persisted before any upload and a selected write loss.
    final first = await f.openQueue();
    final controlled = ControlledQueue(first);
    final service = f.service(controlled);
    final request = await f.request();
    await service.commit(request);
    await service.processNext(networkAllowed: true);
    await service.processNext(networkAllowed: true);
    final prepared = await first.find(request.id);
    controlled.failAt = 'saveReceipt';
    // When upload succeeds remotely but local acknowledgement fails to persist.
    await expectLater(
      service.processNext(networkAllowed: true),
      throwsStateError,
    );
    final unacknowledged = await first.find(request.id);
    // Then the exception remains observable and durable state contains no fake success.
    expect(unacknowledged!.state, SubmissionState.submitting);
    expect(unacknowledged.reservations, prepared!.reservations);
    expect(unacknowledged.receipts, isEmpty);
    expect(f.storage.remote.length, 1);
    await service.close();
    await first.close();
    final second = await f.openQueue();
    final restarted = f.service(second);
    // Given distinct store/service handles borrowing the same controlled remote.
    // When restarted upload replays the exact prepared idempotency reservation.
    final replay = await restarted.processNext(networkAllowed: true);
    await _finish(restarted);
    // Then replay acknowledges the same object and completed receipt is not uploaded again.
    expect(replay.record!.receipts['photo'], f.storage.remote['commit1/photo']);
    expect(
      f.storage.uploadedReservations[0],
      f.storage.uploadedReservations[1],
    );
    expect(f.storage.prepares, 2);
    expect(f.storage.uploads, 3);
    expect(f.storage.remote.length, 2);
    expect((await second.find(request.id))!.request, request);
    expect(
      await f.materials.readMaterial(request.materials.first.original),
      SubmissionFixture.photoBytes,
    );
  });

  test('Q6 fake server success then local write loss replays the immutable request id', () async {
    // Given an empty-material request and controlled complete-write failure.
    final first = await f.openQueue();
    final controlled = ControlledQueue(first);
    final service = f.service(controlled);
    final request = await f.request(withMaterials: false);
    await service.commit(request);
    controlled.failAt = 'complete';
    // When fake server success cannot be checkpointed locally.
    await expectLater(
      service.processNext(networkAllowed: true),
      throwsStateError,
    );
    final old = await first.find(request.id);
    final remote = f.transport.remote[request.id];
    // Then local state is unacknowledged, without failure/success fabrication.
    expect(old!.state, SubmissionState.submitting);
    expect(old.acknowledgement, isNull);
    expect(old.failureHistory, isEmpty);
    expect(remote, isNotNull);
    await service.close();
    await first.close();
    final reopened = await f.openQueue();
    final restarted = f.service(reopened);
    // When a distinct service replays the same durable packet after restart.
    final result = await restarted.processNext(networkAllowed: true);
    // Then idempotent fake transport acknowledges the same remote identity.
    expect(result.outcome, SubmissionRunOutcome.submitted);
    expect(result.record!.acknowledgement, remote);
    expect(f.transport.packets.map((p) => p.request.id), [
      request.id,
      request.id,
    ]);
    expect(f.transport.packets[0], f.transport.packets[1]);
    expect(f.transport.remote.length, 1);
  });

  test('Q7 wake failure preserves durable intent and Submitted duplicate needs no wake', () async {
    // Given a scheduler failure before offline intent is explicitly committed.
    final queue = await f.openQueue();
    final service = f.service(queue);
    final request = await f.request(withMaterials: false);
    f.scheduler.fail = true;
    // When Commit persists intent before wake and wake throws unsafe raw detail.
    final result = await service.commit(request);
    // Then the returned queued snapshot and fixed safe notice reflect durability.
    expect(result.record.state, SubmissionState.readyToSubmit);
    expect(await queue.find(request.id), result.record);
    expect(result.schedulingFailure!.code, 'wakeUnavailable');
    expect(result.schedulingFailure!.message, isNot(contains('private')));
    expect(f.storage.prepares, 0);
    expect(f.transport.submits, 0);
    f.scheduler.fail = false;
    f.transport.onSubmit = (packet) async {
      // Given durable intent whose independent server stage is rejected.
      // When transport is called, supply a safe nonretryable expected failure.
      throw SubmissionAdapterException(
        stage: SubmissionFailureStage.transport,
        code: 'retryRequested',
        message: 'Safe rejection before explicit retry.',
        retryable: false,
      );
      // Then the scenario can observe retry changing Failed to Ready before wake.
    };
    final failed = await service.processNext(networkAllowed: true);
    expect(failed.record!.state, SubmissionState.submissionFailed);
    // Given a wake callback that observes retry's already durable state.
    f.scheduler.onRequest = () async {
      // When retry asks for wake after mutating state.
      final stored = await queue.find(request.id);
      // Then the scheduler sees Ready, never an uncommitted retry.
      expect(stored!.state, SubmissionState.readyToSubmit);
    };
    await service.retry(request.id);
    f.transport.onSubmit = null;
    await service.processNext(networkAllowed: true);
    final wakes = f.scheduler.calls;
    final submits = f.transport.submits;
    // When Submitted intent is committed/retried again and an unknown id is retried.
    final duplicate = await service.commit(request);
    final repeated = await service.retry(request.id);
    await expectLater(service.retry('unknown'), throwsStateError);
    // Then all are safe no-op/rejection without new scheduler or transport activity.
    expect(duplicate.record.state, SubmissionState.submitted);
    expect(repeated.record, duplicate.record);
    expect(f.scheduler.calls, wakes);
    expect(f.transport.submits, submits);
    expect(
      (await service.processNext(networkAllowed: true)).outcome,
      SubmissionRunOutcome.noWork,
    );
  });

  test(
    'Q8 offline and stale-before-claim/dispatch avoid every remote operation',
    () async {
      // Given a queued intent, observable queue port, and controllable run ownership.
      final queue = await f.openQueue();
      final controlled = ControlledQueue(queue);
      final service = f.service(controlled);
      final request = await f.request();
      await service.commit(request);
      final before = controlled.calls;
      // When offline returns or the caller is stale before any claim.
      final offline = await service.processNext(
        networkAllowed: false,
        isRunCurrent: () => throw StateError('offline must not call predicate'),
      );
      final stale = await service.processNext(
        networkAllowed: true,
        isRunCurrent: () => false,
      );
      // Then no queue reads/claims or adapters/scheduler operations are added.
      expect(offline.outcome, SubmissionRunOutcome.offline);
      expect(stale.outcome, SubmissionRunOutcome.cancelled);
      expect(controlled.calls, before);
      expect(f.storage.prepares, 0);
      expect(f.storage.uploads, 0);
      expect(f.transport.submits, 0);
      expect(f.scheduler.calls, 1);
      for (final boundary in ['claimNext', 'renewLease']) {
        // Given ownership that becomes stale at one awaited pre-dispatch boundary.
        var current = true;
        controlled.after = (operation) async {
          // When the actual claim/renewal finishes, invalidate this run.
          if (operation == boundary) current = false;
          // Then the next owner check must prevent adapter dispatch.
        };
        // When the run claims/renews and observes the stale caller.
        final cancelled = await service.processNext(
          networkAllowed: true,
          isRunCurrent: () => current,
        );
        // Then valid claims release to Ready and keep the original immutable intent.
        expect(cancelled.outcome, SubmissionRunOutcome.cancelled);
        expect(cancelled.record!.state, SubmissionState.readyToSubmit);
        expect(cancelled.record!.request, request);
        expect(cancelled.record!.reservations, isEmpty);
        expect(f.storage.prepares, 0);
      }
      controlled.after = null;
    },
  );

  for (final stage in ['prepare', 'upload', 'transport']) {
    test(
      'Q8 owner stale after awaited $stage discards result and releases checkpoints',
      () async {
        // Given an actual ready stage, with earlier checkpoints persisted normally.
        final queue = await f.openQueue();
        final service = f.service(queue);
        final request = await f.request(withMaterials: stage != 'transport');
        await service.commit(request);
        if (stage == 'upload') {
          await service.processNext(networkAllowed: true);
          await service.processNext(networkAllowed: true);
        }
        final before = await queue.find(request.id);
        final entered = Completer<void>();
        final finish = Completer<void>();
        var current = true;
        if (stage == 'prepare') {
          f.storage.onPrepare = (request, material) async {
            // Given an in-flight preparation controlled independently of ownership.
            entered.complete();
            // When the remote operation completes after caller invalidation.
            await finish.future;
            // Then its reservation must be discarded before any checkpoint.
            return f.storage.reservation(material.key, request.id);
          };
        } else if (stage == 'upload') {
          f.storage.onUpload = (request, material, reservation, bytes) async {
            // Given unchanged bytes and the exact persisted reservation.
            entered.complete();
            // When remote storage completes after caller invalidation.
            await finish.future;
            // Then the receipt must be discarded while old checkpoints remain.
            return SubmissionMaterialReceipt(
              key: material.key,
              providerId: f.storage.providerId,
              remoteId: 'lateRemote',
              accessConnectionId: 'drive',
              storedAt: f.now,
            );
          };
        } else {
          f.transport.onSubmit = (packet) async {
            // Given an in-flight complete packet at the independent server port.
            entered.complete();
            // When server acceptance completes after caller invalidation.
            await finish.future;
            // Then no Submitted acknowledgement may be published locally.
            return f.transport.acknowledgement(packet.request);
          };
        }
        // When the owner goes stale while an actual adapter await is in flight.
        final pending = service.processNext(
          networkAllowed: true,
          isRunCurrent: () => current,
        );
        await entered.future;
        current = false;
        finish.complete();
        final cancelled = await pending;
        // Then valid owner cancellation releases Ready with exact prior checkpoints.
        expect(cancelled.outcome, SubmissionRunOutcome.cancelled);
        expect(cancelled.record!.state, SubmissionState.readyToSubmit);
        expect(cancelled.record!.reservations, before!.reservations);
        expect(cancelled.record!.receipts, before.receipts);
        expect(cancelled.record!.acknowledgement, isNull);
        expect(cancelled.record!.failureHistory, isEmpty);
        expect(await queue.find(request.id), cancelled.record);
      },
    );
  }

  test('Q8 close invalidates in-flight upload, drains and preserves borrowed lifetimes', () async {
    // Given both reservations and a controlled upload that is actually dispatched.
    final queue = await f.openQueue();
    final service = f.service(queue);
    final request = await f.request();
    await service.commit(request);
    await service.processNext(networkAllowed: true);
    await service.processNext(networkAllowed: true);
    final entered = Completer<void>();
    final finish = Completer<void>();
    f.storage.onUpload = (request, material, reservation, bytes) async {
      // Given upload owns a persisted reservation but service lifetime may close.
      entered.complete();
      // When completion is released after close invalidates run ownership.
      await finish.future;
      // Then Core must discard the result and release its valid lease.
      return SubmissionMaterialReceipt(
        key: material.key,
        providerId: f.storage.providerId,
        remoteId: 'late',
        accessConnectionId: 'drive',
        storedAt: f.now,
      );
    };
    // When service close begins during the owned operation and completion resumes.
    final pending = service.processNext(networkAllowed: true);
    await entered.future;
    final closing = service.close();
    finish.complete();
    final cancelled = await pending;
    await closing;
    await service.close();
    // Then no receipt is published and every borrowed resource still works.
    expect(cancelled.outcome, SubmissionRunOutcome.cancelled);
    expect(
      (await queue.find(request.id))!.state,
      SubmissionState.readyToSubmit,
    );
    expect((await queue.find(request.id))!.receipts, isEmpty);
    expect(
      await f.materials.readMaterial(request.materials.first.original),
      SubmissionFixture.photoBytes,
    );
    await f.scheduler.requestRun();
    f.storage.onUpload = null;
    final direct = await f.storage.prepare(
      request: request,
      material: request.materials.first,
    );
    expect(direct.key, request.materials.first.key);
    expect(
      (await f.transport.submit(
        SubmissionPacket(
          request: await f.request(
            id: 'empty',
            subjectId: 'emptySubject',
            withMaterials: false,
          ),
          receipts: {},
        ),
      )).serverId,
      'fake-server/empty',
    );
    for (final call in <Future<Object?> Function()>[
      () => service.commit(request),
      () => service.retry(request.id),
      () => service.processNext(networkAllowed: false),
      () => service.find(request.id),
      () => service.findForSubject(request.kind, request.subjectId),
      () => service.list(),
    ]) {
      await expectLater(call(), throwsStateError);
    }
  });

  test('Q8 lease stolen during original read prevents renewed remote dispatch', () async {
    // Given an old service with complete reservations and an independent handle.
    final queue = await f.openQueue();
    final competitor = await f.openQueue();
    final originals = ControlledMaterials(f.materials);
    final service = f.service(queue, originals: originals);
    final request = await f.request();
    await service.commit(request);
    await service.processNext(networkAllowed: true);
    await service.processNext(networkAllowed: true);
    SubmissionRecord? stolen;
    originals.beforeRead = () async {
      // Given an awaited local original read that outlives the old lease.
      f.now = f.now.add(const Duration(minutes: 6));
      // When another handle recovers expiry with its own unique ownership token.
      stolen = await competitor.claimNext(
        now: f.now,
        leaseToken: 'competitor',
        leaseDuration: const Duration(minutes: 5),
      );
      // Then old owner's required renewal must lose before any upload dispatch.
    };
    // When the original read resumes and Core attempts fresh lease renewal.
    final lost = await service.processNext(networkAllowed: true);
    // Then old-owner operation is fenced and the new owner is not changed.
    expect(lost.outcome, SubmissionRunOutcome.leaseLost);
    expect(lost.record, stolen);
    expect(await queue.find(request.id), stolen);
    expect(f.storage.uploads, 0);
    expect(f.transport.submits, 0);
  });

  test(
    'Q8 expired and stolen owner cannot checkpoint late preparation',
    () async {
      // Given a dispatched prepare with a second handle able to recover expiry.
      final queue = await f.openQueue();
      final competitor = await f.openQueue();
      final service = f.service(queue);
      final request = await f.request();
      await service.commit(request);
      SubmissionRecord? newOwner;
      f.storage.onPrepare = (request, material) async {
        // Given remote preparation whose result arrives beyond the old lease.
        f.now = f.now.add(const Duration(minutes: 6));
        // When a competitor atomically takes the expired job before prepare returns.
        newOwner = await competitor.claimNext(
          now: f.now,
          leaseToken: 'newOwner',
          leaseDuration: const Duration(minutes: 5),
        );
        // Then the returned reservation belongs to an owner unable to checkpoint it.
        return f.storage.reservation(material.key, request.id);
      };
      // When old service tries to checkpoint the late result.
      final lost = await service.processNext(networkAllowed: true);
      // Then leaseLost is observable and competitor state remains untouched.
      expect(lost.outcome, SubmissionRunOutcome.leaseLost);
      expect(await queue.find(request.id), newOwner);
      expect(newOwner!.reservations, isEmpty);
      expect(newOwner!.claimCount, 2);
    },
  );

  test(
    'Q8 awaited local read renews fresh lease immediately before upload',
    () async {
      // Given both reservations and an original read that consumes most of a lease.
      final queue = await f.openQueue();
      final originals = ControlledMaterials(f.materials);
      final service = f.service(queue, originals: originals);
      final request = await f.request();
      await service.commit(request);
      await service.processNext(networkAllowed: true);
      await service.processNext(networkAllowed: true);
      originals.beforeRead = () async {
        // Given an unexpired claim that was acquired before this local await.
        // When the supplied wall clock advances while reading the original.
        f.now = f.now.add(const Duration(minutes: 4));
        // Then the dispatch must use a fresh lease after reading, not the old expiry.
      };
      f.storage.onUpload = (request, material, reservation, bytes) async {
        // Given upload is entered only after the final atomic renewal.
        final claimed = await queue.find(request.id);
        // When the controlled adapter observes the current durable claim.
        // Then its timeout fits the full renewed lease without another claim count.
        expect(claimed!.leaseExpiresAt, f.now.add(const Duration(minutes: 5)));
        expect(claimed.claimCount, 3);
        expect(bytes, SubmissionFixture.photoBytes);
        return SubmissionMaterialReceipt(
          key: material.key,
          providerId: f.storage.providerId,
          remoteId: 'freshLeaseRemote',
          accessConnectionId: 'drive',
          storedAt: f.now,
        );
      };
      // When upload follows the awaited original read.
      final result = await service.processNext(networkAllowed: true);
      // Then the exact receipt persists and the valid renewed claim releases Ready.
      expect(result.outcome, SubmissionRunOutcome.progress);
      expect(result.record!.receipts['photo']!.remoteId, 'freshLeaseRemote');
      expect(result.record!.state, SubmissionState.readyToSubmit);
      expect(result.record!.claimCount, 3);
    },
  );

  test('Q8 genuine bounded timeout discards late completion with safe retry history', () async {
    // Given explicit short positive durations and a remote completion barrier.
    final queue = await f.openQueue();
    final service = f.service(
      queue,
      operationTimeout: const Duration(milliseconds: 10),
      leaseDuration: const Duration(seconds: 1),
    );
    final request = await f.request();
    await service.commit(request);
    final finish = Completer<SubmissionStorageReservation>();
    f.storage.onPrepare = (request, material) {
      // Given a genuinely pending remote operation.
      // When Core's timer expires, this future still has no result.
      return finish.future;
      // Then its later result must be observed/discarded without publication.
    };
    // When processNext reaches its actual timeout before preparation completes.
    final timedOut = await service.processNext(networkAllowed: true);
    final durable = await queue.find(request.id);
    finish.complete(f.storage.reservation('photo', request.id));
    await Future<void>.delayed(Duration.zero);
    // Then timeout is safe, retryable and late completion cannot change persistence.
    expect(timedOut.outcome, SubmissionRunOutcome.failed);
    expect(timedOut.record!.lastFailure!.code, 'operationTimeout');
    expect(timedOut.record!.lastFailure!.retryable, isTrue);
    expect(timedOut.record!.reservations, isEmpty);
    expect(await queue.find(request.id), durable);
    expect(f.storage.uploads, 0);
  });

  test('Q8 throwing owner predicate releases valid claim and propagates primary error', () async {
    // Given a dispatched remote await after which caller ownership checking throws.
    final queue = await f.openQueue();
    final service = f.service(queue);
    final request = await f.request();
    await service.commit(request);
    final primary = StateError('caller primary error');
    var shouldThrow = false;
    f.storage.onPrepare = (request, material) async {
      // Given the predicate initially permits dispatch.
      // When preparation finishes, make the next predicate check throw.
      shouldThrow = true;
      // Then that error must prevent checkpoint/failure publication.
      return f.storage.reservation(material.key, request.id);
    };
    // When the caller predicate throws immediately after awaited remote completion.
    await expectLater(
      service.processNext(
        networkAllowed: true,
        isRunCurrent: () {
          // Given a caller-owned predicate whose failure is an observable primary error.
          if (shouldThrow) throw primary;
          // When the caller is still healthy, allow the actual dispatch.
          // Then subsequent throwing checks are asserted by the outer scenario.
          return true;
        },
      ),
      throwsA(same(primary)),
    );
    // Then best-effort release leaves Ready and no failure/ack/reservation publication.
    final ready = await queue.find(request.id);
    expect(ready!.state, SubmissionState.readyToSubmit);
    expect(ready.reservations, isEmpty);
    expect(ready.failureHistory, isEmpty);
    expect(ready.acknowledgement, isNull);
  });

  test('Q9 missing/corrupt originals reject before enqueue and remain undeleted', () async {
    // Given actual originals whose first byte source is deliberately corrupted.
    final queue = await f.openQueue();
    final service = f.service(queue);
    final request = await f.request();
    final file = File(
      '${f.directory.path}/originals/materials/${request.materials.first.original.id}.bin',
    );
    await file.writeAsBytes([1], flush: true);
    // When Commit checks the unchanged reference against its corrupt source bytes.
    await expectLater(
      service.commit(request),
      throwsA(isA<SubmissionAdapterException>()),
    );
    // Then no intent/scheduling/remote activity is published and corrupt source remains.
    expect(await queue.list(), isEmpty);
    expect(await file.readAsBytes(), [1]);
    expect(f.scheduler.calls, 0);
    expect(f.storage.prepares, 0);
    final missing = SubmissionCodec.requestFromJson({
      ...SubmissionCodec.requestToJson(request),
      'id': 'missingCommit',
      'subjectId': 'missingSubject',
      'materials': [
        {
          ...SubmissionCodec.materialToJson(request.materials.first),
          'original': {
            ...request.materials.first.original.toJson(),
            'id': 'absentOriginal',
          },
        },
      ],
    });
    await expectLater(
      service.commit(missing),
      throwsA(isA<SubmissionAdapterException>()),
    );
    expect(await queue.list(), isEmpty);
    expect(await file.exists(), isTrue);
  });

  test('Q9 processing original corruption fails safely and database corruption propagates', () async {
    // Given accepted intent plus all reservations, before original upload reads.
    final queue = await f.openQueue();
    final service = f.service(queue);
    final request = await f.request();
    await service.commit(request);
    await service.processNext(networkAllowed: true);
    await service.processNext(networkAllowed: true);
    final file = File(
      '${f.directory.path}/originals/materials/${request.materials.first.original.id}.bin',
    );
    await file.writeAsBytes([0], flush: true);
    // When processing reads a length-inconsistent original.
    final failed = await service.processNext(networkAllowed: true);
    // Then safe nonretryable local attribution retains checkpoints and source bytes.
    expect(
      failed.record!.lastFailure!.stage,
      SubmissionFailureStage.localMaterial,
    );
    expect(failed.record!.lastFailure!.retryable, isFalse);
    expect(failed.record!.reservations.length, 2);
    expect(failed.record!.receipts, isEmpty);
    expect(await file.readAsBytes(), [0]);
    expect(f.storage.uploads, 0);
    final raw = await databaseFactoryFfi.openDatabase(
      f.databasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      // Given corrupt queue persistence independent of an adapter/local-material error.
      await raw.update(
        'submission_jobs',
        {'body': '{corrupt'},
        where: 'request_id = ?',
        whereArgs: [request.id],
      );
      // When the driver or strict service read touches that queue row.
      await expectLater(
        service.processNext(networkAllowed: true),
        throwsFormatException,
      );
      await expectLater(service.find(request.id), throwsFormatException);
      // Then corruption propagates and neither the queue source nor originals disappear.
      expect((await raw.query('submission_jobs')).single['body'], '{corrupt');
      expect(await file.readAsBytes(), [0]);
    } finally {
      // Given the raw handle is scenario-owned.
      // When source evidence has been asserted, release only that handle.
      await raw.close();
      // Then fixture cleanup remains responsible for its own queue handle.
    }
  });

  test('Q9 consumer timing, duplicate intent and invocation-order recovery are explicit', () async {
    // Given mutable consumer JSON and a delayed actual original-read boundary.
    final queue = await f.openQueue();
    final originals = ControlledMaterials(f.materials);
    final service = f.service(queue, originals: originals);
    final document = <String, Object?>{
      'draft': <Object?>['confirmed'],
    };
    final payload = <String, Object?>{'text': '  committed\n '};
    final request = await f.request(document: document, payload: payload);
    final entered = Completer<void>();
    final finish = Completer<void>();
    originals.beforeRead = () async {
      // Given the first command's original validation is still in flight.
      if (!entered.isCompleted) entered.complete();
      // When the scenario releases the read, queued commands may proceed in order.
      await finish.future;
      // Then the request snapshot stays independent of consumer state mutations.
    };
    // When Commit is invoked first, retry second, and consumer JSON edits afterwards.
    final committed = service.commit(request);
    final retried = service.retry(request.id);
    await entered.future;
    (document['draft']! as List).add('later');
    payload['text'] = 'later';
    finish.complete();
    final accepted = await committed;
    final repeated = await retried;
    // Then serialized retry sees durable intent and accepted snapshot stays unchanged.
    expect(repeated.record.request, accepted.record.request);
    expect(accepted.record.request.document, {
      'draft': ['confirmed'],
    });
    expect(accepted.record.request.payload, {'text': '  committed\n '});
    final readCount = originals.reads;
    final duplicate = await service.commit(request);
    expect(duplicate.record, accepted.record);
    expect(originals.reads, readCount);
    final changed = SubmissionCodec.requestFromJson({
      ...SubmissionCodec.requestToJson(request),
      'payload': {'later': true},
    });
    await expectLater(service.commit(changed), throwsStateError);
    await expectLater(service.retry('unknown'), throwsStateError);
    expect(
      (await service.processNext(networkAllowed: false)).outcome,
      SubmissionRunOutcome.offline,
    );
    expect(
      await service.findForSubject(request.kind, request.subjectId),
      accepted.record,
    );
    expect(await service.list(), [accepted.record]);
  });

  test(
    'Q9 close before enqueue rejects new publication but durable wake finishes',
    () async {
      // Given a new Commit whose original validation is delayed before enqueue.
      final queue = await f.openQueue();
      final originals = ControlledMaterials(f.materials);
      final service = f.service(queue, originals: originals);
      final request = await f.request();
      final entered = Completer<void>();
      final finish = Completer<void>();
      originals.beforeRead = () async {
        // Given validation entered before queue publication.
        entered.complete();
        // When close invalidates service lifetime and the original read is resumed.
        await finish.future;
        // Then Commit must observe closure before starting enqueue.
      };
      final pending = service.commit(request);
      final rejection = expectLater(pending, throwsStateError);
      await entered.future;
      final closing = service.close();
      finish.complete();
      await rejection;
      await closing;
      // Then the new intent and wake have never been published.
      expect(await queue.list(), isEmpty);
      expect(f.scheduler.calls, 0);
      // Given another service whose empty-material enqueue is already durable.
      final other = f.service(queue);
      final empty = await f.request(
        id: 'durable',
        subjectId: 'durableSubject',
        withMaterials: false,
      );
      final wakeEntered = Completer<void>();
      final wakeFinish = Completer<void>();
      f.scheduler.onRequest = () async {
        // Given scheduler is invoked strictly after durable enqueue.
        expect(
          (await queue.find(empty.id))!.state,
          SubmissionState.readyToSubmit,
        );
        wakeEntered.complete();
        // When close begins while the already accepted wake is pending.
        await wakeFinish.future;
        // Then durable intent still returns its accepted Commit result.
      };
      final durable = other.commit(empty);
      await wakeEntered.future;
      final drain = other.close();
      wakeFinish.complete();
      final result = await durable;
      await drain;
      expect(result.record.request, empty);
      expect(await queue.find(empty.id), result.record);
      expect(result.schedulingFailure, isNull);
    },
  );

  test(
    'Q8 invalid duration and connection identities are rejected synchronously',
    () async {
      // Given borrowed resources and invalid configuration without any intent.
      final queue = await f.openQueue();
      // When constructors receive zero/negative durations, insufficient lease or unsafe keys.
      for (final durations in [
        (Duration.zero, const Duration(seconds: 1)),
        (const Duration(seconds: 1), const Duration(seconds: 1)),
      ]) {
        // Then invalid configuration cannot start an actor or mutate the queue.
        expect(
          () => SubmissionService(
            queue: queue,
            materials: f.materials,
            storageAdapters: {},
            transports: {},
            scheduler: f.scheduler,
            operationTimeout: durations.$1,
            leaseDuration: durations.$2,
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => SubmissionService(
          queue: queue,
          materials: f.materials,
          storageAdapters: {'../unsafe': f.storage},
          transports: {},
          scheduler: f.scheduler,
        ),
        throwsArgumentError,
      );
      expect(
        () => SubmissionService(
          queue: queue,
          materials: f.materials,
          storageAdapters: {},
          transports: {},
          scheduler: f.scheduler,
          automaticRetryDelay: Duration.zero,
        ),
        throwsArgumentError,
      );
      expect(await queue.list(), isEmpty);
    },
  );
}

Future<void> _finish(SubmissionService service) async {
  // Given a bounded number of remaining stages in these two-material scenarios.
  for (var i = 0; i < 5; i++) {
    // When a single bounded operation is pumped by the test-owned driver.
    final result = await service.processNext(networkAllowed: true);
    // Then only progress/submitted is acceptable; the helper never loops forever.
    expect(
      result.outcome,
      anyOf(SubmissionRunOutcome.progress, SubmissionRunOutcome.submitted),
    );
    if (result.outcome == SubmissionRunOutcome.submitted) return;
  }
  fail(
    'Two-material controlled driver did not submit within its bounded stages',
  );
}
