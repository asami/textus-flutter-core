import 'display_protocol.dart';
import 'display_prototype_fixture.dart';
import 'display_transport.dart';
import 'presentation_context.dart';
import 'scripted_display_transport.dart';

/// An immutable semantic resource, separate from its presentation projection.
final class FixtureSemanticResource {
  FixtureSemanticResource({
    required String resourceId,
    required int sourceRevision,
    required Map<String, DisplayValue> fields,
  }) : resourceId = _validId(resourceId),
       sourceRevision = _positiveRevision(sourceRevision),
       fields = Map.unmodifiable(fields) {
    for (final key in fields.keys) {
      _validId(key);
    }
  }
  final String resourceId;
  final int sourceRevision;
  final Map<String, DisplayValue> fields;
}

/// Deterministic delivery simulation; ambiguous delivery never triggers replay.
enum FixtureTransportFault {
  unavailable,
  ambiguousBeforeCommit,
  ambiguousAfterCommit,
}

/// Development-only, domain-neutral interpreter of supplied semantic mappings.
final class FixtureDisplaySource implements DisplayTransport {
  FixtureDisplaySource({
    required DisplayPrototypeFixture fixture,
    required String listTemplateId,
    required String detailTemplateId,
    required String componentId,
    required this.contextPolicy,
    required this.nowUtc,
  }) : sourceId = _validId(fixture.reference['sampleId']),
       resourceType = fixture.resourceType,
       componentId = _validId(componentId) {
    _validId(listTemplateId);
    _validId(detailTemplateId);
    final listWire = fixture.displayResponses[listTemplateId];
    final detailWire = fixture.displayResponses[detailTemplateId];
    if (listWire == null || detailWire == null) {
      throw const FormatException('Missing projection template');
    }
    _listTemplate = DisplayListResponse.fromJson(listWire).data;
    _detailTemplate = DisplayDetailResponse.fromJson(detailWire).data;
    final seed = _jsonList(fixture.semanticSeed);
    if (seed.isEmpty) {
      throw const FormatException('Semantic seed must be nonempty');
    }
    for (final item in seed) {
      final object = _jsonMap(item);
      _exactKeys(object, ['resourceId', 'sourceRevision', 'fields']);
      final fields = _jsonMap(object['fields']);
      if (fields.isEmpty) {
        throw const FormatException('Semantic fields must be nonempty');
      }
      final resource = FixtureSemanticResource(
        resourceId: _validId(object['resourceId']),
        sourceRevision: _positiveRevision(object['sourceRevision']),
        fields: fields.map(
          (key, value) =>
              MapEntry(_validId(key), DisplayValue.fromJson(_jsonMap(value))),
        ),
      );
      if (_resources.any((entry) => entry.resourceId == resource.resourceId)) {
        throw const FormatException('Duplicate semantic resource');
      }
      _resources.add(resource);
    }
    final projection = _jsonMap(fixture.projectionBindings);
    _exactKeys(projection, ['screenId', 'sectionId', 'fields']);
    _screenId = _validId(projection['screenId']);
    _sectionId = _validId(projection['sectionId']);
    for (final value in _jsonList(projection['fields'])) {
      final object = _jsonMap(value);
      _exactKeys(object, [
        'fieldId',
        'semanticField',
        'writable',
        'requiredNonBlank',
        if (object.containsKey('lookup')) 'lookup',
      ]);
      final binding = _ProjectionBinding(
        fieldId: _validId(object['fieldId']),
        semanticField: _validId(object['semanticField']),
        writable: _booleanValue(object['writable']),
        requiredNonBlank: _booleanValue(object['requiredNonBlank']),
        lookup: object.containsKey('lookup')
            ? _stringMap(object['lookup'], identifiers: false)
            : null,
      );
      if (_bindings.any((entry) => entry.fieldId == binding.fieldId) ||
          (!binding.writable && binding.requiredNonBlank) ||
          (binding.writable && binding.lookup != null)) {
        throw const FormatException('Invalid projection binding');
      }
      for (final resource in _resources) {
        _validateSemanticValue(binding, resource.fields[binding.semanticField]);
      }
      _bindings.add(binding);
    }
    final editableSemanticFields = _bindings
        .where((binding) => binding.writable)
        .map((binding) => binding.semanticField)
        .toSet();
    if (_bindings.any(
      (binding) =>
          binding.lookup != null &&
          editableSemanticFields.contains(binding.semanticField),
    )) {
      throw const FormatException(
        'Editable semantic field cannot use a lookup projection',
      );
    }
    final model = _detailTemplate.model;
    if (model.screenId != _screenId ||
        model.sections.length != 1 ||
        model.sections.single.id != _sectionId ||
        model.sections.single.fields.length != _bindings.length) {
      throw const FormatException('Detail projection structure differs');
    }
    for (var index = 0; index < _bindings.length; index++) {
      if (model.sections.single.fields[index].id != _bindings[index].fieldId) {
        throw const FormatException('Detail projection field order differs');
      }
    }
    if (_listTemplate.model.detailScreenId != _screenId ||
        _listTemplate.model.items.isEmpty) {
      throw const FormatException('List projection structure differs');
    }
    _rowFields = _listTemplate.model.items.first.fields;
    for (final field in _listTemplate.model.items.expand(
      (item) => item.fields,
    )) {
      if (!_bindings.any((binding) => binding.fieldId == field.id)) {
        throw const FormatException('Unknown List projection field');
      }
    }
    final operations = _jsonMap(fixture.operationBindings);
    for (final entry in operations.entries) {
      final object = _jsonMap(entry.value);
      _exactKeys(object, [
        'developmentOnly',
        'inputFields',
        'expected',
        'transition',
      ]);
      final inputs = _jsonList(object['inputFields']);
      if (object['developmentOnly'] != true ||
          inputs.length != 1 ||
          inputs.single != 'resourceId') {
        throw const FormatException('Invalid development Operation input');
      }
      final operation = _OperationBinding(
        expected: _stringMap(object['expected']),
        transition: _stringMap(object['transition']),
      );
      for (final resource in _resources) {
        for (final key in {
          ...operation.expected.keys,
          ...operation.transition.keys,
        }) {
          if (resource.fields[key] is! TextDisplayValue) {
            throw const FormatException('Operation requires semantic Text');
          }
        }
      }
      for (final binding in _bindings) {
        for (final mapping in [operation.transition]) {
          if (mapping.containsKey(binding.semanticField)) {
            _validateSemanticValue(
              binding,
              TextDisplayValue(mapping[binding.semanticField]!),
            );
          }
        }
      }
      _operations[_validId(entry.key)] = operation;
    }
    if (model.actions.any((action) => !_operations.containsKey(action.id))) {
      throw const FormatException('Action requires Operation binding');
    }
    for (final context in fixture.contexts.values) {
      if (context.sourceId != sourceId ||
          context.componentId != this.componentId ||
          _contexts.containsKey(context.flowId)) {
        throw const FormatException('Fixture context identity differs');
      }
      _contexts[context.flowId] = context;
    }
    if (_contexts.isEmpty) {
      throw const FormatException('Fixture contexts must be nonempty');
    }
  }

