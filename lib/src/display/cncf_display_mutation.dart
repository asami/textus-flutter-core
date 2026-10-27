part of 'cncf_display_read.dart';

/// A field identity scoped by the selected Detail section.
final class CncfDisplayFieldLocator {
  const CncfDisplayFieldLocator(this.sectionId, this.fieldId);
  final String sectionId;
  final String fieldId;

  @override
  bool operator ==(Object other) =>
      other is CncfDisplayFieldLocator &&
      sectionId == other.sectionId &&
      fieldId == other.fieldId;
  @override
  int get hashCode => Object.hash(sectionId, fieldId);
}

/// Exact Text code units; empty text is left to server domain admission.
final class CncfDisplayTextChange {
  const CncfDisplayTextChange(this.locator, this.text);
  final CncfDisplayFieldLocator locator;
  final String text;
}

/// Ordered inert field metadata. An editable hint grants no authorization.
final class CncfDisplayMutationField {
  const CncfDisplayMutationField._(
    this.locator,
    this.editability,
    this.bindingId,
    this.acceptedKinds,
    this.web,
  );
  final CncfDisplayFieldLocator locator;
  final String editability;
  final String? bindingId;
  final List<String> acceptedKinds;
  final Map<String, Object?> web;
  bool get isEditableText =>
      editability == 'editable' &&
      bindingId != null &&
      acceptedKinds.contains('text') &&
      [
        'hidden',
        'system',
        'readonly',
        'multiple',
      ].every((key) => web[key] == false);
}

/// Strict descriptor checked against caller-selected source and revisions.
final class CncfDisplayMutationDescriptor {
  const CncfDisplayMutationDescriptor._(this.wire, this.fields);
  final Map<String, Object?> wire;
  final List<CncfDisplayMutationField> fields;
  String get componentId => wire['componentId']! as String;
  String get resourceType => wire['resourceType']! as String;
  Map<String, Object?> get definition => _object(wire['definition']);
  Map<String, Object?> get provenance => _object(wire['provenance']);
  Map<String, Object?> get capabilities => _object(wire['capabilities']);
  Map<String, Object?> get availability => _object(wire['availability']);
  bool supports(String operation) => capabilities[operation] == 'supported';
  bool isAvailable(String operation) => availability[operation] == 'enabled';
}

/// An admitted authoritative receipt, with an optional current Detail projection.
/// Revision is the exact positive Long spelling, including on web targets.
final class CncfDisplayMutationResult {
  const CncfDisplayMutationResult._({
    required this.descriptor,
    required this.outcome,
    required this.resourceId,
    required this.revision,
    required this.display,
    required this.pendingReason,
    required this.presentationContext,
  });
  final CncfDisplayMutationDescriptor descriptor;
  final String outcome;
  final String resourceId;
  final String revision;
  final CncfDisplayRead? display;
  final String? pendingReason;

  /// Outer acknowledgement context only; absence remains observable as absence.
  final Map<String, Object?>? presentationContext;
  bool get retryCommand => false;
  bool get reloadRequired => display == null;
}

/// Structured Conclusion retained for reconciliation, never message-based logic.
final class CncfDisplayFailure {
  const CncfDisplayFailure._(
    this.conclusion,
    this.category,
    this.symptom,
    this.diagnosticCode,
    this.diagnosticPath,
    this.facets,
    this.fieldLocator,
  );
  final Map<String, Object?> conclusion;
  final String category;
  final String symptom;
  final String? diagnosticCode;
  final String? diagnosticPath;
  final List<Object?> facets;
  final CncfDisplayFieldLocator? fieldLocator;

  /// Exact JSON number token retained in Conclusion metadata, without coercion.
  /// Returns null for all other values, including a numeric-looking String.
  static String? numberLexeme(Object? value) =>
      value is _JsonNumber ? value.lexeme : null;

  bool get isConflict => category == 'operation' && symptom == 'conflict';
  bool get isEditableRejection => fieldLocator != null;
  bool get reconciliationRequired => !isEditableRejection;
  @override
  String toString() => 'CncfDisplayFailure';
}

