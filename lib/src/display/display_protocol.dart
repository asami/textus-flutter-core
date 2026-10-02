/// Candidate, development-only Display value and projection contracts.
library;

/// A typed presentation value, distinct from editable semantic input metadata.
sealed class DisplayValue {
  const DisplayValue();

  /// Decodes the closed candidate value shape.
  factory DisplayValue.fromJson(Map<String, Object?> json) {
    final type = _string(json['type']);
    _keys(json, type == 'missing' ? ['type'] : ['type', 'value']);
    return switch (type) {
      'text' => TextDisplayValue(_string(json['value'])),
      'number' => NumberDisplayValue(_number(json['value'])),
      'bool' => BoolDisplayValue(_bool(json['value'])),
      'timestamp' => TimestampDisplayValue(_instant(json['value'])),
      'missing' => const MissingDisplayValue(),
      _ => throw FormatException('Unknown Display value type: $type'),
    };
  }

  /// Encodes this value without normalizing text.
  Map<String, Object?> toJson();

  @override
  bool operator ==(Object other) =>
      other is DisplayValue && _equal(toJson(), other.toJson());
  @override
  int get hashCode => _hash(toJson());
}

/// Byte-preserving text, including an empty draft.
final class TextDisplayValue extends DisplayValue {
  const TextDisplayValue(this.value);
  final String value;
  @override
  Map<String, Object?> toJson() => {'type': 'text', 'value': value};
}

/// A finite JSON number.
final class NumberDisplayValue extends DisplayValue {
  NumberDisplayValue(num value) : value = _number(value);
  final num value;
  @override
  Map<String, Object?> toJson() => {'type': 'number', 'value': value};
}

/// A boolean presentation value.
final class BoolDisplayValue extends DisplayValue {
  const BoolDisplayValue(this.value);
  final bool value;
  @override
  Map<String, Object?> toJson() => {'type': 'bool', 'value': value};
}

/// An explicit UTC instant; local timestamps are never inferred.
final class TimestampDisplayValue extends DisplayValue {
  TimestampDisplayValue(DateTime value) : value = _utc(value);
  final DateTime value;
  @override
  Map<String, Object?> toJson() => {
    'type': 'timestamp',
    'value': value.toIso8601String(),
  };
}

/// Explicit absence, distinct from null and empty text.
final class MissingDisplayValue extends DisplayValue {
  const MissingDisplayValue();
  @override
  Map<String, Object?> toJson() => {'type': 'missing'};
}

/// The complete scoped identity of a projected field.
final class DisplayFieldLocator {
  DisplayFieldLocator({
    required String screenId,
    required String sectionId,
    required String fieldId,
  }) : screenId = _id(screenId),
       sectionId = _id(sectionId),
       fieldId = _id(fieldId);
  final String screenId;
  final String sectionId;
  final String fieldId;
  factory DisplayFieldLocator.fromJson(Map<String, Object?> json) {
    _keys(json, ['screenId', 'sectionId', 'fieldId']);
    return DisplayFieldLocator(
      screenId: _id(json['screenId']),
      sectionId: _id(json['sectionId']),
      fieldId: _id(json['fieldId']),
    );
  }
  Map<String, Object?> toJson() => {
    'screenId': screenId,
    'sectionId': sectionId,
    'fieldId': fieldId,
  };
  @override
  bool operator ==(Object other) =>
      other is DisplayFieldLocator &&
      screenId == other.screenId &&
      sectionId == other.sectionId &&
      fieldId == other.fieldId;
  @override
  int get hashCode => Object.hash(screenId, sectionId, fieldId);
}

/// Presentation only; editing information lives in [DisplayEditBinding].
final class DisplayField {
  DisplayField({
    required String id,
    required this.label,
    required String role,
    required this.value,
  }) : id = _id(id),
       role = _id(role);
  final String id;
  final String label;
  final String role;
  final DisplayValue value;
  factory DisplayField.fromJson(Map<String, Object?> json) {
    _keys(json, ['id', 'label', 'role', 'value']);
    return DisplayField(
      id: _id(json['id']),
      label: _string(json['label']),
      role: _id(json['role']),
      value: DisplayValue.fromJson(_map(json['value'])),
    );
  }
  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'role': role,
    'value': value.toJson(),
  };
}

/// An ordered section whose field IDs are unique within the section.
final class DisplaySection {
  DisplaySection({required String id, required List<DisplayField> fields})
    : id = _id(id),
      fields = _unique(fields, (field) => field.id);
  final String id;
  final List<DisplayField> fields;
  factory DisplaySection.fromJson(Map<String, Object?> json) {
    _keys(json, ['id', 'fields']);
    return DisplaySection(
      id: _id(json['id']),
      fields: _decodeList(json['fields'], DisplayField.fromJson),
    );
  }
  Map<String, Object?> toJson() => {
    'id': id,
    'fields': fields.map((field) => field.toJson()).toList(),
  };
}