  final String sourceId;
  final String resourceType;
  final String componentId;
  final PresentationContextPolicy contextPolicy;
  final DateTime Function() nowUtc;
  late final DisplayListData _listTemplate;
  late final DisplayDetailData _detailTemplate;
  late final List<DisplayField> _rowFields;
  late final String _screenId;
  late final String _sectionId;
  final List<FixtureSemanticResource> _resources = [];
  final List<_ProjectionBinding> _bindings = [];
  final Map<String, _OperationBinding> _operations = {};
  final Map<String, PresentationContext> _contexts = {};
  final List<DisplayTransportCall> _calls = [];
  final List<OrdinaryOperationRequest> _operationCalls = [];
  final Map<DisplayRequestKind, List<FixtureTransportFault>> _faults = {};
  final List<FixtureTransportFault> _operationFaults = [];
  List<FixtureSemanticResource>? _heldResources;
  int? _heldSnapshot;
  int _snapshot = 1;
  bool _omitProjection = false;

  List<FixtureSemanticResource> get resources => List.unmodifiable(
    _resources.map(
      (resource) => FixtureSemanticResource(
        resourceId: resource.resourceId,
        sourceRevision: resource.sourceRevision,
        fields: resource.fields,
      ),
    ),
  );
  List<DisplayTransportCall> get calls => List.unmodifiable(_calls);
  int get callCount => _calls.length;
  List<OrdinaryOperationRequest> get operationCalls =>
      List.unmodifiable(_operationCalls);
  int get operationCallCount => _operationCalls.length;

