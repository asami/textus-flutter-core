part of 'cncf_display_read.dart';

/// Independently trusted ordinary resource command configuration.
/// Wire actions supply availability only, never routing or authority.
final class CncfDisplayBusinessBinding {
  CncfDisplayBusinessBinding({
    required this.componentId,
    required this.actionId,
    required this.bindingId,
    required this.service,
    required this.operation,
    required this.expectedOutcome,
    this.revisionIncrement = 1,
  }) {
    try {
      for (final value in [componentId, actionId, bindingId, expectedOutcome]) {
        _id(value);
      }
    } on CncfDisplayReadException {
      throw ArgumentError('Invalid Business binding identity or outcome');
    }
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9-]*$').hasMatch(service) ||
        !RegExp(r'^[A-Za-z][A-Za-z0-9]*$').hasMatch(operation) ||
        revisionIncrement < 1 ||
        revisionIncrement > 2147483647) {
      throw ArgumentError('Invalid Business binding route or increment');
    }
  }

  final String componentId;
  final String actionId;
  final String bindingId;
  final String service;
  final String operation;
  final String expectedOutcome;

  /// Trusted contract of this one-resource command, not a universal Business rule.
  final int revisionIncrement;
}

/// An exact ordinary acknowledgement, without a Display or invented context.
final class CncfDisplayBusinessResult {
  const CncfDisplayBusinessResult._({
    required this.binding,
    required this.resourceId,
    required this.revision,
    required this.outcome,
  });
  final CncfDisplayBusinessBinding binding;
  final String resourceId;
  final String revision;
  final String outcome;
}

final class _PreparedBusiness {
  const _PreparedBusiness(
    this.resourceId,
    this.revision,
    this.expectedRevision,
  );
  final String resourceId;
  final String revision;
  final BigInt expectedRevision;
}

_PreparedBusiness _prepareBusiness(
  CncfDisplayReadProfile profile,
  CncfDisplayBusinessBinding binding,
  CncfDisplayRead observation,
) {
  if (binding.componentId != profile.componentId) _fail('sourceMismatch');
  // Re-admit the complete formal wire, rather than a flattened ResourceRecord.
  final admitted = CncfDisplayRead.decode(
    observation.wire,
    profile,
    detail: true,
    expectedResourceId: observation.resources.length == 1
        ? observation.resources.single.entityId
        : null,
  );
  if (admitted.resources.length != 1) _fail('resourceMismatch');
  final actions = _array(admitted.model['actions'])
      .map(_object)
      .where(
        (action) =>
            action['id'] == binding.actionId &&
            action['bindingId'] == binding.bindingId,
      );
  if (actions.length != 1) _fail('businessBindingMismatch');
  if (actions.single['availability'] != 'enabled') _fail('businessUnavailable');
  final resource = admitted.resources.single;
  // UTF8 form encoding replaces isolated UTF16 surrogates. Reject before token
  // lookup so the command can never target a silently altered identity.
  final units = resource.entityId.codeUnits;
  for (var index = 0; index < units.length; index++) {
    final unit = units[index];
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++index >= units.length ||
          units[index] < 0xdc00 ||
          units[index] > 0xdfff) {
        _fail('identityInvalid');
      }
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      _fail('identityInvalid');
    }
  }
  final expected =
      BigInt.parse(resource.revision) + BigInt.from(binding.revisionIncrement);
  if (expected > _longMaximum) _fail('revisionInvalid');
  return _PreparedBusiness(resource.entityId, resource.revision, expected);
}

CncfDisplayBusinessResult _decodeBusinessResult(
  String raw,
  CncfDisplayBusinessBinding binding,
  _PreparedBusiness request,
) {
  final wire = _mutationEnvelope(raw);
  _keys(wire, {'resourceId', 'revision', 'outcome'});
  final resourceId = _id(wire['resourceId']);
  if (resourceId != request.resourceId) _fail('resourceMismatch');
  final outcome = _text(wire['outcome']);
  if (outcome != binding.expectedOutcome) _fail('outcomeInvalid');
  final revision = _integerLexeme(wire['revision'], BigInt.one, _longMaximum);
  if (BigInt.parse(revision) != request.expectedRevision) {
    _fail('receiptRevisionInvalid');
  }
  return CncfDisplayBusinessResult._(
    binding: binding,
    resourceId: resourceId,
    revision: revision,
    outcome: outcome,
  );
}
