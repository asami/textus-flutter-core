import 'submission_json.dart' as j;
import 'submission_request.dart';
import 'tkl_material_delivery.dart';
import 'tkl_material_delivery_codec.dart';
import 'tkl_original_content.dart';

/// Durable lifecycle controlled exclusively by the queue store.
enum SubmissionState {
  readyToSubmit,
  submitting,
  submitted,
  submissionFailed,
  materialRegistered,
}

/// Safe attribution of a failed stage, independent of any domain policy.
enum SubmissionFailureStage { localMaterial, storage, transport, configuration }

/// Trusted attribution of one failed transport attempt, never acknowledgement.
/// Unclassified results retain [unknown]; a later refusal cannot disprove an
/// earlier attempt's possible acceptance.
enum SubmissionTransportFailureOutcome { notSent, rejected, unknown }

/// Earliest potentially unconfirmed dispatch; this does not prove bytes sent.
final class SubmissionTransportCheckpoint {
  /// Attributes uncertainty to a positive current claim and UTC local time.
  /// Invalid claim counts throw [ArgumentError]. No IO or acceptance occurs.
  SubmissionTransportCheckpoint.pending({
    required int claimCount,
    required DateTime startedAt,
  }) : claimCount = claimCount,
       startedAt = startedAt.toUtc(),
       isLegacyUnknown = false {
    if (claimCount <= 0) throw ArgumentError('Dispatch requires a claim');
  }

  /// Retains old-schema uncertainty without inventing a claim or timestamp.
  const SubmissionTransportCheckpoint.legacyUnknown()
    : claimCount = null,
      startedAt = null,
      isLegacyUnknown = true;

  /// Earliest potentially dispatched claim, null for legacy uncertainty.
  final int? claimCount;

  /// UTC local checkpoint time, null when the legacy schema cannot establish it.
  final DateTime? startedAt;

  /// Whether neither claim attribution nor dispatch time is known.
  final bool isLegacyUnknown;

  @override
  bool operator ==(Object other) =>
      other is SubmissionTransportCheckpoint &&
      claimCount == other.claimCount &&
      startedAt == other.startedAt &&
      isLegacyUnknown == other.isLegacyUnknown;
  @override
  int get hashCode => Object.hash(claimCount, startedAt, isLegacyUnknown);
}

/// Safe historical failure; raw exceptions and credentials must never be passed.
final class SubmissionFailure {
  /// Validates safe code, nonblank safe message and positive claim count.
  SubmissionFailure({
    required this.stage,
    required String code,
    required String message,
    required this.retryable,
    required DateTime occurredAt,
    required this.claimCount,
  }) : code = j.token(code),
       message = j.descriptive(message),
       occurredAt = occurredAt.toUtc() {
    if (claimCount <= 0) throw ArgumentError('Failure requires a claim');
  }

  /// Stage that failed.
  final SubmissionFailureStage stage;

  /// Safe diagnostic token, without exception text.
  final String code;

  /// Safe user-facing description supplied by a trusted adapter or Core.
  final String message;

  /// Whether automatic retry may claim this failure when due.
  final bool retryable;

  /// UTC occurrence time supplied by the executing owner.
  final DateTime occurredAt;

  /// Exact claim in which the failure occurred.
  final int claimCount;

  @override
  bool operator ==(Object other) =>
      other is SubmissionFailure &&
      stage == other.stage &&
      code == other.code &&
      message == other.message &&
      retryable == other.retryable &&
      occurredAt == other.occurredAt &&
      claimCount == other.claimCount;
  @override
  int get hashCode =>
      Object.hash(stage, code, message, retryable, occurredAt, claimCount);
}

/// Immutable provider reservation persisted before any upload side effect.
final class SubmissionStorageReservation {
  /// Freezes provider-owned JSON; invalid tokens/JSON throw [ArgumentError].
  SubmissionStorageReservation({
    required String key,
    required String providerId,
    required Map<String, Object?> data,
  }) : key = j.token(key),
       providerId = j.token(providerId),
       data = j.frozenJson(data);

  /// Request material key.
  final String key;

  /// Safe identity of the provider that prepared the reservation.
  final String providerId;

  /// Opaque immutable reservation data; adapters must exclude credentials.
  final Map<String, Object?> data;
  @override
  bool operator ==(Object other) =>
      other is SubmissionStorageReservation &&
      key == other.key &&
      providerId == other.providerId &&
      j.deepEquals(data, other.data);
  @override
  int get hashCode => Object.hash(key, providerId, j.deepHash(data));
}

