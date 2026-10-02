import 'display_protocol.dart';
import 'presentation_context.dart';

/// Candidate Display request kinds, distinct from ordinary Operations.
enum DisplayRequestKind { query, read, update, create, delete }

/// Continuation and concurrency metadata; revision is never a domain input.
final class DisplayRequestMetadata {
  DisplayRequestMetadata({
    required this.context,
    required this.observedRevision,
  }) {
    if (observedRevision != null) {
      _positive(observedRevision);
    }
  }
  final PresentationContext context;
  final int? observedRevision;
  factory DisplayRequestMetadata.fromJson(Map<String, Object?> json) {
    _keys(json, ['context', 'observedRevision']);
    return DisplayRequestMetadata(
      context: PresentationContext.fromJson(_map(json['context'])),
      observedRevision: json['observedRevision'] == null
          ? null
          : _positive(json['observedRevision']),
    );
  }
  Map<String, Object?> toJson() => {
    'context': context.toJson(),
    'observedRevision': observedRevision,
  };
}

/// Scoped semantic input; repeated locators remain representable for rejection.
final class DisplayFieldInput {
  const DisplayFieldInput({required this.locator, required this.value});
  final DisplayFieldLocator locator;
  final DisplayValue value;
  factory DisplayFieldInput.fromJson(Map<String, Object?> json) {
    _keys(json, ['locator', 'value']);
    return DisplayFieldInput(
      locator: DisplayFieldLocator.fromJson(_map(json['locator'])),
      value: DisplayValue.fromJson(_map(json['value'])),
    );
  }
  Map<String, Object?> toJson() => {
    'locator': locator.toJson(),
    'value': value.toJson(),
  };
}

/// Closed candidate request family; common runtime will construct these.
sealed class DisplayRequest {
  DisplayRequest({
    required String resourceType,
    required this.metadata,
    required this.kind,
  }) : resourceType = _id(resourceType) {
    final needsRevision =
        kind == DisplayRequestKind.update || kind == DisplayRequestKind.delete;
    if (needsRevision != (metadata.observedRevision != null)) {
      throw const FormatException('Request revision does not match method');
    }
  }
  final String resourceType;
  final DisplayRequestMetadata metadata;
  final DisplayRequestKind kind;
  Map<String, Object?> toJson() => {
    'schema': 'textus.display.prototype.v1',
    'kind': kind.name,
    'resourceType': resourceType,
    'metadata': metadata.toJson(),
  };
  factory DisplayRequest.fromJson(Map<String, Object?> json) {
    if (json['schema'] != 'textus.display.prototype.v1') {
      throw const FormatException('Wrong request schema');
    }
    final kind = json['kind'];
    final hasId = kind == 'read' || kind == 'update' || kind == 'delete';
    final hasFields = kind == 'update' || kind == 'create';
    _keys(json, [
      'schema',
      'kind',
      'resourceType',
      'metadata',
      if (hasId) 'resourceId',
      if (hasFields) 'fields',
    ]);
    final resourceType = _id(json['resourceType']);
    final metadata = DisplayRequestMetadata.fromJson(_map(json['metadata']));
    return switch (kind) {
      'query' => DisplayQueryRequest(
        resourceType: resourceType,
        metadata: metadata,
      ),
      'read' => DisplayReadRequest(
        resourceType: resourceType,
        metadata: metadata,
        resourceId: _id(json['resourceId']),
      ),
      'update' => DisplayUpdateRequest(
        resourceType: resourceType,
        metadata: metadata,
        resourceId: _id(json['resourceId']),
        fields: _fields(json['fields']),
      ),
      'create' => DisplayCreateRequest(
        resourceType: resourceType,
        metadata: metadata,
        fields: _fields(json['fields']),
      ),
      'delete' => DisplayDeleteRequest(
        resourceType: resourceType,
        metadata: metadata,
        resourceId: _id(json['resourceId']),
      ),
      _ => throw const FormatException('Unknown request kind'),
    };
  }
}

/// Query a resource collection without selecting an eager Detail.
final class DisplayQueryRequest extends DisplayRequest {
  DisplayQueryRequest({required super.resourceType, required super.metadata})
    : super(kind: DisplayRequestKind.query);
}