const _mutationOperations = {'read', 'query', 'create', 'update', 'delete'};
final _longMaximum = BigInt.parse('9223372036854775807');

void _requireMutationProfile(CncfDisplayReadProfile profile) {
  if (profile.mutationRevision == null) _fail('mutationUnconfigured');
}

Map<String, Object?> _mutationDefinition(CncfDisplayReadProfile profile) => {
  'screenId': profile.detailScreenId,
  'revision': profile.definitionRevision,
  'mutationRevision': profile.mutationRevision,
};

void _mutationSelection(
  Map<String, Object?> wire,
  CncfDisplayReadProfile profile,
) {
  _requireMutationProfile(profile);
  if (wire['componentId'] != profile.componentId ||
      wire['resourceType'] != profile.resourceType) {
    _fail('sourceMismatch');
  }
  final definition = _object(wire['definition']);
  _keys(definition, {'screenId', 'revision', 'mutationRevision'});
  if (!_equal(definition, _mutationDefinition(profile))) {
    _fail('definitionMismatch');
  }
  final provenance = _object(wire['provenance']);
  _keys(provenance, {'producerId', 'sourceId', 'revision'});
  for (final value in provenance.values) {
    _id(value);
  }
  if (!_equal(provenance, profile.provenance)) _fail('metadataMismatch');
}

Map<String, Object?> _mutationEnvelope(String raw) {
  final envelope = _object(_StrictMutationJson(raw).parse());
  // The framework may also carry envelope metadata; data is the sole payload.
  return _object(envelope['data']);
}

void _mutationProtocol(Map<String, Object?> wire, String schema) {
  if (wire['schema'] != schema ||
      _integerLexeme(wire['version'], BigInt.one, BigInt.one) != '1') {
    _fail('protocolIncompatible');
  }
}

CncfDisplayMutationDescriptor _decodeMutationDescriptor(
  String raw,
  CncfDisplayReadProfile profile,
) {
  final wire = _mutationEnvelope(raw);
  _keys(wire, {
    'schema',
    'version',
    'componentId',
    'resourceType',
    'definition',
    'provenance',
    'capabilities',
    'availability',
    'fields',
  });
  _mutationProtocol(wire, 'cncf.display-mutation-descriptor.v1');
  _mutationSelection(wire, profile);
  for (final entry in [
    ('capabilities', {'supported', 'unsupported'}),
    ('availability', {'enabled', 'disabled', 'hidden'}),
  ]) {
    final values = _object(wire[entry.$1]);
    _keys(values, _mutationOperations);
    if (values.values.any((value) => !entry.$2.contains(value))) {
      _fail('mutationStateInvalid');
    }
  }
  final locations = <CncfDisplayFieldLocator>{};
  final bindings = <String>{};
  final fields = <CncfDisplayMutationField>[];
  for (final value in _array(wire['fields'])) {
    final field = _object(value);
    _keys(
      field,
      {'sectionId', 'fieldId', 'editability', 'acceptedKinds', 'web'},
      optional: {'bindingId'},
    );
    final locator = CncfDisplayFieldLocator(
      _id(field['sectionId']),
      _id(field['fieldId']),
    );
    if (!locations.add(locator)) _fail('duplicateField');
    final editability = _text(field['editability']);
    if (!{'editable', 'read-only'}.contains(editability)) {
      _fail('editabilityInvalid');
    }
    final binding = field.containsKey('bindingId')
        ? _id(field['bindingId'])
        : null;
    if (binding != null && !bindings.add(binding)) _fail('duplicateBinding');
    if (editability == 'editable' && binding == null) _fail('bindingRequired');
    final kinds = _array(field['acceptedKinds']).map(_text).toList();
    if (kinds.isEmpty ||
        kinds.toSet().length != kinds.length ||
        kinds.any(
          (kind) => !{
            'text',
            'number',
            'boolean',
            'timestamp',
            'missing',
          }.contains(kind),
        )) {
      _fail('valueKindUnsupported');
    }
    final web = _object(field['web']);
    _keys(
      web,
      {'hidden', 'system', 'readonly', 'multiple', 'values', 'validation'},
      optional: {'controlType', 'required', 'placeholder', 'help'},
    );
    for (final flag in [
      'hidden',
      'system',
      'readonly',
      'multiple',
      'required',
    ]) {
      if (web.containsKey(flag) && web[flag] is! bool) _fail('hintInvalid');
    }
    for (final hint in ['controlType', 'placeholder', 'help']) {
      if (web.containsKey(hint)) _text(web[hint]);
    }
    for (final option in _array(web['values'])) {
      _text(option);
    }
    final validation = _object(web['validation']);
    _keys(
      validation,
      {},
      optional: {'min', 'max', 'step', 'minLength', 'maxLength', 'pattern'},
    );
    for (final key in ['min', 'max', 'step']) {
      if (validation.containsKey(key)) {
        _canonicalDecimal(_text(validation[key]));
      }
    }
    for (final key in ['minLength', 'maxLength']) {
      if (validation.containsKey(key)) {
        _integerLexeme(validation[key], BigInt.zero, BigInt.from(2147483647));
      }
    }
    if (validation.containsKey('pattern')) _text(validation['pattern']);
    fields.add(
      CncfDisplayMutationField._(
        locator,
        editability,
        binding,
        List.unmodifiable(kinds),
        _object(_freeze(_ordinaryMutationJson(web))),
      ),
    );
  }
  return CncfDisplayMutationDescriptor._(
    _object(_freeze(_ordinaryMutationJson(wire))),
    List.unmodifiable(fields),
  );
}