/// Storage success for an original; this value alone is never server acceptance.
final class SubmissionMaterialReceipt {
  /// Freezes metadata and validates tokens and a descriptive remote id.
  SubmissionMaterialReceipt({
    required String key,
    required String providerId,
    required String remoteId,
    required String accessConnectionId,
    required DateTime storedAt,
    Map<String, Object?> metadata = const {},
  }) : key = j.token(key),
       providerId = j.token(providerId),
       remoteId = j.descriptive(remoteId),
       accessConnectionId = j.token(accessConnectionId),
       storedAt = storedAt.toUtc(),
       metadata = j.frozenJson(metadata);

  /// Request material key.
  final String key;

  /// Provider matching the persisted reservation.
  final String providerId;

  /// Nonblank remote identity, never interpreted as a local path.
  final String remoteId;

  /// Safe connection identity through which the remote original is accessible.
  final String accessConnectionId;

  /// UTC storage acknowledgement time.
  final DateTime storedAt;

  /// Opaque immutable provider metadata, without credentials.
  final Map<String, Object?> metadata;
  @override
  bool operator ==(Object other) =>
      other is SubmissionMaterialReceipt &&
      key == other.key &&
      providerId == other.providerId &&
      remoteId == other.remoteId &&
      accessConnectionId == other.accessConnectionId &&
      storedAt == other.storedAt &&
      j.deepEquals(metadata, other.metadata);
  @override
  int get hashCode => Object.hash(
    key,
    providerId,
    remoteId,
    accessConnectionId,
    storedAt,
    j.deepHash(metadata),
  );
}

/// Explicit server acceptance, matched to the immutable request and subject.
final class SubmissionAcknowledgement {
  /// Freezes extensions; invalid tokens/blank server id throw [ArgumentError].
  SubmissionAcknowledgement({
    required String requestId,
    required String subjectId,
    required String serverId,
    required DateTime receivedAt,
    Map<String, Object?> extensions = const {},
  }) : requestId = j.token(requestId),
       subjectId = j.token(subjectId),
       serverId = j.descriptive(serverId),
       receivedAt = receivedAt.toUtc(),
       extensions = j.frozenJson(extensions);

  /// Request id used by the idempotent transport.
  final String requestId;

  /// Consumer subject that the server accepted.
  final String subjectId;

  /// Descriptive remote server identity, never a local path.
  final String serverId;

  /// UTC server acknowledgement time.
  final DateTime receivedAt;

  /// Opaque immutable acceptance extensions.
  final Map<String, Object?> extensions;
  @override
  bool operator ==(Object other) =>
      other is SubmissionAcknowledgement &&
      requestId == other.requestId &&
      subjectId == other.subjectId &&
      serverId == other.serverId &&
      receivedAt == other.receivedAt &&
      j.deepEquals(extensions, other.extensions);
  @override
  int get hashCode => Object.hash(
    requestId,
    subjectId,
    serverId,
    receivedAt,
    j.deepHash(extensions),
  );
}

