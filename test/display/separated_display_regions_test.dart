import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  test('recognizes vertical and horizontal physical gaps', () {
    final vertical = SeparatedDisplayRegions.fromMediaQuery(
      _media(const Rect.fromLTWH(310, 0, 20, 800)),
    );
    final horizontal = SeparatedDisplayRegions.fromMediaQuery(
      _media(const Rect.fromLTWH(0, 390, 640, 20)),
    );

    expect(vertical?.axis, Axis.horizontal);
    expect(vertical?.leading, const Rect.fromLTRB(0, 0, 310, 800));
    expect(vertical?.separation, const Rect.fromLTRB(310, 0, 330, 800));
    expect(vertical?.trailing, const Rect.fromLTRB(330, 0, 640, 800));
    expect(vertical?.hasOcclusion, isTrue);
    expect(horizontal?.axis, Axis.vertical);
    expect(horizontal?.leading, const Rect.fromLTRB(0, 0, 640, 390));
    expect(horizontal?.separation, const Rect.fromLTRB(0, 390, 640, 410));
    expect(horizontal?.trailing, const Rect.fromLTRB(0, 410, 640, 800));
    expect(horizontal?.hasOcclusion, isTrue);
  });

  test('preserves zero-thickness vertical and horizontal folds', () {
    final vertical = SeparatedDisplayRegions.fromMediaQuery(
      _media(
        const Rect.fromLTWH(320, 0, 0, 800),
        type: DisplayFeatureType.fold,
      ),
    );
    final horizontal = SeparatedDisplayRegions.fromMediaQuery(
      _media(
        const Rect.fromLTWH(0, 400, 640, 0),
        type: DisplayFeatureType.fold,
      ),
    );

    expect(vertical?.separation, const Rect.fromLTRB(320, 0, 320, 800));
    expect(horizontal?.separation, const Rect.fromLTRB(0, 400, 640, 400));
    expect(vertical?.hasOcclusion, isFalse);
    expect(horizontal?.hasOcclusion, isFalse);
  });

  test('ignores cutouts and partial display features', () {
    final cutout = SeparatedDisplayRegions.fromMediaQuery(
      _media(
        const Rect.fromLTWH(0, 390, 640, 20),
        type: DisplayFeatureType.cutout,
      ),
    );
    final partial = SeparatedDisplayRegions.fromMediaQuery(
      _media(const Rect.fromLTWH(310, 100, 20, 600)),
    );

    expect(cutout, isNull);
    expect(partial, isNull);
  });

  test('clips all regions in full-view coordinates', () {
    final regions = SeparatedDisplayRegions.fromMediaQuery(
      _media(const Rect.fromLTWH(310, 0, 20, 800)),
      viewport: const Rect.fromLTWH(100, 120, 300, 500),
    );

    expect(regions?.leading, const Rect.fromLTRB(100, 120, 310, 620));
    expect(regions?.separation, const Rect.fromLTRB(310, 120, 330, 620));
    expect(regions?.trailing, const Rect.fromLTRB(330, 120, 400, 620));
  });

  test('keeps a gap that partly intersects a viewport edge', () {
    final regions = SeparatedDisplayRegions.fromMediaQuery(
      _media(const Rect.fromLTWH(310, 0, 20, 800)),
      viewport: const Rect.fromLTWH(320, 100, 100, 600),
    );

    expect(regions?.leading.isEmpty, isTrue);
    expect(regions?.separation, const Rect.fromLTRB(320, 100, 330, 700));
    expect(regions?.trailing, const Rect.fromLTRB(330, 100, 420, 700));
  });

  test('returns empty panes for a viewport entirely in a physical gap', () {
    final regions = SeparatedDisplayRegions.fromMediaQuery(
      _media(const Rect.fromLTWH(310, 0, 20, 800)),
      viewport: const Rect.fromLTWH(312, 100, 10, 600),
    );

    expect(regions, isNotNull);
    expect(regions?.leading.isEmpty, isTrue);
    expect(regions?.trailing.isEmpty, isTrue);
    expect(regions?.separation, const Rect.fromLTRB(312, 100, 322, 700));
  });

  test('returns null when a separator is wholly outside the viewport', () {
    final regions = SeparatedDisplayRegions.fromMediaQuery(
      _media(const Rect.fromLTWH(310, 0, 20, 800)),
      viewport: const Rect.fromLTWH(0, 100, 300, 600),
    );

    expect(regions, isNull);
  });

  test(
    'ignores vertical separators that only touch requested viewport edges',
    () {
      // Given a full-height vertical gap and zero-thickness fold.
      final gap = _media(const Rect.fromLTWH(310, 0, 20, 800));
      final fold = _media(
        const Rect.fromLTWH(320, 0, 0, 800),
        type: DisplayFeatureType.fold,
      );

      // When each separator edge exactly meets a requested viewport edge.
      final gapLeading = SeparatedDisplayRegions.fromMediaQuery(
        gap,
        viewport: const Rect.fromLTWH(0, 100, 310, 600),
      );
      final gapTrailing = SeparatedDisplayRegions.fromMediaQuery(
        gap,
        viewport: const Rect.fromLTWH(330, 100, 100, 600),
      );
      final foldLeading = SeparatedDisplayRegions.fromMediaQuery(
        fold,
        viewport: const Rect.fromLTWH(0, 100, 320, 600),
      );
      final foldTrailing = SeparatedDisplayRegions.fromMediaQuery(
        fold,
        viewport: const Rect.fromLTWH(320, 100, 100, 600),
      );

      // Then none establishes a split for that viewport.
      expect(gapLeading, isNull);
      expect(gapTrailing, isNull);
      expect(foldLeading, isNull);
      expect(foldTrailing, isNull);
    },
  );

  test(
    'ignores horizontal separators that only touch requested viewport edges',
    () {
      // Given a full-width horizontal gap and zero-thickness fold.
      final gap = _media(const Rect.fromLTWH(0, 390, 640, 20));
      final fold = _media(
        const Rect.fromLTWH(0, 400, 640, 0),
        type: DisplayFeatureType.fold,
      );

      // When each separator edge exactly meets a requested viewport edge.
      final gapLeading = SeparatedDisplayRegions.fromMediaQuery(
        gap,
        viewport: const Rect.fromLTWH(100, 0, 400, 390),
      );
      final gapTrailing = SeparatedDisplayRegions.fromMediaQuery(
        gap,
        viewport: const Rect.fromLTWH(100, 410, 400, 300),
      );
      final foldLeading = SeparatedDisplayRegions.fromMediaQuery(
        fold,
        viewport: const Rect.fromLTWH(100, 0, 400, 400),
      );
      final foldTrailing = SeparatedDisplayRegions.fromMediaQuery(
        fold,
        viewport: const Rect.fromLTWH(100, 400, 400, 300),
      );

      // Then none establishes a split for that viewport.
      expect(gapLeading, isNull);
      expect(gapTrailing, isNull);
      expect(foldLeading, isNull);
      expect(foldTrailing, isNull);
    },
  );

  test('clamps spanning bounds and rejects invalid view or feature bounds', () {
    final clamped = SeparatedDisplayRegions.fromMediaQuery(
      _media(const Rect.fromLTWH(310, -20, 20, 840)),
    );
    final invalidSize = SeparatedDisplayRegions.fromMediaQuery(
      const MediaQueryData(size: Size(0, 800)),
    );
    final invalidBounds = SeparatedDisplayRegions.fromMediaQuery(
      _media(const Rect.fromLTWH(-1, 0, 20, 800)),
    );
    final nonFiniteBounds = SeparatedDisplayRegions.fromMediaQuery(
      _media(Rect.fromLTWH(double.nan, 0, 20, 800)),
    );

    expect(clamped?.separation, const Rect.fromLTRB(310, 0, 330, 800));
    expect(invalidSize, isNull);
    expect(invalidBounds, isNull);
    expect(nonFiniteBounds, isNull);
  });
}

MediaQueryData _media(
  Rect bounds, {
  DisplayFeatureType type = DisplayFeatureType.hinge,
}) => MediaQueryData(
  size: const Size(640, 800),
  displayFeatures: [
    DisplayFeature(
      bounds: bounds,
      type: type,
      state: type == DisplayFeatureType.cutout
          ? DisplayFeatureState.unknown
          : DisplayFeatureState.postureFlat,
    ),
  ],
);