final class _PreparedTextUpdate {
  const _PreparedTextUpdate(this.body, this.revision, this.requestedFields);
  final String body;
  final String revision;
  final Set<CncfDisplayFieldLocator> requestedFields;
}

_PreparedTextUpdate _prepareTextUpdate(
  CncfDisplayReadProfile profile,
  CncfDisplayMutationDescriptor descriptor,
  CncfDisplayRead observation,
  List<CncfDisplayTextChange> changes,
) {
  _mutationSelection(descriptor.wire, profile);
  final admitted = CncfDisplayRead.decode(
    observation.wire,
    profile,
    detail: true,
    expectedResourceId: observation.resources.length == 1
        ? observation.resources.single.entityId
        : null,
  );
  if (admitted.resources.length != 1) _fail('resourceMismatch');
  final resource = admitted.resources.single;
  if (!descriptor.supports('update')) _fail('mutationUnsupported');
  if (!descriptor.isAvailable('update')) _fail('mutationUnavailable');
  if (changes.isEmpty) _fail('changesRequired');
  final requested = <CncfDisplayFieldLocator>{};
  final entries = <Map<String, Object?>>[];
  for (final change in changes) {
    _id(change.locator.sectionId);
    _id(change.locator.fieldId);
    if (!requested.add(change.locator)) _fail('duplicateField');
    final fields = descriptor.fields.where(
      (field) => field.locator == change.locator,
    );
    if (fields.length != 1) _fail('fieldUnknown');
    if (!fields.single.isEditableText) _fail('fieldNotEditableText');
    entries.add({
      'sectionId': change.locator.sectionId,
      'fieldId': change.locator.fieldId,
      'value': {'type': 'text', 'text': change.text},
    });
  }
  return _PreparedTextUpdate(
    _renderMutationJson({
      'schema': 'cncf.display-mutation.v1',
      'version': 1,
      'resourceType': profile.resourceType,
      'definition': descriptor.definition,
      'provenance': descriptor.provenance,
      'resourceId': resource.entityId,
      'changes': entries,
    }),
    resource.revision,
    Set.unmodifiable(requested),
  );
}