  void failNextDisplay(DisplayRequestKind kind, FixtureTransportFault fault) {
    (_faults[kind] ??= []).add(fault);
  }

  void failNextOperation(FixtureTransportFault fault) {
    _operationFaults.add(fault);
  }

  void holdProjection() {
    if (_heldResources != null) return;
    _heldResources = resources;
    _heldSnapshot = _snapshot;
  }

  void releaseProjection() {
    _heldResources = null;
    _heldSnapshot = null;
  }

  void omitNextMutationProjection() {
    _omitProjection = true;
  }

  PresentationContext _admit(DisplayRequestMetadata metadata, [String? type]) {
    final clock = nowUtc();
    if (!clock.isUtc) {
      throw const PresentationContextException(
        'clock-not-utc',
        'Clock must be explicitly UTC',
      );
    }
    if (type != null && type != resourceType) {
      throw const FormatException('Resource type differs');
    }
    final initial = _contexts[metadata.context.flowId];
    if (initial == null) {
      throw const PresentationContextException('unknown-flow', 'Unknown flow');
    }
    contextPolicy.admit(
      metadata.context,
      sourceId: sourceId,
      componentId: componentId,
      flowId: initial.flowId,
      nowUtc: clock,
    );
    return contextPolicy
        .admitResponse(initial, metadata.context, nowUtc: clock)
        .context;
  }

  FixtureTransportFault? _record(DisplayRequest request) {
    _calls.add(DisplayTransportCall(kind: request.kind, request: request));
    return _consume(_faults[request.kind]);
  }

  FixtureTransportFault? _consume(List<FixtureTransportFault>? queue) =>
      queue == null || queue.isEmpty ? null : queue.removeAt(0);
  void _beforeCommit(FixtureTransportFault? fault) {
    if (fault == FixtureTransportFault.unavailable) {
      throw const DisplayTransportException(
        DisplayTransportFailure.unavailable,
        'Simulated unavailable delivery',
      );
    }
    if (fault == FixtureTransportFault.ambiguousBeforeCommit) {
      throw const DisplayTransportException(
        DisplayTransportFailure.ambiguous,
        'Simulated ambiguity before _commit',
      );
    }
  }

  void _afterCommit(FixtureTransportFault? fault) {
    if (fault == FixtureTransportFault.ambiguousAfterCommit) {
      throw const DisplayTransportException(
        DisplayTransportFailure.ambiguous,
        'Simulated ambiguity after _commit',
      );
    }
  }

  List<FixtureSemanticResource> get _projectedResources =>
      _heldResources ?? _resources;
  FixtureSemanticResource? _findResource(
    List<FixtureSemanticResource> values,
    String id,
  ) {
    for (final resource in values) {
      if (resource.resourceId == id) return resource;
    }
    return null;
  }

  _ProjectionBinding _bindingFor(String fieldId) =>
      _bindings.firstWhere((binding) => binding.fieldId == fieldId);
  DisplayField _projectField(
    DisplayField template,
    FixtureSemanticResource data,
  ) {
    final binding = _bindingFor(template.id);
    final semantic = data.fields[binding.semanticField]!;
    return DisplayField(
      id: template.id,
      label: template.label,
      role: template.role,
      value: binding.lookup == null
          ? semantic
          : TextDisplayValue(
              binding.lookup![(semantic as TextDisplayValue).value]!,
            ),
    );
  }

