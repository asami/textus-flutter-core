import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

import '../support/submission_fixture.dart';

void main() {
  late SubmissionFixture fixture;
  setUp(() async {
    // Given a scenario needing real SQLite rows and saved original bytes.
    // When an isolated native fixture is allocated without global factory swaps.
    fixture = await SubmissionFixture.create();
    // Then the scenario owns all temporary files and borrowed service lifetimes.
  });
  tearDown(() async {
    // Given scenario-owned services and their separately owned native queues.
    // When cleanup drains services before closing queues and deleting artifacts.
    await fixture.dispose();
    // Then no production data or user-owned resource is changed.
  });

  for (final throwsOnObserve in [false, true]) {
    test(
      'construction and offline processing never observe ${throwsOnObserve ? 'throwing' : 'counting'} context',
      () async {
        // Given bound durable intent, observable native ports and a borrowed callback.
        final request = _request(await fixture.request(), binding: _binding());
        final queue = await fixture.openQueue();
        final accepted = await queue.enqueue(request);
        final observedQueue = ControlledQueue(queue);
        final originals = ControlledMaterials(fixture.materials);
        var callbacks = 0;
        final context = SubmissionAuthenticationContext(
          binding: _binding(),
          isCurrent: () {
            callbacks++;
            if (throwsOnObserve) throw StateError('private-context');
            return true;
          },
        );
        // When construction and an offline pump receive the borrowed context.
        final service = _service(
          fixture,
          observedQueue,
          context: context,
          originals: originals,
        );
        final result = await service.processNext(networkAllowed: false);
        // Then no queue claim/read, original read, callback or adapter is touched.
        expect(result.outcome, SubmissionRunOutcome.offline);
        expect(result.record, isNull);
        expect(callbacks, 0);
        expect(observedQueue.calls, 0);
        expect(originals.reads, 0);
        expect(fixture.storage.prepares, 0);
        expect(fixture.storage.uploads, 0);
        expect(fixture.transport.submits, 0);
        expect(fixture.scheduler.calls, 0);
        expect(await queue.find(request.id), accepted);
      },
    );
  }

  test('explicit local Commit works without a processing context and preserves duplicates', () async {
    // Given bound intent with actual saved originals and no authentication context.
    final request = _request(await fixture.request(), binding: _binding());
    final queue = await fixture.openQueue();
    final originals = ControlledMaterials(fixture.materials);
    final service = _service(fixture, queue, originals: originals);
    // When explicit Commit and an equal repeated Commit enqueue the same intent.
    final first = await service.commit(request);
    final duplicate = await service.commit(
      _request(request, binding: _binding()),
    );
    // Then original validation happens only once, intent persists and scheduling stays local.
    expect(first.record, duplicate.record);
    expect(originals.reads, 2);
    expect(fixture.scheduler.calls, 2);
    expect(fixture.transport.submits, 0);
    expect(fixture.storage.prepares, 0);
    expect(fixture.storage.uploads, 0);
    // When conflicting bound intent tries to reuse the ID through Commit.
    await expectLater(
      service.commit(_request(request, binding: _binding(account: 'B'))),
      throwsStateError,
    );
    // Then the immutable row and scheduler count remain unchanged.
    expect(await queue.find(request.id), first.record);
    expect(fixture.scheduler.calls, 2);
  });

  for (final denial in [
    'missing',
    'wrong account',
    'wrong profile',
    'wrong base',
    'withdrawn',
    'throwing',
    'legacy with context',
  ]) {
    test(
      '$denial is a durable safe configuration failure before any original/remote port',
      () async {
        // Given saved originals and a real row whose participant must not be adopted.
        final binding = _binding();
        final request = _request(
          await fixture.request(),
          binding: denial == 'legacy with context' ? null : binding,
        );
        var queue = await fixture.openQueue();
        final accepted = await queue.enqueue(request);
        final originals = ControlledMaterials(fixture.materials);
        var callbacks = 0;
        final contextBinding = switch (denial) {
          'wrong account' => _binding(account: 'B'),
          'wrong profile' => _binding(profile: 'another'),
          'wrong base' => _binding(base: 'https://other.example/account/'),
          _ => binding,
        };
        final context = denial == 'missing'
            ? null
            : SubmissionAuthenticationContext(
                binding: contextBinding,
                isCurrent: () {
                  callbacks++;
                  if (denial == 'throwing') {
                    throw StateError('private-auth-error');
                  }
                  return denial != 'withdrawn';
                },
              );
        final service = _service(
          fixture,
          queue,
          context: context,
          originals: originals,
        );
        // When the online driver claims the actual record and checks its participant.
        final result = await service.processNext(networkAllowed: true);
        await service.close();
        await queue.close();
        queue = await fixture.openQueue();
        final reopened = (await queue.find(request.id))!;
        // Then safe denial persists without originals, preparation, uploads or dispatch.
        expect(result.outcome, SubmissionRunOutcome.failed);
        expect(reopened, result.record);
        expect(reopened.state, SubmissionState.submissionFailed);
        expect(reopened.request, accepted.request);
        expect(reopened.request.materials, request.materials);
        expect(reopened.request.document, request.document);
        expect(
          reopened.request.authenticationBinding,
          request.authenticationBinding,
        );
        expect(reopened.claimCount, 1);
        expect(reopened.leaseToken, isNull);
        expect(reopened.nextAttemptAt, isNull);
        expect(
          reopened.lastFailure!.stage,
          SubmissionFailureStage.configuration,
        );
        expect(reopened.lastFailure!.code, 'authenticationRequired');
        expect(
          reopened.lastFailure!.message,
          'Sign in to the account bound to this submission.',
        );
        expect(reopened.lastFailure!.retryable, isFalse);
        expect(reopened.failureHistory.length, 1);
        expect(reopened.reservations, isEmpty);
        expect(reopened.receipts, isEmpty);
        expect(reopened.transportCheckpoint, isNull);
        expect(reopened.tklProgress, isNull);
        expect(reopened.acknowledgement, isNull);
        expect(callbacks, ['withdrawn', 'throwing'].contains(denial) ? 1 : 0);
        expect(originals.reads, 0);
        expect(fixture.storage.prepares, 0);
        expect(fixture.storage.uploads, 0);
        expect(fixture.transport.submits, 0);
        expect(fixture.referenceAccess.calls, 0);
        // When the original references are read directly after denial.
        final photo = await fixture.materials.readMaterial(
          request.materials[0].original,
        );
        final audio = await fixture.materials.readMaterial(
          request.materials[1].original,
        );
        // Then actual saved bytes survive unchanged for later explicit same-owner work.
        expect(photo, SubmissionFixture.photoBytes);
        expect(audio, SubmissionFixture.audioBytes);
      },
    );
  }

  test('matching A completes saved photo/audio through reopen and different B cannot adopt retry', () async {
    // Given real local intent A and an exact, explicitly current synthetic context A.
    final request = _request(await fixture.request(), binding: _binding());
    var queue = await fixture.openQueue();
    var service = _service(fixture, queue, context: _context());
    await service.commit(request);
    // When A checkpoints the first reservation, then the native service/queue reopen.
    final preparedPhoto = await service.processNext(networkAllowed: true);
    await service.close();
    await queue.close();
    queue = await fixture.openQueue();
    service = _service(fixture, queue, context: _context(account: 'B'));
    final denied = await service.processNext(networkAllowed: true);
    await service.retry(request.id);
    final deniedAgain = await service.processNext(networkAllowed: true);
    // Then B cannot adopt work or change A's reservation/identity by explicit retry.
    expect(preparedPhoto.record!.reservations.keys, ['photo']);
    expect(denied.record!.lastFailure!.code, 'authenticationRequired');
    expect(deniedAgain.record!.lastFailure!.code, 'authenticationRequired');
    expect(deniedAgain.record!.request, request);
    expect(
      deniedAgain.record!.reservations,
      preparedPhoto.record!.reservations,
    );
    expect(fixture.storage.prepares, 1);
    expect(fixture.storage.uploads, 0);
    expect(fixture.transport.submits, 0);
    // When explicit same-A context retries and executes each remaining stage.
    await service.close();
    service = _service(fixture, queue, context: _context());
    await service.retry(request.id);
    final preparedAudio = await service.processNext(networkAllowed: true);
    final uploadedPhoto = await service.processNext(networkAllowed: true);
    final uploadedAudio = await service.processNext(networkAllowed: true);
    final submitted = await service.processNext(networkAllowed: true);
    await service.close();
    await queue.close();
    queue = await fixture.openQueue();
    final reopened = (await queue.find(request.id))!;
    // Then actual ordered originals reach storage and only matching server ACK completes A.
    expect(preparedAudio.outcome, SubmissionRunOutcome.progress);
    expect(uploadedPhoto.outcome, SubmissionRunOutcome.progress);
    expect(uploadedAudio.outcome, SubmissionRunOutcome.progress);
    expect(submitted.outcome, SubmissionRunOutcome.submitted);
    expect(reopened, submitted.record);
    expect(reopened.request, request);
    expect(reopened.request.authenticationBinding, _binding());
    expect(reopened.receipts.keys, ['photo', 'audio']);
    expect(reopened.transportCheckpoint, isNull);
    expect(
      reopened.acknowledgement,
      fixture.transport.acknowledgement(request),
    );
    expect(reopened.failureHistory.length, 2);
    expect(fixture.storage.prepares, 2);
    expect(fixture.storage.uploads, 2);
    expect(fixture.storage.uploadedBytes, [
      SubmissionFixture.photoBytes,
      SubmissionFixture.audioBytes,
    ]);
    expect(fixture.transport.submits, 1);
    expect(
      fixture.transport.packets.single.request.authenticationBinding,
      _binding(),
    );
  });

  for (final lateError in [false, true]) {
    test(
      'withdrawal discards late storage ${lateError ? 'failure' : 'reservation'} and releases A',
      () async {
        // Given bound A and a controlled storage future held after actual dispatch.
        final request = _request(await fixture.request(), binding: _binding());
        var queue = await fixture.openQueue();
        await queue.enqueue(request);
        var current = true;
        final context = SubmissionAuthenticationContext(
          binding: _binding(),
          isCurrent: () => current,
        );
        final started = Completer<void>();
        final pending = Completer<SubmissionStorageReservation>();
        fixture.storage.onPrepare = (request, material) {
          started.complete();
          return pending.future;
        };
        final service = _service(fixture, queue, context: context);
        final run = service.processNext(networkAllowed: true);
        await started.future;
        // When the exact borrowed lifetime retires before the held operation settles.
        current = false;
        if (lateError) {
          pending.completeError(StateError('private-late-error'));
        } else {
          pending.complete(fixture.storage.reservation('photo', request.id));
        }
        final result = await run;
        await service.close();
        await queue.close();
        queue = await fixture.openQueue();
        final reopened = (await queue.find(request.id))!;
        // Then success and catch paths release without publishing late progress/failure/ACK.
        expect(result.outcome, SubmissionRunOutcome.cancelled);
        expect(reopened, result.record);
        expect(reopened.state, SubmissionState.readyToSubmit);
        expect(reopened.request, request);
        expect(reopened.leaseToken, isNull);
        expect(reopened.reservations, isEmpty);
        expect(reopened.receipts, isEmpty);
        expect(reopened.failureHistory, isEmpty);
        expect(reopened.acknowledgement, isNull);
        expect(fixture.storage.prepares, 1);
        expect(fixture.storage.uploads, 0);
        expect(fixture.transport.submits, 0);
      },
    );
  }

  test('withdrawal during upload discards late receipt while retaining reservation and bytes', () async {
    // Given A with a prepared photo/audio and a controlled upload future.
    final request = _request(await fixture.request(), binding: _binding());
    var queue = await fixture.openQueue();
    await queue.enqueue(request);
    var current = true;
    final service = _service(
      fixture,
      queue,
      context: SubmissionAuthenticationContext(
        binding: _binding(),
        isCurrent: () => current,
      ),
    );
    await service.processNext(networkAllowed: true);
    await service.processNext(networkAllowed: true);
    final before = (await queue.find(request.id))!;
    final started = Completer<void>();
    final pending = Completer<SubmissionMaterialReceipt>();
    fixture.storage.onUpload = (request, material, reservation, bytes) {
      started.complete();
      return pending.future;
    };
    final run = service.processNext(networkAllowed: true);
    await started.future;
    // When A withdraws after upload was possible and the remote later reports success.
    current = false;
    pending.complete(
      SubmissionMaterialReceipt(
        key: 'photo',
        providerId: fixture.storage.providerId,
        remoteId: 'remote-A-photo',
        accessConnectionId: 'drive',
        storedAt: fixture.now,
      ),
    );
    final result = await run;
    await service.close();
    await queue.close();
    queue = await fixture.openQueue();
    final reopened = (await queue.find(request.id))!;
    // Then late receipt is discarded, preserving the exact reservation for reconciliation.
    expect(result.outcome, SubmissionRunOutcome.cancelled);
    expect(reopened.request, request);
    expect(reopened.state, SubmissionState.readyToSubmit);
    expect(reopened.reservations, before.reservations);
    expect(reopened.receipts, isEmpty);
    expect(reopened.acknowledgement, isNull);
    expect(fixture.storage.uploadedBytes.single, SubmissionFixture.photoBytes);
    expect(
      await fixture.materials.readMaterial(request.materials.first.original),
      SubmissionFixture.photoBytes,
    );
    // When B attempts the released work through another context.
    final b = _service(fixture, queue, context: _context(account: 'B'));
    final denied = await b.processNext(networkAllowed: true);
    // Then B gains no receipt or rewritten identity and no second upload starts.
    expect(denied.record!.lastFailure!.code, 'authenticationRequired');
    expect(denied.record!.request, request);
    expect(denied.record!.receipts, isEmpty);
    expect(fixture.storage.uploads, 1);
  });

  test('late ACK is discarded and earlier dispatch uncertainty survives B denial and same-A retry', () async {
    // Given bound A without originals and a held transport after durable dispatch.
    final request = _request(
      await fixture.request(withMaterials: false),
      binding: _binding(),
    );
    var queue = await fixture.openQueue();
    await queue.enqueue(request);
    var current = true;
    final service = _service(
      fixture,
      queue,
      context: SubmissionAuthenticationContext(
        binding: _binding(),
        isCurrent: () => current,
      ),
    );
    final started = Completer<void>();
    final pending = Completer<SubmissionAcknowledgement>();
    fixture.transport.onSubmit = (packet) {
      started.complete();
      return pending.future;
    };
    final run = service.processNext(networkAllowed: true);
    await started.future;
    final dispatched = (await queue.find(request.id))!.transportCheckpoint;
    // When A retires while remote acceptance is possible and a late ACK arrives.
    current = false;
    pending.complete(fixture.transport.acknowledgement(request));
    final result = await run;
    await service.close();
    await queue.close();
    queue = await fixture.openQueue();
    final reopened = (await queue.find(request.id))!;
    // Then no late ACK publishes and the possible remote effect stays uncertain.
    expect(result.outcome, SubmissionRunOutcome.cancelled);
    expect(dispatched, isNotNull);
    expect(reopened.transportCheckpoint, dispatched);
    expect(reopened.acknowledgement, isNull);
    expect(reopened.request, request);
    expect(reopened.state, SubmissionState.readyToSubmit);
    // When B claims this released operation, then explicit same-A retries afterward.
    final b = _service(fixture, queue, context: _context(account: 'B'));
    final denied = await b.processNext(networkAllowed: true);
    // Then initial authentication denial preserves the earlier unknown dispatch.
    expect(denied.record!.transportCheckpoint, dispatched);
    expect(denied.record!.lastFailure!.code, 'authenticationRequired');
    expect(denied.record!.acknowledgement, isNull);
    expect(denied.record!.request, request);
    expect(fixture.transport.submits, 1);
    await b.close();
    fixture.transport.onSubmit = null;
    final a = _service(fixture, queue, context: _context());
    await a.retry(request.id);
    final submitted = await a.processNext(networkAllowed: true);
    // Then only A's explicit continuation reconciles ACK and clears uncertainty.
    expect(submitted.outcome, SubmissionRunOutcome.submitted);
    expect(submitted.record!.request, request);
    expect(
      submitted.record!.acknowledgement,
      fixture.transport.acknowledgement(request),
    );
    expect(submitted.record!.transportCheckpoint, isNull);
    expect(fixture.transport.submits, 2);
  });

  test('legacy unknown checkpoint survives participant denial unchanged', () async {
    // Given an old unbound row with actual legacy dispatch uncertainty in SQLite.
    final original = await fixture.request(withMaterials: false);
    var queue = await fixture.openQueue();
    await queue.enqueue(original);
    await queue.claimNext(
      now: fixture.now,
      leaseToken: 'oldOwner',
      leaseDuration: const Duration(minutes: 5),
    );
    await queue.markTransportDispatch(
      id: original.id,
      leaseToken: 'oldOwner',
      now: fixture.now,
    );
    await queue.release(
      id: original.id,
      leaseToken: 'oldOwner',
      now: fixture.now,
    );
    // The legacy uncertainty import uses the existing closed v1 record decoder.
    final previous = (await queue.find(original.id))!;
    final legacyJson = SubmissionCodec.recordToJson(previous)..['version'] = 1;
    legacyJson.remove('transportCheckpoint');
    final legacy = SubmissionCodec.recordFromJson(legacyJson);
    await queue.close();
    final database = await databaseFactoryFfi.openDatabase(
      fixture.databasePath,
    );
    try {
      await database.update(
        'submission_jobs',
        {'body': jsonEncode(legacyJson)},
        where: 'request_id = ?',
        whereArgs: [original.id],
      );
    } finally {
      await database.close();
    }
    queue = await fixture.openQueue();
    // When a participant context tries to dispatch the actual old-schema row.
    final imported = (await queue.find(original.id))!;
    final service = _service(fixture, queue, context: _context());
    final denied = await service.processNext(networkAllowed: true);
    await service.close();
    await queue.close();
    queue = await fixture.openQueue();
    // Then authentication denial keeps legacy uncertainty without inventing attribution or ACK.
    expect(imported, legacy);
    expect(imported.transportCheckpoint!.isLegacyUnknown, isTrue);
    expect(denied.record!.transportCheckpoint, imported.transportCheckpoint);
    expect(
      (await queue.find(original.id))!.transportCheckpoint,
      imported.transportCheckpoint,
    );
    expect(denied.record!.request.authenticationBinding, isNull);
    expect(denied.record!.lastFailure!.code, 'authenticationRequired');
    expect(denied.record!.acknowledgement, isNull);
    expect(fixture.transport.submits, 0);
  });

  test('caller predicate still cancels before claim without observing authentication', () async {
    // Given bound A and a separately false caller lifetime predicate.
    final queue = await fixture.openQueue();
    final request = _request(await fixture.request(), binding: _binding());
    final accepted = await queue.enqueue(request);
    final observed = ControlledQueue(queue);
    var callbacks = 0;
    final service = _service(
      fixture,
      observed,
      context: SubmissionAuthenticationContext(
        binding: _binding(),
        isCurrent: () {
          callbacks++;
          return true;
        },
      ),
    );
    // When online processing receives the withdrawn caller predicate.
    final result = await service.processNext(
      networkAllowed: true,
      isRunCurrent: () => false,
    );
    // Then original caller cancellation precedes both queue selection and auth callback.
    expect(result.outcome, SubmissionRunOutcome.cancelled);
    expect(observed.calls, 0);
    expect(callbacks, 0);
    expect(await queue.find(request.id), accepted);
  });

  test('unbound request without a context retains the complete controlled legacy path', () async {
    // Given old unbound intent and controlled storage/transport ports without auth context.
    final request = await fixture.request();
    var queue = await fixture.openQueue();
    final service = _service(fixture, queue);
    await service.commit(request);
    // When the driver performs two preparations, two uploads and transport acceptance.
    final first = await service.processNext(networkAllowed: true);
    final second = await service.processNext(networkAllowed: true);
    final third = await service.processNext(networkAllowed: true);
    final fourth = await service.processNext(networkAllowed: true);
    final submitted = await service.processNext(networkAllowed: true);
    await service.close();
    await queue.close();
    queue = await fixture.openQueue();
    // Then all legacy stages and persisted unbound intent remain compatible.
    expect([
      first.outcome,
      second.outcome,
      third.outcome,
      fourth.outcome,
    ], List.filled(4, SubmissionRunOutcome.progress));
    expect(submitted.outcome, SubmissionRunOutcome.submitted);
    expect(await queue.find(request.id), submitted.record);
    expect(submitted.record!.request, request);
    expect(submitted.record!.request.authenticationBinding, isNull);
    expect(
      SubmissionCodec.requestToJson(submitted.record!.request)['version'],
      1,
    );
    expect(fixture.storage.prepares, 2);
    expect(fixture.storage.uploadedBytes, [
      SubmissionFixture.photoBytes,
      SubmissionFixture.audioBytes,
    ]);
    expect(fixture.transport.submits, 1);
  });

  test('TKL participant denial precedes find, destination resolution, prepare and originals', () async {
    // Given bound TKL intent, a configured client and observable original reader.
    final request = _request(
      await fixture.request(),
      binding: _binding(),
      tkl: true,
    );
    var queue = await fixture.openQueue();
    await queue.enqueue(request);
    final originals = ControlledMaterials(fixture.materials);
    final client = _ControlledTkl(request);
    final service = _service(
      fixture,
      queue,
      context: _context(account: 'B'),
      originals: originals,
      tkl: client,
    );
    // When B claims the existing A-bound TKL row.
    final result = await service.processNext(networkAllowed: true);
    await service.close();
    await queue.close();
    queue = await fixture.openQueue();
    // Then real durable denial occurs before any client or original work.
    expect(result.record!.lastFailure!.code, 'authenticationRequired');
    expect(await queue.find(request.id), result.record);
    expect(result.record!.request, request);
    expect(result.record!.tklProgress, isNull);
    expect(result.record!.tklContentDigests, isEmpty);
    expect(result.record!.directReceipts, isEmpty);
    expect(client.calls, isEmpty);
    expect(originals.reads, 0);
    expect(fixture.storage.prepares, 0);
    expect(fixture.transport.submits, 0);
  });

  test('matching TKL context uses current predicate through held preparation and same-A continuation', () async {
    // Given bound real originals and an exact current A context at TKL selection.
    final request = _request(
      await fixture.request(),
      binding: _binding(),
      tkl: true,
    );
    var queue = await fixture.openQueue();
    await queue.enqueue(request);
    var current = true;
    final client = _ControlledTkl(request);
    final started = Completer<void>();
    final pending = Completer<TklMaterialDeliverySnapshot>();
    client.onPrepare = () {
      started.complete();
      return pending.future;
    };
    final service = _service(
      fixture,
      queue,
      context: SubmissionAuthenticationContext(
        binding: _binding(),
        isCurrent: () => current,
      ),
      tkl: client,
    );
    final run = service.processNext(networkAllowed: true);
    await started.future;
    // When A retires during preparation and TKL's late success becomes possible remote work.
    current = false;
    pending.complete(client.prepared());
    final cancelled = await run;
    await service.close();
    await queue.close();
    queue = await fixture.openQueue();
    // Then no late progress/registration/ACK publishes into the released A row.
    expect(cancelled.outcome, SubmissionRunOutcome.cancelled);
    expect(cancelled.record!.request, request);
    expect(cancelled.record!.tklProgress, isNull);
    expect(cancelled.record!.acknowledgement, isNull);
    expect(client.calls, ['find', 'destination', 'prepare']);
    expect(await queue.find(request.id), cancelled.record);
    // When explicit current same-A composition reconciles the existing correlation.
    client.found = client.prepared();
    client.onPrepare = null;
    final resumed = _service(fixture, queue, context: _context(), tkl: client);
    final photo = await resumed.processNext(networkAllowed: true);
    final audio = await resumed.processNext(networkAllowed: true);
    final registered = await resumed.processNext(networkAllowed: true);
    await resumed.close();
    await queue.close();
    queue = await fixture.openQueue();
    // Then actual saved originals finish existing TKL stages without a new identity or fake Studio ACK.
    expect(photo.outcome, SubmissionRunOutcome.progress);
    expect(audio.outcome, SubmissionRunOutcome.progress);
    expect(registered.outcome, SubmissionRunOutcome.materialRegistered);
    expect(registered.record!.request, request);
    expect(registered.record!.request.authenticationBinding, _binding());
    expect(
      registered.record!.tklProgress!.state,
      TklMaterialDeliveryState.registered,
    );
    expect(registered.record!.acknowledgement, isNull);
    expect(await queue.find(request.id), registered.record);
    expect(client.uploads, [
      SubmissionFixture.photoBytes,
      SubmissionFixture.audioBytes,
    ]);
    expect(client.calls.where((call) => call == 'prepare').length, 1);
    expect(fixture.transport.submits, 0);
  });
}

