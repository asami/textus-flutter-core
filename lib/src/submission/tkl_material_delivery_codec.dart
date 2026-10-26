import 'submission_json.dart' as j;
import 'tkl_material_delivery.dart';
import 'tkl_original_content.dart';

/// Shared wire/checkpoint projection, independent of HTTP and local queue IO.
abstract final class TklMaterialDeliveryCodec {
  /// The tested native RecordEncoder emits camelCase; the HTTP adapter and
  /// retained checkpoints may use snake_case for this closed projection.
  /// Normalize only this closed projection vocabulary; opaque JSON is untouched.
  /// Ambiguous aliases are rejected rather than selecting either value.
  static Map<String, Object?> responseFields(
    Object? value,
    Set<String> required, [
    Set<String> optional = const {},
  ]) => _fields(value, required, optional);
  static Map<String, Object?> directReceiptToJson(
    TklDirectUploadReceipt value,
  ) => {
    'resourceId': value.resourceId,
    'transferRef': value.transferRef,
    'byteLength': value.byteLength,
  };
  static TklDirectUploadReceipt directReceiptFromJson(Object? value) {
    final fields = j.exact(value, {'resourceId', 'transferRef', 'byteLength'});
    return TklDirectUploadReceipt(
      resourceId: j.string(fields['resourceId']),
      transferRef: j.string(fields['transferRef']),
      byteLength: j.integer(fields['byteLength']),
    );
  }

  static TklMaterialDeliveryDestination destinationFromJson(Object? value) =>
      _destination(value);
  static TklMaterialDeliverySnapshot snapshotFromJson(Object? value) =>
      _snapshot(value);
  static Map<String, Object?> requestToJson(TklMaterialDeliveryRequest value) =>
      {
        'requestId': value.requestId,
        'contribution': j.detach(value.contribution),
      };
  static TklMaterialDeliveryRequest requestFromJson(Object? value) {
    final fields = j.exact(value, {'requestId', 'contribution'});
    return TklMaterialDeliveryRequest(
      requestId: j.string(fields['requestId']),
      contribution: j.object(fields['contribution']),
    );
  }

  static Map<String, Object?> snapshotToJson(
    TklMaterialDeliverySnapshot value,
  ) => {
    'delivery_ref': value.deliveryRef,
    'request_id': value.requestId,
    'revision': value.revision,
    'destination_id': value.destinationId,
    'destination_label': value.destinationLabel,
    'transfer_method': value.transferMethod.name,
    'transfer_reason': ?value.transferReason,
    'state': value.state.name,
    'resources': [
      for (final resource in value.resources)
        {
          'resource_id': resource.resourceId,
          'media_type': resource.mediaType,
          'byte_length': resource.byteLength,
          'state': resource.state.name,
          if (resource.contentDigest != null) ...{
            'content_digest': resource.contentDigest!.toJson(),
            'verification_state': resource.verificationState!.name,
            'verification_attempts': resource.verificationAttempts,
            'verification_reason': ?resource.verificationReason,
          },
        },
    ],
    'material_ref': ?value.materialRef,
    'action_required': ?value.actionRequired,
  };
}

TklMaterialDeliveryDestination _destination(Object? value) {
  final fields = _fields(
    value,
    {'availability'},
    {
      'destination_id',
      'label',
      'transfer_method',
      'transfer_reason',
      'max_resource_bytes',
      'content_integrity',
    },
  );
  if (fields.containsKey('content_integrity') &&
      fields['content_integrity'] != 'sha256') {
    _invalid();
  }
  return TklMaterialDeliveryDestination(
    availability: _enum(
      TklDestinationAvailability.values,
      fields['availability'],
    ),
    destinationId: _optionalString(fields['destination_id']),
    label: _optionalString(fields['label']),
    transferMethod: fields['transfer_method'] == null
        ? null
        : _enum(TklMaterialTransferMethod.values, fields['transfer_method']),
    maxResourceBytes: fields['max_resource_bytes'] == null
        ? null
        : _integer(fields['max_resource_bytes']),
    transferReason: _optionalString(fields['transfer_reason']),
    contentIntegrity: _optionalString(fields['content_integrity']),
  );
}