/// Read one resource projection.
final class DisplayReadRequest extends DisplayRequest {
  DisplayReadRequest({
    required super.resourceType,
    required super.metadata,
    required String resourceId,
  }) : resourceId = _id(resourceId),
       super(kind: DisplayRequestKind.read);
  final String resourceId;
  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'resourceId': resourceId,
  };
}

/// Submit ordered inputs under the observed revision, without deduplication.
final class DisplayUpdateRequest extends DisplayRequest {
  DisplayUpdateRequest({
    required super.resourceType,
    required super.metadata,
    required String resourceId,
    required List<DisplayFieldInput> fields,
  }) : resourceId = _id(resourceId),
       fields = List.unmodifiable(fields),
       super(kind: DisplayRequestKind.update);
  final String resourceId;
  final List<DisplayFieldInput> fields;
  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'resourceId': resourceId,
    'fields': fields.map((field) => field.toJson()).toList(),
  };
}

/// Create capability request, even when a fixture explicitly rejects support.
final class DisplayCreateRequest extends DisplayRequest {
  DisplayCreateRequest({
    required super.resourceType,
    required super.metadata,
    required List<DisplayFieldInput> fields,
  }) : fields = List.unmodifiable(fields),
       super(kind: DisplayRequestKind.create);
  final List<DisplayFieldInput> fields;
  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'fields': fields.map((field) => field.toJson()).toList(),
  };
}

/// Delete capability request under the observed revision.
final class DisplayDeleteRequest extends DisplayRequest {
  DisplayDeleteRequest({
    required super.resourceType,
    required super.metadata,
    required String resourceId,
  }) : resourceId = _id(resourceId),
       super(kind: DisplayRequestKind.delete);
  final String resourceId;
  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'resourceId': resourceId,
  };
}

/// Ordinary Operation input contains only resource identity; no implicit reload.
final class OrdinaryOperationRequest {
  OrdinaryOperationRequest({
    required String operationId,
    required String resourceId,
    required this.metadata,
  }) : operationId = _id(operationId),
       resourceId = _id(resourceId) {
    _positive(metadata.observedRevision);
  }
  final String operationId;
  final String resourceId;
  final DisplayRequestMetadata metadata;
  factory OrdinaryOperationRequest.fromJson(Map<String, Object?> json) {
    _keys(json, ['schema', 'operationId', 'input', 'metadata']);
    if (json['schema'] != 'textus.operation.prototype.v1') {
      throw const FormatException('Wrong Operation request schema');
    }
    final input = _map(json['input']);
    _keys(input, ['resourceId']);
    return OrdinaryOperationRequest(
      operationId: _id(json['operationId']),
      resourceId: _id(input['resourceId']),
      metadata: DisplayRequestMetadata.fromJson(_map(json['metadata'])),
    );
  }
  Map<String, Object?> toJson() => {
    'schema': 'textus.operation.prototype.v1',
    'operationId': operationId,
    'input': {'resourceId': resourceId},
    'metadata': metadata.toJson(),
  };
}

/// Raw wire Display port; neither codec nor transport retries commands.
abstract interface class DisplayTransport {
  Future<Map<String, Object?>> query(DisplayQueryRequest request);
  Future<Map<String, Object?>> read(DisplayReadRequest request);
  Future<Map<String, Object?>> update(DisplayUpdateRequest request);
  Future<Map<String, Object?>> create(DisplayCreateRequest request);
  Future<Map<String, Object?>> delete(DisplayDeleteRequest request);
}

/// Separate ordinary Operation port, with no shared Display response.
abstract interface class OrdinaryOperationTransport {
  Future<Map<String, Object?>> execute(OrdinaryOperationRequest request);
}

/// A closed List envelope beside admitted presentation context.
final class DisplayListResponse {
  DisplayListResponse({required this.context, required this.data}) {
    _source(context, data.provenance);
  }
  final PresentationContext context;
  final DisplayListData data;
  factory DisplayListResponse.fromJson(Map<String, Object?> json) {
    _envelope(json, 'list');
    return DisplayListResponse(
      context: PresentationContext.fromJson(_map(json['context'])),
      data: DisplayListData.fromJson(_map(json['data'])),
    );
  }
  Map<String, Object?> toJson() => _wire('list', context, data.toJson());
}

