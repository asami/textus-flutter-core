import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  group('TS1 actual independent upload and submission facts', () {
    test('initial, observed network and partial receipt progress', () {
      // Given two unchanged originals and an initial durable ready record.
      final request = _request();
      final ready = _record(request);
      // When network knowledge is absent, explicitly offline or policy blocked.
      final unknown = _status(ready);
      final offline = _status(ready, network: SubmissionNetworkState.offline);
      final blocked = _status(
        ready,
        network: SubmissionNetworkState.policyBlocked,
      );
      // Then unknown invents no wait, while supplied observations remain visible.
      expect(unknown.upload.state, SubmissionTransferOperationState.queued);
      expect(unknown.upload.waitingReason, isNull);
      expect(unknown.upload.completedCount, 0);
      expect(unknown.upload.totalCount, 2);
      expect(unknown.upload.completedAt, isNull);
      expect(unknown.upload.nextAttemptAt, isNull);
      expect(unknown.upload.leaseExpiresAt, isNull);
      expect(
        offline.upload.waitingReason,
        SubmissionTransferWaitingReason.networkUnavailable,
      );
      expect(
        blocked.upload.waitingReason,
        SubmissionTransferWaitingReason.policyBlocked,
      );
      expect(
        unknown.submission.waitingReason,
        SubmissionTransferWaitingReason.materialUpload,
      );
      expect(unknown.submission.completedCount, isNull);
      expect(unknown.submission.totalCount, isNull);

      // Given one actual reservation and successful receipt in request order.
      final partial = _record(request, uploaded: 1, claimCount: 2);
      // When the immutable aggregate is projected without inventing an active file.
      final status = _status(partial);
      // Then only the acknowledged original succeeds and all other files queue.
      expect(status.files.map((file) => file.key), ['photo', 'audio']);
      expect(status.files.first.original, request.materials.first.original);
      expect(status.files.first.reservation, partial.reservations['photo']);
      expect(status.files.first.receipt, partial.receipts['photo']);
      expect(
        status.files.first.state,
        SubmissionTransferOperationState.succeeded,
      );
      expect(status.files.last.reservation, isNull);
      expect(status.files.last.receipt, isNull);
      expect(status.files.last.state, SubmissionTransferOperationState.queued);
      expect(status.upload.completedCount, 1);
      expect(status.upload.totalCount, 2);
      expect(status.upload.completedAt, isNull);
      expect(status.submission.failure, isNull);
    });

    test('failed upload owns failure and actual future retry deadline', () {
      // Given an aggregate safe failure with one successfully uploaded original.
      final request = _request();
      final due = _at.add(const Duration(seconds: 30));
      final failed = _record(
        request,
        uploaded: 1,
        claimCount: 3,
        state: SubmissionState.submissionFailed,
        retryAt: due,
      );
      // When this queue row is observed before and after its persisted deadline.
      final future = _status(failed);
      final past = _status(failed, observed: due);
      // Then failure remains aggregate and submission only waits on material upload.
      expect(future.upload.state, SubmissionTransferOperationState.failed);
      expect(future.upload.failure, failed.lastFailure);
      expect(future.upload.nextAttemptAt, due);
      expect(
        future.upload.waitingReason,
        SubmissionTransferWaitingReason.retryScheduled,
      );
      expect(past.upload.waitingReason, isNull);
      expect(past.upload.nextAttemptAt, due);
      expect(future.files.last.state, SubmissionTransferOperationState.queued);
      expect(
        future.files.first.state,
        SubmissionTransferOperationState.succeeded,
      );
      expect(future.submission.state, SubmissionTransferOperationState.waiting);
      expect(
        future.submission.waitingReason,
        SubmissionTransferWaitingReason.materialUpload,
      );
      expect(future.submission.failure, isNull);
      expect(future.submission.nextAttemptAt, isNull);
      expect(future.actions, {SubmissionTransferAction.retry});
    });

    test('complete upload and known failure versus uncertain submission', () {
      // Given all actual receipts and a safely failed submission with no dispatch.
      final request = _request();
      final failed = _record(
        request,
        uploaded: 2,
        claimCount: 4,
        state: SubmissionState.submissionFailed,
      );
      // When reference availability is explicitly supplied for that observation.
      final known = _status(
        failed,
        access: SubmissionReferenceAccessState.available,
      );
      // Then completed uploads remain successful despite independent submit failure.
      expect(known.upload.state, SubmissionTransferOperationState.succeeded);
      expect(known.upload.completedCount, 2);
      expect(known.upload.completedAt, _at.add(const Duration(seconds: 1)));
      expect(known.upload.failure, isNull);
      expect(known.upload.nextAttemptAt, isNull);
      expect(known.submission.state, SubmissionTransferOperationState.failed);
      expect(known.submission.failure, failed.lastFailure);
      expect(known.acknowledgementUncertain, isFalse);
      // Given the same known failed attempt without current reference availability.
      final beforeAccess = failed;
      // When required-reference access remains unknown at this fresh observation.
      final unavailable = _status(beforeAccess);
      // Then the reference gate precedes a new attempt and does not undo upload success.
      expect(
        unavailable.submission.waitingReason,
        SubmissionTransferWaitingReason.referenceAccess,
      );
      expect(
        unavailable.submission.state,
        SubmissionTransferOperationState.waiting,
      );
      expect(
        unavailable.upload.state,
        SubmissionTransferOperationState.succeeded,
      );

      // Given the earliest potentially dispatched claim before that current failure.
      final uncertain = _record(
        request,
        uploaded: 2,
        claimCount: 4,
        state: SubmissionState.submissionFailed,
        retryAt: _at.add(const Duration(seconds: 30)),
        checkpoint: SubmissionTransportCheckpoint.pending(
          claimCount: 2,
          startedAt: _at,
        ),
      );
      // When offline and unavailable references are observed after possible dispatch.
      final status = _status(
        uncertain,
        network: SubmissionNetworkState.offline,
        access: SubmissionReferenceAccessState.unavailable,
      );
      // Then uncertainty outranks refusal/access while retaining current waiting facts.
      expect(
        status.submission.state,
        SubmissionTransferOperationState.outcomeUnknown,
      );
      expect(
        status.submission.waitingReason,
        SubmissionTransferWaitingReason.networkUnavailable,
      );
      expect(status.submission.nextAttemptAt, uncertain.nextAttemptAt);
      expect(status.submission.failure, uncertain.lastFailure);
      expect(status.acknowledgementUncertain, isTrue);
      expect(status.acknowledgement, isNull);
      expect(status.actions, {SubmissionTransferAction.retry});
    });

    test('matching server acknowledgement and no-upload requests', () {
      // Given explicit server acceptance matching a completely uploaded request.
      final request = _request();
      final ack = SubmissionAcknowledgement(
        requestId: request.id,
        subjectId: request.subjectId,
        serverId: 'controlled/server',
        receivedAt: _at.add(const Duration(minutes: 1)),
      );
      final submitted = _record(
        request,
        uploaded: 2,
        claimCount: 5,
        state: SubmissionState.submitted,
        acknowledgement: ack,
      );
      // When current connectivity and access are absent after accepted completion.
      final status = _status(
        submitted,
        network: SubmissionNetworkState.offline,
      );
      // Then both operations succeed solely from their actual independent receipts.
      expect(status.upload.state, SubmissionTransferOperationState.succeeded);
      expect(
        status.submission.state,
        SubmissionTransferOperationState.succeeded,
      );
      expect(status.submission.completedAt, ack.receivedAt);
      expect(status.submission.waitingReason, isNull);
      expect(status.submission.leaseExpiresAt, isNull);
      expect(status.acknowledgement, ack);
      expect(status.acknowledgementUncertain, isFalse);
      expect(status.actions, isEmpty);

      // Given an accepted intent requiring no original uploads or reference access.
      final empty = _record(_request(withMaterials: false));
      // When access remains unknown, as it does after restart.
      final noUpload = _status(empty);
      // Then upload is not required and submission queues without an access gate.
      expect(
        noUpload.upload.state,
        SubmissionTransferOperationState.notRequired,
      );
      expect(noUpload.upload.completedCount, 0);
      expect(noUpload.upload.totalCount, 0);
      expect(noUpload.upload.completedAt, isNull);
      expect(noUpload.storageConnectionId, isNull);
      expect(noUpload.files, isEmpty);
      expect(
        noUpload.submission.state,
        SubmissionTransferOperationState.queued,
      );
    });
  });

  group('TS2 presentation observations and supported queue actions', () {
    for (final uploaded in [0, 2]) {
      test('active and expired durable claims with $uploaded receipts', () {
        // Given a durable current lease, without proof an executing process lives.
        final request = _request();
        final record = _record(
          request,
          uploaded: uploaded,
          claimCount: 2,
          state: SubmissionState.submitting,
          checkpoint: uploaded == 2
              ? SubmissionTransportCheckpoint.pending(
                  claimCount: 2,
                  startedAt: _at,
                )
              : null,
        );
        // When observations straddle the actual expiry, including exact equality.
        final active = _status(record);
        final expired = _status(record, observed: record.leaseExpiresAt);
        // Then only an expired claim supports wake, retaining the exact deadline.
        final operation = uploaded == 2 ? active.submission : active.upload;
        final recovered = uploaded == 2 ? expired.submission : expired.upload;
        expect(operation.state, SubmissionTransferOperationState.running);
        expect(operation.leaseExpiresAt, record.leaseExpiresAt);
        expect(active.actions, isEmpty);
        expect(
          recovered.state,
          uploaded == 2
              ? SubmissionTransferOperationState.outcomeUnknown
              : SubmissionTransferOperationState.waiting,
        );
        expect(
          recovered.waitingReason,
          SubmissionTransferWaitingReason.leaseRecovery,
        );
        expect(recovered.leaseExpiresAt, record.leaseExpiresAt);
        expect(expired.actions, {SubmissionTransferAction.requestRun});
        expect(active.acknowledgementUncertain, uploaded == 2);
      });
    }

    test('reference observations reset to unknown and never mutate intent', () {
      // Given complete storage references and exact navigation/connection identity.
      final record = _record(_request(), uploaded: 2, claimCount: 4);
      final before = SubmissionCodec.recordToJson(record);
      // When availability changes between independent presentation observations.
      final available = _status(
        record,
        access: SubmissionReferenceAccessState.available,
      );
      final unavailable = _status(
        record,
        access: SubmissionReferenceAccessState.unavailable,
      );
      final restarted = _status(record);
      // Then unknown/unavailable wait without changing queue, packet or scheduling.
      expect(
        available.submission.state,
        SubmissionTransferOperationState.queued,
      );
      expect(
        unavailable.submission.waitingReason,
        SubmissionTransferWaitingReason.referenceAccess,
      );
      expect(
        restarted.submission.waitingReason,
        SubmissionTransferWaitingReason.referenceAccess,
      );
      expect(restarted.requestId, record.request.id);
      expect(restarted.kind, record.request.kind);
      expect(restarted.subjectId, record.request.subjectId);
      expect(restarted.storageConnectionId, 'drive');
      expect(restarted.transportConnectionId, 'server');
      expect(restarted.updatedAt, record.updatedAt);
      expect(restarted.observedAt.isUtc, isTrue);
      expect(restarted.actions, {SubmissionTransferAction.requestRun});
      expect(SubmissionCodec.recordToJson(record), before);

      // Given ready intent retaining uncertain dispatch after cancellation/restart.
      final pending = _record(
        record.request,
        uploaded: 2,
        claimCount: 4,
        checkpoint: const SubmissionTransportCheckpoint.legacyUnknown(),
      );
      // When a fresh observation supplies neither network nor reference evidence.
      final unknown = _status(pending);
      // Then it keeps uncertainty and exposes only the existing intent's wake action.
      expect(
        unknown.submission.state,
        SubmissionTransferOperationState.outcomeUnknown,
      );
      expect(unknown.submission.waitingReason, isNull);
      expect(unknown.submission.completedAt, isNull);
      expect(unknown.actions, {SubmissionTransferAction.requestRun});
      expect(pending.transportCheckpoint!.startedAt, isNull);
    });

    test('collections freeze and values compare by every observed fact', () {
      // Given one validated record and independent observations of identical facts.
      final record = _record(_request(), uploaded: 1, claimCount: 2);
      // When separate projections are constructed with the same normalized UTC time.
      final first = _status(record);
      final equal = _status(
        record,
        observed: DateTime.parse('2026-10-10T10:00:00+09:00'),
      );
      // Then aggregate, operation and file equality/hashing are ordinary immutable values.
      expect(first, equal);
      expect(first.hashCode, equal.hashCode);
      expect(first.upload, equal.upload);
      expect(first.upload.hashCode, equal.upload.hashCode);
      expect(first.files.first, equal.files.first);
      expect(first.files.first.hashCode, equal.files.first.hashCode);
      expect(first.files.first, isNot(first.files.last));
      expect(() => first.files.clear(), throwsUnsupportedError);
      expect(() => first.actions.clear(), throwsUnsupportedError);
      expect(
        first,
        isNot(_status(record, observed: _at.add(const Duration(seconds: 1)))),
      );
      expect(
        first,
        isNot(_status(record, network: SubmissionNetworkState.offline)),
      );
      expect(first.upload, isNot(_status(_record(record.request)).upload));
      expect(first.submission.completedCount, isNull);
      expect(first.submission.totalCount, isNull);
      expect(first.files.last.receipt, isNull);
    });
  });
}

