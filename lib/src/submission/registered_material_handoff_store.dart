import 'registered_material_submission.dart';
import 'submission_connections.dart';
import 'submission_json.dart' as j;
import 'submission_record.dart';
import 'submission_request.dart';
import 'tkl_material_delivery.dart';
import 'tkl_material_delivery_codec.dart';

enum RegisteredMaterialHandoffState { pending, sending, outcomeUnknown, failed, accepted }
enum RegisteredMaterialHandoffFailureKind { configuration, notSent, rejected, outcomeUnknown }

/// Safe fixed diagnostics only; never pass submitted values or raw exceptions.
final class RegisteredMaterialHandoffFailure {
  RegisteredMaterialHandoffFailure({
    required this.kind, required String code, required String message,
  }) : code = j.token(code), message = j.descriptive(message);
  final RegisteredMaterialHandoffFailureKind kind;
  final String code;
  final String message;
  @override
  bool operator ==(Object other) => other is RegisteredMaterialHandoffFailure &&
      kind == other.kind && code == other.code && message == other.message;
  @override
  int get hashCode => Object.hash(kind, code, message);
}

/// Frozen saved registration, source intent, packet and target plus local state.
/// A DTO is not evidence that a source exists: createHandoff rereads that source.
final class RegisteredMaterialHandoffRecord {
  RegisteredMaterialHandoffRecord({
    required String id,
    required this.sourceRequest,
    required this.registeredSnapshot,
    required DateTime sourceCheckpointUpdatedAt,
    required this.target,
    required this.packet,
    required DateTime createdAt,
    required DateTime updatedAt,
    required this.state,
    String? leaseToken,
    DateTime? leaseExpiresAt,
    this.acknowledgement,
    this.failure,
  }) : id = j.token(id),
       sourceCheckpointUpdatedAt = sourceCheckpointUpdatedAt.toUtc(),
       createdAt = createdAt.toUtc(), updatedAt = updatedAt.toUtc(),
       leaseToken = leaseToken == null ? null : j.token(leaseToken),
       leaseExpiresAt = leaseExpiresAt?.toUtc() {
    final snapshot = registeredSnapshot;
    if (sourceRequest != packet.sourceRequest ||
        !sameRegisteredMaterialTarget(target, packet.target) ||
        snapshot.state != TklMaterialDeliveryState.registered ||
        snapshot.requestId != sourceRequest.id ||
        snapshot.materialRef != packet.association.materialRef ||
        snapshot.resources.length != sourceRequest.materials.length ||
        this.updatedAt.isBefore(this.createdAt)) {
      throw ArgumentError('Handoff must retain its exact Registered source');
    }
    for (var i = 0; i < snapshot.resources.length; i++) {
      final resource = snapshot.resources[i];
      final original = sourceRequest.materials[i];
      if (packet.association.resources[i].resourceId != resource.resourceId ||
          packet.association.resources[i].key != original.key ||
          resource.resourceId != original.key ||
          resource.mediaType != original.original.mediaType ||
          resource.byteLength != original.original.byteLength) {
        throw ArgumentError('Handoff must retain its saved original mappings');
      }
    }
    final sending = state == RegisteredMaterialHandoffState.sending;
    final accepted = state == RegisteredMaterialHandoffState.accepted;
    if ((sending && (this.leaseToken == null || this.leaseExpiresAt == null ||
             !this.leaseExpiresAt!.isAfter(this.updatedAt))) ||
        (!sending && (this.leaseToken != null || this.leaseExpiresAt != null)) ||
        accepted != (acknowledgement != null) ||
        (acknowledgement != null &&
            (acknowledgement!.requestId != sourceRequest.id ||
             acknowledgement!.subjectId != sourceRequest.subjectId)) ||
        ((state == RegisteredMaterialHandoffState.failed ||
          state == RegisteredMaterialHandoffState.outcomeUnknown) != (failure != null)) ||
        (state == RegisteredMaterialHandoffState.outcomeUnknown &&
            failure!.kind != RegisteredMaterialHandoffFailureKind.outcomeUnknown) ||
        (state == RegisteredMaterialHandoffState.failed &&
            failure!.kind == RegisteredMaterialHandoffFailureKind.outcomeUnknown)) {
      throw ArgumentError('Invalid handoff state, acknowledgement or lease');
    }
  }

