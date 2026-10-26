import '../capture/capture_material.dart';
import 'registered_material_handoff_store.dart';
import 'submission_json.dart' as j;
import 'submission_record.dart';
import 'tkl_material_delivery.dart';
import 'tkl_material_delivery_codec.dart';

/// Current caller observation; unknown conveys no network permission or liveness.
enum SubmissionNetworkState { unknown, allowed, offline, policyBlocked }

/// Caller observation of remote reference accessibility, never execution consent.
enum SubmissionReferenceAccessState { unknown, available, unavailable }

/// Presentation of one operation from durable facts and current observations.
enum SubmissionTransferOperationState {
  notRequired,
  queued,
  waiting,
  running,
  succeeded,
  failed,
  outcomeUnknown,
}

/// One current waiting cause; deadline fields retain the actual queue facts.
enum SubmissionTransferWaitingReason {
  networkUnavailable,
  policyBlocked,
  materialUpload,
  referenceAccess,
  leaseRecovery,
  retryScheduled,
}

/// Intent-preserving actions supported by the observed durable queue state.
enum SubmissionTransferAction { retry, requestRun }

/// Immutable aggregate operation value. Private construction prevents callers
/// from manufacturing acceptance. Running denotes a current durable lease only.
final class SubmissionTransferOperationStatus {
  const SubmissionTransferOperationStatus._({
    required this.state,
    this.waitingReason,
    this.failure,
    this.nextAttemptAt,
    this.leaseExpiresAt,
    this.completedAt,
    this.completedCount,
    this.totalCount,
  });

  /// State supported by durable facts and the supplied observation.
  final SubmissionTransferOperationState state;

  /// Current waiting cause, null when no cause is established.
  final SubmissionTransferWaitingReason? waitingReason;

  /// Current aggregate safe failure, null for success or dependent upload wait.
  final SubmissionFailure? failure;

  /// Actual current queue retry deadline when this operation still needs work.
  final DateTime? nextAttemptAt;

  /// Actual current claim expiry when this operation still needs work.
  final DateTime? leaseExpiresAt;

  /// Latest actual upload receipt time or matching server acknowledgement time.
  /// Null when no required operation has completed.
  final DateTime? completedAt;

  /// Actual upload receipt count, null for submission.
  final int? completedCount;

  /// Required upload file count, null for submission.
  final int? totalCount;

  @override
  bool operator ==(Object other) =>
      other is SubmissionTransferOperationStatus &&
      state == other.state &&
      waitingReason == other.waitingReason &&
      failure == other.failure &&
      nextAttemptAt == other.nextAttemptAt &&
      leaseExpiresAt == other.leaseExpiresAt &&
      completedAt == other.completedAt &&
      completedCount == other.completedCount &&
      totalCount == other.totalCount;
  @override
  int get hashCode => Object.hash(
    state,
    waitingReason,
    failure,
    nextAttemptAt,
    leaseExpiresAt,
    completedAt,
    completedCount,
    totalCount,
  );
}

/// One immutable original and its actual reservation/receipt. Without a receipt
/// the file is queued; no active file or file-specific failure is inferred.
final class SubmissionFileTransferStatus {
  SubmissionFileTransferStatus._({
    required this.key,
    required this.original,
    required this.reservation,
    required this.receipt,
    this.lakeProgress,
    this.directReceipt,
  }) : state = directReceipt != null
           ? SubmissionTransferOperationState.succeeded
           : lakeProgress != null
           ? switch (lakeProgress.state) {
               TklOriginalTransferState.uploaded =>
                 SubmissionTransferOperationState.succeeded,
               TklOriginalTransferState.transferring =>
                 SubmissionTransferOperationState.running,
               TklOriginalTransferState.reconciliationRequired =>
                 SubmissionTransferOperationState.outcomeUnknown,
               TklOriginalTransferState.pending =>
                 SubmissionTransferOperationState.queued,
             }
           : receipt == null
           ? SubmissionTransferOperationState.queued
           : SubmissionTransferOperationState.succeeded;

  /// Exact request material key, in request order.
  final String key;

  /// Borrowed immutable original reference; this value owns no original bytes.
  final CaptureMaterialReference original;

  /// Actual durable reservation, null until reserved.
  final SubmissionStorageReservation? reservation;

  /// Actual successful upload receipt, null until acknowledged by storage.
  final SubmissionMaterialReceipt? receipt;

  /// Actual TKL resource observation; distinct from a legacy Drive receipt.
  final TklOriginalTransferProgress? lakeProgress;