SubmissionAuthenticationBinding _binding({
  String account = 'A',
  String profile = 'authority.main',
  String base = 'https://authority.example/account/',
}) => SubmissionAuthenticationBinding(
  authority: UserAccountHttpProfile.fromString(
    profileId: profile,
    serviceBaseUri: base,
  ),
  userAccountId: account,
);

SubmissionAuthenticationContext _context({String account = 'A'}) =>
    SubmissionAuthenticationContext(
      binding: _binding(account: account),
      isCurrent: () => true,
    );

SubmissionRequest _request(
  SubmissionRequest original, {
  SubmissionAuthenticationBinding? binding,
  bool tkl = false,
}) => SubmissionRequest(
  id: original.id,
  kind: original.kind,
  subjectId: original.subjectId,
  createdAt: original.createdAt,
  document: original.document,
  payload: original.payload,
  materials: original.materials,
  transportConnectionId: tkl ? 'lake' : original.transportConnectionId,
  storageConnectionId: tkl ? null : original.storageConnectionId,
  authenticationBinding: binding,
  extensions: original.extensions,
  tklDelivery: tkl
      ? TklMaterialDeliveryRequest(
          requestId: original.id,
          contribution: {
            'originals': [
              for (final material in original.materials)
                {
                  'resourceId': material.key,
                  'mediaType': material.original.mediaType,
                  'byteLength': material.original.byteLength,
                  'sourceReference': {'kind': 'mobileOriginal'},
                },
            ],
          },
        )
      : null,
);