  bool _matches(
    FixtureSemanticResource resource,
    Map<String, String> expected,
  ) => expected.entries.every(
    (entry) => resource.fields[entry.key] == TextDisplayValue(entry.value),
  );
  DisplayDetailData _detailFor(String id) {
    final resource = _findResource(_projectedResources, id);
    if (resource == null) {
      throw const DisplayTransportException(
        DisplayTransportFailure.unavailable,
        'Resource unavailable for read',
      );
    }
    final template = _detailTemplate.model;
    return DisplayDetailData(
      resourceId: id,
      sourceRevision: resource.sourceRevision,
      provenance: DisplayProvenance(
        producerId: _detailTemplate.provenance.producerId,
        sourceId: sourceId,
        revision: resource.sourceRevision.toString(),
      ),
      bindings: _bindings
          .map(
            (binding) => DisplayEditBinding(
              locator: DisplayFieldLocator(
                screenId: _screenId,
                sectionId: _sectionId,
                fieldId: binding.fieldId,
              ),
              writable: binding.writable,
              inputValue: binding.writable
                  ? resource.fields[binding.semanticField]!
                  : const MissingDisplayValue(),
              requiredNonBlank: binding.requiredNonBlank,
            ),
          )
          .toList(),
      model: DisplayDetailModel(
        screenId: template.screenId,
        title: template.title,
        sections: [
          DisplaySection(
            id: _sectionId,
            fields: template.sections.single.fields
                .map((field) => _projectField(field, resource))
                .toList(),
          ),
        ],
        actions: template.actions
            .where(
              (action) => _matches(resource, _operations[action.id]!.expected),
            )
            .toList(),
      ),
    );
  }

  @override
  Future<Map<String, Object?>> query(DisplayQueryRequest request) async {
    final context = _admit(request.metadata, request.resourceType);
    final fault = _record(request);
    _beforeCommit(fault);
    _afterCommit(fault);
    final snapshot = 'snapshot-${_heldSnapshot ?? _snapshot}';
    final template = _listTemplate.model;
    return DisplayListResponse(
      context: context,
      data: DisplayListData(
        resourceType: resourceType,
        snapshotId: snapshot,
        provenance: DisplayProvenance(
          producerId: _listTemplate.provenance.producerId,
          sourceId: sourceId,
          revision: snapshot,
        ),
        model: DisplayListModel(
          screenId: template.screenId,
          title: template.title,
          detailScreenId: template.detailScreenId,
          items: _projectedResources
              .map(
                (resource) => DisplayResourceSummary(
                  resourceId: resource.resourceId,
                  sourceRevision: resource.sourceRevision,
                  fields: _rowFields
                      .map((field) => _projectField(field, resource))
                      .toList(),
                ),
              )
              .toList(),
        ),
      ),
    ).toJson();
  }

  @override
  Future<Map<String, Object?>> read(DisplayReadRequest request) async {
    final context = _admit(request.metadata, request.resourceType);
    final fault = _record(request);
    _beforeCommit(fault);
    _afterCommit(fault);
    return DisplayDetailResponse(
      context: context,
      data: _detailFor(request.resourceId),
    ).toJson();
  }

  DisplayFieldError _error(String code, [DisplayFieldLocator? locator]) =>
      DisplayFieldError(locator: locator, code: code, message: code);
  Map<String, Object?> _mutation(
    PresentationContext context,
    String id,
    DisplayCommandOutcome outcome,
    int? revision, {
    List<DisplayFieldError> errors = const [],
  }) {
    final success =
        outcome == DisplayCommandOutcome.changed ||
        outcome == DisplayCommandOutcome.noOp;
    final omit = success && _omitProjection;
    if (success) _omitProjection = false;
    return DisplayMutationResponse(
      context: context,
      result: DisplayMutationResult(
        resourceId: id,
        outcome: outcome,
        currentRevision: revision,
        committedRevision: outcome == DisplayCommandOutcome.changed
            ? revision
            : null,
        fieldErrors: errors,
        message: null,
        display: success && !omit ? _detailFor(id) : null,
      ),
    ).toJson();
  }

