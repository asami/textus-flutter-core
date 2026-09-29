import 'dart:math' as math;
import 'dart:ui' show DisplayFeatureType;

import 'package:flutter/widgets.dart';

/// Usable regions on either side of one full-span fold or hinge.
///
/// [Axis.horizontal] represents a left/right separation; [Axis.vertical]
/// represents a top/bottom separation. All rectangles use the full Flutter
/// view's logical coordinate space, even when [fromMediaQuery] clips them to a
/// smaller [viewport].
///
/// This class recognizes only the first relevant full-span separator. It does
/// not model partial features or partition a view around multiple features.
class SeparatedDisplayRegions {
  const SeparatedDisplayRegions._({
    required this.axis,
    required this.leading,
    required this.separation,
    required this.trailing,
  });

  /// The axis on which the separator divides the view.
  final Axis axis;

  /// The left or upper usable region.
  final Rect leading;

  /// The fold or hinge bounds between [leading] and [trailing].
  final Rect separation;

  /// The right or lower usable region.
  final Rect trailing;

  /// Whether the separator has a positive physical thickness.
  bool get hasOcclusion =>
      axis == Axis.horizontal ? separation.width > 0 : separation.height > 0;

  /// Reads the first full-height vertical or full-width horizontal fold/hinge.
  ///
  /// The optional [viewport] is intersected with the Flutter view before the
  /// returned regions are constructed. A separator outside that viewport does
  /// not establish regions for it. Zero-thickness folds retain their separator
  /// coordinate when the viewport includes that coordinate.
  static SeparatedDisplayRegions? fromMediaQuery(
    MediaQueryData data, {
    Rect? viewport,
  }) {
    final size = data.size;
    if (!_isFinitePositive(size.width) || !_isFinitePositive(size.height)) {
      return null;
    }
    final screen = Rect.fromLTWH(0, 0, size.width, size.height);
    final requestedViewport = viewport ?? screen;
    if (!_isFiniteRect(requestedViewport)) return null;
    final clippedViewport = _clip(requestedViewport, screen);
    if (clippedViewport.isEmpty) return null;

    for (final feature in data.displayFeatures) {
      if (feature.type != DisplayFeatureType.fold &&
          feature.type != DisplayFeatureType.hinge) {
        continue;
      }
      final bounds = feature.bounds;
      if (!_isFiniteRect(bounds)) continue;
      final clampedBounds = _clip(bounds, screen);
      const tolerance = 1.0;
      final isVertical =
          bounds.top <= tolerance &&
          bounds.bottom >= size.height - tolerance &&
          clampedBounds.left > 0 &&
          clampedBounds.right < size.width;
      final isHorizontal =
          bounds.left <= tolerance &&
          bounds.right >= size.width - tolerance &&
          clampedBounds.top > 0 &&
          clampedBounds.bottom < size.height;
      if (!isVertical && !isHorizontal) continue;

      final axis = isVertical ? Axis.horizontal : Axis.vertical;
      final fullViewLeading = axis == Axis.horizontal
          ? Rect.fromLTRB(0, 0, clampedBounds.left, size.height)
          : Rect.fromLTRB(0, 0, size.width, clampedBounds.top);
      final fullViewSeparation = axis == Axis.horizontal
          ? Rect.fromLTRB(
              clampedBounds.left,
              0,
              clampedBounds.right,
              size.height,
            )
          : Rect.fromLTRB(
              0,
              clampedBounds.top,
              size.width,
              clampedBounds.bottom,
            );
      final fullViewTrailing = axis == Axis.horizontal
          ? Rect.fromLTRB(clampedBounds.right, 0, size.width, size.height)
          : Rect.fromLTRB(0, clampedBounds.bottom, size.width, size.height);
      if (!_intersectsAlongSplitAxis(
        fullViewSeparation,
        clippedViewport,
        axis,
      )) {
        return null;
      }
      return SeparatedDisplayRegions._(
        axis: axis,
        leading: _clip(fullViewLeading, clippedViewport),
        separation: _clip(fullViewSeparation, clippedViewport),
        trailing: _clip(fullViewTrailing, clippedViewport),
      );
    }
    return null;
  }

  static bool _isFinitePositive(double value) => value.isFinite && value > 0;

  static bool _isFiniteRect(Rect rect) =>
      rect.left.isFinite &&
      rect.top.isFinite &&
      rect.right.isFinite &&
      rect.bottom.isFinite &&
      rect.left <= rect.right &&
      rect.top <= rect.bottom;

  static bool _intersectsAlongSplitAxis(
    Rect separator,
    Rect viewport,
    Axis axis,
  ) => axis == Axis.horizontal
      ? separator.right > viewport.left && separator.left < viewport.right
      : separator.bottom > viewport.top && separator.top < viewport.bottom;

  static Rect _clip(Rect rect, Rect clip) {
    double clamp(double value, double minimum, double maximum) =>
        math.min(math.max(value, minimum), maximum);
    return Rect.fromLTRB(
      clamp(rect.left, clip.left, clip.right),
      clamp(rect.top, clip.top, clip.bottom),
      clamp(rect.right, clip.left, clip.right),
      clamp(rect.bottom, clip.top, clip.bottom),
    );
  }
}