/// An availability descriptor, never execution authority or an endpoint.
final class DisplayAction {
  DisplayAction({
    required String id,
    required this.label,
    required this.enabled,
  }) : id = _id(id);
  final String id;
  final String label;
  final bool enabled;
  factory DisplayAction.fromJson(Map<String, Object?> json) {
    _keys(json, ['id', 'label', 'enabled']);
    return DisplayAction(
      id: _id(json['id']),
      label: _string(json['label']),
      enabled: _bool(json['enabled']),
    );
  }
  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'enabled': enabled,
  };
}

/// Producer and source identity with a distinct resource or snapshot revision.
final class DisplayProvenance {
  DisplayProvenance({
    required String producerId,
    required String sourceId,
    required String revision,
  }) : producerId = _id(producerId),
       sourceId = _id(sourceId),
       revision = _id(revision);
  final String producerId;
  final String sourceId;
  final String revision;
  factory DisplayProvenance.fromJson(Map<String, Object?> json) {
    _keys(json, ['producerId', 'sourceId', 'revision']);
    return DisplayProvenance(
      producerId: _id(json['producerId']),
      sourceId: _id(json['sourceId']),
      revision: _id(json['revision']),
    );
  }
  Map<String, Object?> toJson() => {
    'producerId': producerId,
    'sourceId': sourceId,
    'revision': revision,
  };
}

/// Semantic input beside a presentation field, with no inverse projection.
final class DisplayEditBinding {
  DisplayEditBinding({
    required this.locator,
    required this.writable,
    required this.inputValue,
    required this.requiredNonBlank,
  }) {
    if (!writable && (inputValue is! MissingDisplayValue || requiredNonBlank)) {
      throw const FormatException(
        'Read-only input must be missing/unconstrained',
      );
    }
  }
  final DisplayFieldLocator locator;
  final bool writable;
  final DisplayValue inputValue;
  final bool requiredNonBlank;
  factory DisplayEditBinding.fromJson(Map<String, Object?> json) {
    _keys(json, ['locator', 'writable', 'inputValue', 'requiredNonBlank']);
    return DisplayEditBinding(
      locator: DisplayFieldLocator.fromJson(_map(json['locator'])),
      writable: _bool(json['writable']),
      inputValue: DisplayValue.fromJson(_map(json['inputValue'])),
      requiredNonBlank: _bool(json['requiredNonBlank']),
    );
  }
  Map<String, Object?> toJson() => {
    'locator': locator.toJson(),
    'writable': writable,
    'inputValue': inputValue.toJson(),
    'requiredNonBlank': requiredNonBlank,
  };
}

/// A list row, never an eager Detail.
final class DisplayResourceSummary {
  DisplayResourceSummary({
    required String resourceId,
    required int sourceRevision,
    required List<DisplayField> fields,
  }) : resourceId = _id(resourceId),
       sourceRevision = _positive(sourceRevision),
       fields = _unique(fields, (field) => field.id);
  final String resourceId;
  final int sourceRevision;
  final List<DisplayField> fields;
  factory DisplayResourceSummary.fromJson(Map<String, Object?> json) {
    _keys(json, ['resourceId', 'sourceRevision', 'fields']);
    return DisplayResourceSummary(
      resourceId: _id(json['resourceId']),
      sourceRevision: _positive(json['sourceRevision']),
      fields: _decodeList(json['fields'], DisplayField.fromJson),
    );
  }
  Map<String, Object?> toJson() => {
    'resourceId': resourceId,
    'sourceRevision': sourceRevision,
    'fields': fields.map((field) => field.toJson()).toList(),
  };
}

/// Ordered presentation list and logical Detail screen target.
final class DisplayListModel {
  DisplayListModel({
    required String screenId,
    required this.title,
    required String detailScreenId,
    required List<DisplayResourceSummary> items,
  }) : screenId = _id(screenId),
       detailScreenId = _id(detailScreenId),
       items = _unique(items, (item) => item.resourceId);
  final String screenId;
  final String title;
  final String detailScreenId;
  final List<DisplayResourceSummary> items;
  factory DisplayListModel.fromJson(Map<String, Object?> json) {
    _keys(json, ['screenId', 'title', 'detailScreenId', 'items']);
    return DisplayListModel(
      screenId: _id(json['screenId']),
      title: _string(json['title']),
      detailScreenId: _id(json['detailScreenId']),
      items: _decodeList(json['items'], DisplayResourceSummary.fromJson),
    );
  }
  Map<String, Object?> toJson() => {
    'screenId': screenId,
    'title': title,
    'detailScreenId': detailScreenId,
    'items': items.map((item) => item.toJson()).toList(),
  };
}

