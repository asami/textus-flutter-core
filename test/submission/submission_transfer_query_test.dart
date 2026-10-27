import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

import '../support/submission_background_fixture.dart';
import '../support/submission_fixture.dart';

void main() {
  late SubmissionFixture f;
  late MemorySubmissionConfigurationStore configuration;
  setUp(() async {
    // Given independent real files/SQLite and a separately owned safe test store.
    f = await SubmissionFixture.create();
    configuration = MemorySubmissionConfigurationStore();
    // When exact registered definitions are supplied without inferred reference access.
    await configuration.putDrive(
      DriveSubmissionConnection(
        id: 'drive',
        accountId: 'owner@example.test',
        folderId: 'Folder',
      ),
    );
    await configuration.putHttp(
      HttpSubmissionConnection(
        id: 'server',
        endpoint: Uri.parse('https://example.test/submit'),
      ),
    );
    // Then future queries observe only current explicit controlled declarations.
    expect(configuration.snapshotCalls, 0);
  });
  tearDown(() async {
    // Given services borrow both real queues and the independent configuration port.
    // When all service reads/work drain before those owning ports close.
    await f.dispose();
    await configuration.close();
    // Then no borrowed configuration lifetime has been claimed by a service.
    expect(configuration.closed, isTrue);
  });

  test('RA7 public queries reflect live bindings without mutation or active side effects', () async {
    // Given actual full receipts and a read-only spy over the same real queue.
    final queue = await f.openQueue();
    final controlled = ControlledQueue(queue);
    final originals = ControlledMaterials(f.materials);
    final service = f.service(
      controlled,
      originals: originals,
      referenceAccessPolicy: ConfiguredSubmissionReferenceAccessPolicy(
        configuration: configuration,
      ),
    );
    final request = await f.request();
    await service.commit(request);
    await _progress(service, 4);
    final durable = await queue.list();
    final reads = originals.reads;
    final wakes = f.scheduler.calls;
    final operations = <String>[];
    controlled.after = (name) async {
      // Given all query forwarding operations are observable after actual SQLite IO.
      // When the borrowed wrapper reports its completed operation.
      operations.add(name);
      // Then assertions can reject any command/claim/wake rather than infer purity.
    };
    final observed = DateTime.parse('2026-10-10T10:00:00+09:00');
    // When all three public query routes read the same required unbound packet.
    final byId = (await service.findTransferStatus(
      request.id,
      observedAt: observed,
    ))!;
    final bySubject = await service.findTransferStatusForSubject(
      request.kind,
      request.subjectId,
      observedAt: observed,
    );
    final listed = await service.listTransferStatuses(observedAt: observed);
    // Then identity, actual progress, UTC time and immutable values agree freshly.
    expect(bySubject, byId);
    expect(listed, [byId]);
    expect(byId.requestId, request.id);
    expect(byId.kind, request.kind);
    expect(byId.subjectId, request.subjectId);
    expect(byId.observedAt, observed.toUtc());
    expect(byId.observedAt.isUtc, isTrue);
    expect(byId.storageConnectionId, 'drive');
    expect(byId.transportConnectionId, 'server');
    expect(byId.upload.completedCount, 2);
    expect(byId.upload.totalCount, 2);
    expect(
      byId.files.map((file) => file.receipt),
      durable.single.receipts.values,
    );
    expect(
      byId.submission.waitingReason,
      SubmissionTransferWaitingReason.referenceAccess,
    );
    expect(() => listed.clear(), throwsUnsupportedError);
    expect(() => byId.files.clear(), throwsUnsupportedError);
    expect(() => byId.actions.clear(), throwsUnsupportedError);
    // When explicit binding changes after service creation, every read observes it.
    await configuration.setReferenceAccess(
      transportConnectionId: 'server',
      storageConnectionIds: ['drive'],
    );
    final available = (await service.findTransferStatus(
      request.id,
      observedAt: observed,
    ))!;
    final offline = (await service.findTransferStatus(
      request.id,
      observedAt: observed,
      networkState: SubmissionNetworkState.offline,
    ))!;
    final reset = (await service.findTransferStatus(
      request.id,
      observedAt: observed,
    ))!;
    await configuration.setReferenceAccess(
      transportConnectionId: 'server',
      storageConnectionIds: [],
    );
    final revoked = (await service.findTransferStatus(
      request.id,
      observedAt: observed,
    ))!;
    // Then omitted network observation resets and revoked access never grants dispatch.
    expect(available.submission.state, SubmissionTransferOperationState.queued);
    expect(
      offline.submission.waitingReason,
      SubmissionTransferWaitingReason.networkUnavailable,
    );
    expect(reset, available);
    expect(
      revoked.submission.waitingReason,
      SubmissionTransferWaitingReason.referenceAccess,
    );
    expect(configuration.snapshotCalls, 7);
    expect(configuration.credentialCalls, 0);
    expect(originals.reads, reads);
    expect(f.scheduler.calls, wakes);
    expect(f.storage.prepares, 2);
    expect(f.storage.uploads, 2);
    expect(f.transport.submits, 0);
    expect(await queue.list(), durable);
    expect(operations, [
      'find',
      'findForSubject',
      'list',
      'find',
      'find',
      'find',
      'find',
    ]);
    // Given a real durable earliest dispatch, released without server acceptance.
    final claimed = (await queue.claimNext(
      now: f.now,
      leaseToken: 'queryOwner',
      leaseDuration: const Duration(minutes: 5),
    ))!;
    final marked = await queue.markTransportDispatch(
      id: request.id,
      leaseToken: claimed.leaseToken!,
      now: f.now,
    );
    await queue.release(
      id: request.id,
      leaseToken: claimed.leaseToken!,
      now: f.now,
    );
    // When a fresh query projects actual uncertainty alongside current denied access.
    final uncertain = (await service.findTransferStatus(
      request.id,
      observedAt: observed,
    ))!;
    // Then current observations cannot erase possible earlier acceptance or receipts.
    expect(uncertain.acknowledgementUncertain, isTrue);
    expect(
      uncertain.submission.state,
      SubmissionTransferOperationState.outcomeUnknown,
    );
    expect(
      (await queue.find(request.id))!.transportCheckpoint,
      marked.transportCheckpoint,
    );
    expect(uncertain.upload.state, SubmissionTransferOperationState.succeeded);
    expect(f.transport.submits, 0);
  });

  for (final scenario in ['missing', 'partial', 'submitted', 'noUpload']) {
    test('RA7 $scenario skips reference policy and does not wake', () async {
      // Given one real queue state whose observation requires no policy read.
      final queue = await f.openQueue();
      final request = await f.request(withMaterials: scenario != 'noUpload');
      final uploader = f.service(queue);
      if (scenario != 'missing') {
        // When actual queue/service operations establish the selected durable state.
        await uploader.commit(request);
        if (scenario == 'partial') await _progress(uploader, 3);
        if (scenario == 'submitted') {
          await _progress(uploader, 4);
          final submitted = await uploader.processNext(networkAllowed: true);
          // Then only the matching controlled acknowledgement establishes acceptance.
          expect(submitted.outcome, SubmissionRunOutcome.submitted);
        }
      }
      final snapshot = await queue.list();
      final beforeCalls = f.referenceAccess.calls;
      final beforeWake = f.scheduler.calls;
      final beforePost = f.transport.submits;
      f.referenceAccess.onEvaluate = (_) async {
        // Given these states must never require a local policy observation.
        // When accidentally invoked, then the controlled test fact fails visibly.
        throw StateError('PRIVATE_MARKER policy must be skipped');
      };
      // When id/subject/list queries inspect the actual state with a failing policy.
      final byId = await uploader.findTransferStatus(
        request.id,
        observedAt: f.now,
      );
      final bySubject = await uploader.findTransferStatusForSubject(
        request.kind,
        request.subjectId,
        observedAt: f.now,
      );
      final list = await uploader.listTransferStatuses(observedAt: f.now);
      // Then absence is null and other values reflect only durable facts.
      expect(bySubject, byId);
      expect(list, scenario == 'missing' ? isEmpty : [byId]);
      if (scenario == 'missing') {
        expect(byId, isNull);
      } else if (scenario == 'partial') {
        expect(byId!.upload.completedCount, 1);
        expect(
          byId.submission.waitingReason,
          SubmissionTransferWaitingReason.materialUpload,
        );
      } else if (scenario == 'submitted') {
        expect(
          byId!.submission.state,
          SubmissionTransferOperationState.succeeded,
        );
        expect(byId.acknowledgement, snapshot.single.acknowledgement);
      } else {
        expect(
          byId!.upload.state,
          SubmissionTransferOperationState.notRequired,
        );
        expect(byId.submission.state, SubmissionTransferOperationState.queued);
      }
      expect(f.referenceAccess.calls, beforeCalls);
      expect(f.scheduler.calls, beforeWake);
      expect(f.transport.submits, beforePost);
      expect(await queue.list(), snapshot);
    });
  }

  test('RA7 omitted policy stays unknown and queue faults/corruption propagate', () async {
    // Given fully uploaded real intent and an omitted production observation policy.
    final queue = await f.openQueue();
    final uploader = f.service(queue);
    final request = await f.request();
    await uploader.commit(request);
    await _progress(uploader, 4);
    final controlled = ControlledQueue(queue);
    final service = SubmissionService(
      queue: controlled,
      materials: f.materials,
      storageAdapters: {'drive': f.storage},
      transports: {'server': f.transport},
      scheduler: f.scheduler,
    );
    f.services.add(service);
    // When current status is queried without any explicit access policy.
    final status = await service.findTransferStatus(
      request.id,
      observedAt: f.now,
    );
    // Then unknown waits and cannot become successful or implicitly configured.
    expect(
      status!.submission.waitingReason,
      SubmissionTransferWaitingReason.referenceAccess,
    );
    expect(f.referenceAccess.calls, 0);
    // When the actual borrowed read boundary reports a queue failure.
    controlled.failAt = 'find';
    await expectLater(
      service.findTransferStatus(request.id, observedAt: f.now),
      throwsStateError,
    );
    // Then local queue failure is an error, with no empty/success fallback.
    expect(f.transport.submits, 0);
    final raw = await databaseFactoryFfi.openDatabase(
      f.databasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      // Given the raw test-owned handle can corrupt the actual persisted record.
      final durable = (await queue.find(request.id))!;
      final corrupted = SubmissionCodec.recordToJson(durable)
        ..['version'] = 999;
      // When exact SQLite backing is replaced with a malformed record body.
      await raw.update(
        'submission_jobs',
        {'body': jsonEncode(corrupted)},
        where: 'request_id = ?',
        whereArgs: [request.id],
      );
      // Then all three real read routes propagate decoder corruption observably.
      await expectLater(
        service.findTransferStatus(request.id, observedAt: f.now),
        throwsFormatException,
      );
      await expectLater(
        service.findTransferStatusForSubject(
          request.kind,
          request.subjectId,
          observedAt: f.now,
        ),
        throwsFormatException,
      );
      await expectLater(
        service.listTransferStatuses(observedAt: f.now),
        throwsFormatException,
      );
    } finally {
      // Given this raw handle alone belongs to setup, independent of service reads.
      // When its owner closes it, then fixture cleanup can drain its own queue.
      await raw.close();
    }
  });

  for (final failure in ['raw', 'timeout']) {
    test(
      'RA7 $failure policy observation throws only fixed safe configuration error',
      () async {
        // Given real full receipts and a bounded observation policy with controlled failure.
        final queue = await f.openQueue();
        final service = f.service(
          queue,
          operationTimeout: const Duration(milliseconds: 30),
          leaseDuration: const Duration(seconds: 1),
        );
        final request = await f.request();
        await service.commit(request);
        await _progress(service, 4);
        final durable = await queue.list();
        final entered = Completer<void>();
        final response = Completer<SubmissionReferenceAccessState>();
        f.referenceAccess.onEvaluate = (_) async {
          // Given the observation is explicitly entered, independent of dispatch.
          entered.complete();
          // When sensitive raw failure or a held response reaches the policy port.
          if (failure == 'raw') {
            throw StateError('PRIVATE_MARKER owner@example.test');
          }
          // Then only a bounded local observation can reach the public query.
          return response.future;
        };
        final pending = service.findTransferStatus(
          request.id,
          observedAt: f.now,
        );
        final rejected = expectLater(pending, throwsA(_safeConfiguration()));
        try {
          await entered.future.timeout(const Duration(seconds: 2));
          // When the bounded read rejects without any command transition.
          await rejected.timeout(const Duration(seconds: 2));
          // Then the safe error has not fabricated state or changed durable facts.
          expect(await queue.list(), durable);
          expect(f.transport.submits, 0);
          expect(configuration.credentialCalls, 0);
        } finally {
          // Given the scenario owns the underlying held response beyond query timeout.
          if (!response.isCompleted) {
            response.complete(SubmissionReferenceAccessState.available);
          }
          // When its released read settles, then owner cleanup sees no unresolved future.
          await rejected.timeout(const Duration(seconds: 2));
        }
      },
    );
  }

  test(
    'RA7 close joins accepted held query and discards its late value',
    () async {
      // Given full real receipts and a held actual configured-store snapshot read.
      final queue = await f.openQueue();
      final service = f.service(
        queue,
        referenceAccessPolicy: ConfiguredSubmissionReferenceAccessPolicy(
          configuration: configuration,
        ),
      );
      final request = await f.request();
      await service.commit(request);
      await _progress(service, 4);
      final durable = await queue.list();
      final entered = Completer<void>();
      final release = Completer<void>();
      configuration.beforeSnapshot = () async {
        // Given the borrowed configuration is still owned by this scenario.
        entered.complete();
        // When current access observation remains held during service close.
        await release.future.timeout(const Duration(seconds: 2));
        // Then a late snapshot cannot publish status for the closing service.
      };
      final pending = service.findTransferStatus(request.id, observedAt: f.now);
      final rejected = expectLater(pending, throwsStateError);
      Future<void>? closing;
      var closed = false;
      try {
        await entered.future.timeout(const Duration(seconds: 2));
        // When close invalidates new calls while joining the accepted bounded read.
        closing = service.close();
        final observedClose = closing.then((_) {
          // Given the accepted read must finish before service cleanup can complete.
          // When close resolves, then its completion is observable to the scenario.
          closed = true;
        });
        await expectLater(
          service.findTransferStatus(request.id, observedAt: f.now),
          throwsStateError,
        );
        await expectLater(
          service.findTransferStatusForSubject(
            request.kind,
            request.subjectId,
            observedAt: f.now,
          ),
          throwsStateError,
        );
        await expectLater(
          service.listTransferStatuses(observedAt: f.now),
          throwsStateError,
        );
        // Then close is still pending and has neither closed queue nor configuration.
        expect(closed, isFalse);
        expect(configuration.closed, isFalse);
        expect(await queue.list(), durable);
        release.complete();
        await rejected.timeout(const Duration(seconds: 2));
        await observedClose.timeout(const Duration(seconds: 2));
        configuration.beforeSnapshot = null;
        // When the independent configuration/queue owners read after service close.
        final retained = await configuration.snapshot();
        // Then borrowed ports remain usable and no late status mutated intent.
        expect(closed, isTrue);
        expect(retained.referenceAccessBindings, isEmpty);
        expect(await queue.list(), durable);
        expect(f.transport.submits, 0);
        expect(configuration.credentialCalls, 0);
      } finally {
        // Given the scenario owns every entry/release signal and cleanup join.
        if (!release.isCompleted) release.complete();
        // When pending read/close drain, then borrowed owners can safely close later.
        await rejected.timeout(const Duration(seconds: 2));
        await closing;
        configuration.beforeSnapshot = null;
      }
    },
  );
}

Future<void> _progress(SubmissionService service, int steps) async {
  // Given an explicit number of actual one-operation prepare/upload transitions.
  for (var index = 0; index < steps; index++) {
    // When the public service operates against real originals and SQLite.
    final result = await service.processNext(networkAllowed: true);
    // Then every requested setup transition is durable progress without POST.
    expect(result.outcome, SubmissionRunOutcome.progress);
  }
}

Matcher _safeConfiguration() {
  // Given only fixed public configuration failure is safe after arbitrary policy IO.
  // When a query throws, the matcher inspects code and diagnostic exclusion.
  final matcher = isA<SubmissionConfigurationException>()
      .having((value) => value.code, 'fixed code', 'configurationUnavailable')
      .having(
        (value) => value.message,
        'fixed message',
        'Submission configuration is unavailable.',
      )
      .having(
        (value) => '$value',
        'no private marker',
        isNot(contains('PRIVATE_MARKER')),
      );
  // Then timeout/raw causes cannot become success, unknown fallback or leaked data.
  return matcher;
}