TklMaterialDeliverySnapshot _snapshot(Object? value) {
  final fields = _fields(
    value,
    {
      'delivery_ref',
      'request_id',
      'revision',
      'destination_id',
      'destination_label',
      'state',
      'resources',
    },
    {'material_ref', 'action_required', 'transfer_method', 'transfer_reason'},
  );
  final resources = fields['resources'];
  if (resources is! List) _invalid();
  return TklMaterialDeliverySnapshot(
    deliveryRef: j.string(fields['delivery_ref']),
    requestId: j.string(fields['request_id']),
    revision: _integer(fields['revision']),
    destinationId: j.string(fields['destination_id']),
    destinationLabel: j.string(fields['destination_label']),
    state: _enum(TklMaterialDeliveryState.values, fields['state']),
    resources: [for (final value in resources) _resource(value)],
    materialRef: _optionalString(fields['material_ref']),
    actionRequired: _optionalString(fields['action_required']),
    transferMethod: fields['transfer_method'] == null
        ? TklMaterialTransferMethod.tklMultipart
        : _enum(TklMaterialTransferMethod.values, fields['transfer_method']),
    transferReason: _optionalString(fields['transfer_reason']),
  );
}

TklOriginalTransferProgress _resource(Object? value) {
  final fields = _fields(value, {
    'resource_id', 'media_type', 'byte_length', 'state',
  }, {
    'content_digest', 'verification_state', 'verification_attempts',
    'verification_reason',
  });
  final hasDigest = fields.containsKey('content_digest');
  if (hasDigest != fields.containsKey('verification_state') ||
      hasDigest != fields.containsKey('verification_attempts') ||
      (fields.containsKey('verification_reason') &&
          (!hasDigest || fields['verification_reason'] == null))) {
    _invalid();
  }
  return TklOriginalTransferProgress(
    resourceId: j.string(fields['resource_id']),
    mediaType: j.string(fields['media_type']),
    byteLength: _integer(fields['byte_length']),
    state: _enum(TklOriginalTransferState.values, fields['state']),
    contentDigest: hasDigest
        ? TklContentDigest.fromJson(fields['content_digest']) : null,
    verificationState: hasDigest
        ? _enum(TklOriginalVerificationState.values, fields['verification_state']) : null,
    verificationAttempts: hasDigest ? _integer(fields['verification_attempts']) : null,
    verificationReason: _optionalString(fields['verification_reason']),
  );
}

Map<String, Object?> _fields(
  Object? value,
  Set<String> required, [
  Set<String> optional = const {},
]) {
  final source = j.object(value);
  final allowed = {...required, ...optional};
  final aliases = {
    for (final key in allowed)
      key.replaceAllMapped(
        RegExp(r'_([a-z])'),
        (match) => match[1]!.toUpperCase(),
      ): key,
  };
  final fields = <String, Object?>{};
  for (final entry in source.entries) {
    final key = allowed.contains(entry.key)
        ? entry.key
        : aliases[entry.key] ?? entry.key;
    if (fields.containsKey(key)) _invalid();
    fields[key] = entry.value;
  }
  if (!required.every(fields.containsKey) ||
      !fields.keys.every(
        (key) => required.contains(key) || optional.contains(key),
      )) {
    _invalid();
  }
  return fields;
}

T _enum<T extends Enum>(List<T> values, Object? value) {
  if (value is String) {
    for (final candidate in values) {
      if (candidate.name == value) return candidate;
    }
  }
  _invalid();
}

int _integer(Object? value) => value is int ? value : _invalid();
String? _optionalString(Object? value) =>
    value == null ? null : j.string(value);

Never _invalid() => throw const FormatException('Invalid TKL response.');