  /// Provider completion can precede independent TKL confirmation.
  final TklDirectUploadReceipt? directReceipt;

  /// Succeeded exactly when a storage receipt exists; otherwise queued.
  final SubmissionTransferOperationState state;

  @override
  bool operator ==(Object other) =>
      other is SubmissionFileTransferStatus &&
      key == other.key &&
      original == other.original &&
      reservation == other.reservation &&
      receipt == other.receipt &&
      directReceipt == other.directReceipt &&
      (
            lakeProgress?.resourceId,
            lakeProgress?.mediaType,
            lakeProgress?.byteLength,
            lakeProgress?.state,
            lakeProgress?.contentDigest,
            lakeProgress?.verificationState,
            lakeProgress?.verificationAttempts,
            lakeProgress?.verificationReason,
          ) ==
          (
            other.lakeProgress?.resourceId,
            other.lakeProgress?.mediaType,
            other.lakeProgress?.byteLength,
            other.lakeProgress?.state,
            other.lakeProgress?.contentDigest,
            other.lakeProgress?.verificationState,
            other.lakeProgress?.verificationAttempts,
            other.lakeProgress?.verificationReason,
          );
  @override
  int get hashCode => Object.hash(
    key,
    original,
    reservation,
    receipt,
    directReceipt,
    lakeProgress?.resourceId,
    lakeProgress?.mediaType,
    lakeProgress?.byteLength,
    lakeProgress?.state,
    lakeProgress?.contentDigest,
    lakeProgress?.verificationState,
    lakeProgress?.verificationAttempts,
    lakeProgress?.verificationReason,
  );
}

/// Pure immutable two-operation presentation. Construction performs no IO,
/// scheduling or queue transition, works on every Dart platform and owns no ports.
/// A status observation cannot authorize dispatch; the execution access guard is
/// independently required before consumer runtime acceptance.
final class SubmissionTransferStatus {
  SubmissionTransferStatus._({
    required this.requestId,
    required this.kind,
    required this.subjectId,
    required this.updatedAt,
    required this.observedAt,
    required this.storageConnectionId,
    required this.transportConnectionId,
    required this.upload,
    required this.submission,
    required List<SubmissionFileTransferStatus> files,
    required Set<SubmissionTransferAction> actions,
    required this.acknowledgementUncertain,
    required this.acknowledgement,
    this.usesLakeDelivery = false,
    this.registration,
    this.preparation,
    this.verification,
    this.tklProgress,
    this.studioHandoff,
  }) : files = List<SubmissionFileTransferStatus>.unmodifiable(files),
       actions = Set<SubmissionTransferAction>.unmodifiable(actions);

