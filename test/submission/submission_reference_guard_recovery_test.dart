import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

import '../support/submission_background_fixture.dart';
import '../support/submission_fixture.dart';

void main() {
  late SubmissionFixture f;
  final stores = <MemorySubmissionConfigurationStore>[];
  setUp(() async {
    // Given a scenario owns its actual FileCaptureStore and SQLite directory.
    f = await SubmissionFixture.create();
    // When the lifetime is admitted, then all ports remain separately owned.
    stores.clear();
    expect(await f.directory.exists(), isTrue);
  });
  tearDown(() async {
    // Given services borrow configuration independently of their real queues.
    final directory = f.directory;
    // When all work drains before configuration owners close and files disappear.
    await f.dispose();
    for (final store in stores) {
      // Given this store is separately owned and no service work remains.
      // When its owner closes it, then durable software evidence stays distinct.
      await store.close();
      expect(store.closed, isTrue);
    }
    // Then no scenario-owned original/database artifact survives cleanup.
    expect(await directory.exists(), isFalse);
  });

  test('RA3', () async {
    // Given actual photo/audio originals, real SQLite and registered unbound ids.
    var queue = await f.openQueue();
    var store = await _configuration(stores);
    var service = f.service(
      queue,
      referenceAccessPolicy: ConfiguredSubmissionReferenceAccessPolicy(
        configuration: store,
      ),
    );
    final request = await f.request();
    await service.commit(request);
    await _uploadAll(service);
    final uploaded = (await queue.find(request.id))!;
    final packet = SubmissionPacket(
      request: request,
      receipts: uploaded.receipts,
    );
    final wire = SubmissionCodec.packetToJson(packet);
    // When all receipts exist but no explicit server resolver binding exists.
    final denied = await service.processNext(networkAllowed: true);
    final waiting = await service.findTransferStatus(
      request.id,
      observedAt: f.now,
    );
    // Then upload succeeds while submission waits, without POST/new checkpoint.
    expect(denied.outcome, SubmissionRunOutcome.failed);
    expect(denied.record!.lastFailure!.code, 'referenceAccessRequired');
    expect(denied.record!.lastFailure!.retryable, isFalse);
    expect(denied.record!.transportCheckpoint, isNull);
    expect(denied.record!.receipts, uploaded.receipts);
    expect(waiting!.upload.state, SubmissionTransferOperationState.succeeded);
    expect(waiting.submission.state, SubmissionTransferOperationState.waiting);
    expect(
      waiting.submission.waitingReason,
      SubmissionTransferWaitingReason.referenceAccess,
    );
    expect(f.transport.submits, 0);
    expect(f.storage.prepares, 2);
    expect(f.storage.uploads, 2);
    // When the operator provisions a controlled binding and retries the same id.
    await store.setReferenceAccess(
      transportConnectionId: 'server',
      storageConnectionIds: ['drive'],
    );
    final saved = jsonEncode((await store.snapshot()).toJson());
    final retried = await service.retry(request.id);
    final submitted = await service.processNext(networkAllowed: true);
    // Then matching controlled acknowledgement accepts exactly the unchanged packet.
    expect(retried.record.request, request);
    expect(submitted.outcome, SubmissionRunOutcome.submitted);
    expect(f.transport.submits, 1);
    expect(f.transport.packets.single, packet);
    expect(SubmissionCodec.packetToJson(f.transport.packets.single), wire);
    expect(submitted.record!.acknowledgement, f.transport.remote[request.id]);
    expect(f.storage.prepares, 2);
    expect(f.storage.uploads, 2);
    // Given a separately serialized safe configuration, not native durability proof.
    final previousQueue = queue;
    final previousService = service;
    final previousStore = store;
    // When owners close and distinct handles reopen with explicitly populated test data.
    await service.close();
    await queue.close();
    await store.close();
    final restored = SubmissionConfigurationSnapshot.fromJson(
      Map<String, Object?>.from(jsonDecode(saved) as Map),
    );
    store = await _configuration(stores, restored: restored);
    queue = await f.openQueue();
    service = f.service(
      queue,
      referenceAccessPolicy: ConfiguredSubmissionReferenceAccessPolicy(
        configuration: store,
      ),
    );
    final retained = (await queue.find(request.id))!;
    final status = await service.findTransferStatus(
      request.id,
      observedAt: f.now,
    );
    // Then original/provenance/manual whitespace and submitted intent survive real reopen.
    expect(identical(queue, previousQueue), isFalse);
    expect(identical(service, previousService), isFalse);
    expect(identical(store, previousStore), isFalse);
    expect((await store.snapshot()).toJson(), restored.toJson());
    expect(retained, submitted.record);
    expect(retained.request, request);
    expect(retained.reservations, uploaded.reservations);
    expect(retained.receipts, uploaded.receipts);
    expect(retained.request.payload['transcript'], '  手入力\n原文  ');
    expect(
      status!.submission.state,
      SubmissionTransferOperationState.succeeded,
    );
    expect(status.acknowledgement, submitted.record!.acknowledgement);
    expect(status.acknowledgementUncertain, isFalse);
    for (final material in retained.request.materials) {
      // Given the exact accepted original reference and provenance in the packet.
      final serialized = (wire['materials']! as List).cast<Map>().singleWhere(
        (value) => value['key'] == material.key,
      );
      // When actual FileCaptureStore bytes are read independently after reopening.
      final bytes = await f.materials.readMaterial(material.original);
      // Then neither uploaded originals nor opaque capture context was rewritten.
      expect(
        bytes,
        material.key == 'photo'
            ? SubmissionFixture.photoBytes
            : SubmissionFixture.audioBytes,
      );
      expect(serialized['original'], material.original.toJson());
      expect(serialized['provenance'], material.provenance);
    }
    expect(store.credentialCalls, 0);
  });

  test('RA4 omitted production policy denies references and zero-upload bypasses policy', () async {
    // Given real complete uploads and a service with omitted production policy.
    final queue = await f.openQueue();
    final uploader = f.service(queue);
    final request = await f.request();
    await uploader.commit(request);
    await _uploadAll(uploader);
    final service = _withoutPolicy(f, queue);
    // When required references reach dispatch without any explicit policy.
    final denied = await service.processNext(networkAllowed: true);
    // Then unknown denies before checkpoint/POST while successful uploads survive.
    expect(denied.record!.lastFailure!.code, 'referenceAccessRequired');
    expect(denied.record!.transportCheckpoint, isNull);
    expect(denied.record!.receipts.length, 2);
    expect(f.referenceAccess.calls, 0);
    expect(f.transport.submits, 0);
    // Given a distinct no-upload request and an explicitly failing test policy.
    final empty = await f.request(
      id: 'empty',
      subjectId: 'emptySubject',
      withMaterials: false,
    );
    f.referenceAccess.onEvaluate = (_) async {
      // Given this callback would expose an accidental no-upload evaluation.
      // When invoked, then the explicit test failure prevents fabricated success.
      throw StateError('No-upload must not inspect this policy');
    };
    await uploader.commit(empty);
    // When no-upload intent dispatches, then both guard checkpoints skip policy.
    final accepted = await uploader.processNext(networkAllowed: true);
    expect(accepted.outcome, SubmissionRunOutcome.submitted);
    expect(accepted.record!.request, empty);
    expect(f.referenceAccess.calls, 0);
    expect(f.transport.submits, 1);
  });

  test('RA4 revocation after actual mark clears only current checkpoint without POST', () async {
    // Given actual uploaded intent with one explicit controlled provisioned binding.
    final queue = await f.openQueue();
    final controlled = ControlledQueue(queue);
    final store = await _configuration(stores, available: true);
    final service = f.service(
      controlled,
      referenceAccessPolicy: ConfiguredSubmissionReferenceAccessPolicy(
        configuration: store,
      ),
    );
    final request = await f.request();
    await service.commit(request);
    await _uploadAll(service);
    SubmissionTransportCheckpoint? marked;
    controlled.after = (name) async {
      // Given the actual durable current-claim dispatch mark has just committed.
      if (name != 'markTransportDispatch') return;
      marked = (await queue.find(request.id))!.transportCheckpoint;
      // When the operator revokes the binding before the second fresh policy read.
      await store.setReferenceAccess(
        transportConnectionId: 'server',
        storageConnectionIds: [],
      );
      // Then final dispatch must observe the live empty binding, without credentials.
    };
    // When transport processing crosses both independent access checks.
    final refused = await service.processNext(networkAllowed: true);
    // Then trusted notSent clears this mark alone and retains all upload facts.
    expect(marked, isNotNull);
    expect(refused.record!.transportCheckpoint, isNull);
    expect(refused.record!.lastFailure!.code, 'referenceAccessRequired');
    expect(f.transport.submits, 0);
    expect(f.storage.uploads, 2);
    expect(store.credentialCalls, 0);
  });

  for (final legacy in [false, true]) {
    test(
      'RA4 ${legacy ? 'legacy' : 'earlier'} uncertainty survives later access refusal',
      () async {
        // Given complete real uploads and an earlier unconfirmed dispatch or legacy row.
        final queue = await f.openQueue();
        final store = await _configuration(stores, available: true);
        final service = f.service(
          queue,
          referenceAccessPolicy: ConfiguredSubmissionReferenceAccessPolicy(
            configuration: store,
          ),
        );
        final request = await f.request();
        await service.commit(request);
        await _uploadAll(service);
        if (legacy) {
          // Given complete old-schema intent with a positive actual claim history.
          final uploaded = (await queue.find(request.id))!;
          final old = SubmissionCodec.recordToJson(uploaded)
            ..['version'] = 1
            ..remove('transportCheckpoint');
          final raw = await databaseFactoryFfi.openDatabase(
            f.databasePath,
            options: OpenDatabaseOptions(singleInstance: false),
          );
          try {
            // When the test-only raw owner installs that old row in actual SQLite.
            await raw.update(
              'submission_jobs',
              {'body': jsonEncode(old)},
              where: 'request_id = ?',
              whereArgs: [request.id],
            );
            // Then the public reader conservatively retains legacy uncertainty.
            expect(
              (await queue.find(request.id))!
                  .transportCheckpoint!
                  .isLegacyUnknown,
              isTrue,
            );
          } finally {
            // Given the scenario alone owns this raw setup handle.
            // When it closes, then public queue ownership stays independent.
            await raw.close();
          }
        } else {
          f.transport.onSubmit = (_) async {
            // Given this controlled transport entered a potentially sent attempt.
            // When an unclassified private result fails, then no safe outcome is inferred.
            throw StateError('PRIVATE_MARKER uncertain remote result');
          };
          final unconfirmed = await service.processNext(networkAllowed: true);
          // Then its current checkpoint remains actual earlier possible acceptance.
          expect(unconfirmed.record!.transportCheckpoint, isNotNull);
          await service.retry(request.id);
        }
        final earliest = (await queue.find(request.id))!.transportCheckpoint;
        // When a later explicit revocation refuses dispatch before any new POST.
        await store.setReferenceAccess(
          transportConnectionId: 'server',
          storageConnectionIds: [],
        );
        final refused = await service.processNext(networkAllowed: true);
        // Then trusted notSent cannot erase earlier or unattributed legacy uncertainty.
        expect(refused.record!.transportCheckpoint, earliest);
        expect(refused.record!.lastFailure!.code, 'referenceAccessRequired');
        expect(f.transport.submits, legacy ? 0 : 1);
        expect(f.storage.uploads, 2);
        await service.close();
        await queue.close();
        // When a distinct real handle reopens, then earliest uncertainty remains durable.
        final reopened = await f.openQueue();
        expect(
          (await reopened.find(request.id))!.transportCheckpoint,
          earliest,
        );
      },
    );
  }

  for (final check in [1, 2]) {
    for (final retirement in ['cancel', 'close', 'steal', 'expire']) {
      test('RA4 $retirement during policy check $check fences ownership', () async {
        // Given complete real uploads and independently owned competing handles.
        final queue = await f.openQueue();
        final other = await f.openQueue();
        final service = f.service(queue);
        final request = await f.request();
        await service.commit(request);
        await _uploadAll(service);
        final entered = Completer<void>();
        final release = Completer<void>();
        var current = true;
        f.referenceAccess.onEvaluate = (_) async {
          // Given each observation is collected as an explicit controlled test fact.
          if (f.referenceAccess.calls != check) {
            return SubmissionReferenceAccessState.available;
          }
          entered.complete();
          // When this selected first/second observation is held for owner change.
          await release.future.timeout(const Duration(seconds: 2));
          // Then service must check current lifetime and actual lease after the await.
          return SubmissionReferenceAccessState.available;
        };
        final running = service.processNext(
          networkAllowed: true,
          isRunCurrent: () => current,
        );
        Future<void>? closing;
        SubmissionRecord? stolen;
        try {
          await entered.future.timeout(const Duration(seconds: 2));
          final before = (await other.find(request.id))!;
          // When the caller retires or real wall time expires under the held policy.
          if (retirement == 'cancel') {
            current = false;
          } else if (retirement == 'close') {
            closing = service.close();
          } else {
            f.now = f.now.add(const Duration(minutes: 6));
            if (retirement == 'steal') {
              stolen = await other.claimNext(
                now: f.now,
                leaseToken: 'otherOwner',
                leaseDuration: const Duration(minutes: 5),
              );
            }
          }
          release.complete();
          final result = await running.timeout(const Duration(seconds: 2));
          await closing;
          // Then neither held check can publish a dispatch from a retired/expired owner.
          expect(
            result.outcome,
            retirement == 'cancel' || retirement == 'close'
                ? SubmissionRunOutcome.cancelled
                : SubmissionRunOutcome.leaseLost,
          );
          expect(f.transport.submits, 0);
          expect(f.storage.prepares, 2);
          expect(f.storage.uploads, 2);
          expect(before.transportCheckpoint == null, check == 1);
          if (stolen != null) {
            // Given the other real handle owns the current unexpired claim.
            // When its record is read after the stale owner settles.
            final retained = await other.find(request.id);
            // Then the stale service has changed neither claim nor checkpoints.
            expect(retained, stolen);
          }
        } finally {
          // Given scenario-owned policy work must drain even after assertion failure.
          if (!release.isCompleted) release.complete();
          // When accepted work and any service close join their bounded futures.
          await running.timeout(const Duration(seconds: 2));
          await closing;
          // Then fixture owners may safely close their borrowed resources.
        }
      });
    }
  }

  for (final check in [1, 2]) {
    for (final failure in ['raw', 'timeout']) {
      test(
        'RA4 $failure at policy check $check yields safe retry without reupload',
        () async {
          // Given real complete uploads and a bounded policy with controlled failure.
          final queue = await f.openQueue();
          final service = f.service(
            queue,
            operationTimeout: const Duration(milliseconds: 30),
            leaseDuration: const Duration(seconds: 1),
          );
          final request = await f.request();
          await service.commit(request);
          await _uploadAll(service);
          final entered = Completer<void>();
          final response = Completer<SubmissionReferenceAccessState>();
          f.referenceAccess.onEvaluate = (_) async {
            // Given a selected fresh check, independently of all previous uploads.
            if (f.referenceAccess.calls != check) {
              return SubmissionReferenceAccessState.available;
            }
            entered.complete();
            // When a raw private error or held response crosses the local policy port.
            if (failure == 'raw') {
              throw StateError('PRIVATE_MARKER owner@example.test');
            }
            // Then only the bounded observation may reach a durable result.
            return response.future;
          };
          final running = service.processNext(networkAllowed: true);
          try {
            await entered.future.timeout(const Duration(seconds: 2));
            // When policy fails/times out before a transport side effect.
            final failed = await running.timeout(const Duration(seconds: 2));
            final record = failed.record!;
            // Then fixed safe configuration failure has an actual persisted retry deadline.
            expect(failed.outcome, SubmissionRunOutcome.failed);
            expect(
              record.lastFailure!.stage,
              SubmissionFailureStage.configuration,
            );
            expect(record.lastFailure!.code, 'referenceAccessUnavailable');
            expect(
              record.lastFailure!.message,
              'Server access configuration is unavailable.',
            );
            expect(record.lastFailure!.retryable, isTrue);
            expect(
              record.nextAttemptAt,
              f.now.add(service.automaticRetryDelay),
            );
            expect(record.transportCheckpoint, isNull);
            expect(
              jsonEncode(SubmissionCodec.recordToJson(record)),
              isNot(contains('PRIVATE_MARKER')),
            );
            expect(f.transport.submits, 0);
            response.complete(SubmissionReferenceAccessState.available);
            // When a late available value is released and the explicit policy recovers.
            f.referenceAccess.onEvaluate = null;
            await service.retry(request.id);
            final accepted = await service.processNext(networkAllowed: true);
            // Then the same immutable packet succeeds once without prepare/upload repetition.
            expect(accepted.outcome, SubmissionRunOutcome.submitted);
            expect(accepted.record!.request, request);
            expect(accepted.record!.receipts, record.receipts);
            expect(f.storage.prepares, 2);
            expect(f.storage.uploads, 2);
            expect(f.transport.submits, 1);
          } finally {
            // Given late underlying policy futures remain owned by this scenario.
            if (!response.isCompleted) {
              response.complete(SubmissionReferenceAccessState.available);
            }
            // When bounded accepted work drains, then fixture resources may close.
            await running.timeout(const Duration(seconds: 2));
          }
        },
      );
    }
  }
}