SubmissionService _service(
  SubmissionFixture fixture,
  SubmissionQueueStore queue, {
  SubmissionAuthenticationContext? context,
  LocalCaptureStore? originals,
  TklMaterialDeliveryClient? tkl,
}) {
  final service = SubmissionService(
    queue: queue,
    materials: originals ?? fixture.materials,
    storageAdapters: {'drive': fixture.storage},
    transports: {'server': fixture.transport},
    scheduler: fixture.scheduler,
    referenceAccessPolicy: fixture.referenceAccess,
    authenticationContext: context,
    tklClients: {'lake': ?tkl},
    now: () => fixture.now,
  );
  fixture.services.add(service);
  return service;
}

/// Synthetic typed port only; no HTTP, credential or server wire substitute.
final class _ControlledTkl implements TklMaterialDeliveryClient {
  _ControlledTkl(this.request);
  final SubmissionRequest request;
  final List<String> calls = [];
  final List<Uint8List> uploads = [];
  final Set<String> uploaded = {};
  TklMaterialDeliverySnapshot? found;
  Future<TklMaterialDeliverySnapshot> Function()? onPrepare;
  int revision = 1;

  TklMaterialDeliverySnapshot prepared({bool registered = false}) =>
      TklMaterialDeliverySnapshot(
        deliveryRef: 'delivery-A',
        requestId: request.id,
        revision: revision,
        destinationId: 'selected',
        destinationLabel: 'Selected',
        state: registered
            ? TklMaterialDeliveryState.registered
            : TklMaterialDeliveryState.prepared,
        materialRef: registered ? 'urn:material:A' : null,
        resources: [
          for (final material in request.materials)
            TklOriginalTransferProgress(
              resourceId: material.key,
              mediaType: material.original.mediaType,
              byteLength: material.original.byteLength,
              state: uploaded.contains(material.key)
                  ? TklOriginalTransferState.uploaded
                  : TklOriginalTransferState.pending,
            ),
        ],
      );