  /// Projects an already validated record at UTC [observedAt]. Network and
  /// reference observations default to unknown on every independent call.
  /// Unknown observations never fabricate connectivity, access or completion.
  factory SubmissionTransferStatus.fromRecord(
    SubmissionRecord record, {
    required DateTime observedAt,
    SubmissionNetworkState networkState = SubmissionNetworkState.unknown,
    SubmissionReferenceAccessState referenceAccessState =
        SubmissionReferenceAccessState.unknown,
    RegisteredMaterialHandoffRecord? handoff,
  }) {
    final observed = observedAt.toUtc();
    if (handoff != null &&
        (record.request.tklDelivery == null ||
         handoff.sourceRequest != record.request ||
         record.state != SubmissionState.materialRegistered)) {
      throw ArgumentError('Studio handoff does not match its Registered source');
    }
    if (record.request.tklDelivery != null) {
      return _fromTkl(record, observed, networkState, handoff);
    }
    final total = record.request.materials.length;
    final completed = record.receipts.length;
    final allUploaded = total == completed;
    final claimed = record.state == SubmissionState.submitting;
    final active = claimed && record.leaseExpiresAt!.isAfter(observed);
    final expired = claimed && !active;
    final uncertain = record.transportCheckpoint != null;
    final networkWaiting = switch (networkState) {
      SubmissionNetworkState.offline =>
        SubmissionTransferWaitingReason.networkUnavailable,
      SubmissionNetworkState.policyBlocked =>
        SubmissionTransferWaitingReason.policyBlocked,
      _ => null,
    };
    final waiting =
        networkWaiting ??
        (expired
            ? SubmissionTransferWaitingReason.leaseRecovery
            : record.nextAttemptAt?.isAfter(observed) == true
            ? SubmissionTransferWaitingReason.retryScheduled
            : null);
    final lease = claimed ? record.leaseExpiresAt : null;
    final retry = record.state == SubmissionState.submissionFailed
        ? record.nextAttemptAt
        : null;

    SubmissionTransferOperationStatus upload;
    if (total == 0) {
      upload = const SubmissionTransferOperationStatus._(
        state: SubmissionTransferOperationState.notRequired,
        completedCount: 0,
        totalCount: 0,
      );
    } else if (allUploaded) {
      final times = record.receipts.values.map((receipt) => receipt.storedAt);
      upload = SubmissionTransferOperationStatus._(
        state: SubmissionTransferOperationState.succeeded,
        completedCount: completed,
        totalCount: total,
        completedAt: times.reduce((a, b) => a.isAfter(b) ? a : b),
      );
    } else {
      upload = SubmissionTransferOperationStatus._(
        state: record.state == SubmissionState.submissionFailed
            ? SubmissionTransferOperationState.failed
            : active
            ? SubmissionTransferOperationState.running
            : waiting != null
            ? SubmissionTransferOperationState.waiting
            : SubmissionTransferOperationState.queued,
        waitingReason: active
            ? null
            : expired
            ? SubmissionTransferWaitingReason.leaseRecovery
            : waiting,
        failure: record.lastFailure,
        nextAttemptAt: retry,
        leaseExpiresAt: lease,
        completedCount: completed,
        totalCount: total,
      );
    }

    SubmissionTransferOperationStatus submission;
    if (record.acknowledgement != null) {
      submission = SubmissionTransferOperationStatus._(
        state: SubmissionTransferOperationState.succeeded,
        completedAt: record.acknowledgement!.receivedAt,
      );
    } else if (!allUploaded) {
      submission = const SubmissionTransferOperationStatus._(
        state: SubmissionTransferOperationState.waiting,
        waitingReason: SubmissionTransferWaitingReason.materialUpload,
      );
    } else {
      final referenceWaiting =
          total > 0 &&
          referenceAccessState != SubmissionReferenceAccessState.available;
      final state = active
          ? SubmissionTransferOperationState.running
          : uncertain
          ? SubmissionTransferOperationState.outcomeUnknown
          : expired || referenceWaiting
          ? SubmissionTransferOperationState.waiting
          : record.state == SubmissionState.submissionFailed
          ? SubmissionTransferOperationState.failed
          : waiting != null
          ? SubmissionTransferOperationState.waiting
          : SubmissionTransferOperationState.queued;
      submission = SubmissionTransferOperationStatus._(
        state: state,
        waitingReason: active
            ? null
            : uncertain || expired
            ? waiting
            : referenceWaiting
            ? SubmissionTransferWaitingReason.referenceAccess
            : waiting,
        failure: record.lastFailure,
        nextAttemptAt: retry,
        leaseExpiresAt: lease,
      );
    }
    final actions = <SubmissionTransferAction>{
      if (record.state == SubmissionState.submissionFailed)
        SubmissionTransferAction.retry,
      if (record.state == SubmissionState.readyToSubmit || expired)
        SubmissionTransferAction.requestRun,
    };
    return SubmissionTransferStatus._(
      requestId: record.request.id,
      kind: record.request.kind,
      subjectId: record.request.subjectId,
      updatedAt: record.updatedAt,
      observedAt: observed,
      storageConnectionId: record.request.storageConnectionId,
      transportConnectionId: record.request.transportConnectionId,
      upload: upload,
      submission: submission,
      files: [
        for (final material in record.request.materials)
          SubmissionFileTransferStatus._(
            key: material.key,
            original: material.original,
            reservation: record.reservations[material.key],
            receipt: record.receipts[material.key],
          ),
      ],
      actions: actions,
      acknowledgementUncertain: uncertain,
      acknowledgement: record.acknowledgement,
    );
  }