CncfDisplayMutationResult _decodeMutationResult(
  String raw,
  CncfDisplayReadProfile profile,
  CncfDisplayMutationDescriptor descriptor,
  CncfDisplayRead observation,
) {
  final wire = _mutationEnvelope(raw);
  _keys(
    wire,
    {
      'schema',
      'version',
      'componentId',
      'resourceType',
      'definition',
      'provenance',
      'outcome',
      'resource',
      'projection',
      'retryCommand',
    },
    optional: {'presentationContext'},
  );
  _mutationProtocol(wire, 'cncf.display-mutation-result.v1');
  _mutationSelection(wire, profile);
  final outcome = _text(wire['outcome']);
  if (!{'updated', 'unchanged'}.contains(outcome)) _fail('outcomeInvalid');
  if (wire['retryCommand'] != false) _fail('retryCommandInvalid');
  final resource = _object(wire['resource']);
  _keys(resource, {'entityId', 'revision'});
  final original = observation.resources.single;
  final id = _id(resource['entityId']);
  if (id != original.entityId) _fail('resourceMismatch');
  final revision = _integerLexeme(
    resource['revision'],
    BigInt.one,
    _longMaximum,
  );
  final observed = BigInt.parse(original.revision);
  final expected = outcome == 'unchanged' ? observed : observed + BigInt.one;
  if (expected > _longMaximum || BigInt.parse(revision) != expected) {
    _fail('receiptRevisionInvalid');
  }
  final projection = _object(wire['projection']);
  CncfDisplayRead? display;
  String? reason;
  switch (projection['type']) {
    case 'ready':
      _keys(projection, {'type', 'display'});
      _readIntegerLexemes(projection['display'], profile);
      display = CncfDisplayRead.decode(
        _object(_ordinaryMutationJson(projection['display'])),
        profile,
        detail: true,
        expectedResourceId: id,
      );
      if (display.resources.single.revision != revision) {
        _fail('receiptRevisionInvalid');
      }
    case 'pending':
      _keys(projection, {'type', 'reason'});
      reason = _text(projection['reason']);
      if (!{'view-not-current', 'projection-unavailable'}.contains(reason)) {
        _fail('projectionInvalid');
      }
    default:
      _fail('projectionInvalid');
  }
  if (wire.containsKey('presentationContext')) {
    _contextIntegerLexemes(wire['presentationContext']);
  }
  final context = wire.containsKey('presentationContext')
      ? _context(_freeze(_ordinaryMutationJson(wire['presentationContext'])))
      : null;
  if (context != null &&
      display != null &&
      !_equal(context, display.presentationContext)) {
    _fail('contextMismatch');
  }
  return CncfDisplayMutationResult._(
    descriptor: descriptor,
    outcome: outcome,
    resourceId: id,
    revision: revision,
    display: display,
    pendingReason: reason,
    presentationContext: context,
  );
}

CncfDisplayFailure _decodeDisplayFailure(
  String raw,
  CncfDisplayReadProfile profile,
  Set<CncfDisplayFieldLocator> requested,
) {
  final envelope = _object(_StrictMutationJson(raw).parse());
  final error = _object(envelope['error']);
  final conclusion = _object(error['conclusion']);
  final observation = _object(conclusion['observation']);
  final taxonomy = _object(observation['taxonomy']);
  final category = _id(taxonomy['category']);
  final symptom = _id(taxonomy['symptom']);
  final cause = _object(observation['cause']);
  final facets = _array(cause['facets']);
  String? code;
  String? path;
  if (cause.containsKey('diagnostic')) {
    final diagnostic = _object(cause['diagnostic']);
    code = _text(diagnostic['code']);
    path = _text(diagnostic['path']);
  }
  CncfDisplayFieldLocator? locator;
  if (category == 'argument' &&
      symptom == 'invalid' &&
      code == 'DSP96_MUTATION_VALUE_INVALID') {
    for (final field in requested) {
      if (path ==
          '${profile.detailScreenId}/${field.sectionId}/${field.fieldId}') {
        locator = field;
      }
    }
  }
  return CncfDisplayFailure._(
    _object(_freezeFailureJson(conclusion)),
    category,
    symptom,
    code,
    path,
    _freezeFailureJson(facets)! as List<Object?>,
    locator,
  );
}

