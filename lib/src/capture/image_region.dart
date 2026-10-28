import 'capture_material.dart';
import 'recognition_report.dart';
import 'recognition_report_codec.dart';

/// Axis-aligned selection in the canonical upright source raster.
enum ImageRegionShape { rectangle, ellipse }

/// Immutable normalized geometry; a physical circle has equal pixel axes.
final class ImageRegionGeometry {
  /// Rejects nonfinite, empty or out-of-frame selections.
  ImageRegionGeometry({required this.shape, required this.x, required this.y,
    required this.width, required this.height}) {
    if (![x, y, width, height].every((v) => v.isFinite) || x < 0 || y < 0 ||
        width <= 0 || height <= 0 || x + width > 1 || y + height > 1) {
      throw ArgumentError('Geometry must be a positive normalized selection');
    }
  }
  /// Selection mask shape.
  final ImageRegionShape shape;
  /// Normalized left edge.
  final double x;
  /// Normalized top edge.
  final double y;
  /// Normalized horizontal extent.
  final double width;
  /// Normalized vertical extent.
  final double height;

  /// Rounded bounds in the source raster, with exclusive right and bottom.
  ImageRegionBounds boundsFor({required int pixelWidth, required int pixelHeight}) {
    if (pixelWidth <= 0 || pixelHeight <= 0) throw ArgumentError('Invalid raster');
    return ImageRegionBounds(
      left: (x * pixelWidth).floor().clamp(0, pixelWidth),
      top: (y * pixelHeight).floor().clamp(0, pixelHeight),
      right: ((x + width) * pixelWidth).ceil().clamp(0, pixelWidth),
      bottom: ((y + height) * pixelHeight).ceil().clamp(0, pixelHeight),
    );
  }
  /// Detached exact wire representation.
  Map<String, Object?> toJson() => {'shape': shape.name, 'x': x, 'y': y,
    'width': width, 'height': height};
  /// Strict exact-key decoder.
  factory ImageRegionGeometry.fromJson(Map<String, Object?> json) => _decode(() {
    _keys(json, {'shape', 'x', 'y', 'width', 'height'});
    final shape = ImageRegionShape.values.where((v) => v.name == json['shape']);
    if (shape.isEmpty) throw const FormatException('Invalid region shape');
    return ImageRegionGeometry(shape: shape.single, x: _number(json['x']),
      y: _number(json['y']), width: _number(json['width']), height: _number(json['height']));
  });
  @override
  bool operator ==(Object other) => other is ImageRegionGeometry &&
      shape == other.shape && x == other.x && y == other.y &&
      width == other.width && height == other.height;
  @override
  int get hashCode => Object.hash(shape, x, y, width, height);
}

