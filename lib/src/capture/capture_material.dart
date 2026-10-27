import 'dart:collection';

/// Immutable descriptive reference to original bytes in a local capture store.
///
/// [id] is a logical token, never a path or an integrity hash. Extensions carry
/// opaque JSON without domain interpretation or remote-storage semantics.
final class CaptureMaterialReference {
  /// Snapshots and freezes all nested [extensions].
  ///
  /// Throws [ArgumentError] for unsafe identity, invalid MIME-like media type,
  /// nonpositive length, or non-JSON/cyclic/nonfinite extension values.
  CaptureMaterialReference({
    required String id,
    required String mediaType,
    required int byteLength,
    required DateTime capturedAt,
    this.originalName,
    Map<String, Object?> extensions = const <String, Object?>{},
  }) : id = _requireToken(id),
       mediaType = _requireMediaType(mediaType),
       byteLength = _requireLength(byteLength),
       capturedAt = capturedAt.toUtc(),
       extensions = _freezeJson(extensions, HashSet<Object>.identity())
           as Map<String, Object?>;

  /// Logical identity within the configured local store.
  final String id;

  /// MIME-like description of the unchanged original bytes.
  final String mediaType;

  /// Positive original byte length used to detect inconsistent local reads.
  final int byteLength;

  /// Capture time normalized to UTC.
  final DateTime capturedAt;

  /// Optional descriptive original name; never used as a storage path.
  final String? originalName;

  /// Immutable, deeply frozen JSON extension snapshot.
  final Map<String, Object?> extensions;

  /// Serializes the exact public keys and UTC ISO capture time.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'mediaType': mediaType,
    'byteLength': byteLength,
    'capturedAt': capturedAt.toIso8601String(),
    'originalName': originalName,
    'extensions': extensions,
  };

  /// Decodes the exact public schema, rejecting missing/unknown keys and types.
  ///
  /// Throws [FormatException] for malformed data, including invalid values.
  /// The capture time uses ISO date/time with an explicit timezone and is
  /// normalized to UTC. No absolute storage path is accepted or inferred.
  factory CaptureMaterialReference.fromJson(Map<String, Object?> json) {
    const keys = <String>{
      'id', 'mediaType', 'byteLength', 'capturedAt', 'originalName', 'extensions',
    };
    if (json.length != keys.length || !json.keys.every(keys.contains)) {
      throw const FormatException('Invalid capture material reference keys');
    }
    final id = json['id'];
    final mediaType = json['mediaType'];
    final byteLength = json['byteLength'];
    final capturedAt = json['capturedAt'];
    final originalName = json['originalName'];
    final extensions = json['extensions'];
    if (id is! String || mediaType is! String || byteLength is! int ||
        capturedAt is! String ||
        (originalName != null && originalName is! String) ||
        extensions is! Map || extensions.keys.any((key) => key is! String)) {
      throw const FormatException('Invalid capture material reference types');
    }
    final time = _parseCaptureTime(capturedAt);
    try {
      return CaptureMaterialReference(
        id: id,
        mediaType: mediaType,
        byteLength: byteLength,
        capturedAt: time,
        originalName: originalName as String?,
        extensions: Map<String, Object?>.from(extensions),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid capture material reference: $error');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is CaptureMaterialReference &&
      id == other.id && mediaType == other.mediaType &&
      byteLength == other.byteLength && capturedAt == other.capturedAt &&
      originalName == other.originalName &&
      _jsonEquals(extensions, other.extensions);

  /// Ordinary Dart value hashing; not an integrity or control hash.
  @override
  int get hashCode => Object.hash(
    id, mediaType, byteLength, capturedAt, originalName, _jsonHash(extensions),
  );
}

DateTime _parseCaptureTime(String value) {
  final match = RegExp(
    r'^([+-]?\d{4,6})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})'
    r'(?:\.(\d{1,6}))?(Z|[+-]\d{2}:\d{2})$',
  ).firstMatch(value);
  final parsed = DateTime.tryParse(value);
  if (match == null || parsed == null) {
    throw const FormatException('Invalid ISO capture time');
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.parse(match.group(6)!);
  final zone = match.group(8)!;
  if (zone != 'Z' && (int.parse(zone.substring(1, 3)) > 23 ||
      int.parse(zone.substring(4, 6)) > 59)) {
    throw const FormatException('Invalid capture timezone');
  }
  try {
    final calendar = DateTime.utc(year, month, day, hour, minute, second);
    if (calendar.year != year || calendar.month != month || calendar.day != day ||
        calendar.hour != hour || calendar.minute != minute ||
        calendar.second != second) {
      throw const FormatException('Invalid capture calendar date/time');
    }
  } on ArgumentError {
    throw const FormatException('Invalid capture calendar date/time');
  }
  return parsed.toUtc();
}

String _requireToken(String value) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(value)) {
    throw ArgumentError.value(value, 'id', 'must be a safe identity token');
  }
  return value;
}

String _requireMediaType(String value) {
  if (!RegExp(r"^[A-Za-z0-9!#$%&'*+.^_`|~-]+/[A-Za-z0-9!#$%&'*+.^_`|~-]+$")
      .hasMatch(value)) {
    throw ArgumentError.value(value, 'mediaType', 'must be a MIME-like type');
  }
  return value;
}

int _requireLength(int value) {
  if (value <= 0) {
    throw ArgumentError.value(value, 'byteLength', 'must be positive');
  }
  return value;
}

Object? _freezeJson(Object? value, Set<Object> ancestors) {
  if (value == null || value is String || value is bool) return value;
  if (value is num && value.isFinite) return value;
  if (value is! Map && value is! List) {
    throw ArgumentError.value(value, 'extensions', 'must contain only JSON');
  }
  if (!ancestors.add(value)) {
    throw ArgumentError('JSON extensions must not be cyclic');
  }
  try {
    if (value is Map) {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw ArgumentError('JSON extension keys must be strings');
        }
        result[entry.key as String] = _freezeJson(entry.value, ancestors);
      }
      return Map<String, Object?>.unmodifiable(result);
    }
    return List<Object?>.unmodifiable(
      (value as List).map((item) => _freezeJson(item, ancestors)),
    );
  } finally {
    ancestors.remove(value);
  }
}

bool _jsonEquals(Object? first, Object? second) {
  if (first is Map && second is Map) {
    return first.length == second.length && first.keys.every(
      (key) => second.containsKey(key) && _jsonEquals(first[key], second[key]),
    );
  }
  if (first is List && second is List) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (!_jsonEquals(first[index], second[index])) return false;
    }
    return true;
  }
  return first == second;
}

int _jsonHash(Object? value) {
  if (value is Map) {
    return Object.hashAllUnordered(value.entries.map(
      (entry) => Object.hash(entry.key, _jsonHash(entry.value)),
    ));
  }
  if (value is List) return Object.hashAll(value.map(_jsonHash));
  return value.hashCode;
}
