import '../capture/capture_material.dart';
import 'submission_json.dart' as j;

/// An immutable original reference and opaque provenance at Commit time.
final class SubmissionMaterial {
  /// Snapshots [provenance]; unsafe keys or invalid JSON throw [ArgumentError].
  SubmissionMaterial({
    required String key,
    required this.original,
    Map<String, Object?> provenance = const {},
  }) : key = j.token(key),
       provenance = j.frozenJson(provenance);

  /// Safe logical material key within the request.
  final String key;

  /// Complete immutable reference to unchanged local original bytes.
  final CaptureMaterialReference original;

  /// Deeply immutable consumer provenance, without domain interpretation.
  final Map<String, Object?> provenance;

  @override
  bool operator ==(Object other) =>
      other is SubmissionMaterial &&
      key == other.key &&
      original == other.original &&
      j.deepEquals(provenance, other.provenance);

  @override
  int get hashCode => Object.hash(key, original, j.deepHash(provenance));
}

/// Explicit immutable intent; subsequent consumer edits cannot alter this value.
final class SubmissionRequest {
  /// Snapshots all JSON and material order synchronously.
  ///
  /// Throws [ArgumentError] for unsafe tokens, duplicate material keys, invalid
  /// JSON or a storage connection that is absent/present inconsistently with
  /// [materials]. Empty materials and opaque execution context are supported.
  SubmissionRequest({
    required String id,
    required String kind,
    required String subjectId,
    required DateTime createdAt,
    required Map<String, Object?> document,
    required Map<String, Object?> payload,
    required List<SubmissionMaterial> materials,
    required String transportConnectionId,
    String? storageConnectionId,
    Map<String, Object?> extensions = const {},
  }) : id = j.token(id),
       kind = j.token(kind),
       subjectId = j.token(subjectId),
       createdAt = createdAt.toUtc(),
       document = j.frozenJson(document),
       payload = j.frozenJson(payload),
       materials = List<SubmissionMaterial>.unmodifiable(materials),
       transportConnectionId = j.token(transportConnectionId),
       storageConnectionId = storageConnectionId == null
           ? null
           : j.token(storageConnectionId),
       extensions = j.frozenJson(extensions) {
    if (this.materials.map((m) => m.key).toSet().length !=
        this.materials.length) {
      throw ArgumentError('Duplicate material key');
    }
    if (this.materials.isEmpty != (this.storageConnectionId == null)) {
      throw ArgumentError('Storage connection must match material presence');
    }
  }

  /// Safe immutable request identity and transport idempotency key.
  final String id;

  /// Open safe domain kind, interpreted only by consumers.
  final String kind;

  /// Safe consumer subject identity; only one Commit per kind/subject is allowed.
  final String subjectId;

  /// UTC creation time used for deterministic queue order.
  final DateTime createdAt;

  /// Local-only immutable consumer document; excluded from transport packets.
  final Map<String, Object?> document;

  /// Immutable server payload with exact whitespace and opaque values retained.
  final Map<String, Object?> payload;

  /// Immutable ordered original references; never owns or deletes the bytes.
  final List<SubmissionMaterial> materials;

  /// Safe key into the service's borrowed transport connections.
  final String transportConnectionId;

  /// Safe storage connection key, null exactly when there are no materials.
  final String? storageConnectionId;

  /// Immutable opaque presentation/execution extensions.
  final Map<String, Object?> extensions;

  @override
  bool operator ==(Object other) =>
      other is SubmissionRequest &&
      id == other.id &&
      kind == other.kind &&
      subjectId == other.subjectId &&
      createdAt == other.createdAt &&
      j.deepEquals(document, other.document) &&
      j.deepEquals(payload, other.payload) &&
      j.deepEquals(materials, other.materials) &&
      transportConnectionId == other.transportConnectionId &&
      storageConnectionId == other.storageConnectionId &&
      j.deepEquals(extensions, other.extensions);

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    subjectId,
    createdAt,
    j.deepHash(document),
    j.deepHash(payload),
    j.deepHash(materials),
    transportConnectionId,
    storageConnectionId,
    j.deepHash(extensions),
  );
}
