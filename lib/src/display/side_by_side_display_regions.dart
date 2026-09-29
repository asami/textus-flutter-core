import 'dart:ui' show DisplayFeatureType;

import 'package:flutter/widgets.dart';

/// Usable left/right regions separated by a vertical fold or hinge.
///
/// The dimensions use the full Flutter view's logical coordinate space.
class SideBySideDisplayRegions {
  const SideBySideDisplayRegions._({
    required this.leadingWidth,
    required this.separationWidth,
    required this.trailingWidth,
  });

  final double leadingWidth;
  final double separationWidth;
  final double trailingWidth;

  /// Reads the first full-height vertical fold or hinge in [mediaQuery].
  ///
  /// Cutouts and horizontal folds cannot establish side-by-side regions.
  static SideBySideDisplayRegions? fromMediaQuery(MediaQueryData mediaQuery) {
    final size = mediaQuery.size;
    if (size.width <= 0 || size.height <= 0) return null;

    for (final feature in mediaQuery.displayFeatures) {
      if (feature.type != DisplayFeatureType.fold &&
          feature.type != DisplayFeatureType.hinge) {
        continue;
      }
      final bounds = feature.bounds;
      if (bounds.top > 1 ||
          bounds.bottom < size.height - 1 ||
          bounds.left <= 0 ||
          bounds.right >= size.width) {
        continue;
      }
      return SideBySideDisplayRegions._(
        leadingWidth: bounds.left,
        separationWidth: bounds.width,
        trailingWidth: size.width - bounds.right,
      );
    }
    return null;
  }
}
