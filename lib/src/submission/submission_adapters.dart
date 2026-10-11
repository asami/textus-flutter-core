import 'dart:typed_data';

import 'submission_json.dart' as j;
import 'submission_record.dart';
import 'submission_request.dart';

/// Borrowed storage connection. Implementations must exclude credentials from
/// values/errors and make upload idempotent for a persisted reservation.
abstract interface class SubmissionStorageAdapter {
  /// Safe provider identity, matched against every returned checkpoint.
  String get providerId;

  /// Prepares a reservation without uploading bytes; Core persists it first.
  /// Safe expected failures use [SubmissionAdapterException].
  Future<SubmissionStorageReservation> prepare({
    required SubmissionRequest request,
    required SubmissionMaterial material,
  });

  /// Uploads caller-owned unchanged bytes using the exact persisted reservation.
  /// Retrying this reservation must return the same remote identity. A timeout
  /// does not undo remote effects; late results are discarded by Core.
  Future<SubmissionMaterialReceipt> upload({
    required SubmissionRequest request,
    required SubmissionMaterial material,
    required SubmissionStorageReservation reservation,
    required Uint8List bytes,
  });
}

/// Borrowed transport; submit must be idempotent by immutable request identity.
abstract interface class SubmissionTransport {
  /// Safe provider identity for connection configuration.
  String get providerId;

  /// Returns matching server acceptance; storage success alone is insufficient.
  /// Safe expected failures use [SubmissionAdapterException]. Late timeout
  /// results cannot acknowledge the local queue.
  Future<SubmissionAcknowledgement> submit(SubmissionPacket packet);
}

/// Borrowed wake port; no scheduler/timer/native driver is supplied by this slice.
abstract interface class SubmissionWakeScheduler {
  /// Requests future queue work after durable enqueue/retry. Failure cannot
  /// roll back accepted intent and is returned as a safe scheduling notice.
  Future<void> requestRun();
}

/// Immutable complete packet value. The codec excludes the local document.
final class SubmissionPacket {
  /// Freezes receipts and rejects missing, unknown or mismatched material keys.
  SubmissionPacket({
    required this.request,
    required Map<String, SubmissionMaterialReceipt> receipts,
  }) : receipts = Map<String, SubmissionMaterialReceipt>.unmodifiable(
         receipts,
       ) {
    final keys = request.materials.map((m) => m.key).toSet();
    if (this.receipts.length != keys.length ||
        this.receipts.entries.any(
          (entry) => !keys.contains(entry.key) || entry.key != entry.value.key,
        )) {
      throw ArgumentError('Packet requires all matching material receipts');
    }
  }

  /// Immutable request; document remains local in wire serialization.
  final SubmissionRequest request;

  /// Immutable matching complete receipt map.
  final Map<String, SubmissionMaterialReceipt> receipts;
  @override
  bool operator ==(Object other) =>
      other is SubmissionPacket &&
      request == other.request &&
      j.deepEquals(receipts, other.receipts);
  @override
  int get hashCode => Object.hash(request, j.deepHash(receipts));
}

/// Trusted safe adapter failure. Never pass raw exception text, tokens or bodies.
final class SubmissionAdapterException implements Exception {
  /// Validates a safe code and nonblank message; no raw cause is retained.
  SubmissionAdapterException({
    required this.stage,
    required String code,
    required String message,
    required this.retryable,
    this.transportFailureOutcome = SubmissionTransportFailureOutcome.unknown,
  }) : code = j.token(code),
       message = j.descriptive(message);

  /// Safe stage attribution.
  final SubmissionFailureStage stage;

  /// Safe diagnostic token.
  final String code;

  /// Safe user-facing message.
  final String message;

  /// Whether delayed automatic retry is permitted.
  final bool retryable;

  /// Trusted attempt outcome. Select notSent only before any submit side effect;
  /// rejected only for conclusive current-attempt refusal. Unknown is safest.
  /// This value carries no server acknowledgement or raw cause.
  final SubmissionTransportFailureOutcome transportFailureOutcome;
  @override
  String toString() => 'SubmissionAdapterException(${stage.name}, $code)';
}
