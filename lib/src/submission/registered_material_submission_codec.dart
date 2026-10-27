import 'registered_material_handoff_store.dart';
import 'registered_material_submission.dart';
import 'submission_codec.dart';
import 'submission_connections.dart';
import 'submission_json.dart' as j;
import 'submission_request.dart';
import 'tkl_material_delivery_codec.dart';

/// Closed v2 wire schema, distinct from the legacy persisted request version 2.
abstract final class RegisteredMaterialSubmissionCodec {
  static Map<String, Object?> associationToJson(RegisteredMaterialAssociation value) => {
    'schema': RegisteredMaterialAssociation.schema,
    'materialRef': value.materialRef,
    'resources': [for (final resource in value.resources)
      {'key': resource.key, 'resourceId': resource.resourceId}],
  };

  static RegisteredMaterialAssociation associationFromJson(Object? json) => j.decode(() {
    final value = j.exact(json, {'schema', 'materialRef', 'resources'});
    if (value['schema'] != RegisteredMaterialAssociation.schema) {
      throw const FormatException('Unsupported registered Material schema');
    }
    return RegisteredMaterialAssociation(
      materialRef: j.string(value['materialRef']),
      resources: [for (final entry in j.array(value['resources']))
        _resourceFromJson(entry)],
    );
  });

  static RegisteredMaterialResource _resourceFromJson(Object? json) {
    final value = j.exact(json, {'key', 'resourceId'});
    return RegisteredMaterialResource(
      key: j.string(value['key']), resourceId: j.string(value['resourceId']),
    );
  }

  /// Exactly nine fields, no receipt, local document, target or credential.
  static Map<String, Object?> packetToJson(RegisteredMaterialSubmissionPacket packet) => {
    'version': 2,
    'requestId': packet.sourceRequest.id,
    'kind': packet.sourceRequest.kind,
    'subjectId': packet.sourceRequest.subjectId,
    'createdAt': packet.sourceRequest.createdAt.toIso8601String(),
    'payload': j.detach(packet.sourceRequest.payload),
    'extensions': j.detach(packet.sourceRequest.extensions),
    'materials': packet.sourceRequest.materials.map(SubmissionCodec.materialToJson).toList(),
    'registeredMaterial': associationToJson(packet.association),
  };

  /// Reattaches only the explicitly supplied original local intent and target.
  /// Wire decoding grants no saved-registration or dispatch authority.
  static RegisteredMaterialSubmissionPacket packetFromJson(
    Object? json, {
    required SubmissionRequest sourceRequest,
    required HttpSubmissionConnection target,
  }) => j.decode(() {
    final value = j.exact(json, {
      'version', 'requestId', 'kind', 'subjectId', 'createdAt', 'payload',
      'extensions', 'materials', 'registeredMaterial',
    });
    if (j.integer(value['version']) != 2 ||
        j.string(value['requestId']) != sourceRequest.id ||
        j.string(value['kind']) != sourceRequest.kind ||
        j.string(value['subjectId']) != sourceRequest.subjectId ||
        j.time(value['createdAt']) != sourceRequest.createdAt ||
        !j.deepEquals(j.object(value['payload']), sourceRequest.payload) ||
        !j.deepEquals(j.object(value['extensions']), sourceRequest.extensions)) {
      throw const FormatException('Registered packet differs from source intent');
    }
    final materials = [for (final item in j.array(value['materials']))
      SubmissionCodec.materialFromJson(j.object(item))];
    if (!j.deepEquals(materials, sourceRequest.materials)) {
      throw const FormatException('Registered packet differs from source originals');
    }
    return RegisteredMaterialSubmissionPacket(
      sourceRequest: sourceRequest, target: target,
      association: associationFromJson(value['registeredMaterial']),
    );
  });

  /// Closed local handoff version 1, retaining all source/registration facts.
  static Map<String, Object?> handoffToJson(RegisteredMaterialHandoffRecord value) => {
    'version': 1,
    'id': value.id,
    'sourceRequest': SubmissionCodec.requestToJson(value.sourceRequest),
    'registeredSnapshot': TklMaterialDeliveryCodec.snapshotToJson(value.registeredSnapshot),
    'sourceCheckpointUpdatedAt': value.sourceCheckpointUpdatedAt.toIso8601String(),
    'target': value.target.toJson(),
    'packet': packetToJson(value.packet),
    'createdAt': value.createdAt.toIso8601String(),
    'updatedAt': value.updatedAt.toIso8601String(),
    'state': value.state.name,
    'leaseToken': value.leaseToken,
    'leaseExpiresAt': value.leaseExpiresAt?.toIso8601String(),
    'acknowledgement': value.acknowledgement == null ? null
        : SubmissionCodec.acknowledgementToJson(value.acknowledgement!),
    'failure': value.failure == null ? null : {
      'kind': value.failure!.kind.name,
      'code': value.failure!.code,
      'message': value.failure!.message,
    },
  };

  static RegisteredMaterialHandoffRecord handoffFromJson(Object? json) => j.decode(() {
    final value = j.exact(json, {
      'version', 'id', 'sourceRequest', 'registeredSnapshot', 'sourceCheckpointUpdatedAt',
      'target', 'packet', 'createdAt', 'updatedAt', 'state', 'leaseToken',
      'leaseExpiresAt', 'acknowledgement', 'failure',
    });
    j.version(value);
    final source = SubmissionCodec.requestFromJson(j.object(value['sourceRequest']));
    final target = HttpSubmissionConnection.fromJson(j.object(value['target']));
    final failure = value['failure'] == null ? null
        : j.exact(value['failure'], {'kind', 'code', 'message'});
    return RegisteredMaterialHandoffRecord(
      id: j.string(value['id']), sourceRequest: source,
      registeredSnapshot: TklMaterialDeliveryCodec.snapshotFromJson(value['registeredSnapshot']),
      sourceCheckpointUpdatedAt: j.time(value['sourceCheckpointUpdatedAt']),
      target: target,
      packet: packetFromJson(value['packet'], sourceRequest: source, target: target),
      createdAt: j.time(value['createdAt']), updatedAt: j.time(value['updatedAt']),
      state: j.enumeration(value['state'], RegisteredMaterialHandoffState.values),
      leaseToken: j.nullableString(value['leaseToken']),
      leaseExpiresAt: j.nullableTime(value['leaseExpiresAt']),
      acknowledgement: value['acknowledgement'] == null ? null
          : SubmissionCodec.acknowledgementFromJson(j.object(value['acknowledgement'])),
      failure: failure == null ? null : RegisteredMaterialHandoffFailure(
        kind: j.enumeration(failure['kind'], RegisteredMaterialHandoffFailureKind.values),
        code: j.string(failure['code']), message: j.string(failure['message']),
      ),
    );
  });
}
