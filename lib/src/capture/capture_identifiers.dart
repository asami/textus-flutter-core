import 'dart:collection';

/// Identifies one capture session.
final class CaptureSessionId {
  /// Creates a session identifier from a non-blank [value].
  CaptureSessionId(String value) : value = _requireNonBlank(value, 'value');

  /// The externally supplied identifier value.
  final String value;

  @override
  bool operator ==(Object other) =>
      other is CaptureSessionId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'CaptureSessionId($value)';
}

/// Identifies one item within a capture session.
final class CaptureItemId {
  /// Creates an item identifier from a non-blank [value].
  CaptureItemId(String value) : value = _requireNonBlank(value, 'value');

  /// The externally supplied identifier value.
  final String value;

  @override
  bool operator ==(Object other) =>
      other is CaptureItemId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'CaptureItemId($value)';
}

/// Names an externally defined kind of captured item.
///
/// This is an open value type so applications can introduce their own kinds.
final class CaptureItemType {
  /// Creates an item type from a non-blank [value].
  CaptureItemType(String value) : value = _requireNonBlank(value, 'value');

  /// The externally supplied item-type value.
  final String value;

  @override
  bool operator ==(Object other) =>
      other is CaptureItemType && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'CaptureItemType($value)';
}

/// Names an externally defined source of capture provenance.
///
/// This is an open value type so applications can introduce their own sources.
final class CaptureProvenanceSource {
  /// Creates a provenance source from a non-blank [value].
  CaptureProvenanceSource(String value)
    : value = _requireNonBlank(value, 'value');

  /// The externally supplied provenance-source value.
  final String value;

  @override
  bool operator ==(Object other) =>
      other is CaptureProvenanceSource && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'CaptureProvenanceSource($value)';
}

/// Immutable descriptive data associated with a captured item.
final class CaptureMetadata {
  /// Creates metadata from a defensive copy of [data].
  CaptureMetadata(Map<String, String> data)
    : _data = UnmodifiableMapView(Map<String, String>.of(data));

  final Map<String, String> _data;

  /// An immutable snapshot of the metadata data.
  Map<String, String> get data => _data;
}

/// Immutable record of where and when a captured item originated.
final class CaptureProvenance {
  /// Creates provenance with [source], [recordedAt], and a defensive copy of
  /// [data].
  CaptureProvenance({
    required this.source,
    required this.recordedAt,
    required Map<String, String> data,
  }) : _data = UnmodifiableMapView(Map<String, String>.of(data));

  /// The open value identifying the source of the capture.
  final CaptureProvenanceSource source;

  /// The time at which the provenance was recorded.
  final DateTime recordedAt;

  final Map<String, String> _data;

  /// An immutable snapshot of the provenance data.
  Map<String, String> get data => _data;
}

String _requireNonBlank(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be blank');
  }
  return value;
}