/// Ordered Detail presentation, independent of source input metadata.
final class DisplayDetailModel {
  DisplayDetailModel({
    required String screenId,
    required this.title,
    required List<DisplaySection> sections,
    required List<DisplayAction> actions,
  }) : screenId = _id(screenId),
       sections = _unique(sections, (section) => section.id),
       actions = _unique(actions, (action) => action.id);
  final String screenId;
  final String title;
  final List<DisplaySection> sections;
  final List<DisplayAction> actions;
  factory DisplayDetailModel.fromJson(Map<String, Object?> json) {
    _keys(json, ['screenId', 'title', 'sections', 'actions']);
    return DisplayDetailModel(
      screenId: _id(json['screenId']),
      title: _string(json['title']),
      sections: _decodeList(json['sections'], DisplaySection.fromJson),
      actions: _decodeList(json['actions'], DisplayAction.fromJson),
    );
  }
  Map<String, Object?> toJson() => {
    'screenId': screenId,
    'title': title,
    'sections': sections.map((section) => section.toJson()).toList(),
    'actions': actions.map((action) => action.toJson()).toList(),
  };
}

/// List metadata beside its presentation model.
final class DisplayListData {
  DisplayListData({
    required String resourceType,
    required String snapshotId,
    required this.provenance,
    required this.model,
  }) : resourceType = _id(resourceType),
       snapshotId = _id(snapshotId) {
    if (provenance.revision != snapshotId) {
      throw const FormatException(
        'List provenance must equal snapshot identity',
      );
    }
  }
  final String resourceType;
  final String snapshotId;
  final DisplayProvenance provenance;
  final DisplayListModel model;
  factory DisplayListData.fromJson(Map<String, Object?> json) {
    _keys(json, ['metadata', 'model']);
    final metadata = _map(json['metadata']);
    _keys(metadata, ['resourceType', 'snapshotId', 'provenance']);
    return DisplayListData(
      resourceType: _id(metadata['resourceType']),
      snapshotId: _id(metadata['snapshotId']),
      provenance: DisplayProvenance.fromJson(_map(metadata['provenance'])),
      model: DisplayListModel.fromJson(_map(json['model'])),
    );
  }
  Map<String, Object?> toJson() => {
    'metadata': {
      'resourceType': resourceType,
      'snapshotId': snapshotId,
      'provenance': provenance.toJson(),
    },
    'model': model.toJson(),
  };
}

/// Exact resource revision and scoped bindings beside Detail presentation.
final class DisplayDetailData {
  DisplayDetailData({
    required String resourceId,
    required int sourceRevision,
    required this.provenance,
    required List<DisplayEditBinding> bindings,
    required this.model,
  }) : resourceId = _id(resourceId),
       sourceRevision = _positive(sourceRevision),
       bindings = List.unmodifiable(bindings) {
    if (provenance.revision != sourceRevision.toString()) {
      throw const FormatException(
        'Detail provenance must equal source revision',
      );
    }
    final seen = <DisplayFieldLocator>{};
    for (final binding in bindings) {
      final locator = binding.locator;
      if (!seen.add(locator) ||
          locator.screenId != model.screenId ||
          model.sections
                  .where((section) => section.id == locator.sectionId)
                  .expand((section) => section.fields)
                  .where((field) => field.id == locator.fieldId)
                  .length !=
              1) {
        throw const FormatException(
          'Binding must uniquely resolve its scoped field',
        );
      }
    }
  }
  final String resourceId;
  final int sourceRevision;
  final DisplayProvenance provenance;
  final List<DisplayEditBinding> bindings;
  final DisplayDetailModel model;
  factory DisplayDetailData.fromJson(Map<String, Object?> json) {
    _keys(json, ['metadata', 'model']);
    final metadata = _map(json['metadata']);
    _keys(metadata, ['resourceId', 'sourceRevision', 'provenance', 'bindings']);
    return DisplayDetailData(
      resourceId: _id(metadata['resourceId']),
      sourceRevision: _positive(metadata['sourceRevision']),
      provenance: DisplayProvenance.fromJson(_map(metadata['provenance'])),
      bindings: _decodeList(metadata['bindings'], DisplayEditBinding.fromJson),
      model: DisplayDetailModel.fromJson(_map(json['model'])),
    );
  }
  Map<String, Object?> toJson() => {
    'metadata': {
      'resourceId': resourceId,
      'sourceRevision': sourceRevision,
      'provenance': provenance.toJson(),
      'bindings': bindings.map((binding) => binding.toJson()).toList(),
    },
    'model': model.toJson(),
  };
}