/// Positive integer rectangle in a raster, right and bottom exclusive.
final class ImageRegionBounds {
  /// Requires nonnegative edges and positive extents.
  ImageRegionBounds({required this.left, required this.top, required this.right,
    required this.bottom}) {
    if (left < 0 || top < 0 || right <= left || bottom <= top) {
      throw ArgumentError('Invalid region bounds');
    }
  }
  /// Inclusive left edge.
  final int left;
  /// Inclusive top edge.
  final int top;
  /// Exclusive right edge.
  final int right;
  /// Exclusive bottom edge.
  final int bottom;
  /// Exact integer wire representation.
  Map<String, Object?> toJson() => {'left': left, 'top': top, 'right': right, 'bottom': bottom};
  /// Strict exact-key decoder.
  factory ImageRegionBounds.fromJson(Map<String, Object?> json) => _decode(() {
    _keys(json, {'left', 'top', 'right', 'bottom'});
    return ImageRegionBounds(left: _integer(json['left']), top: _integer(json['top']),
      right: _integer(json['right']), bottom: _integer(json['bottom']));
  });
  @override
  bool operator ==(Object other) => other is ImageRegionBounds && left == other.left &&
      top == other.top && right == other.right && bottom == other.bottom;
  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

/// One immutable revision binding geometry to an exact unchanged source.
final class ImageRegionSnapshot {
  /// Creates a positive revision at or after source capture.
  ImageRegionSnapshot({required String regionId, required this.revision,
    required this.source, required this.pixelWidth, required this.pixelHeight,
    required this.geometry, required DateTime recordedAt})
    : regionId = _token(regionId), recordedAt = recordedAt.toUtc() {
    if (revision <= 0 || pixelWidth <= 0 || pixelHeight <= 0 ||
        !source.mediaType.startsWith('image/') || this.recordedAt.isBefore(source.capturedAt)) {
      throw ArgumentError('Invalid source-bound region revision');
    }
  }
  /// Stable safe region identity.
  final String regionId;
  /// Positive contiguous revision owned by an entry.
  final int revision;
  /// Unchanged original material.
  final CaptureMaterialReference source;
  /// Upright source width.
  final int pixelWidth;
  /// Upright source height.
  final int pixelHeight;
  /// Selection in the upright source raster.
  final ImageRegionGeometry geometry;
  /// UTC revision time.
  final DateTime recordedAt;
  /// Versioned orientation convention.
  String get frameVersion => 'exifUprightV1';
  /// Detached exact wire representation.
  Map<String, Object?> toJson() => {'regionId': regionId, 'revision': revision,
    'source': _detach(source.toJson()), 'pixelWidth': pixelWidth, 'pixelHeight': pixelHeight,
    'geometry': geometry.toJson(), 'recordedAt': recordedAt.toIso8601String(),
    'frameVersion': frameVersion};
  /// Strict exact-key decoder including the supported frame convention.
  factory ImageRegionSnapshot.fromJson(Map<String, Object?> json) => _decode(() {
    _keys(json, {'regionId', 'revision', 'source', 'pixelWidth', 'pixelHeight',
      'geometry', 'recordedAt', 'frameVersion'});
    if (json['frameVersion'] != 'exifUprightV1') throw const FormatException('Unsupported region frame');
    return ImageRegionSnapshot(regionId: _string(json['regionId']), revision: _integer(json['revision']),
      source: CaptureMaterialReference.fromJson(_map(json['source'])),
      pixelWidth: _integer(json['pixelWidth']), pixelHeight: _integer(json['pixelHeight']),
      geometry: ImageRegionGeometry.fromJson(_map(json['geometry'])), recordedAt: _time(json['recordedAt']));
  });
}

/// Provenance of a distinct stored PNG produced from an exact region revision.
final class ImageRegionDerivation {
  /// Validates input identity, timing and exact integer bounds.
  ImageRegionDerivation({required this.region, required this.input, required this.bounds}) {
    if (input.id == region.source.id || input.mediaType != 'image/png' ||
        input.capturedAt.isBefore(region.recordedAt) || bounds != region.geometry.boundsFor(
          pixelWidth: region.pixelWidth, pixelHeight: region.pixelHeight)) {
      throw ArgumentError('Invalid region derivation provenance');
    }
  }
  /// Exact selected revision and original.
  final ImageRegionSnapshot region;
  /// Actual returned store reference for derived PNG bytes.
  final CaptureMaterialReference input;
  /// Integer bounds in the upright source.
  final ImageRegionBounds bounds;
  /// Versioned mask algorithm.
  String get maskMethod => region.geometry.shape == ImageRegionShape.rectangle
      ? 'rectangleBoundsV1' : 'ellipsePixelCenterWhiteV1';
  /// Detached exact wire representation.
  Map<String, Object?> toJson() => {'region': region.toJson(), 'input': _detach(input.toJson()),
    'bounds': bounds.toJson(), 'maskMethod': maskMethod};
  /// Strict exact-key decoder with mask validation.
  factory ImageRegionDerivation.fromJson(Map<String, Object?> json) => _decode(() {
    _keys(json, {'region', 'input', 'bounds', 'maskMethod'});
    final result = ImageRegionDerivation(region: ImageRegionSnapshot.fromJson(_map(json['region'])),
      input: CaptureMaterialReference.fromJson(_map(json['input'])),
      bounds: ImageRegionBounds.fromJson(_map(json['bounds'])));
    if (json['maskMethod'] != result.maskMethod) throw const FormatException('Invalid region mask');
    return result;
  });
}

/// Durable raw recognition comparison linked to its exact derived PNG.
final class ImageRegionExtraction {
  /// Requires matching derived material and monotone report creation time.
  ImageRegionExtraction({required this.derivation, required this.comparison}) {
    if (comparison.material != derivation.input ||
        comparison.createdAt.isBefore(derivation.input.capturedAt)) {
      throw ArgumentError('Extraction must recognize the exact derived material');
    }
  }
  /// Exact crop provenance.
  final ImageRegionDerivation derivation;
  /// Unmodified provider comparison, including empty and failed attempts.
  final RecognitionComparison comparison;
  /// Actual comparison identity.
  String get id => comparison.id;
  /// Raw comparison serialization delegates to the existing report codec.
  Map<String, Object?> toJson() => {'derivation': derivation.toJson(),
    'comparison': RecognitionReportCodec.encode(comparison)};
  /// Strict exact-key decoder.
  factory ImageRegionExtraction.fromJson(Map<String, Object?> json) => _decode(() {
    _keys(json, {'derivation', 'comparison'});
    return ImageRegionExtraction(derivation: ImageRegionDerivation.fromJson(_map(json['derivation'])),
      comparison: RecognitionReportCodec.decode(_map(json['comparison'])));
  });
}

T _decode<T>(T Function() operation) {
  try { return operation(); } on ArgumentError catch (error) {
    throw FormatException('Invalid image region: $error');
  }
}
void _keys(Map<String, Object?> json, Set<String> keys) {
  if (json.length != keys.length || !json.keys.every(keys.contains)) throw const FormatException('Invalid region keys');
}
Map<String, Object?> _map(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) throw const FormatException('Expected region object');
  return Map<String, Object?>.from(value);
}
String _string(Object? value) {
  if (value is! String) throw const FormatException('Expected string');
  return value;
}
int _integer(Object? value) {
  if (value is! int) throw const FormatException('Expected integer');
  return value;
}
double _number(Object? value) {
  if (value is! num || !value.isFinite) throw const FormatException('Expected finite number');
  return value.toDouble();
}
DateTime _time(Object? value) => CaptureMaterialReference.fromJson({'id': 'time',
  'mediaType': 'application/json', 'byteLength': 1, 'capturedAt': _string(value),
  'originalName': null, 'extensions': <String, Object?>{}}).capturedAt;
String _token(String value) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(value)) throw ArgumentError('Unsafe region identity');
  return value;
}
Object? _detach(Object? value) {
  if (value is Map) return <String, Object?>{for (final e in value.entries) e.key as String: _detach(e.value)};
  if (value is List) return value.map(_detach).toList();
  return value;
}