/// Complete immutable queue snapshot, including all retained checkpoints/history.
final class SubmissionRecord {
  /// Rejects inconsistent state, lease, acknowledgement, checkpoints or history.
  ///
  /// Invalid values throw [ArgumentError]. This constructor does not publish a
  /// transition; only queue store operations persist state changes.
  SubmissionRecord({
    required this.request,
    required this.state,
    required this.claimCount,
    required DateTime updatedAt,
    String? leaseToken,
    DateTime? leaseExpiresAt,
    DateTime? nextAttemptAt,
    Map<String, SubmissionStorageReservation> reservations = const {},
    Map<String, SubmissionMaterialReceipt> receipts = const {},
    List<SubmissionFailure> failureHistory = const [],
    this.acknowledgement,
    this.transportCheckpoint,
    this.tklProgress,
    Map<String, TklContentDigest> tklContentDigests = const {},
    Map<String, TklDirectUploadReceipt> directReceipts = const {},
  }) : tklContentDigests = Map<String, TklContentDigest>.unmodifiable(tklContentDigests),
       updatedAt = updatedAt.toUtc(),
       leaseToken = leaseToken == null ? null : j.token(leaseToken),
       leaseExpiresAt = leaseExpiresAt?.toUtc(),
       nextAttemptAt = nextAttemptAt?.toUtc(),
       reservations = Map<String, SubmissionStorageReservation>.unmodifiable(
         reservations,
       ),
       receipts = Map<String, SubmissionMaterialReceipt>.unmodifiable(receipts),
       failureHistory = List<SubmissionFailure>.unmodifiable(failureHistory),
       directReceipts = Map<String, TklDirectUploadReceipt>.unmodifiable(
         directReceipts,
       ) {
    if (claimCount < 0 ||
        (state != SubmissionState.readyToSubmit && claimCount == 0)) {
      throw ArgumentError('Invalid claim count');
    }
    if (request.tklDelivery != null &&
        (acknowledgement != null ||
            transportCheckpoint != null ||
            this.reservations.isNotEmpty ||
            this.receipts.isNotEmpty ||
            state == SubmissionState.submitted)) {
      throw ArgumentError('TKL progress and Studio acceptance are distinct.');
    }
    final materialKeys = request.materials.map((m) => m.key).toSet();
    if ((this.tklContentDigests.isNotEmpty && request.tklDelivery == null) ||
        !this.tklContentDigests.keys.every(materialKeys.contains)) {
      throw ArgumentError('Content expectation does not match its TKL original.');
    }
    if (tklProgress != null) {
      if (request.tklDelivery == null ||
          tklProgress!.requestId != request.id ||
          tklProgress!.resources.length != request.materials.length) {
        throw ArgumentError(
          'TKL progress does not match its committed request.',
        );
      }
      for (var i = 0; i < request.materials.length; i++) {
        final material = request.materials[i];
        final progress = tklProgress!.resources[i];
        final expected = this.tklContentDigests[material.key];
        final requiresProof = this.tklContentDigests.isNotEmpty &&
            {TklMaterialDeliveryState.readyToRegister,
             TklMaterialDeliveryState.registering,
             TklMaterialDeliveryState.registered}.contains(tklProgress!.state);
        if ((progress.contentDigest != null && progress.contentDigest != expected) ||
            (requiresProof && (expected == null || progress.contentDigest != expected ||
                progress.verificationState != TklOriginalVerificationState.verified)) ||
            progress.resourceId != material.key ||
            progress.mediaType != material.original.mediaType ||
            progress.byteLength != material.original.byteLength) {
          throw ArgumentError(
            'TKL original progress does not match its committed reference.',
          );
        }
      }
    }
    final keys = request.materials.map((m) => m.key).toSet();
    for (final entry in this.directReceipts.entries) {
      if (tklProgress?.transferMethod !=
              TklMaterialTransferMethod.googleDriveResumable ||
          entry.key != entry.value.resourceId ||
          !request.materials.any(
            (material) =>
                material.key == entry.key &&
                material.original.byteLength == entry.value.byteLength,
          )) {
        throw ArgumentError(
          'Direct upload receipt does not match its retained delivery.',
        );
      }
    }
    for (final entry in this.reservations.entries) {
      if (!keys.contains(entry.key) || entry.key != entry.value.key) {
        throw ArgumentError('Reservation does not match a request material');
      }
    }
    for (final entry in this.receipts.entries) {
      final reservation = this.reservations[entry.key];
      if (!keys.contains(entry.key) ||
          entry.key != entry.value.key ||
          reservation == null ||
          reservation.providerId != entry.value.providerId) {
        throw ArgumentError('Receipt does not match its reservation');
      }
    }
    final checkpoint = transportCheckpoint;
    if (checkpoint != null &&
        (state == SubmissionState.submitted ||
            claimCount <= 0 ||
            this.receipts.length != keys.length ||
            (!checkpoint.isLegacyUnknown &&
                (checkpoint.claimCount! > claimCount ||
                    checkpoint.startedAt!.isAfter(this.updatedAt))))) {
      throw ArgumentError('Invalid transport checkpoint');
    }
    var previousClaim = 0;
    for (final failure in this.failureHistory) {
      if (failure.claimCount <= previousClaim ||
          failure.claimCount > claimCount) {
        throw ArgumentError('Invalid failure history claim order');
      }
      previousClaim = failure.claimCount;
    }
    final hasLease = this.leaseToken != null && this.leaseExpiresAt != null;
    final noLease = this.leaseToken == null && this.leaseExpiresAt == null;
    switch (state) {
      case SubmissionState.readyToSubmit:
        if (!noLease || acknowledgement != null || nextAttemptAt != null) {
          throw ArgumentError('Invalid ready record');
        }
      case SubmissionState.submitting:
        if (!hasLease || acknowledgement != null || nextAttemptAt != null) {
          throw ArgumentError('Invalid submitting record');
        }
      case SubmissionState.submitted:
        if (!noLease ||
            nextAttemptAt != null ||
            acknowledgement == null ||
            acknowledgement!.requestId != request.id ||
            acknowledgement!.subjectId != request.subjectId ||
            this.receipts.length != keys.length) {
          throw ArgumentError('Invalid submitted record');
        }
      case SubmissionState.materialRegistered:
        if (!noLease ||
            nextAttemptAt != null ||
            request.tklDelivery == null ||
            tklProgress?.state != TklMaterialDeliveryState.registered ||
            acknowledgement != null) {
          throw ArgumentError(
            'Material registration requires a confirmed TKL receipt.',
          );
        }
      case SubmissionState.submissionFailed:
        if (!noLease ||
            acknowledgement != null ||
            this.failureHistory.isEmpty ||
            this.failureHistory.last.claimCount != claimCount) {
          throw ArgumentError('Invalid failed record');
        }
        final failure = this.failureHistory.last;
        if (failure.retryable != (this.nextAttemptAt != null) ||
            (this.nextAttemptAt != null &&
                !this.nextAttemptAt!.isAfter(failure.occurredAt))) {
          throw ArgumentError('Invalid retry deadline');
        }
    }
  }