  void _commit(
    FixtureSemanticResource resource,
    Map<String, DisplayValue> fields,
  ) {
    final index = _resources.indexOf(resource);
    _resources[index] = FixtureSemanticResource(
      resourceId: resource.resourceId,
      sourceRevision: resource.sourceRevision + 1,
      fields: fields,
    );
    _snapshot++;
  }

  @override
  Future<Map<String, Object?>> update(DisplayUpdateRequest request) async {
    final context = _admit(request.metadata, request.resourceType);
    final fault = _record(request);
    _beforeCommit(fault);
    final resource = _findResource(_resources, request.resourceId);
    if (resource == null) {
      return _mutation(
        context,
        request.resourceId,
        DisplayCommandOutcome.rejected,
        null,
        errors: [_error('unknown-resource')],
      );
    }
    if (request.metadata.observedRevision != resource.sourceRevision) {
      return _mutation(
        context,
        request.resourceId,
        DisplayCommandOutcome.conflict,
        resource.sourceRevision,
      );
    }
    final errors = <DisplayFieldError>[];
    final seen = <DisplayFieldLocator>{};
    final submittedValues = <String, DisplayValue>{};
    final fields = Map<String, DisplayValue>.of(resource.fields);
    for (final input in request.fields) {
      final locator = input.locator;
      if (!seen.add(locator)) {
        errors.add(_error('duplicate-field', locator));
        continue;
      }
      if (locator.screenId != _screenId ||
          locator.sectionId != _sectionId ||
          !_bindings.any((binding) => binding.fieldId == locator.fieldId)) {
        errors.add(_error('unknown-field', locator));
        continue;
      }
      final binding = _bindingFor(locator.fieldId);
      if (!binding.writable) {
        errors.add(_error('read-only', locator));
      } else if (input.value is! TextDisplayValue) {
        errors.add(_error('invalid-type', locator));
      } else if (_bindings.any(
            (alias) =>
                alias.semanticField == binding.semanticField &&
                alias.requiredNonBlank,
          ) &&
          _blankText((input.value as TextDisplayValue).value)) {
        errors.add(_error('required-nonblank', locator));
      } else if (submittedValues.containsKey(binding.semanticField) &&
          submittedValues[binding.semanticField] != input.value) {
        errors.add(_error('duplicate-field', locator));
      } else {
        submittedValues[binding.semanticField] = input.value;
        fields[binding.semanticField] = input.value;
      }
    }
    if (errors.isNotEmpty) {
      return _mutation(
        context,
        request.resourceId,
        DisplayCommandOutcome.rejected,
        resource.sourceRevision,
        errors: errors,
      );
    }
    final changed = fields.entries.any(
      (entry) => resource.fields[entry.key] != entry.value,
    );
    if (!changed) {
      return _mutation(
        context,
        request.resourceId,
        DisplayCommandOutcome.noOp,
        resource.sourceRevision,
      );
    }
    _commit(resource, fields);
    _afterCommit(fault);
    return _mutation(
      context,
      request.resourceId,
      DisplayCommandOutcome.changed,
      resource.sourceRevision + 1,
    );
  }

  @override
  Future<Map<String, Object?>> create(DisplayCreateRequest request) async {
    final context = _admit(request.metadata, request.resourceType);
    _beforeCommit(_record(request));
    return _mutation(
      context,
      'unsupported:create',
      DisplayCommandOutcome.unsupported,
      null,
    );
  }

  @override
  Future<Map<String, Object?>> delete(DisplayDeleteRequest request) async {
    final context = _admit(request.metadata, request.resourceType);
    _beforeCommit(_record(request));
    return _mutation(
      context,
      request.resourceId,
      DisplayCommandOutcome.unsupported,
      _findResource(_resources, request.resourceId)?.sourceRevision,
    );
  }