  @override
  Future<TklMaterialDeliveryDestination> getDestination() async {
    calls.add('destination');
    return TklMaterialDeliveryDestination(
      availability: TklDestinationAvailability.available,
      destinationId: 'selected',
      label: 'Selected',
      transferMethod: TklMaterialTransferMethod.tklMultipart,
    );
  }

  @override
  Future<TklMaterialDeliverySnapshot?> findForRequest(String requestId) async {
    calls.add('find');
    return found;
  }

  @override
  Future<TklMaterialDeliverySnapshot> get(String deliveryRef) async {
    calls.add('get');
    return found!;
  }

  @override
  Future<TklMaterialDeliverySnapshot> prepare(
    TklMaterialDeliveryRequest request,
  ) async {
    calls.add('prepare');
    final action = onPrepare;
    if (action != null) return action();
    return found = prepared();
  }

  @override
  Future<TklMaterialDeliverySnapshot> uploadOriginal({
    required String deliveryRef,
    required String resourceId,
    required String mediaType,
    required Uint8List content,
  }) async {
    calls.add('upload');
    uploads.add(Uint8List.fromList(content));
    uploaded.add(resourceId);
    revision++;
    return found = prepared();
  }

  @override
  Future<TklMaterialDeliverySnapshot> finalize(String deliveryRef) async {
    calls.add('finalize');
    revision++;
    return found = prepared(registered: true);
  }
}
