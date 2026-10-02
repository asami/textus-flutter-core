import 'dart:convert';

import 'display_protocol.dart';

const _locale = 'textus.presentation.locale';
const _arm = 'textus.presentation.arm';
const _correlation = 'textus.presentation.correlation';

/// A bounded, presentation-facing projection; never a runtime/security object.
final class PresentationContext {
  PresentationContext({
    required String flowId,
    required String sourceId,
    required String componentId,
    required List<PresentationContextFamily> families,
  }) : flowId = _id(flowId),
       sourceId = _id(sourceId),
       componentId = _id(componentId),
       families = List.unmodifiable(families) {
    if (families.length > 8 ||
        families.map((family) => family.namespace).toSet().length !=
            families.length) {
      throw const FormatException(
        'Context requires at most eight unique families',
      );
    }
    for (final family in families) {
      final payload = family.payload;
      if (payload is CorrelationPresentationPayload &&
          payload.flowReference != flowId) {
        throw const FormatException('Correlation flow must equal context flow');
      }
    }
  }
  final String flowId;
  final String sourceId;
  final String componentId;
  final List<PresentationContextFamily> families;
  factory PresentationContext.fromJson(Map<String, Object?> json) {
    _keys(json, ['schema', 'flowId', 'sourceId', 'componentId', 'families']);
    if (json['schema'] != 'textus.presentation-context.v1') {
      throw const FormatException('Wrong context schema');
    }
    final families = json['families'];
    if (families is! List) {
      throw const FormatException('Expected family array');
    }
    return PresentationContext(
      flowId: _id(json['flowId']),
      sourceId: _id(json['sourceId']),
      componentId: _id(json['componentId']),
      families: families
          .map((family) => PresentationContextFamily.fromJson(_map(family)))
          .toList(),
    );
  }
  Map<String, Object?> toJson() => {
    'schema': 'textus.presentation-context.v1',
    'flowId': flowId,
    'sourceId': sourceId,
    'componentId': componentId,
    'families': families.map((family) => family.toJson()).toList(),
  };
  @override
  bool operator ==(Object other) =>
      other is PresentationContext && _equal(toJson(), other.toJson());
  @override
  int get hashCode => _hash(toJson());
}

/// Versioned producer-owned family with explicit required/expiry policy.
final class PresentationContextFamily {
  PresentationContextFamily({
    required String namespace,
    required int version,
    required String producerId,
    required this.isRequired,
    required this.expiresAt,
    required this.payload,
  }) : namespace = _id(namespace),
       version = _positive(version),
       producerId = _id(producerId) {
    if (expiresAt != null) {
      TimestampDisplayValue(expiresAt!);
    }
    // Re-decode to validate exact namespace/type pairing and all payload limits.
    final decoded = _payload(namespace, version, payload.toJson());
    if (decoded.runtimeType != payload.runtimeType) {
      throw const FormatException('Payload type does not match family');
    }
    if (namespace == _arm && !isRequired) {
      throw const FormatException('Supplied arm must be required');
    }
  }
  final String namespace;
  final int version;
  final String producerId;
  final bool isRequired;
  final DateTime? expiresAt;
  final PresentationContextPayload payload;
  factory PresentationContextFamily.fromJson(Map<String, Object?> json) {
    _keys(json, [
      'namespace',
      'version',
      'producerId',
      'required',
      'expiresAt',
      'payload',
    ]);
    final namespace = _id(json['namespace']);
    final version = _positive(json['version']);
    return PresentationContextFamily(
      namespace: namespace,
      version: version,
      producerId: _id(json['producerId']),
      isRequired: _bool(json['required']),
      expiresAt: json['expiresAt'] == null
          ? null
          : (DisplayValue.fromJson({
              'type': 'timestamp',
              'value': json['expiresAt'],
            }) as TimestampDisplayValue).value,
      payload: _payload(namespace, version, _map(json['payload'])),
    );
  }
  Map<String, Object?> toJson() => {
    'namespace': namespace,
    'version': version,
    'producerId': producerId,
    'required': isRequired,
    'expiresAt': expiresAt?.toIso8601String(),
    'payload': payload.toJson(),
  };
  @override
  bool operator ==(Object other) =>
      other is PresentationContextFamily && _equal(toJson(), other.toJson());
  @override
  int get hashCode => _hash(toJson());
}