  final String id;
  String get sourceRequestId => sourceRequest.id;
  final SubmissionRequest sourceRequest;
  final TklMaterialDeliverySnapshot registeredSnapshot;
  /// Original queue checkpoint time, never a physical write/observation time.
  final DateTime sourceCheckpointUpdatedAt;
  final HttpSubmissionConnection target;
  final RegisteredMaterialSubmissionPacket packet;
  final DateTime createdAt;
  final DateTime updatedAt;
  final RegisteredMaterialHandoffState state;
  final String? leaseToken;
  final DateTime? leaseExpiresAt;
  final SubmissionAcknowledgement? acknowledgement;
  final RegisteredMaterialHandoffFailure? failure;

  @override
  bool operator ==(Object other) => other is RegisteredMaterialHandoffRecord &&
      id == other.id && sourceRequest == other.sourceRequest &&
      j.deepEquals(TklMaterialDeliveryCodec.snapshotToJson(registeredSnapshot),
          TklMaterialDeliveryCodec.snapshotToJson(other.registeredSnapshot)) &&
      sourceCheckpointUpdatedAt == other.sourceCheckpointUpdatedAt &&
      packet == other.packet && createdAt == other.createdAt &&
      updatedAt == other.updatedAt && state == other.state &&
      leaseToken == other.leaseToken && leaseExpiresAt == other.leaseExpiresAt &&
      acknowledgement == other.acknowledgement && failure == other.failure;
  @override
  int get hashCode => Object.hash(id, sourceRequest,
      j.deepHash(TklMaterialDeliveryCodec.snapshotToJson(registeredSnapshot)),
      sourceCheckpointUpdatedAt, packet, createdAt, updatedAt, state,
      leaseToken, leaseExpiresAt, acknowledgement, failure);
}

final class RegisteredMaterialHandoffLeaseLostException implements Exception {
  RegisteredMaterialHandoffLeaseLostException(String id) : id = j.token(id);
  final String id;
  @override
  String toString() => 'RegisteredMaterialHandoffLeaseLostException';
}

/// Independent durable handoff port, sharing the queue's transaction owner.
/// None of these operations reads original bytes or calls a remote service.
abstract interface class RegisteredMaterialHandoffStore {
  Future<RegisteredMaterialHandoffRecord?> findHandoffForSource(String sourceRequestId);
  Future<List<RegisteredMaterialHandoffRecord>> listHandoffs();
  /// Rereads the real source atomically. Equal source/target returns unchanged;
  /// another target conflicts. Does not modify the source queue row.
  Future<RegisteredMaterialHandoffRecord> createHandoff({
    required String id, required SubmissionRecord source,
    required HttpSubmissionConnection target,
    required RegisteredMaterialSubmissionPacket packet, required DateTime now,
  });
  /// Observes expired sending as unknown without returning it for dispatch.
  /// Only the oldest pending row can receive a persisted sending lease.
  Future<RegisteredMaterialHandoffRecord?> claimNextHandoff({
    required DateTime now, required String leaseToken, required Duration leaseDuration,
  });
  Future<RegisteredMaterialHandoffRecord> finishHandoff({
    required String id, required String leaseToken, required DateTime now,
    required RegisteredMaterialHandoffState state,
    SubmissionAcknowledgement? acknowledgement,
    RegisteredMaterialHandoffFailure? failure,
  });
  /// Explicit replay of the identical frozen packet; active/accepted rejects.
  Future<RegisteredMaterialHandoffRecord> reconcileHandoff({
    required String sourceRequestId, required DateTime now,
  });
}