/// A scoped validation error or a global error when locator is absent.
final class DisplayFieldError {
  DisplayFieldError({
    required this.locator,
    required String code,
    required this.message,
  }) : code = _id(code);
  final DisplayFieldLocator? locator;
  final String code;
  final String message;
  factory DisplayFieldError.fromJson(Map<String, Object?> json) {
    _keys(json, ['locator', 'code', 'message']);
    return DisplayFieldError(
      locator: json['locator'] == null
          ? null
          : DisplayFieldLocator.fromJson(_map(json['locator'])),
      code: _id(json['code']),
      message: _string(json['message']),
    );
  }
  Map<String, Object?> toJson() => {
    'locator': locator?.toJson(),
    'code': code,
    'message': message,
  };
}

/// Decoded command outcomes, distinct from transport failures.
enum DisplayCommandOutcome { changed, noOp, rejected, conflict, unsupported }

/// A Display command receipt; a stale projection can accompany a committed write.
final class DisplayMutationResult {
  DisplayMutationResult({
    required String resourceId,
    required this.outcome,
    required this.currentRevision,
    required this.committedRevision,
    required List<DisplayFieldError> fieldErrors,
    required this.message,
    required this.display,
  }) : resourceId = _id(resourceId),
       fieldErrors = List.unmodifiable(fieldErrors) {
    _receipt(outcome, currentRevision, committedRevision);
    if ((display != null && display!.resourceId != resourceId) ||
        (display != null &&
            outcome != DisplayCommandOutcome.changed &&
            outcome != DisplayCommandOutcome.noOp)) {
      throw const FormatException('Display receipt identity/outcome mismatch');
    }
  }
  final String resourceId;
  final DisplayCommandOutcome outcome;
  final int? currentRevision;
  final int? committedRevision;
  final List<DisplayFieldError> fieldErrors;
  final String? message;
  final DisplayDetailData? display;
  factory DisplayMutationResult.fromJson(Map<String, Object?> json) {
    _keys(json, [
      'resourceId',
      'outcome',
      'currentRevision',
      'committedRevision',
      'fieldErrors',
      'message',
      'display',
    ]);
    return DisplayMutationResult(
      resourceId: _id(json['resourceId']),
      outcome: _outcome(json['outcome']),
      currentRevision: _revision(json['currentRevision']),
      committedRevision: _revision(json['committedRevision']),
      fieldErrors: _decodeList(json['fieldErrors'], DisplayFieldError.fromJson),
      message: json['message'] == null ? null : _string(json['message']),
      display: json['display'] == null
          ? null
          : DisplayDetailData.fromJson(_map(json['display'])),
    );
  }
  Map<String, Object?> toJson() => {
    'resourceId': resourceId,
    'outcome': _tag(outcome),
    'currentRevision': currentRevision,
    'committedRevision': committedRevision,
    'fieldErrors': fieldErrors.map((error) => error.toJson()).toList(),
    'message': message,
    'display': display?.toJson(),
  };
}

/// An ordinary Operation receipt with no implicit Display reload evidence.
final class DisplayOperationResult {
  DisplayOperationResult({
    required String resourceId,
    required this.outcome,
    required this.currentRevision,
    required this.committedRevision,
    required List<DisplayFieldError> fieldErrors,
    required this.message,
  }) : resourceId = _id(resourceId),
       fieldErrors = List.unmodifiable(fieldErrors) {
    _receipt(outcome, currentRevision, committedRevision);
    if (outcome == DisplayCommandOutcome.noOp) {
      throw const FormatException('Operation cannot claim noop');
    }
  }
  final String resourceId;
  final DisplayCommandOutcome outcome;
  final int? currentRevision;
  final int? committedRevision;
  final List<DisplayFieldError> fieldErrors;
  final String? message;
  factory DisplayOperationResult.fromJson(Map<String, Object?> json) {
    _keys(json, [
      'resourceId',
      'outcome',
      'currentRevision',
      'committedRevision',
      'fieldErrors',
      'message',
    ]);
    return DisplayOperationResult(
      resourceId: _id(json['resourceId']),
      outcome: _outcome(json['outcome']),
      currentRevision: _revision(json['currentRevision']),
      committedRevision: _revision(json['committedRevision']),
      fieldErrors: _decodeList(json['fieldErrors'], DisplayFieldError.fromJson),
      message: json['message'] == null ? null : _string(json['message']),
    );
  }
  Map<String, Object?> toJson() => {
    'resourceId': resourceId,
    'outcome': _tag(outcome),
    'currentRevision': currentRevision,
    'committedRevision': committedRevision,
    'fieldErrors': fieldErrors.map((error) => error.toJson()).toList(),
    'message': message,
  };
}

