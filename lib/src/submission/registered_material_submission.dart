import 'submission_connections.dart';
import 'submission_json.dart' as j;
import 'submission_record.dart';
import 'submission_request.dart';

/// One ordered original-to-TKL-resource association, without physical authority.
final class RegisteredMaterialResource {
  RegisteredMaterialResource({required String key, required String resourceId})
    : key = j.token(key), resourceId = j.token(resourceId);

  final String key;
  final String resourceId;

  @override
  bool operator ==(Object other) => other is RegisteredMaterialResource &&
      key == other.key && resourceId == other.resourceId;
  @override
  int get hashCode => Object.hash(key, resourceId);
}

/// Exact literal TKL reference and ordered unique original mappings.
/// This descriptive DTO supplies no registration or dispatch authority.
final class RegisteredMaterialAssociation {
  RegisteredMaterialAssociation({
    required String materialRef,
    required List<RegisteredMaterialResource> resources,
  }) : materialRef = j.descriptive(materialRef),
       resources = List<RegisteredMaterialResource>.unmodifiable(resources) {
    if (this.resources.map((r) => r.key).toSet().length != resources.length ||
        this.resources.map((r) => r.resourceId).toSet().length != resources.length) {
      throw ArgumentError('Registered original mappings must be unique');
    }
  }

  static const schema = 'textus.registered-material-reference/1';
  final String materialRef;
  final List<RegisteredMaterialResource> resources;

  @override
  bool operator ==(Object other) => other is RegisteredMaterialAssociation &&
      materialRef == other.materialRef && j.deepEquals(resources, other.resources);
  @override
  int get hashCode => Object.hash(materialRef, j.deepHash(resources));
}

/// Separate v2 wire value retaining the original saved TKL intent and destination.
/// Construction validates shape, not whether a Registered source was saved.
/// Only the handoff service/store can establish that durable precondition.
final class RegisteredMaterialSubmissionPacket {
  RegisteredMaterialSubmissionPacket({
    required this.sourceRequest,
    required this.target,
    required this.association,
  }) {
    final payload = sourceRequest.payload;
    final material = payload['material'];
    if (sourceRequest.tklDelivery == null ||
        sourceRequest.kind != 'bookMaterial' ||
        sourceRequest.subjectId != sourceRequest.id ||
        payload.length != 4 ||
        !payload.keys.toSet().containsAll({
          'schemaVersion', 'type', 'material', 'recognitionReports',
        }) ||
        payload['schemaVersion'] is! int || payload['schemaVersion'] != 1 ||
        payload['type'] != 'bookMaterial' ||
        payload['recognitionReports'] is! Map ||
        material is! Map || material['schemaVersion'] is! int ||
        material['schemaVersion'] != 2 || material['id'] != sourceRequest.id ||
        sourceRequest.materials.length != association.resources.length) {
      throw ArgumentError('Registered packet requires the original Book intent');
    }
    for (var i = 0; i < sourceRequest.materials.length; i++) {
      final original = sourceRequest.materials[i];
      if (original.key != association.resources[i].key ||
          original.original.byteLength <= 0) {
        throw ArgumentError('Registered packet requires exact ordered originals');
      }
    }
  }

  final SubmissionRequest sourceRequest;
  final HttpSubmissionConnection target;
  final RegisteredMaterialAssociation association;

  @override
  bool operator ==(Object other) => other is RegisteredMaterialSubmissionPacket &&
      sourceRequest == other.sourceRequest && association == other.association &&
      sameRegisteredMaterialTarget(target, other.target);
  @override
  int get hashCode => Object.hash(sourceRequest, association,
      target.id, target.endpoint, target.requiresBearerToken);
}

/// Exact immutable destination equality; a matching ID alone cannot retarget IO.
bool sameRegisteredMaterialTarget(
  HttpSubmissionConnection left, HttpSubmissionConnection right,
) => left.id == right.id && left.endpoint == right.endpoint &&
    left.requiresBearerToken == right.requiresBearerToken;

/// Borrowed typed v2 capability. No storage or arbitrary JSON send operation.
abstract interface class RegisteredMaterialSubmissionTransport {
  HttpSubmissionConnection get connection;
  Future<SubmissionAcknowledgement> submitRegisteredMaterial(
    RegisteredMaterialSubmissionPacket packet,
  );
}