// Conclusion metadata is retained rather than interpreted. Every number keeps
// its original token, including Longs and arbitrary valid decimal/exponent JSON.
Object? _freezeFailureJson(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.unmodifiable(
      value.map((key, item) => MapEntry(key, _freezeFailureJson(item))),
    );
  }
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(value.map(_freezeFailureJson));
  }
  if (value == null ||
      value is String ||
      value is bool ||
      value is _JsonNumber) {
    return value;
  }
  _fail('jsonInvalid');
}

// Number tokens remain lexical until their owning schema has checked them.
final class _JsonNumber {
  const _JsonNumber(this.lexeme);
  final String lexeme;
}

String _integerLexeme(Object? value, BigInt minimum, BigInt maximum) {
  if (value is! _JsonNumber ||
      !RegExp(r'^(?:0|[1-9][0-9]*)$').hasMatch(value.lexeme)) {
    _fail('integerLiteralInvalid');
  }
  final number = BigInt.parse(value.lexeme);
  if (number < minimum || number > maximum) _fail('integerLiteralInvalid');
  return value.lexeme;
}

// Only schema-owned integer paths carry structural authority. Unknown-family
// data remains ordinary JSON, including properties coincidentally named version.
void _readIntegerLexemes(Object? value, CncfDisplayReadProfile profile) {
  final wire = _object(value);
  _integerLexeme(wire['version'], BigInt.one, BigInt.one);
  _integerLexeme(_object(wire['abi'])['version'], BigInt.one, BigInt.one);
  final semanticVersion = profile.semanticContract['version'];
  if (semanticVersion is int) {
    final pinned = BigInt.from(semanticVersion);
    _integerLexeme(
      _object(wire['semanticContract'])['version'],
      pinned,
      pinned,
    );
  }
  if (wire.containsKey('presentationContext')) {
    _contextIntegerLexemes(wire['presentationContext']);
  }
}

void _contextIntegerLexemes(Object? value) {
  final context = _object(value);
  _integerLexeme(context['version'], BigInt.one, BigInt.one);
  for (final family in _array(context['families'])) {
    _integerLexeme(
      _object(family)['version'],
      BigInt.one,
      BigInt.from(2147483647),
    );
  }
}

// Schema-owned scalars are admitted before ordinary decoding. Outer receipt
// revisions and immutable Conclusion tokens never pass through this bridge.
Object? _ordinaryMutationJson(Object? value) =>
    jsonDecode(_renderMutationJson(value));

void _canonicalDecimal(String text) {
  final match = RegExp(r'^(-?)([0-9]+)(?:\.([0-9]+))?(?:E([+-]?[0-9]+))?$')
      .firstMatch(text);
  if (match == null) _fail('decimalInvalid');
  final fraction = match.group(3) ?? '';
  final scale =
      BigInt.from(fraction.length) - BigInt.parse(match.group(4) ?? '0');
  if (scale < BigInt.from(-2147483648) || scale > BigInt.from(2147483647)) {
    _fail('decimalInvalid');
  }
  final digits = (match.group(2)! + fraction).replaceFirst(RegExp(r'^0+'), '');
  final coefficient = digits.isEmpty ? '0' : digits;
  final sign = digits.isEmpty ? '' : match.group(1)!;
  final adjusted = BigInt.from(coefficient.length - 1) - scale;
  String canonical;
  if (scale >= BigInt.zero && adjusted >= BigInt.from(-6)) {
    final point = coefficient.length - scale.toInt();
    canonical = point > 0
        ? coefficient.substring(0, point) +
              (point == coefficient.length
                  ? ''
                  : '.${coefficient.substring(point)}')
        : '0.${'0' * -point}$coefficient';
  } else {
    final mantissa = coefficient.length == 1
        ? coefficient
        : '${coefficient[0]}.${coefficient.substring(1)}';
    canonical =
        '$mantissa'
        'E${adjusted >= BigInt.zero ? '+' : ''}$adjusted';
  }
  if ('$sign$canonical' != text) _fail('decimalInvalid');
}