  Future<Map<String, Object?>> _execute(
    OrdinaryOperationRequest request,
  ) async {
    final context = _admit(request.metadata);
    _operationCalls.add(request);
    final fault = _consume(_operationFaults);
    _beforeCommit(fault);
    final resource = _findResource(_resources, request.resourceId);
    final operation = _operations[request.operationId];
    var outcome = DisplayCommandOutcome.rejected;
    final errors = <DisplayFieldError>[];
    int? revision = resource?.sourceRevision;
    if (resource == null) {
      errors.add(_error('unknown-resource'));
    } else if (operation == null) {
      errors.add(_error('unknown-operation'));
    } else if (request.metadata.observedRevision != resource.sourceRevision) {
      outcome = DisplayCommandOutcome.conflict;
    } else if (!_matches(resource, operation.expected)) {
      errors.add(_error('operation-precondition'));
    } else {
      _commit(resource, {
        ...resource.fields,
        for (final entry in operation.transition.entries)
          entry.key: TextDisplayValue(entry.value),
      });
      revision = resource.sourceRevision + 1;
      outcome = DisplayCommandOutcome.changed;
      _afterCommit(fault);
    }
    return OrdinaryOperationResponse(
      context: context,
      result: DisplayOperationResult(
        resourceId: request.resourceId,
        outcome: outcome,
        currentRevision: revision,
        committedRevision: outcome == DisplayCommandOutcome.changed
            ? revision
            : null,
        fieldErrors: errors,
        message: null,
      ),
    ).toJson();
  }
}

/// Separate public Operation port sharing only the supplied semantic source.
final class FixtureOrdinaryOperationTransport
    implements OrdinaryOperationTransport {
  const FixtureOrdinaryOperationTransport({required this.source});
  final FixtureDisplaySource source;
  @override
  Future<Map<String, Object?>> execute(OrdinaryOperationRequest request) =>
      source._execute(request);
}

final class _ProjectionBinding {
  const _ProjectionBinding({
    required this.fieldId,
    required this.semanticField,
    required this.writable,
    required this.requiredNonBlank,
    required this.lookup,
  });
  final String fieldId;
  final String semanticField;
  final bool writable;
  final bool requiredNonBlank;
  final Map<String, String>? lookup;
}

final class _OperationBinding {
  const _OperationBinding({required this.expected, required this.transition});
  final Map<String, String> expected;
  final Map<String, String> transition;
}

void _validateSemanticValue(_ProjectionBinding binding, DisplayValue? value) {
  if (value == null ||
      ((binding.writable || binding.lookup != null) &&
          value is! TextDisplayValue) ||
      (binding.requiredNonBlank &&
          value is TextDisplayValue &&
          _blankText(value.value)) ||
      (binding.lookup != null &&
          value is TextDisplayValue &&
          !binding.lookup!.containsKey(value.value))) {
    throw const FormatException('Invalid bound semantic value');
  }
}

bool _blankText(String value) => value.replaceAll('\u0085', ' ').trim().isEmpty;
void _exactKeys(Map<String, Object?> value, List<String> keys) {
  if (value.length != keys.length || !keys.every(value.containsKey)) {
    throw const FormatException('Unsupported fixture object shape');
  }
}

Map<String, Object?> _jsonMap(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Expected fixture object');
  }
  return Map<String, Object?>.from(value);
}

List<Object?> _jsonList(Object? value) {
  if (value is! List) throw const FormatException('Expected fixture array');
  return List<Object?>.from(value);
}

Map<String, String> _stringMap(Object? value, {bool identifiers = true}) {
  final object = _jsonMap(value);
  if (object.isEmpty || object.values.any((item) => item is! String)) {
    throw const FormatException('Expected nonempty string mapping');
  }
  return Map.unmodifiable(
    object.map(
      (key, item) =>
          MapEntry(identifiers ? _validId(key) : key, item as String),
    ),
  );
}

String _validId(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Expected nonblank identifier');
  }
  return value;
}

int _positiveRevision(Object? value) {
  if (value is! int || value <= 0) {
    throw const FormatException('Expected positive revision');
  }
  return value;
}

bool _booleanValue(Object? value) {
  if (value is! bool) throw const FormatException('Expected boolean');
  return value;
}
