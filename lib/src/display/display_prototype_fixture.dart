import 'dart:convert';

import 'display_transport.dart';
import 'presentation_context.dart';

/// Generic immutable fixture decoder; semantic and projection mappings are
/// application-owned inputs, not interpreted domain commands.
final class DisplayPrototypeFixture {
  DisplayPrototypeFixture._({
    required this.reference,
    required this.resourceType,
    required this.contexts,
    required this.displayResponses,
    required this.operationResponses,
    required this.semanticSeed,
    required this.projectionBindings,
    required this.operationBindings,
  });
  final Map<String, Object?> reference;
  final String resourceType;
  final Map<String, PresentationContext> contexts;
  final Map<String, Map<String, Object?>> displayResponses;
  final Map<String, Map<String, Object?>> operationResponses;
  final Object semanticSeed;
  final Object projectionBindings;
  final Object operationBindings;

  factory DisplayPrototypeFixture.fromJson(Map<String, Object?> json) {
    _keys(json, [
      'schema',
      'reference',
      'resourceType',
      'contexts',
      'displayResponses',
      'operationResponses',
      'semanticSeed',
      'projectionBindings',
      'operationBindings',
    ]);
    if (json['schema'] != 'textus.display.fixture.v1') {
      throw const FormatException('Wrong fixture schema');
    }
    final reference = _map(json['reference']);
    _keys(reference, [
      'sampleId',
      'sampleRevision',
      'provisionalVersion',
      'developmentOnly',
    ]);
    _id(reference['sampleId']);
    _positive(reference['sampleRevision']);
    _positive(reference['provisionalVersion']);
    if (reference['developmentOnly'] != true) {
      throw const FormatException('Fixture must be development-only');
    }
    final contexts = _map(json['contexts']).map(
      (id, context) =>
          MapEntry(_id(id), PresentationContext.fromJson(_map(context))),
    );
    final displayResponses = _map(json['displayResponses']).map((id, wire) {
      final envelope = _map(wire);
      final decoded = switch (envelope['kind']) {
        'list' => DisplayListResponse.fromJson(envelope).toJson(),
        'detail' => DisplayDetailResponse.fromJson(envelope).toJson(),
        'mutation' => DisplayMutationResponse.fromJson(envelope).toJson(),
        _ => throw const FormatException(
          'Unknown fixture Display response kind',
        ),
      };
      return MapEntry(_id(id), _freeze(decoded, 1) as Map<String, Object?>);
    });
    final operationResponses = _map(json['operationResponses']).map(
      (id, wire) => MapEntry(
        _id(id),
        _freeze(OrdinaryOperationResponse.fromJson(_map(wire)).toJson(), 1)
            as Map<String, Object?>,
      ),
    );
    return DisplayPrototypeFixture._(
      reference: Map.unmodifiable(reference),
      resourceType: _id(json['resourceType']),
      contexts: Map.unmodifiable(contexts),
      displayResponses: Map.unmodifiable(displayResponses),
      operationResponses: Map.unmodifiable(operationResponses),
      semanticSeed: _collection(json['semanticSeed']),
      projectionBindings: _collection(json['projectionBindings']),
      operationBindings: _collection(json['operationBindings']),
    );
  }

  /// Look up a supplied context without inventing a default flow.
  PresentationContext contextFor(String id) =>
      contexts[id] ?? (throw StateError('Fixture context missing: $id'));

  /// Return a frozen strictly decoded raw Display envelope for playback.
  Map<String, Object?> displayResponse(String id) =>
      displayResponses[id] ??
      (throw StateError('Fixture Display response missing: $id'));

  /// Return a frozen ordinary Operation envelope, with no Display reload.
  Map<String, Object?> operationResponse(String id) =>
      operationResponses[id] ??
      (throw StateError('Fixture Operation response missing: $id'));
  Map<String, Object?> toJson() => {
    'schema': 'textus.display.fixture.v1',
    'reference': reference,
    'resourceType': resourceType,
    'contexts': contexts.map((id, context) => MapEntry(id, context.toJson())),
    'displayResponses': displayResponses,
    'operationResponses': operationResponses,
    'semanticSeed': semanticSeed,
    'projectionBindings': projectionBindings,
    'operationBindings': operationBindings,
  };
}

Object _collection(Object? value) {
  if (value is! Map && value is! List) {
    throw const FormatException('Fixture mapping must be a JSON collection');
  }
  final frozen = _freeze(value, 1)!;
  if (utf8.encode(jsonEncode(frozen)).length > 65536) {
    throw const FormatException('Fixture collection exceeds 65536 UTF-8 bytes');
  }
  return frozen;
}

Object? _freeze(Object? value, int depth) {
  if (value is Map) {
    if (depth > 16 || value.keys.any((key) => key is! String)) {
      throw const FormatException('Fixture depth/key limit');
    }
    return Map<String, Object?>.unmodifiable(
      value.map(
        (key, item) => MapEntry(key as String, _freeze(item, depth + 1)),
      ),
    );
  }
  if (value is List) {
    if (depth > 16) {
      throw const FormatException('Fixture depth limit');
    }
    return List<Object?>.unmodifiable(
      value.map((item) => _freeze(item, depth + 1)),
    );
  }
  if (value == null ||
      value is String ||
      value is bool ||
      (value is num && value.isFinite)) {
    return value;
  }
  throw const FormatException('Fixture requires finite JSON');
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