  static SubmissionTransferStatus _fromTkl(
    SubmissionRecord record,
    DateTime observed,
    SubmissionNetworkState network,
    RegisteredMaterialHandoffRecord? handoff,
  ) {
    final progress = record.tklProgress;
    final resources = {
      for (final resource
          in progress?.resources ?? <TklOriginalTransferProgress>[])
        resource.resourceId: resource,
    };
    final total = record.request.materials.length;
    final completed = resources.values
        .where(
          (resource) =>
              resource.state == TklOriginalTransferState.uploaded ||
              record.directReceipts.containsKey(resource.resourceId),
        )
        .length;
    final claimed = record.state == SubmissionState.submitting;
    final active = claimed && record.leaseExpiresAt!.isAfter(observed);
    final waiting = switch (network) {
      SubmissionNetworkState.offline =>
        SubmissionTransferWaitingReason.networkUnavailable,
      SubmissionNetworkState.policyBlocked =>
        SubmissionTransferWaitingReason.policyBlocked,
      _ =>
        claimed && !active
            ? SubmissionTransferWaitingReason.leaseRecovery
            : record.nextAttemptAt?.isAfter(observed) == true
            ? SubmissionTransferWaitingReason.retryScheduled
            : null,
    };
    final uncertain =
        progress?.state == TklMaterialDeliveryState.reconciliationRequired ||
        record.lastFailure?.code == 'lakeOutcomeUnknown';
    final state = uncertain
        ? SubmissionTransferOperationState.outcomeUnknown
        : active
        ? SubmissionTransferOperationState.running
        : record.lastFailure != null
        ? SubmissionTransferOperationState.failed
        : waiting != null
        ? SubmissionTransferOperationState.waiting
        : SubmissionTransferOperationState.queued;
    final registration = record.state == SubmissionState.materialRegistered
        ? SubmissionTransferOperationStatus._(
            state: SubmissionTransferOperationState.succeeded,
            completedAt: record.updatedAt,
          )
        : SubmissionTransferOperationStatus._(
            state: state,
            waitingReason: waiting,
            failure: record.lastFailure,
            nextAttemptAt: record.nextAttemptAt,
            leaseExpiresAt: record.leaseExpiresAt,
          );
    final prepared = record.tklContentDigests.length;
    final hasVerification = resources.values.any((r) => r.contentDigest != null);
    final verified = resources.values.where(
      (r) => r.verificationState == TklOriginalVerificationState.verified,
    ).length;
    final terminalIntegrity = {'integrityMismatch', 'verificationUnavailable',
      'integrityUpgradeRequired'}.contains(record.lastFailure?.code);
    return SubmissionTransferStatus._(
      requestId: record.request.id,
      kind: record.request.kind,
      subjectId: record.request.subjectId,
      updatedAt: record.updatedAt,
      observedAt: observed,
      storageConnectionId: null,
      transportConnectionId: record.request.transportConnectionId,
      usesLakeDelivery: true,
      tklProgress: progress,
      registration: registration,
      preparation: SubmissionTransferOperationStatus._(
        state: total == 0 ? SubmissionTransferOperationState.notRequired
            : prepared == total ? SubmissionTransferOperationState.succeeded
            : state,
        completedCount: prepared, totalCount: total,
        waitingReason: prepared == total ? null : waiting,
        failure: prepared == total ? null : record.lastFailure,
        leaseExpiresAt: prepared == total ? null : record.leaseExpiresAt,
      ),
      verification: !hasVerification ? null : SubmissionTransferOperationStatus._(
        state: verified == total ? SubmissionTransferOperationState.succeeded
            : progress?.state == TklMaterialDeliveryState.verificationFailed
            ? SubmissionTransferOperationState.failed : state,
        completedCount: verified, totalCount: total,
        waitingReason: verified == total ? null : waiting,
        failure: verified == total ? null : record.lastFailure,
        leaseExpiresAt: verified == total ? null : record.leaseExpiresAt,
      ),
      upload: SubmissionTransferOperationStatus._(
        state: total == 0
            ? SubmissionTransferOperationState.notRequired
            : completed == total
            ? SubmissionTransferOperationState.succeeded
            : state,
        completedCount: completed,
        totalCount: total,
        waitingReason: completed == total ? null : waiting,
        failure: completed == total ? null : record.lastFailure,
      ),
      submission: handoff == null
          ? const SubmissionTransferOperationStatus._(
              state: SubmissionTransferOperationState.notRequired)
          : SubmissionTransferOperationStatus._(
              state: switch (handoff.state) {
                RegisteredMaterialHandoffState.pending => SubmissionTransferOperationState.queued,
                RegisteredMaterialHandoffState.sending =>
                  handoff.leaseExpiresAt!.isAfter(observed)
                    ? SubmissionTransferOperationState.running
                    : SubmissionTransferOperationState.outcomeUnknown,
                RegisteredMaterialHandoffState.outcomeUnknown => SubmissionTransferOperationState.outcomeUnknown,
                RegisteredMaterialHandoffState.failed => SubmissionTransferOperationState.failed,
                RegisteredMaterialHandoffState.accepted => SubmissionTransferOperationState.succeeded,
              },
              leaseExpiresAt: handoff.leaseExpiresAt,
              completedAt: handoff.acknowledgement?.receivedAt,
            ),
      files: [
        for (final material in record.request.materials)
          SubmissionFileTransferStatus._(
            key: material.key,
            original: material.original,
            reservation: null,
            receipt: null,
            lakeProgress: resources[material.key],
            directReceipt: record.directReceipts[material.key],
          ),
      ],
      actions: {
        if (!terminalIntegrity && record.state == SubmissionState.submissionFailed)
          SubmissionTransferAction.retry,
        if (!terminalIntegrity && (record.state == SubmissionState.readyToSubmit ||
            (claimed && !active)))
          SubmissionTransferAction.requestRun,
      },
      acknowledgementUncertain: handoff?.state == RegisteredMaterialHandoffState.outcomeUnknown ||
          (handoff?.state == RegisteredMaterialHandoffState.sending &&
              !handoff!.leaseExpiresAt!.isAfter(observed)),
      acknowledgement: handoff?.acknowledgement,
      studioHandoff: handoff,
    );
  }