/// Closed typed known payloads, or bounded opaque structural decoding.
sealed class PresentationContextPayload {
  const PresentationContextPayload();
  Map<String, Object?> toJson();
  @override
  bool operator ==(Object other) =>
      other is PresentationContextPayload &&
      runtimeType == other.runtimeType &&
      _equal(toJson(), other.toJson());
  @override
  int get hashCode => Object.hash(runtimeType, _hash(toJson()));
}

/// The explicit candidate locale-tag subset.
final class LocalePresentationPayload extends PresentationContextPayload {
  LocalePresentationPayload({required String localeTag})
    : localeTag = _id(localeTag) {
    if (!RegExp(r'^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$').hasMatch(localeTag)) {
      throw const FormatException('Invalid candidate locale tag');
    }
    _bounded(toJson());
  }
  final String localeTag;
  @override
  Map<String, Object?> toJson() => {'localeTag': localeTag};
}

/// Supplied identity; allocation and UI selection belong to other owners.
final class SuppliedArmPresentationPayload extends PresentationContextPayload {
  SuppliedArmPresentationPayload({
    required String namespace,
    required String presentationSet,
    required String armId,
    required int definitionVersion,
    required String assignmentReference,
  }) : namespace = _id(namespace),
       presentationSet = _id(presentationSet),
       armId = _id(armId),
       definitionVersion = _positive(definitionVersion),
       assignmentReference = _id(assignmentReference) {
    _bounded(toJson());
  }
  final String namespace;
  final String presentationSet;
  final String armId;
  final int definitionVersion;
  final String assignmentReference;
  @override
  Map<String, Object?> toJson() => {
    'namespace': namespace,
    'presentationSet': presentationSet,
    'armId': armId,
    'definitionVersion': definitionVersion,
    'assignmentReference': assignmentReference,
  };
}

/// Producer-controlled attempt reference within a fixed flow.
final class CorrelationPresentationPayload extends PresentationContextPayload {
  CorrelationPresentationPayload({
    required String flowReference,
    required String attemptReference,
  }) : flowReference = _id(flowReference),
       attemptReference = _id(attemptReference) {
    _bounded(toJson());
  }
  final String flowReference;
  final String attemptReference;
  @override
  Map<String, Object?> toJson() => {
    'flowReference': flowReference,
    'attemptReference': attemptReference,
  };
}

/// Immutable JSON; structural decoding grants no carriage or interpretation.
final class OpaquePresentationPayload extends PresentationContextPayload {
  OpaquePresentationPayload(Map<String, Object?> values)
    : values = _bounded(values);
  final Map<String, Object?> values;
  @override
  Map<String, Object?> toJson() => values;
}

/// Exact optional namespace/version/producer carriage permission.
final class PresentationExtensionSupport {
  PresentationExtensionSupport({
    required String namespace,
    required int version,
    required String producerId,
  }) : namespace = _id(namespace),
       version = _positive(version),
       producerId = _id(producerId);
  final String namespace;
  final int version;
  final String producerId;
}

/// An observable optional omission, never silent fallback.
final class PresentationContextDiagnostic {
  const PresentationContextDiagnostic({
    required this.namespace,
    required this.code,
    required this.message,
  });
  final String namespace;
  final String code;
  final String message;
}

/// Admitted immutable context and optional-family diagnostics.
final class PresentationContextAdmission {
  PresentationContextAdmission({
    required this.context,
    required List<PresentationContextDiagnostic> diagnostics,
  }) : diagnostics = List.unmodifiable(diagnostics);
  final PresentationContext context;
  final List<PresentationContextDiagnostic> diagnostics;
}