  /// Immutable accepted intent, preserved across every transition.
  final SubmissionRequest request;

  /// Durable queue lifecycle.
  final SubmissionState state;

  /// Number of claims, including recovered expired owners.
  final int claimCount;

  /// UTC transition time, monotonically retained even under clock rollback.
  final DateTime updatedAt;

  /// Safe private ownership token, present only while submitting.
  final String? leaseToken;

  /// Supplied wall-clock expiry; null outside submitting.
  final DateTime? leaseExpiresAt;

  /// Due time of the current retryable failure, otherwise null.
  final DateTime? nextAttemptAt;

  /// Immutable map of persisted reservations by request material key.
  final Map<String, SubmissionStorageReservation> reservations;

  /// Immutable map of successful uploads by request material key.
  final Map<String, SubmissionMaterialReceipt> receipts;

  /// Complete immutable history, retained through retry and success.
  final List<SubmissionFailure> failureHistory;

  /// Matching server acceptance, present only in submitted state.
  final SubmissionAcknowledgement? acknowledgement;

  /// Earliest unconfirmed dispatch, cleared only by matching acknowledgement or
  /// a trusted refusal/no-send attribution for that exact nonlegacy claim.
  final SubmissionTransportCheckpoint? transportCheckpoint;

  /// Last confirmed TKL progress; no Studio acknowledgement is fabricated.
  final TklMaterialDeliverySnapshot? tklProgress;

  /// Provider PUT completion awaiting independent TKL confirmation; contains no URI.
  final Map<String, TklDirectUploadReceipt> directReceipts;

  /// Immutable actual retained-byte expectations, keyed by accepted material.
  final Map<String, TklContentDigest> tklContentDigests;

  /// Current failure only when failed; null during retry, progress or success.
  SubmissionFailure? get lastFailure =>
      state == SubmissionState.submissionFailed ? failureHistory.last : null;

  @override
  bool operator ==(Object other) =>
      other is SubmissionRecord &&
      request == other.request &&
      state == other.state &&
      claimCount == other.claimCount &&
      updatedAt == other.updatedAt &&
      leaseToken == other.leaseToken &&
      leaseExpiresAt == other.leaseExpiresAt &&
      nextAttemptAt == other.nextAttemptAt &&
      j.deepEquals(reservations, other.reservations) &&
      j.deepEquals(receipts, other.receipts) &&
      j.deepEquals(directReceipts, other.directReceipts) &&
      j.deepEquals(tklContentDigests, other.tklContentDigests) &&
      j.deepEquals(failureHistory, other.failureHistory) &&
      acknowledgement == other.acknowledgement &&
      transportCheckpoint == other.transportCheckpoint &&
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
    request,
    state,
    claimCount,
    updatedAt,
    leaseToken,
    leaseExpiresAt,
    nextAttemptAt,
    j.deepHash(reservations),
    j.deepHash(receipts),
    j.deepHash(directReceipts),
    j.deepHash(tklContentDigests),
    j.deepHash(failureHistory),
    acknowledgement,
    transportCheckpoint,
    j.deepHash(
      tklProgress == null
          ? null
          : TklMaterialDeliveryCodec.snapshotToJson(tklProgress!),
    ),
  );
}
