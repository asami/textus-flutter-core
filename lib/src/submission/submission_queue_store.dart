import 'submission_json.dart' as j;
import 'submission_record.dart';
import 'submission_request.dart';

/// Safe lost-owner signal; never exposes a lease token or credential.
final class SubmissionLeaseLostException implements Exception {
  /// Retains only a validated safe request identity.
  SubmissionLeaseLostException(String id) : id = j.token(id);

  /// Request whose lease is no longer valid.
  final String id;
  @override
  String toString() => 'SubmissionLeaseLostException($id)';
}

/// Durable queue authority. All transitions are atomic, preserve the accepted
/// intent, and propagate persistence/corruption errors. Ownership of a store is
/// independent of a borrowing service. Calls after close throw [StateError].
abstract interface class SubmissionQueueStore {
  /// Atomically persists ready intent; equal id is unchanged, conflicting id or
  /// kind/subject throws [StateError] without replacing the accepted row.
  Future<SubmissionRecord> enqueue(SubmissionRequest request);

  /// Strict uncached read, null only for an absent safe id.
  Future<SubmissionRecord?> find(String id);

  /// Strict uncached read, null only for an absent safe kind/subject pair.
  Future<SubmissionRecord?> findForSubject(String kind, String subjectId);

  /// Strict immutable list ordered by request creation time then identity.
  Future<List<SubmissionRecord>> list();

  /// Claims the oldest ready/due retry/expired owner using supplied UTC time.
  /// Returns null if no row is eligible. Duration must be positive; lease token
  /// must be safe and distinct from every persisted current lease.
  Future<SubmissionRecord?> claimNext({
    required DateTime now,
    required String leaseToken,
    required Duration leaseDuration,
  });

  /// Renews only a matching, unexpired submitting lease; never revives an owner.
  Future<SubmissionRecord> renewLease({
    required String id,
    required String leaseToken,
    required DateTime now,
    required Duration leaseDuration,
  });

  /// Checkpoints a matching reservation under a valid lease. Equal duplicate is
  /// idempotent; unequal replacement or unknown material throws [StateError].
  Future<SubmissionRecord> saveReservation({
    required String id,
    required String leaseToken,
    required SubmissionStorageReservation reservation,
    required DateTime now,
  });

  /// Checkpoints a matching receipt under a valid lease and reservation.
  /// Equal duplicate is idempotent; unequal/provider/key mismatch is rejected.
  Future<SubmissionRecord> saveReceipt({
    required String id,
    required String leaseToken,
    required SubmissionMaterialReceipt receipt,
    required DateTime now,
  });

  /// Persists the earliest potentially unconfirmed dispatch under a valid lease.
  /// Requires all receipts; an existing earlier/legacy checkpoint is retained.
  /// Incomplete references throw [StateError]; lost ownership throws
  /// [SubmissionLeaseLostException]. Persistence errors prevent dispatch.
  Future<SubmissionRecord> markTransportDispatch({
    required String id,
    required String leaseToken,
    required DateTime now,
  });

  /// Publishes submitted only with all receipts and matching server acceptance,
  /// clearing transport uncertainty atomically with that acknowledgement.
  Future<SubmissionRecord> complete({
    required String id,
    required String leaseToken,
    required SubmissionAcknowledgement acknowledgement,
    required DateTime now,
  });

  /// Appends a safe failure of this exact claim/time. A retryable failure needs
  /// nextAttemptAt strictly after now; a nonretryable failure needs null.
  /// Trusted transport/configuration no-send/refusal clears only this exact
  /// nonlegacy claim's checkpoint. Incompatible attribution throws
  /// [ArgumentError]; earlier/legacy uncertainty always survives.
  Future<SubmissionRecord> fail({
    required String id,
    required String leaseToken,
    required SubmissionFailure failure,
    required DateTime now,
    DateTime? nextAttemptAt,
    SubmissionTransportFailureOutcome transportFailureOutcome =
        SubmissionTransportFailureOutcome.unknown,
  });

  /// Releases a valid owned claim to ready, preserving checkpoints/history.
  /// Fenced operations throw [SubmissionLeaseLostException] without any write.
  Future<SubmissionRecord> release({
    required String id,
    required String leaseToken,
    required DateTime now,
  });

  /// Moves failed to ready; ready/submitted are unchanged, submitting/unknown
  /// throws [StateError]. All original values and history survive explicit retry.
  Future<SubmissionRecord> retry({required String id, required DateTime now});

  /// Prevents new calls, drains this handle's operations and closes only this
  /// owned handle. Repeated close joins the same future and never deletes data.
  Future<void> close();
}