/// A closed Detail envelope with exact resource provenance.
final class DisplayDetailResponse {
  DisplayDetailResponse({required this.context, required this.data}) {
    _source(context, data.provenance);
  }
  final PresentationContext context;
  final DisplayDetailData data;
  factory DisplayDetailResponse.fromJson(Map<String, Object?> json) {
    _envelope(json, 'detail');
    return DisplayDetailResponse(
      context: PresentationContext.fromJson(_map(json['context'])),
      data: DisplayDetailData.fromJson(_map(json['data'])),
    );
  }
  Map<String, Object?> toJson() => _wire('detail', context, data.toJson());
}

/// A command receipt, which may include stale or absent projection evidence.
final class DisplayMutationResponse {
  DisplayMutationResponse({required this.context, required this.result}) {
    if (result.display != null) {
      _source(context, result.display!.provenance);
    }
  }
  final PresentationContext context;
  final DisplayMutationResult result;
  factory DisplayMutationResponse.fromJson(Map<String, Object?> json) {
    _envelope(json, 'mutation');
    return DisplayMutationResponse(
      context: PresentationContext.fromJson(_map(json['context'])),
      result: DisplayMutationResult.fromJson(_map(json['data'])),
    );
  }
  Map<String, Object?> toJson() => _wire('mutation', context, result.toJson());
}

/// Ordinary Operation result, deliberately lacking any Display data member.
final class OrdinaryOperationResponse {
  const OrdinaryOperationResponse({
    required this.context,
    required this.result,
  });
  final PresentationContext context;
  final DisplayOperationResult result;
  factory OrdinaryOperationResponse.fromJson(Map<String, Object?> json) {
    _keys(json, ['schema', 'context', 'result']);
    if (json['schema'] != 'textus.operation.prototype.v1') {
      throw const FormatException('Wrong Operation response schema');
    }
    return OrdinaryOperationResponse(
      context: PresentationContext.fromJson(_map(json['context'])),
      result: DisplayOperationResult.fromJson(_map(json['result'])),
    );
  }
  Map<String, Object?> toJson() => {
    'schema': 'textus.operation.prototype.v1',
    'context': context.toJson(),
    'result': result.toJson(),
  };
}

/// Wire delivery failures, distinct from decoded command outcomes.
enum DisplayTransportFailure { unavailable, ambiguous }

/// An unavailable read or ambiguous command receipt; retry belongs to runtime.
final class DisplayTransportException implements Exception {
  const DisplayTransportException(this.failure, this.message);
  final DisplayTransportFailure failure;
  final String message;
  @override
  String toString() => 'DisplayTransportException(${failure.name}): $message';
}

void _source(PresentationContext context, DisplayProvenance provenance) {
  if (context.sourceId != provenance.sourceId) {
    throw const FormatException('Context/projection source mismatch');
  }
}

Map<String, Object?> _wire(
  String kind,
  PresentationContext context,
  Map<String, Object?> data,
) => {
  'schema': 'textus.display.prototype.v1',
  'kind': kind,
  'context': context.toJson(),
  'data': data,
};
void _envelope(Map<String, Object?> json, String kind) {
  _keys(json, ['schema', 'kind', 'context', 'data']);
  if (json['schema'] != 'textus.display.prototype.v1' || json['kind'] != kind) {
    throw const FormatException('Wrong Display response schema/kind');
  }
}

void _keys(Map<String, Object?> json, List<String> keys) {
  if (json.length != keys.length || !keys.every(json.containsKey)) {
    throw FormatException('Expected exactly ${keys.join(', ')}');
  }
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Expected JSON object');
  }
  return Map<String, Object?>.from(value);
}

String _id(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Expected nonblank identifier');
  }
  return value;
}

int _positive(Object? value) {
  if (value is! int || value <= 0) {
    throw const FormatException('Expected positive integer');
  }
  return value;
}

List<DisplayFieldInput> _fields(Object? value) {
  if (value is! List) {
    throw const FormatException('Expected input array');
  }
  return value.map((field) => DisplayFieldInput.fromJson(_map(field))).toList();
}