final _at = DateTime.utc(2026, 10, 10, 1);

SubmissionRequest _request({bool withMaterials = true}) {
  // Given two logical original references without file/port IO in this pure suite.
  final originals = <SubmissionMaterial>[
    if (withMaterials)
      for (final key in ['photo', 'audio'])
        SubmissionMaterial(
          key: key,
          original: CaptureMaterialReference(
            id: 'original_$key',
            mediaType: key == 'photo' ? 'image/jpeg' : 'audio/wav',
            byteLength: 8,
            capturedAt: _at,
          ),
        ),
  ];
  // When public immutable intent captures exact consumer identity and whitespace.
  final request = SubmissionRequest(
    id: 'commit1',
    kind: 'bookMaterial',
    subjectId: 'subject1',
    createdAt: _at,
    document: const {'draft': true},
    payload: const {'transcript': '  原文\n '},
    materials: originals,
    storageConnectionId: withMaterials ? 'drive' : null,
    transportConnectionId: 'server',
  );
  // Then each scenario receives actual public values without scheduled work.
  return request;
}

SubmissionRecord _record(
  SubmissionRequest request, {
  int uploaded = 0,
  int claimCount = 0,
  SubmissionState state = SubmissionState.readyToSubmit,
  DateTime? retryAt,
  SubmissionTransportCheckpoint? checkpoint,
  SubmissionAcknowledgement? acknowledgement,
}) {
  // Given only the requested count of actual matched reservations and receipts.
  final reservations = <String, SubmissionStorageReservation>{};
  final receipts = <String, SubmissionMaterialReceipt>{};
  for (var index = 0; index < uploaded; index++) {
    final material = request.materials[index];
    reservations[material.key] = SubmissionStorageReservation(
      key: material.key,
      providerId: 'controlledDrive',
      data: {'remoteId': material.key},
    );
    receipts[material.key] = SubmissionMaterialReceipt(
      key: material.key,
      providerId: 'controlledDrive',
      remoteId: material.key,
      accessConnectionId: 'drive',
      storedAt: _at.add(Duration(seconds: index)),
    );
  }
  // When the public constructor validates queue state and checkpoint relationships.
  final record = SubmissionRecord(
    request: request,
    state: state,
    claimCount: claimCount,
    updatedAt: _at,
    reservations: reservations,
    receipts: receipts,
    transportCheckpoint: checkpoint,
    acknowledgement: acknowledgement,
    leaseToken: state == SubmissionState.submitting ? 'owner' : null,
    leaseExpiresAt: state == SubmissionState.submitting
        ? _at.add(const Duration(minutes: 5))
        : null,
    nextAttemptAt: retryAt,
    failureHistory: [
      if (state == SubmissionState.submissionFailed)
        SubmissionFailure(
          stage: uploaded == request.materials.length
              ? SubmissionFailureStage.transport
              : SubmissionFailureStage.storage,
          code: 'controlledFailure',
          message: 'Safe controlled failure.',
          retryable: retryAt != null,
          occurredAt: _at,
          claimCount: claimCount,
        ),
    ],
  );
  // Then scenarios assert the exact immutable snapshot without queue transitions.
  return record;
}

SubmissionTransferStatus _status(
  SubmissionRecord record, {
  DateTime? observed,
  SubmissionNetworkState network = SubmissionNetworkState.unknown,
  SubmissionReferenceAccessState access =
      SubmissionReferenceAccessState.unknown,
}) {
  // Given explicit observations and a prevalidated immutable queue record.
  final time = observed ?? _at;
  // When the public projection is built without any runtime ports.
  final status = SubmissionTransferStatus.fromRecord(
    record,
    observedAt: time,
    networkState: network,
    referenceAccessState: access,
  );
  // Then callers inspect actual values; this helper performs no IO or scheduling.
  return status;
}
