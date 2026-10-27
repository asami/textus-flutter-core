import 'dart:convert';

/// Immutable JSON envelope, retaining uninterpreted application-owned data.
class SettingsRecord {
  SettingsRecord._({
    required this.version,
    required Map<String, Object?> values,
    required Map<String, Object?> extraFields,
  }) : values = _freezeMap(values),
       extraFields = _freezeMap(extraFields);

  /// Version understood by Core's settings lifecycle.
  static const currentVersion = 1;

  /// Creates an absent-storage baseline without writing catalog defaults.
  factory SettingsRecord.empty() => SettingsRecord._(
    version: currentVersion,
    values: const {},
    extraFields: const {},
  );

  /// Decodes a well-formed envelope, retaining unsupported integer versions.
  /// Malformed JSON and invalid envelope shapes throw [FormatException].
  factory SettingsRecord.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] is! int ||
        decoded['values'] is! Map<String, dynamic>) {
      throw const FormatException(
        'Settings require integer version and values',
      );
    }
    return SettingsRecord._(
      version: decoded['version'] as int,
      values: decoded['values'] as Map<String, dynamic>,
      extraFields: {
        for (final entry in decoded.entries)
          if (entry.key != 'version' && entry.key != 'values')
            entry.key: entry.value,
      },
    );
  }

  /// Retained wire version; unsupported versions are never implicitly upgraded.
  final int version;

  /// Deeply immutable raw values, without registry interpretation or defaults.
  final Map<String, Object?> values;

  /// Deeply immutable fields other than the canonical version and values.
  final Map<String, Object?> extraFields;

  /// Whether ordinary updates may use this envelope.
  bool get isSupported => version == currentVersion;

  /// Overlays only named keys, accepting recursively JSON-representable values.
  /// An unsupported envelope requires explicit [resetVersion] authorization.
  SettingsRecord withUpdates(
    Map<String, Object?> updates, {
    bool resetVersion = false,
  }) {
    if (!isSupported && !resetVersion) {
      throw StateError('Unsupported settings version $version');
    }
    final copiedUpdates = _freezeMap(updates);
    return SettingsRecord._(
      version: resetVersion ? currentVersion : version,
      values: {...values, ...copiedUpdates},
      extraFields: extraFields,
    );
  }

  /// Encodes semantic JSON data, preserving unknown keys and explicit nulls.
  String encode() =>
      jsonEncode({...extraFields, 'version': version, 'values': values});
}

Map<String, Object?> _freezeMap(
  Map<dynamic, dynamic> source, [
  Set<Object>? ancestors,
]) {
  final active = ancestors ?? Set<Object>.identity();
  if (!active.add(source)) {
    throw ArgumentError.value(source, 'value', 'Cyclic JSON data');
  }
  final result = <String, Object?>{};
  try {
    for (final entry in source.entries) {
      if (entry.key is! String) {
        throw ArgumentError.value(entry.key, 'key', 'JSON String key required');
      }
      result[entry.key as String] = _freezeValue(entry.value, active);
    }
  } finally {
    active.remove(source);
  }
  return Map.unmodifiable(result);
}

Object? _freezeValue(Object? value, Set<Object> ancestors) {
  if (value == null || value is bool || value is String || value is int) {
    return value;
  }
  if (value is double && value.isFinite) return value;
  if (value is Map) return _freezeMap(value, ancestors);
  if (value is List) {
    if (!ancestors.add(value)) {
      throw ArgumentError.value(value, 'value', 'Cyclic JSON data');
    }
    try {
      return List<Object?>.unmodifiable(
        value.map((item) => _freezeValue(item, ancestors)),
      );
    } finally {
      ancestors.remove(value);
    }
  }
  throw ArgumentError.value(value, 'value', 'Finite JSON data required');
}
