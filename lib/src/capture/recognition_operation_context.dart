import 'dart:collection';

/// Immutable caller intent for one recognition operation on one original.
///
/// Roles and candidate kinds are opaque vocabulary owned by the caller. This
/// metadata requests work; it never proves extraction or provider execution.
final class RecognitionOperationContext {
  /// Snapshots exact nonblank values and deeply freezes finite JSON extensions.
  /// Throws [ArgumentError] for blank, empty, duplicate or invalid JSON values.
  RecognitionOperationContext({
    required String sourceRole,
    required Iterable<String> targetKinds,
    required String instructions,
    Map<String, Object?> extensions = const {},
  }) : sourceRole = _nonblank(sourceRole, 'sourceRole'),
       targetKinds = _kinds(targetKinds),
       instructions = _nonblank(instructions, 'instructions'),
       extensions = _freeze(extensions, HashSet<Object>.identity())
           as Map<String, Object?>;

  /// Optional namespace in the unchanged version1 raw comparison report.
  static const extensionKey = 'recognitionOperationContext';

  /// Exact caller-assigned role, without normalization or domain inference.
  final String sourceRole;

  /// Distinct, ordered, nonempty caller-requested candidate kinds.
  final List<String> targetKinds;

  /// Trusted caller instructions, separate from raw source data and metadata.
  final String instructions;

  /// Deeply immutable caller metadata containing only finite, acyclic JSON.
  final Map<String, Object?> extensions;

  /// Returns a detached mutable wire snapshot with exactly the schema1 keys.
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'sourceRole': sourceRole,
    'targetKinds': List<String>.of(targetKinds),
    'instructions': instructions,
    'extensions': _detach(extensions),
  };

  /// Strictly decodes schema1; malformed keys, types and values throw
  /// [FormatException]. Absence is handled by the owning report namespace.
  factory RecognitionOperationContext.fromJson(Object? value) {
    const keys = {
      'schemaVersion', 'sourceRole', 'targetKinds', 'instructions', 'extensions',
    };
    if (value is! Map || value.length != keys.length ||
        !value.keys.every(keys.contains)) {
      throw const FormatException('Invalid recognition operation context keys');
    }
    final version = value['schemaVersion'];
    final role = value['sourceRole'];
    final kinds = value['targetKinds'];
    final instructions = value['instructions'];
    final extensions = value['extensions'];
    if (version is! int || version != 1 || role is! String ||
        kinds is! List || kinds.any((kind) => kind is! String) ||
        instructions is! String || extensions is! Map ||
        extensions.keys.any((key) => key is! String)) {
      throw const FormatException('Invalid recognition operation context types');
    }
    try {
      return RecognitionOperationContext(
        sourceRole: role,
        targetKinds: kinds.cast<String>(),
        instructions: instructions,
        extensions: Map<String, Object?>.from(extensions),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid recognition operation context: $error');
    }
  }

  @override
  bool operator ==(Object other) => other is RecognitionOperationContext &&
      sourceRole == other.sourceRole && instructions == other.instructions &&
      _equal(targetKinds, other.targetKinds) &&
      _equal(extensions, other.extensions);

  @override
  int get hashCode => Object.hash(
    sourceRole, instructions, _hash(targetKinds), _hash(extensions),
  );
}

String _nonblank(String value, String name) {
  if (value.trim().isEmpty) throw ArgumentError.value(value, name, 'blank');
  return value;
}

List<String> _kinds(Iterable<String> values) {
  final result = values.map((value) => _nonblank(value, 'targetKinds')).toList();
  if (result.isEmpty || result.toSet().length != result.length) {
    throw ArgumentError('Target kinds must be distinct and nonempty');
  }
  return List<String>.unmodifiable(result);
}

Object? _freeze(Object? value, Set<Object> ancestors) {
  if (value == null || value is String || value is bool) return value;
  if (value is num && value.isFinite) return value;
  if (value is! Map && value is! List) {
    throw ArgumentError('Operation extensions must contain only finite JSON');
  }
  if (!ancestors.add(value)) {
    throw ArgumentError('Operation extensions must not be cyclic');
  }
  try {
    if (value is Map) {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw ArgumentError('Operation extension keys must be strings');
        }
        result[entry.key as String] = _freeze(entry.value, ancestors);
      }
      return Map<String, Object?>.unmodifiable(result);
    }
    return List<Object?>.unmodifiable(
      (value as List).map((item) => _freeze(item, ancestors)),
    );
  } finally {
    ancestors.remove(value);
  }
}

Object? _detach(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries) entry.key as String: _detach(entry.value),
    };
  }
  if (value is List) return value.map(_detach).toList();
  return value;
}

bool _equal(Object? first, Object? second) {
  if (first is Map && second is Map) {
    return first.length == second.length && first.keys.every(
      (key) => second.containsKey(key) && _equal(first[key], second[key]),
    );
  }
  if (first is List && second is List) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (!_equal(first[index], second[index])) return false;
    }
    return true;
  }
  return first == second;
}

int _hash(Object? value) {
  if (value is Map) {
    return Object.hashAllUnordered(value.entries.map(
      (entry) => Object.hash(entry.key, _hash(entry.value)),
    ));
  }
  if (value is List) return Object.hashAll(value.map(_hash));
  return value.hashCode;
}