/// Context incompatibility, distinct from codec and transport failure.
final class PresentationContextException implements Exception {
  const PresentationContextException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'PresentationContextException($code): $message';
}

/// Pure admission/replacement policy with an explicit caller-supplied UTC clock.
final class PresentationContextPolicy {
  PresentationContextPolicy({
    required Set<String> allowedProducerIds,
    List<PresentationExtensionSupport> optionalExtensions = const [],
  }) : allowedProducerIds = Set.unmodifiable(allowedProducerIds.map(_id)),
       optionalExtensions = List.unmodifiable(optionalExtensions);
  final Set<String> allowedProducerIds;
  final List<PresentationExtensionSupport> optionalExtensions;

  PresentationContextAdmission admit(
    PresentationContext context, {
    required String sourceId,
    required String componentId,
    required String flowId,
    required DateTime nowUtc,
  }) {
    _clock(nowUtc);
    if (context.sourceId != sourceId) {
      _fail('source-mismatch', 'Context source differs');
    }
    if (context.componentId != componentId) {
      _fail('component-mismatch', 'Context component differs');
    }
    if (context.flowId != flowId) {
      _fail('flow-mismatch', 'Context flow differs');
    }
    final families = <PresentationContextFamily>[];
    final diagnostics = <PresentationContextDiagnostic>[];
    for (final family in context.families) {
      if (!allowedProducerIds.contains(family.producerId)) {
        _fail(
          'producer-not-allowed',
          'Unallowed producer for ${family.namespace}',
        );
      }
      final known = [_locale, _arm, _correlation].contains(family.namespace);
      String? reason;
      if (_expired(family, nowUtc)) {
        reason = 'expired';
      } else if (!known || family.version != 1) {
        if (family.isRequired || !_extension(family)) {
          reason = known ? 'unsupported-version' : 'unknown-family';
        }
      }
      if (reason != null) {
        if (family.isRequired) {
          _fail(reason, 'Required family ${family.namespace} is $reason');
        }
        diagnostics.add(
          PresentationContextDiagnostic(
            namespace: family.namespace,
            code: reason,
            message: 'Optional family omitted: $reason',
          ),
        );
      } else {
        families.add(family);
      }
    }
    return PresentationContextAdmission(
      context: PresentationContext(
        flowId: context.flowId,
        sourceId: context.sourceId,
        componentId: context.componentId,
        families: families,
      ),
      diagnostics: diagnostics,
    );
  }

  PresentationContextAdmission admitResponse(
    PresentationContext previous,
    PresentationContext received, {
    required DateTime nowUtc,
  }) {
    final admitted = admit(
      received,
      sourceId: previous.sourceId,
      componentId: previous.componentId,
      flowId: previous.flowId,
      nowUtc: nowUtc,
    );
    final old = {
      for (final family in previous.families) family.namespace: family,
    };
    final next = {
      for (final family in admitted.context.families) family.namespace: family,
    };
    // Even a newly supplied family that would be filtered must not enter a flow.
    for (final family in received.families) {
      if (!old.containsKey(family.namespace)) {
        _fail('new-family', 'Family cannot appear mid-flow');
      }
    }
    for (final family in previous.families) {
      final replacement = next[family.namespace];
      if (replacement == null) {
        if (family.namespace == _arm ||
            family.isRequired ||
            (!_expired(family, nowUtc) &&
                !admitted.diagnostics.any(
                  (diagnostic) => diagnostic.namespace == family.namespace,
                ))) {
          _fail(
            'incompatible-omission',
            'Family ${family.namespace} cannot disappear',
          );
        }
        continue;
      }
      if (family.namespace != replacement.namespace ||
          family.version != replacement.version ||
          family.producerId != replacement.producerId ||
          family.expiresAt != replacement.expiresAt ||
          family.isRequired != replacement.isRequired) {
        _fail('incompatible-family', 'Family identity/lifetime changed');
      }
      final before = family.payload;
      final after = replacement.payload;
      if (before is CorrelationPresentationPayload &&
          after is CorrelationPresentationPayload) {
        if (before.flowReference != after.flowReference) {
          _fail('incompatible-correlation', 'Correlation flow changed');
        }
      } else if (before is OpaquePresentationPayload &&
          after is OpaquePresentationPayload &&
          !family.isRequired &&
          _extension(family)) {
        // Whole bounded replacement; constructor already rechecks JSON limits.
      } else if (before != after) {
        _fail('incompatible-payload', 'Fixed family payload changed');
      }
    }
    return admitted;
  }

