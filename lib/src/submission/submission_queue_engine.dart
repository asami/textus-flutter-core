import 'dart:convert';

import 'submission_codec.dart';
import 'registered_material_handoff_store.dart';
import 'registered_material_submission.dart';
import 'registered_material_submission_codec.dart';
import 'submission_connections.dart';
import 'submission_json.dart' as j;
import 'submission_queue_store.dart';
import 'submission_record.dart';
import 'submission_request.dart';
import 'tkl_material_delivery.dart';
import 'tkl_original_content.dart';

/// Atomic persistence beneath the existing queue transitions. No transaction
/// performs material/provider/network IO or replays an entered callback.
enum SubmissionStoreTable { jobs, handoffs }

abstract interface class SubmissionQueueTransaction {
  Future<List<Map<String, Object?>>> rows(
    SubmissionStoreTable table, {
    Map<String, Object?> equals = const {},
  });
  Future<void> insert(SubmissionStoreTable table, Map<String, Object?> values);
  Future<int> update(
    SubmissionStoreTable table,
    Map<String, Object?> values, {
    required Map<String, Object?> equals,
  });
}

abstract interface class SubmissionQueuePersistence {
  Future<T> transaction<T>(
    Future<T> Function(SubmissionQueueTransaction) action,
  );
  Future<void> close();
}

