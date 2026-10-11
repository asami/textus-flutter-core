import 'submission_adapters.dart';
import 'submission_configuration.dart';
import 'submission_transfer_status.dart';

/// Borrowed local access observation. Evaluation must not authorize, share,
/// schedule or perform network IO. The service bounds accepted evaluations and
/// owns no policy/store lifetime; implementations expose no close operation.
abstract interface class SubmissionReferenceAccessPolicy {
  /// Observes access for the actual complete packet, without changing its values.
  Future<SubmissionReferenceAccessState> evaluate(SubmissionPacket packet);
}

/// Reads the same borrowed live configuration afresh on every required packet.
/// Explicit bindings declare a provisioned server resolver; neither receipts,
/// credentials nor selection prove actual remote accessibility. No result caches.
final class ConfiguredSubmissionReferenceAccessPolicy
    implements SubmissionReferenceAccessPolicy {
  /// Borrows [configuration]; its composing owner alone drains and closes it.
  const ConfiguredSubmissionReferenceAccessPolicy({
    required this._configuration,
  });

  final SubmissionConfigurationStore _configuration;

  /// Zero-material packets bypass store IO. Store failures propagate to the
  /// service's fixed safe dispatch/query failure boundary, without empty fallback.
  @override
  Future<SubmissionReferenceAccessState> evaluate(
    SubmissionPacket packet,
  ) async {
    if (packet.request.materials.isEmpty) {
      return SubmissionReferenceAccessState.available;
    }
    final snapshot = await _configuration.snapshot();
    return evaluateSnapshot(packet: packet, snapshot: snapshot);
  }

  /// Pure exact-id evaluation of a frozen packet and safe snapshot. Actual
  /// receipt access ids determine references, independently of selected targets.
  static SubmissionReferenceAccessState evaluateSnapshot({
    required SubmissionPacket packet,
    required SubmissionConfigurationSnapshot snapshot,
  }) {
    if (packet.request.materials.isEmpty) {
      return SubmissionReferenceAccessState.available;
    }
    final transport = packet.request.transportConnectionId;
    final keys = packet.request.materials.map((m) => m.key).toSet();
    if (!snapshot.httpConnections.any((c) => c.id == transport) ||
        packet.receipts.length != keys.length ||
        packet.receipts.entries.any(
          (entry) => !keys.contains(entry.key) || entry.key != entry.value.key,
        ) ||
        packet.receipts.values.any(
          (receipt) => !snapshot.driveConnections.any(
            (c) => c.id == receipt.accessConnectionId,
          ),
        )) {
      return SubmissionReferenceAccessState.unavailable;
    }
    final access = snapshot.referenceAccessBindings[transport];
    if (access == null) return SubmissionReferenceAccessState.unknown;
    return packet.receipts.values.every(
          (receipt) => access.contains(receipt.accessConnectionId),
        )
        ? SubmissionReferenceAccessState.available
        : SubmissionReferenceAccessState.unavailable;
  }
}