  bool _extension(PresentationContextFamily family) => optionalExtensions.any(
    (support) =>
        support.namespace == family.namespace &&
        support.version == family.version &&
        support.producerId == family.producerId,
  );
}

PresentationContextPayload _payload(
  String namespace,
  int version,
  Map<String, Object?> json,
) {
  final values = _bounded(json);
  if (version != 1) {
    return OpaquePresentationPayload(values);
  }
  switch (namespace) {
    case _locale:
      _keys(values, ['localeTag']);
      return LocalePresentationPayload(localeTag: _id(values['localeTag']));
    case _arm:
      _keys(values, [
        'namespace',
        'presentationSet',
        'armId',
        'definitionVersion',
        'assignmentReference',
      ]);
      return SuppliedArmPresentationPayload(
        namespace: _id(values['namespace']),
        presentationSet: _id(values['presentationSet']),
        armId: _id(values['armId']),
        definitionVersion: _positive(values['definitionVersion']),
        assignmentReference: _id(values['assignmentReference']),
      );
    case _correlation:
      _keys(values, ['flowReference', 'attemptReference']);
      return CorrelationPresentationPayload(
        flowReference: _id(values['flowReference']),
        attemptReference: _id(values['attemptReference']),
      );
    default:
      return OpaquePresentationPayload(values);
  }
}

Map<String, Object?> _bounded(Map<String, Object?> values) {
  final frozen = _freeze(values, 1) as Map<String, Object?>;
  if (utf8.encode(jsonEncode(frozen)).length > 4096) {
    throw const FormatException('Payload exceeds 4096 UTF-8 bytes');
  }
  return frozen;
}

Object? _freeze(Object? value, int depth) {
  if (value is Map) {
    if (depth > 4 || value.keys.any((key) => key is! String)) {
      throw const FormatException('Payload depth/key limit');
    }
    return Map<String, Object?>.unmodifiable(
      value.map(
        (key, item) => MapEntry(key as String, _freeze(item, depth + 1)),
      ),
    );
  }
  if (value is List) {
    if (depth > 4) {
      throw const FormatException('Payload depth limit');
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
  throw const FormatException('Payload must be finite JSON');
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Expected JSON object');
  }
  return Map<String, Object?>.from(value);
}

void _keys(Map<String, Object?> json, List<String> keys) {
  if (json.length != keys.length || !keys.every(json.containsKey)) {
    throw FormatException('Expected exactly ${keys.join(', ')}');
  }
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

bool _bool(Object? value) {
  if (value is! bool) {
    throw const FormatException('Expected bool');
  }
  return value;
}

void _clock(DateTime nowUtc) {
  if (!nowUtc.isUtc) {
    throw const PresentationContextException(
      'clock-not-utc',
      'nowUtc must be explicit UTC',
    );
  }
}

bool _expired(PresentationContextFamily family, DateTime nowUtc) =>
    family.expiresAt != null && !family.expiresAt!.isAfter(nowUtc);
Never _fail(String code, String message) =>
    throw PresentationContextException(code, message);
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
        ).every((item) => item);
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