  /// Exact immutable request identity, suitable for navigation and wake/retry.
  final String requestId;

  /// Exact open consumer kind.
  final String kind;

  /// Exact immutable consumer subject identity.
  final String subjectId;

  /// UTC durable transition time, never an inferred progress time.
  final DateTime updatedAt;

  /// UTC caller observation time, never persisted by this projection.
  final DateTime observedAt;

  /// Safe storage connection identity, null for no-upload requests.
  final String? storageConnectionId;

  /// Safe transport connection identity, with no credentials or endpoint data.
  final String transportConnectionId;

  /// Aggregate upload operation with actual receipt/required file counts.
  final SubmissionTransferOperationStatus upload;

  /// Independent submission operation; upload success alone cannot complete it.
  final SubmissionTransferOperationStatus submission;

  /// Frozen file statuses in accepted request order.
  final List<SubmissionFileTransferStatus> files;

  /// Frozen supported actions from actual queue state; execution reads freshly.
  final Set<SubmissionTransferAction> actions;

  /// Whether an earliest potentially unconfirmed dispatch remains durable.
  final bool acknowledgementUncertain;

  /// Exact matching server acceptance, null until submitted.
  final SubmissionAcknowledgement? acknowledgement;

  /// Explicit TKL route; Studio receipt remains independent and absent.
  final bool usesLakeDelivery;
  final SubmissionTransferOperationStatus? registration;

  /// Actual immutable digest checkpoints; no byte percentage is inferred.
  final SubmissionTransferOperationStatus? preparation;

  /// Actual server verification count; null when no integrity proof is reported.
  final SubmissionTransferOperationStatus? verification;
  final TklMaterialDeliverySnapshot? tklProgress;

  /// Separate frozen Studio destination/lifecycle and actual ACK, when supplied.
  /// The original TKL record and its transport identity remain authoritative.
  final RegisteredMaterialHandoffRecord? studioHandoff;

  @override
  bool operator ==(Object other) =>
      other is SubmissionTransferStatus &&
      requestId == other.requestId &&
      kind == other.kind &&
      subjectId == other.subjectId &&
      updatedAt == other.updatedAt &&
      observedAt == other.observedAt &&
      storageConnectionId == other.storageConnectionId &&
      transportConnectionId == other.transportConnectionId &&
      upload == other.upload &&
      submission == other.submission &&
      j.deepEquals(files, other.files) &&
      actions.length == other.actions.length &&
      actions.containsAll(other.actions) &&
      acknowledgementUncertain == other.acknowledgementUncertain &&
      acknowledgement == other.acknowledgement &&
      usesLakeDelivery == other.usesLakeDelivery &&
      registration == other.registration &&
      preparation == other.preparation &&
      verification == other.verification &&
      studioHandoff == other.studioHandoff &&
      j.deepEquals(
        tklProgress == null
            ? null
            : TklMaterialDeliveryCodec.snapshotToJson(tklProgress!),
        other.tklProgress == null
            ? null
            : TklMaterialDeliveryCodec.snapshotToJson(other.tklProgress!),
      );
  @override
  int get hashCode => Object.hash(
    requestId,
    kind,
    subjectId,
    updatedAt,
    observedAt,
    storageConnectionId,
    transportConnectionId,
    upload,
    submission,
    j.deepHash(files),
    Object.hashAllUnordered(actions),
    acknowledgementUncertain,
    acknowledgement,
    usesLakeDelivery,
    registration,
    preparation,
    verification,
    studioHandoff,
    j.deepHash(
      tklProgress == null
          ? null
          : TklMaterialDeliveryCodec.snapshotToJson(tklProgress!),
    ),
  );
}