Future<MemorySubmissionConfigurationStore> _configuration(
  List<MemorySubmissionConfigurationStore> owners, {
  bool available = false,
  SubmissionConfigurationSnapshot? restored,
}) async {
  // Given explicit registered local values or a separately decoded safe snapshot.
  final store = MemorySubmissionConfigurationStore();
  owners.add(store);
  final values =
      restored ??
      SubmissionConfigurationSnapshot(
        driveConnections: [
          DriveSubmissionConnection(
            id: 'drive',
            accountId: 'owner@example.test',
            folderId: 'Folder',
          ),
        ],
        httpConnections: [
          HttpSubmissionConnection(
            id: 'server',
            endpoint: Uri.parse('https://example.test/submit'),
          ),
        ],
        selectedStorageConnectionId: 'drive',
        selectedTransportConnectionId: 'server',
        referenceAccessBindings: available
            ? {
                'server': ['drive'],
              }
            : {},
      );
  // When the new behavioral port is populated explicitly, never secretly persisted.
  for (final connection in values.driveConnections) {
    // Given an exact restored Drive identity, when inserted, then its kind survives.
    await store.putDrive(connection);
  }
  for (final connection in values.httpConnections) {
    // Given an exact restored HTTP identity, when inserted, then no retarget occurs.
    await store.putHttp(connection);
  }
  await store.select(
    storageConnectionId: values.selectedStorageConnectionId,
    transportConnectionId: values.selectedTransportConnectionId,
  );
  for (final entry in values.referenceAccessBindings.entries) {
    // Given a serialized explicit declaration, including empty revocation.
    // When the distinct test port accepts it through the actual required operation.
    await store.setReferenceAccess(
      transportConnectionId: entry.key,
      storageConnectionIds: entry.value,
    );
    // Then configuration reopen evidence is controlled, not Android durability proof.
  }
  // Then live policy can observe only those explicit copied declarations.
  return store;
}

Future<void> _uploadAll(SubmissionService service) async {
  // Given photo/audio originals require two reserves and two binary uploads.
  for (var index = 0; index < 4; index++) {
    // When the actual service performs one bounded stage per invocation.
    final progress = await service.processNext(networkAllowed: true);
    // Then access configuration has not prevented preparing/uploading originals.
    expect(progress.outcome, SubmissionRunOutcome.progress);
    expect(progress.record!.transportCheckpoint, isNull);
  }
}

SubmissionService _withoutPolicy(
  SubmissionFixture fixture,
  SubmissionQueueStore queue,
) {
  // Given a production constructor with genuinely omitted optional access policy.
  // When the fixture takes ownership of that service while its ports stay borrowed.
  final service = SubmissionService(
    queue: queue,
    materials: fixture.materials,
    storageAdapters: {'drive': fixture.storage},
    transports: {'server': fixture.transport},
    scheduler: fixture.scheduler,
    now: () => fixture.now,
  );
  fixture.services.add(service);
  // Then controlled fixture availability cannot implicitly enter this service.
  return service;
}