void _keys(Map<String, Object?> json, List<String> keys) {
  if (json.length != keys.length || !keys.every(json.containsKey)) {
    throw FormatException('Expected exactly ${keys.join(', ')}');
  }
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Expected string-keyed JSON object');
  }
  return Map<String, Object?>.from(value);
}

String _string(Object? value) {
  if (value is! String) {
    throw const FormatException('Expected string');
  }
  return value;
}

String _id(Object? value) {
  final text = _string(value);
  if (text.trim().isEmpty) {
    throw const FormatException('Identifier is blank');
  }
  return text;
}

bool _bool(Object? value) {
  if (value is! bool) {
    throw const FormatException('Expected bool');
  }
  return value;
}

num _number(Object? value) {
  if (value is! num || !value.isFinite) {
    throw const FormatException('Expected finite number');
  }
  return value;
}

int _positive(Object? value) {
  if (value is! int || value <= 0) {
    throw const FormatException('Expected positive integer');
  }
  return value;
}

int? _revision(Object? value) => value == null ? null : _positive(value);
DateTime _utc(DateTime value) {
  if (!value.isUtc) {
    throw const FormatException('Expected explicit UTC instant');
  }
  // Require the same representable calendar subset as the wire decoder.
  _instant(value.toIso8601String());
  return value;
}

DateTime _instant(Object? value) {
  final text = _string(value);
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?Z$',
  ).firstMatch(text);
  if (match == null) {
    throw const FormatException('Expected UTC ISO instant');
  }
  final parts = List.generate(6, (index) => int.parse(match.group(index + 1)!));
  final parsed = DateTime.tryParse(text);
  if (parsed == null ||
      parsed.year != parts[0] ||
      parsed.month != parts[1] ||
      parsed.day != parts[2] ||
      parsed.hour != parts[3] ||
      parsed.minute != parts[4] ||
      parsed.second != parts[5]) {
    throw const FormatException('Invalid calendar instant');
  }
  return parsed;
}

List<T> _decodeList<T>(Object? value, T Function(Map<String, Object?>) decode) {
  if (value is! List) {
    throw const FormatException('Expected array');
  }
  return value.map((item) => decode(_map(item))).toList();
}

List<T> _unique<T>(List<T> values, Object Function(T) key) {
  final keys = <Object>{};
  if (values.any((value) => !keys.add(key(value)))) {
    throw const FormatException('Duplicate identity');
  }
  return List.unmodifiable(values);
}

String _tag(DisplayCommandOutcome value) =>
    value == DisplayCommandOutcome.noOp ? 'noop' : value.name;
DisplayCommandOutcome _outcome(Object? value) {
  for (final outcome in DisplayCommandOutcome.values) {
    if (_tag(outcome) == value) {
      return outcome;
    }
  }
  throw const FormatException('Unknown command outcome');
}

void _receipt(DisplayCommandOutcome outcome, int? current, int? committed) {
  if (current != null) {
    _positive(current);
  }
  if (committed != null) {
    _positive(committed);
  }
  if (outcome == DisplayCommandOutcome.changed) {
    if (committed == null || current != committed) {
      throw const FormatException(
        'Changed requires matching committed/current revision',
      );
    }
  } else {
    if (committed != null) {
      throw const FormatException('Uncommitted outcome has a commit');
    }
    if ((outcome == DisplayCommandOutcome.noOp ||
            outcome == DisplayCommandOutcome.conflict) &&
        current == null) {
      throw const FormatException('Outcome requires current revision');
    }
  }
}

bool _equal(Object? left, Object? right) {
  if (left is Map && right is Map) {
    return left.length == right.length &&
        left.keys.every(
          (key) => right.containsKey(key) && _equal(left[key], right[key]),
        );
  }
  if (left is List && right is List) {
    return left.length == right.length &&
        List.generate(
          left.length,
          (index) => _equal(left[index], right[index]),
        ).every((value) => value);
  }
  return left == right;
}

int _hash(Object? value) {
  if (value is Map) {
    return Object.hashAllUnordered(
      value.entries.map((entry) => Object.hash(entry.key, _hash(entry.value))),
    );
  }
  if (value is List) {
    return Object.hashAll(value.map(_hash));
  }
  return value.hashCode;
}
