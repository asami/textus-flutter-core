import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  test('vertical hinge yields two usable regions and a physical gap', () {
    // Given a full-height vertical hinge in a 640-pixel Flutter view.
    const mediaQuery = MediaQueryData(
      size: Size(640, 800),
      displayFeatures: [
        DisplayFeature(
          bounds: Rect.fromLTWH(310, 0, 20, 800),
          type: DisplayFeatureType.hinge,
          state: DisplayFeatureState.postureFlat,
        ),
      ],
    );

    // When Core interprets the display feature.
    final regions = SideBySideDisplayRegions.fromMediaQuery(mediaQuery);

    // Then it exposes both panes without including the hinge in either pane.
    expect(regions?.leadingWidth, 310);
    expect(regions?.separationWidth, 20);
    expect(regions?.trailingWidth, 310);
  });

  test('zero-width vertical fold yields two adjoining regions', () {
    // Given a full-height fold without an obstructing physical gap.
    const mediaQuery = MediaQueryData(
      size: Size(640, 800),
      displayFeatures: [
        DisplayFeature(
          bounds: Rect.fromLTWH(320, 0, 0, 800),
          type: DisplayFeatureType.fold,
          state: DisplayFeatureState.postureHalfOpened,
        ),
      ],
    );

    // When Core interprets the fold.
    final regions = SideBySideDisplayRegions.fromMediaQuery(mediaQuery);

    // Then both logical panes remain available and the gap is zero.
    expect(regions?.leadingWidth, 320);
    expect(regions?.separationWidth, 0);
    expect(regions?.trailingWidth, 320);
  });

  test('cutouts and horizontal hinges do not create side-by-side regions', () {
    // Given only a cutout and a full-width horizontal hinge.
    const mediaQuery = MediaQueryData(
      size: Size(640, 800),
      displayFeatures: [
        DisplayFeature(
          bounds: Rect.fromLTWH(280, 0, 80, 20),
          type: DisplayFeatureType.cutout,
          state: DisplayFeatureState.unknown,
        ),
        DisplayFeature(
          bounds: Rect.fromLTWH(0, 390, 640, 20),
          type: DisplayFeatureType.hinge,
          state: DisplayFeatureState.postureFlat,
        ),
      ],
    );

    // When Core checks for a vertical separation.
    final regions = SideBySideDisplayRegions.fromMediaQuery(mediaQuery);

    // Then TFAF has no side-by-side fold geometry to consume.
    expect(regions, isNull);
  });
}
