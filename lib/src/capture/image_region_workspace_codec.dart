import 'image_region_workspace.dart';

/// Exact schema1 generic workspace codec; absence remains a caller decision.
abstract final class ImageRegionWorkspaceCodec {
  /// Returns detached maps/lists; audio reviews are represented only by links.
  static Map<String, Object?> encode(ImageRegionWorkspace workspace) => {
    'schemaVersion': 1, 'regions': workspace.regions.map((r) => r.toJson()).toList(),
  };

  /// Malformed current data throws [FormatException]. Future integer versions
  /// throw [UnsupportedError], allowing callers to preserve opaque draft data.
  static ImageRegionWorkspace decode(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    if (version is int && version > 1) throw UnsupportedError('Unsupported image region workspace schemaVersion $version');
    if (json.length != 2 || !json.containsKey('schemaVersion') || !json.containsKey('regions') ||
        version is! int || version != 1 || json['regions'] is! List) {
      throw const FormatException('Invalid image region workspace schema');
    }
    try {
      return ImageRegionWorkspace(regions: (json['regions'] as List).map((value) {
        if (value is! Map || value.keys.any((key) => key is! String)) throw const FormatException('Invalid region entry');
        return ImageRegionEntry.fromJson(Map<String, Object?>.from(value));
      }));
    } on ArgumentError catch (error) {
      throw FormatException('Invalid image region workspace: $error');
    }
  }
}