String _renderMutationJson(Object? value) {
  if (value == null) return 'null';
  if (value is _JsonNumber) return value.lexeme;
  if (value is String) {
    final result = StringBuffer('"');
    for (final unit in value.codeUnits) {
      switch (unit) {
        case 0x22:
          result.write(r'\"');
        case 0x5c:
          result.write(r'\\');
        case 0x08:
          result.write(r'\b');
        case 0x0c:
          result.write(r'\f');
        case 0x0a:
          result.write(r'\n');
        case 0x0d:
          result.write(r'\r');
        case 0x09:
          result.write(r'\t');
        default:
          if (unit < 0x20 || unit > 0x7e) {
            result.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
          } else {
            result.writeCharCode(unit);
          }
      }
    }
    return (result..write('"')).toString();
  }
  if (value is Map<String, Object?>) {
    return '{${value.entries.map((entry) => '${_renderMutationJson(entry.key)}:${_renderMutationJson(entry.value)}').join(',')}}';
  }
  if (value is List) return '[${value.map(_renderMutationJson).join(',')}]';
  if (value is bool || value is int) return value.toString();
  _fail('jsonInvalid');
}

/// Bounded JSON syntax parser with decoded-key uniqueness and number lexemes.
final class _StrictMutationJson {
  _StrictMutationJson(this.source);
  final String source;
  int offset = 0;

  Object? parse() {
    if (utf8.encode(source).length > 262144) _fail('responseTooLarge');
    final value = _value(0);
    _space();
    if (offset != source.length) _fail('jsonInvalid');
    return value;
  }

  void _space() {
    while (offset < source.length && ' \r\n\t'.contains(source[offset])) {
      offset++;
    }
  }

  Object? _value(int depth) {
    _space();
    if (offset >= source.length) _fail('jsonInvalid');
    final char = source[offset];
    if (char == '"') return _string();
    if (char == '{' || char == '[') {
      if (depth >= 64) _fail('jsonDepthExceeded');
      offset++;
      _space();
      if (char == '{') {
        final result = <String, Object?>{};
        if (_take('}')) return result;
        do {
          _space();
          if (offset >= source.length || source[offset] != '"') {
            _fail('jsonInvalid');
          }
          final key = _string();
          if (result.containsKey(key)) _fail('duplicateJsonMember');
          _space();
          if (!_take(':')) _fail('jsonInvalid');
          result[key] = _value(depth + 1);
          _space();
          if (_take('}')) return result;
        } while (_take(','));
      } else {
        final result = <Object?>[];
        if (_take(']')) return result;
        do {
          result.add(_value(depth + 1));
          _space();
          if (_take(']')) return result;
        } while (_take(','));
      }
      _fail('jsonInvalid');
    }
    for (final entry in [('true', true), ('false', false), ('null', null)]) {
      if (source.startsWith(entry.$1, offset)) {
        offset += entry.$1.length;
        return entry.$2;
      }
    }
    final number = RegExp(
      r'-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?',
    ).matchAsPrefix(source, offset);
    if (number == null) _fail('jsonInvalid');
    offset = number.end;
    return _JsonNumber(number.group(0)!);
  }

  bool _take(String char) {
    if (offset < source.length && source[offset] == char) {
      offset++;
      return true;
    }
    return false;
  }

  String _string() {
    final start = offset++;
    while (offset < source.length) {
      final unit = source.codeUnitAt(offset++);
      if (unit == 0x22) {
        try {
          return jsonDecode(source.substring(start, offset)) as String;
        } catch (_) {
          _fail('jsonInvalid');
        }
      }
      if (unit < 0x20) _fail('jsonInvalid');
      if (unit == 0x5c) {
        if (offset >= source.length) _fail('jsonInvalid');
        offset++;
      }
    }
    _fail('jsonInvalid');
  }
}