/// Storage-neutral reuse of the accepted queue/handoff rules and codecs.
/// Implementation library, not a second delivery state machine.
class SubmissionQueueEngine
    implements SubmissionQueueStore, RegisteredMaterialHandoffStore {
  SubmissionQueueEngine(this._persistence);
  final SubmissionQueuePersistence _persistence;
  Future<void> _tail = Future<void>.value();
  Future<void>? _closeFuture;
  bool _closing = false;

  RegisteredMaterialHandoffRecord _decodeHandoff(Map<String, Object?> row) {
    final value = RegisteredMaterialSubmissionCodec.handoffFromJson(
      jsonDecode(j.string(row['body'])),
    );
    if (value.id != row['handoff_id'] ||
        value.sourceRequestId != row['source_request_id']) {
      throw const FormatException('Handoff indexed identity mismatch');
    }
    return value;
  }

  Future<RegisteredMaterialHandoffRecord?> _handoffForSource(
    SubmissionQueueTransaction tx,
    String sourceRequestId,
  ) async {
    final rows = await tx.rows(
      SubmissionStoreTable.handoffs,
      equals: {'source_request_id': j.token(sourceRequestId)},
    );
    return rows.isEmpty ? null : _decodeHandoff(rows.single);
  }

  Future<List<RegisteredMaterialHandoffRecord>> _allHandoffs(
    SubmissionQueueTransaction tx,
  ) async {
    final rows = await tx.rows(SubmissionStoreTable.handoffs);
    final values = rows.map(_decodeHandoff).toList();
    values.sort((a, b) {
      final order = a.createdAt.compareTo(b.createdAt);
      return order == 0 ? a.id.compareTo(b.id) : order;
    });
    return values;
  }

  RegisteredMaterialHandoffRecord _nextHandoff(
    RegisteredMaterialHandoffRecord old,
    DateTime now, {
    required RegisteredMaterialHandoffState state,
    String? leaseToken,
    DateTime? leaseExpiresAt,
    SubmissionAcknowledgement? acknowledgement,
    RegisteredMaterialHandoffFailure? failure,
  }) => RegisteredMaterialHandoffRecord(
    id: old.id,
    sourceRequest: old.sourceRequest,
    registeredSnapshot: old.registeredSnapshot,
    sourceCheckpointUpdatedAt: old.sourceCheckpointUpdatedAt,
    target: old.target,
    packet: old.packet,
    createdAt: old.createdAt,
    updatedAt: now.toUtc().isAfter(old.updatedAt) ? now : old.updatedAt,
    state: state,
    leaseToken: leaseToken,
    leaseExpiresAt: leaseExpiresAt,
    acknowledgement: acknowledgement,
    failure: failure,
  );

  Future<RegisteredMaterialHandoffRecord> _writeHandoff(
    SubmissionQueueTransaction tx,
    RegisteredMaterialHandoffRecord value,
  ) async {
    final count = await tx.update(
      SubmissionStoreTable.handoffs,
      {
        'body': jsonEncode(
          RegisteredMaterialSubmissionCodec.handoffToJson(value),
        ),
      },
      equals: {
        'handoff_id': value.id,
        'source_request_id': value.sourceRequestId,
      },
    );
    if (count != 1) throw StateError('Handoff disappeared during transition');
    return value;
  }

  @override
  Future<RegisteredMaterialHandoffRecord?> findHandoffForSource(
    String sourceRequestId,
  ) => _transaction((tx) => _handoffForSource(tx, sourceRequestId));

  @override
  Future<List<RegisteredMaterialHandoffRecord>> listHandoffs() => _transaction(
    (tx) async => List<RegisteredMaterialHandoffRecord>.unmodifiable(
      await _allHandoffs(tx),
    ),
  );

  @override
  Future<RegisteredMaterialHandoffRecord> createHandoff({
    required String id,
    required SubmissionRecord source,
    required HttpSubmissionConnection target,
    required RegisteredMaterialSubmissionPacket packet,
    required DateTime now,
  }) => _transaction((tx) async {
    j.token(id);
    final saved = await _read(tx, source.request.id);
    if (saved == null ||
        saved != source ||
        saved.state != SubmissionState.materialRegistered ||
        saved.request.tklDelivery == null ||
        saved.tklProgress?.state != TklMaterialDeliveryState.registered ||
        saved.request != packet.sourceRequest ||
        !sameRegisteredMaterialTarget(target, packet.target)) {
      throw StateError('A matching saved Registered source is required');
    }
    final value = RegisteredMaterialHandoffRecord(
      id: id,
      sourceRequest: saved.request,
      registeredSnapshot: saved.tklProgress!,
      sourceCheckpointUpdatedAt: saved.updatedAt,
      target: target,
      packet: packet,
      createdAt: now,
      updatedAt: now,
      state: RegisteredMaterialHandoffState.pending,
    );
    final old = await _handoffForSource(tx, saved.request.id);
    if (old != null) {
      if (!sameRegisteredMaterialTarget(old.target, target) ||
          old.sourceRequest != saved.request ||
          old.packet != packet ||
          old.sourceCheckpointUpdatedAt != saved.updatedAt ||
          !j.deepEquals(
            RegisteredMaterialSubmissionCodec.handoffToJson(
              old,
            )['registeredSnapshot'],
            RegisteredMaterialSubmissionCodec.handoffToJson(
              value,
            )['registeredSnapshot'],
          )) {
        throw StateError('Registered handoff source or target conflicts');
      }
      return old;
    }
    await tx.insert(SubmissionStoreTable.handoffs, {
      'handoff_id': value.id,
      'source_request_id': value.sourceRequestId,
      'body': jsonEncode(
        RegisteredMaterialSubmissionCodec.handoffToJson(value),
      ),
    });
    return value;
  });

  @override
  Future<RegisteredMaterialHandoffRecord?> claimNextHandoff({
    required DateTime now,
    required String leaseToken,
    required Duration leaseDuration,
  }) => _transaction((tx) async {
    j.token(leaseToken);
    _positive(leaseDuration);
    final records = await _allHandoffs(tx);
    if (records.any((r) => r.leaseToken == leaseToken)) {
      throw ArgumentError('Lease token must be unique');
    }
    for (final record in records) {
      if (record.state == RegisteredMaterialHandoffState.sending &&
          !record.leaseExpiresAt!.isAfter(now.toUtc())) {
        await _writeHandoff(
          tx,
          _nextHandoff(
            record,
            now,
            state: RegisteredMaterialHandoffState.outcomeUnknown,
            failure: RegisteredMaterialHandoffFailure(
              kind: RegisteredMaterialHandoffFailureKind.outcomeUnknown,
              code: 'leaseExpired',
              message: 'Studio acceptance is unknown after lease expiry.',
            ),
          ),
        );
      }
    }
    for (final record in records) {
      if (record.state == RegisteredMaterialHandoffState.pending) {
        // Persist the uncertainty boundary before any transport can run.
        final start = now.toUtc().isAfter(record.updatedAt)
            ? now.toUtc()
            : record.updatedAt;
        return _writeHandoff(
          tx,
          _nextHandoff(
            record,
            now,
            state: RegisteredMaterialHandoffState.sending,
            leaseToken: leaseToken,
            leaseExpiresAt: start.add(leaseDuration),
          ),
        );
      }
    }
    return null;
  });

  @override
  Future<RegisteredMaterialHandoffRecord> finishHandoff({
    required String id,
    required String leaseToken,
    required DateTime now,
    required RegisteredMaterialHandoffState state,
    SubmissionAcknowledgement? acknowledgement,
    RegisteredMaterialHandoffFailure? failure,
  }) => _transaction((tx) async {
    j.token(id);
    j.token(leaseToken);
    if (!{
      RegisteredMaterialHandoffState.accepted,
      RegisteredMaterialHandoffState.failed,
      RegisteredMaterialHandoffState.outcomeUnknown,
    }.contains(state)) {
      throw ArgumentError('Invalid handoff completion state');
    }
    final rows = await tx.rows(
      SubmissionStoreTable.handoffs,
      equals: {'handoff_id': id},
    );
    final old = rows.isEmpty ? null : _decodeHandoff(rows.single);
    if (old == null ||
        old.state != RegisteredMaterialHandoffState.sending ||
        old.leaseToken != leaseToken ||
        !old.leaseExpiresAt!.isAfter(now.toUtc())) {
      throw RegisteredMaterialHandoffLeaseLostException(id);
    }
    return _writeHandoff(
      tx,
      _nextHandoff(
        old,
        now,
        state: state,
        acknowledgement: acknowledgement,
        failure: failure,
      ),
    );
  });

  @override
  Future<RegisteredMaterialHandoffRecord> reconcileHandoff({
    required String sourceRequestId,
    required DateTime now,
  }) => _transaction((tx) async {
    final old = await _handoffForSource(tx, sourceRequestId);
    if (old == null ||
        old.state == RegisteredMaterialHandoffState.accepted ||
        (old.state == RegisteredMaterialHandoffState.sending &&
            old.leaseExpiresAt!.isAfter(now.toUtc()))) {
      throw StateError('Handoff cannot be reconciled in its current state');
    }
    if (old.state == RegisteredMaterialHandoffState.pending) return old;
    return _writeHandoff(
      tx,
      _nextHandoff(old, now, state: RegisteredMaterialHandoffState.pending),
    );
  });

  Future<T> _transaction<T>(
    Future<T> Function(SubmissionQueueTransaction) action,
  ) {
    if (_closing) return Future<T>.error(StateError('Queue is closed'));
    final result = _tail.then((_) => _persistence.transaction<T>(action));
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  SubmissionRecord _decode(Map<String, Object?> row) {
    final record = SubmissionCodec.recordFromJson(
      j.object(jsonDecode(j.string(row['body']))),
    );
    if (record.request.id != row['request_id'] ||
        record.request.kind != row['kind'] ||
        record.request.subjectId != row['subject_id']) {
      throw const FormatException('Submission indexed identity mismatch');
    }
    return record;
  }

  Future<SubmissionRecord?> _read(
    SubmissionQueueTransaction tx,
    String id,
  ) async {
    final rows = await tx.rows(
      SubmissionStoreTable.jobs,
      equals: {'request_id': j.token(id)},
    );
    return rows.isEmpty ? null : _decode(rows.single);
  }

  Future<List<SubmissionRecord>> _all(SubmissionQueueTransaction tx) async {
    final rows = await tx.rows(SubmissionStoreTable.jobs);
    final records = rows.map(_decode).toList();
    records.sort((a, b) {
      final time = a.request.createdAt.compareTo(b.request.createdAt);
      return time == 0 ? a.request.id.compareTo(b.request.id) : time;
    });
    return records;
  }

  Future<SubmissionRecord> _write(
    SubmissionQueueTransaction tx,
    SubmissionRecord value,
  ) async {
    final count = await tx.update(
      SubmissionStoreTable.jobs,
      {'body': jsonEncode(SubmissionCodec.recordToJson(value))},
      equals: {'request_id': value.request.id},
    );
    if (count != 1) {
      throw StateError('Submission disappeared during transition');
    }
    return value;
  }

  SubmissionRecord _next(
    SubmissionRecord old,
    DateTime now, {
    required SubmissionState state,
    int? claimCount,
    String? leaseToken,
    DateTime? leaseExpiresAt,
    DateTime? nextAttemptAt,
    Map<String, SubmissionStorageReservation>? reservations,
    Map<String, SubmissionMaterialReceipt>? receipts,
    List<SubmissionFailure>? history,
    SubmissionAcknowledgement? acknowledgement,
    SubmissionTransportCheckpoint? transportCheckpoint,
    bool clearTransportCheckpoint = false,
    TklMaterialDeliverySnapshot? tklProgress,
    Map<String, TklDirectUploadReceipt>? directReceipts,
    Map<String, TklContentDigest>? tklContentDigests,
  }) => SubmissionRecord(
    request: old.request,
    state: state,
    claimCount: claimCount ?? old.claimCount,
    updatedAt: now.toUtc().isAfter(old.updatedAt) ? now : old.updatedAt,
    leaseToken: leaseToken,
    leaseExpiresAt: leaseExpiresAt,
    nextAttemptAt: nextAttemptAt,
    reservations: reservations ?? old.reservations,
    receipts: receipts ?? old.receipts,
    failureHistory: history ?? old.failureHistory,
    tklProgress: tklProgress ?? old.tklProgress,
    directReceipts: directReceipts ?? old.directReceipts,
    tklContentDigests: tklContentDigests ?? old.tklContentDigests,
    acknowledgement: acknowledgement,
    transportCheckpoint: clearTransportCheckpoint
        ? null
        : transportCheckpoint ?? old.transportCheckpoint,
  );

  Future<SubmissionRecord> _owned(
    SubmissionQueueTransaction tx,
    String id,
    String leaseToken,
    DateTime now,
  ) async {
    j.token(leaseToken);
    final value = await _read(tx, id);
    if (value == null ||
        value.state != SubmissionState.submitting ||
        value.leaseToken != leaseToken ||
        !value.leaseExpiresAt!.isAfter(now.toUtc())) {
      throw SubmissionLeaseLostException(id);
    }
    return value;
  }

  void _positive(Duration duration) {
    if (duration <= Duration.zero) {
      throw ArgumentError('Duration must be positive');
    }
  }

  @override
  Future<SubmissionRecord> enqueue(SubmissionRequest request) => _transaction((
    tx,
  ) async {
    final old = await _read(tx, request.id);
    if (old != null) {
      if (old.request != request) throw StateError('Conflicting request id');
      return old;
    }
    final subjects = await tx.rows(
      SubmissionStoreTable.jobs,
      equals: {'kind': request.kind, 'subject_id': request.subjectId},
    );
    if (subjects.isNotEmpty) {
      _decode(subjects.single);
      throw StateError('Subject already has an immutable Commit');
    }
    final value = SubmissionRecord(
      request: request,
      state: SubmissionState.readyToSubmit,
      claimCount: 0,
      updatedAt: request.createdAt,
    );
    await tx.insert(SubmissionStoreTable.jobs, {
      'request_id': request.id,
      'kind': request.kind,
      'subject_id': request.subjectId,
      'body': jsonEncode(SubmissionCodec.recordToJson(value)),
    });
    return value;
  });

  @override
  Future<SubmissionRecord?> find(String id) =>
      _transaction((tx) => _read(tx, id));

  @override
  Future<SubmissionRecord?> findForSubject(String kind, String subjectId) =>
      _transaction((tx) async {
        final rows = await tx.rows(
          SubmissionStoreTable.jobs,
          equals: {'kind': j.token(kind), 'subject_id': j.token(subjectId)},
        );
        return rows.isEmpty ? null : _decode(rows.single);
      });

  @override
  Future<List<SubmissionRecord>> list() => _transaction(
    (tx) async => List<SubmissionRecord>.unmodifiable(await _all(tx)),
  );

  @override
  Future<SubmissionRecord?> claimNext({
    required DateTime now,
    required String leaseToken,
    required Duration leaseDuration,
  }) => _transaction((tx) async {
    j.token(leaseToken);
    _positive(leaseDuration);
    final records = await _all(tx);
    if (records.any((r) => r.leaseToken == leaseToken)) {
      throw ArgumentError('Lease token must be unique');
    }
    for (final value in records) {
      final eligible = switch (value.state) {
        SubmissionState.readyToSubmit => true,
        SubmissionState.submitted ||
        SubmissionState.materialRegistered => false,
        SubmissionState.submitting => !value.leaseExpiresAt!.isAfter(
          now.toUtc(),
        ),
        SubmissionState.submissionFailed =>
          value.lastFailure!.retryable &&
              !value.nextAttemptAt!.isAfter(now.toUtc()),
      };
      if (eligible) {
        return _write(
          tx,
          _next(
            value,
            now,
            state: SubmissionState.submitting,
            claimCount: value.claimCount + 1,
            leaseToken: leaseToken,
            leaseExpiresAt: now.toUtc().add(leaseDuration),
          ),
        );
      }
    }
    return null;
  });

  @override
  Future<SubmissionRecord> renewLease({
    required String id,
    required String leaseToken,
    required DateTime now,
    required Duration leaseDuration,
  }) => _transaction((tx) async {
    _positive(leaseDuration);
    final old = await _owned(tx, id, leaseToken, now);
    return _write(
      tx,
      _next(
        old,
        now,
        state: old.state,
        leaseToken: leaseToken,
        leaseExpiresAt: now.toUtc().add(leaseDuration),
      ),
    );
  });

  @override
  Future<SubmissionRecord> saveReservation({
    required String id,
    required String leaseToken,
    required SubmissionStorageReservation reservation,
    required DateTime now,
  }) => _transaction((tx) async {
    final old = await _owned(tx, id, leaseToken, now);
    if (!old.request.materials.any((m) => m.key == reservation.key)) {
      throw StateError('Unknown reservation material');
    }
    final existing = old.reservations[reservation.key];
    if (existing != null) {
      if (existing != reservation) throw StateError('Reservation replacement');
      return old;
    }
    return _write(
      tx,
      _next(
        old,
        now,
        state: old.state,
        leaseToken: leaseToken,
        leaseExpiresAt: old.leaseExpiresAt,
        reservations: {...old.reservations, reservation.key: reservation},
      ),
    );
  });

  @override
  Future<SubmissionRecord> saveReceipt({
    required String id,
    required String leaseToken,
    required SubmissionMaterialReceipt receipt,
    required DateTime now,
  }) => _transaction((tx) async {
    final old = await _owned(tx, id, leaseToken, now);
    final reservation = old.reservations[receipt.key];
    if (reservation == null || reservation.providerId != receipt.providerId) {
      throw StateError('Receipt does not match reservation');
    }
    final existing = old.receipts[receipt.key];
    if (existing != null) {
      if (existing != receipt) throw StateError('Receipt replacement');
      return old;
    }
    return _write(
      tx,
      _next(
        old,
        now,
        state: old.state,
        leaseToken: leaseToken,
        leaseExpiresAt: old.leaseExpiresAt,
        receipts: {...old.receipts, receipt.key: receipt},
      ),
    );
  });

  @override
  Future<SubmissionRecord> markTransportDispatch({
    required String id,
    required String leaseToken,
    required DateTime now,
  }) => _transaction((tx) async {
    final old = await _owned(tx, id, leaseToken, now);
    if (old.receipts.length != old.request.materials.length) {
      throw StateError('Dispatch requires all material receipts');
    }
    if (old.transportCheckpoint != null) return old;
    return _write(
      tx,
      _next(
        old,
        now,
        state: old.state,
        leaseToken: leaseToken,
        leaseExpiresAt: old.leaseExpiresAt,
        transportCheckpoint: SubmissionTransportCheckpoint.pending(
          claimCount: old.claimCount,
          startedAt: now,
        ),
      ),
    );
  });

  @override
  Future<SubmissionRecord> saveTklContentDigest({
    required String id,
    required String leaseToken,
    required String key,
    required TklContentDigest digest,
    required DateTime now,
  }) => _transaction((tx) async {
    final old = await _owned(tx, id, leaseToken, now);
    if (old.request.tklDelivery == null ||
        !old.request.materials.any((m) => m.key == key)) {
      throw StateError(
        'Content expectation requires an accepted TKL original.',
      );
    }
    final existing = old.tklContentDigests[key];
    if (existing != null) {
      if (existing != digest) {
        throw StateError('Content expectation is immutable.');
      }
      return old;
    }
    return _write(
      tx,
      _next(
        old,
        now,
        state: old.state,
        leaseToken: old.leaseToken,
        leaseExpiresAt: old.leaseExpiresAt,
        tklContentDigests: {...old.tklContentDigests, key: digest},
      ),
    );
  });

  @override
  Future<SubmissionRecord> saveTklProgress({
    required String id,
    required String leaseToken,
    required TklMaterialDeliverySnapshot progress,
    required DateTime now,
  }) => _transaction((tx) async {
    final old = await _owned(tx, id, leaseToken, now);
    final previous = old.tklProgress;
    if (old.request.tklDelivery == null ||
        progress.requestId != id ||
        (previous != null &&
            (previous.deliveryRef != progress.deliveryRef ||
                previous.destinationId != progress.destinationId ||
                previous.destinationLabel != progress.destinationLabel ||
                previous.transferMethod != progress.transferMethod ||
                previous.transferReason != progress.transferReason ||
                previous.revision > progress.revision ||
                (previous.materialRef != null &&
                    previous.materialRef != progress.materialRef)))) {
      throw StateError('TKL progress does not match its retained delivery.');
    }
    if (previous != null) {
      for (final resource in previous.resources) {
        final next = progress.resources.where(
          (r) => r.resourceId == resource.resourceId,
        );
        if (next.length != 1 ||
            (resource.contentDigest != null &&
                next.single.contentDigest != resource.contentDigest) ||
            (resource.verificationAttempts != null &&
                (next.single.verificationAttempts == null ||
                    next.single.verificationAttempts! <
                        resource.verificationAttempts!)) ||
            (resource.verificationState ==
                    TklOriginalVerificationState.verified &&
                next.single.verificationState !=
                    TklOriginalVerificationState.verified)) {
          throw StateError('Confirmed TKL integrity cannot regress.');
        }
        if (resource.state == TklOriginalTransferState.uploaded &&
            !progress.resources.any(
              (next) =>
                  next.resourceId == resource.resourceId &&
                  next.state == TklOriginalTransferState.uploaded,
            )) {
          throw StateError('Confirmed TKL upload cannot regress.');
        }
      }
    }
    return _write(
      tx,
      _next(
        old,
        now,
        state: old.state,
        leaseToken: old.leaseToken,
        leaseExpiresAt: old.leaseExpiresAt,
        tklProgress: progress,
      ),
    );
  });

  @override
  Future<SubmissionRecord> saveDirectUploadReceipt({
    required String id,
    required String leaseToken,
    required TklDirectUploadReceipt receipt,
    required DateTime now,
  }) => _transaction((tx) async {
    final old = await _owned(tx, id, leaseToken, now);
    final existing = old.directReceipts[receipt.resourceId];
    if (existing != null && existing != receipt) {
      throw StateError('Direct upload receipt cannot be replaced.');
    }
    return _write(
      tx,
      _next(
        old,
        now,
        state: old.state,
        leaseToken: old.leaseToken,
        leaseExpiresAt: old.leaseExpiresAt,
        directReceipts: {...old.directReceipts, receipt.resourceId: receipt},
      ),
    );
  });

  @override
  Future<SubmissionRecord> completeMaterialRegistration({
    required String id,
    required String leaseToken,
    required DateTime now,
  }) => _transaction((tx) async {
    final old = await _owned(tx, id, leaseToken, now);
    if (old.request.tklDelivery == null ||
        old.tklProgress?.state != TklMaterialDeliveryState.registered) {
      throw StateError('Confirmed TKL registration is required.');
    }
    return _write(
      tx,
      _next(old, now, state: SubmissionState.materialRegistered),
    );
  });

  @override
  Future<SubmissionRecord> complete({
    required String id,
    required String leaseToken,
    required SubmissionAcknowledgement acknowledgement,
    required DateTime now,
  }) => _transaction((tx) async {
    final old = await _owned(tx, id, leaseToken, now);
    if (old.request.tklDelivery != null ||
        acknowledgement.requestId != old.request.id ||
        acknowledgement.subjectId != old.request.subjectId ||
        old.receipts.length != old.request.materials.length) {
      throw StateError('Incomplete or mismatched server acceptance');
    }
    return _write(
      tx,
      _next(
        old,
        now,
        state: SubmissionState.submitted,
        acknowledgement: acknowledgement,
        clearTransportCheckpoint: true,
      ),
    );
  });

  @override
  Future<SubmissionRecord> fail({
    required String id,
    required String leaseToken,
    required SubmissionFailure failure,
    required DateTime now,
    DateTime? nextAttemptAt,
    SubmissionTransportFailureOutcome transportFailureOutcome =
        SubmissionTransportFailureOutcome.unknown,
  }) => _transaction((tx) async {
    final old = await _owned(tx, id, leaseToken, now);
    final conclusive =
        transportFailureOutcome != SubmissionTransportFailureOutcome.unknown;
    if (conclusive &&
        failure.stage != SubmissionFailureStage.transport &&
        failure.stage != SubmissionFailureStage.configuration) {
      throw ArgumentError('Transport outcome requires a transport failure');
    }
    if (failure.claimCount != old.claimCount ||
        failure.occurredAt != now.toUtc() ||
        failure.retryable != (nextAttemptAt != null) ||
        (nextAttemptAt != null &&
            !nextAttemptAt.toUtc().isAfter(now.toUtc()))) {
      throw ArgumentError('Failure must match executing claim/time and retry');
    }
    return _write(
      tx,
      _next(
        old,
        now,
        state: SubmissionState.submissionFailed,
        nextAttemptAt: nextAttemptAt,
        history: [...old.failureHistory, failure],
        clearTransportCheckpoint:
            conclusive &&
            old.transportCheckpoint != null &&
            !old.transportCheckpoint!.isLegacyUnknown &&
            old.transportCheckpoint!.claimCount == old.claimCount,
      ),
    );
  });

  @override
  Future<SubmissionRecord> release({
    required String id,
    required String leaseToken,
    required DateTime now,
  }) => _transaction((tx) async {
    final old = await _owned(tx, id, leaseToken, now);
    return _write(tx, _next(old, now, state: SubmissionState.readyToSubmit));
  });

  @override
  Future<SubmissionRecord> retry({required String id, required DateTime now}) =>
      _transaction((tx) async {
        final old = await _read(tx, id);
        if (old == null) throw StateError('Unknown submission');
        if (old.state == SubmissionState.submitting) {
          throw StateError('Cannot retry an active claim');
        }
        if (old.state != SubmissionState.submissionFailed) return old;
        return _write(
          tx,
          _next(old, now, state: SubmissionState.readyToSubmit),
        );
      });

  @override
  Future<void> close() {
    _closing = true;
    return _closeFuture ??= _tail.then((_) => _persistence.close());
  }
}
