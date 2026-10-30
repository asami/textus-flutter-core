import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  group('canonical source region geometry', () {
    test('fractional edges round outward and equality is by value', () {
      // Given fractional normalized rectangle edges on a nonsquare raster.
      final geometry = ImageRegionGeometry(shape: ImageRegionShape.rectangle,
        x: .11, y: .21, width: .32, height: .41);
      // When bounds are calculated and exact JSON is decoded.
      final bounds = geometry.boundsFor(pixelWidth: 13, pixelHeight: 7);
      final decoded = ImageRegionGeometry.fromJson(geometry.toJson());
      // Then the raster includes each rounded bounding pixel without resizing.
      expect(bounds, ImageRegionBounds(left: 1, top: 1, right: 6, bottom: 5));
      expect(ImageRegionBounds.fromJson(bounds.toJson()), bounds);
      expect(ImageRegionBounds.fromJson(bounds.toJson()).hashCode, bounds.hashCode);
      expect(decoded, geometry);
      expect(decoded.hashCode, geometry.hashCode);
      expect(ImageRegionGeometry(shape: ImageRegionShape.rectangle, x: 0, y: 0,
        width: 1, height: 1).boundsFor(pixelWidth: 13, pixelHeight: 7),
        ImageRegionBounds(left: 0, top: 0, right: 13, bottom: 7));
    });

    test('ellipse models physical circles with equal pixel axes', () {
      // Given a 200 by 100 image and a fifty-pixel circular selection.
      final circle = ImageRegionGeometry(shape: ImageRegionShape.ellipse,
        x: .1, y: .2, width: .25, height: .5);
      // When converting the normalized ellipse to raster bounds and JSON.
      final bounds = circle.boundsFor(pixelWidth: 200, pixelHeight: 100);
      // Then a circle uses ellipse wire shape and unequal normalized axes.
      expect(bounds.right - bounds.left, 50);
      expect(bounds.bottom - bounds.top, 50);
      expect(circle.toJson()['shape'], 'ellipse');
      expect(circle.width, isNot(circle.height));
    });

    test('nonfinite empty outside and malformed geometry reject', () {
      // Given invalid normalized selections and exact-schema mutations.
      final bad = <List<double>>[
        [double.nan, 0, 1, 1], [0, double.infinity, 1, 1],
        [0, 0, double.negativeInfinity, 1], [0, 0, 0, 1], [0, 0, 1, 0],
        [-.1, 0, .5, 1], [0, -.1, 1, .5], [.8, 0, .3, 1], [0, .8, 1, .3],
      ];
      final good = ImageRegionGeometry(shape: ImageRegionShape.rectangle, x: 0, y: 0, width: 1, height: 1);
      // When invalid public values and wire payloads are admitted.
      // Then each fails observably, including bool-as-number and unknown keys.
      for (final row in bad) {
        expect(() => ImageRegionGeometry(shape: ImageRegionShape.rectangle,
          x: row[0], y: row[1], width: row[2], height: row[3]), throwsArgumentError);
      }
      for (final json in [
        {...good.toJson(), 'x': true}, {...good.toJson(), 'height': double.nan},
        {...good.toJson(), 'shape': 'circle'}, {...good.toJson(), 'extra': 1},
        good.toJson()..remove('width'),
      ]) { expect(() => ImageRegionGeometry.fromJson(json), throwsFormatException); }
      expect(() => good.boundsFor(pixelWidth: 0, pixelHeight: 1), throwsArgumentError);
      expect(() => ImageRegionBounds(left: 1, top: 0, right: 1, bottom: 1), throwsArgumentError);
      expect(() => ImageRegionBounds.fromJson({'left': false, 'top': 0, 'right': 1, 'bottom': 1}), throwsFormatException);
    });

    test('snapshot and derivation codecs retain exact source frame and detached data', () {
      // Given mutable source extensions and a derived PNG reference.
      final extension = <String, Object?>{'items': <Object?>[1]};
      final source = CaptureMaterialReference(id: 'photo', mediaType: 'image/jpeg',
        byteLength: 99, capturedAt: DateTime.utc(2026), extensions: extension);
      final region = ImageRegionSnapshot(regionId: 'r1', revision: 1, source: source,
        pixelWidth: 20, pixelHeight: 10, geometry: ImageRegionGeometry(
          shape: ImageRegionShape.ellipse, x: 0, y: 0, width: 1, height: 1), recordedAt: DateTime.utc(2026, 1, 2));
      final derivation = ImageRegionDerivation(region: region,
        input: CaptureMaterialReference(id: 'crop', mediaType: 'image/png', byteLength: 10,
          capturedAt: region.recordedAt), bounds: region.geometry.boundsFor(pixelWidth: 20, pixelHeight: 10));
      // When caller inputs and encoded nested maps are mutated after decoding.
      (extension['items'] as List).clear();
      final wire = derivation.toJson();
      final decoded = ImageRegionDerivation.fromJson(wire);
      (((wire['region'] as Map)['source'] as Map)['extensions'] as Map).clear();
      // Then original source, version, mask and source extension snapshot survive.
      expect(decoded.region.source, source);
      expect(source.extensions['items'], [1]);
      expect(decoded.region.frameVersion, 'exifUprightV1');
      expect(decoded.maskMethod, 'ellipsePixelCenterWhiteV1');
      expect(decoded.input.id, 'crop');
      expect(() => ImageRegionSnapshot.fromJson({...region.toJson(), 'frameVersion': 'raw'}), throwsFormatException);
      expect(() => ImageRegionSnapshot.fromJson({...region.toJson(), 'revision': true}), throwsFormatException);
      expect(() => ImageRegionSnapshot.fromJson({...region.toJson(), 'recordedAt': '2026-02-30T00:00:00Z'}), throwsFormatException);
      expect(() => ImageRegionSnapshot.fromJson({...region.toJson(), 'recordedAt': '2026-01-02T00:00:00'}), throwsFormatException);
      expect(() => ImageRegionDerivation.fromJson({...derivation.toJson(), 'maskMethod': 'rectangleBoundsV1'}), throwsFormatException);
      expect(() => ImageRegionDerivation(region: region, input: source, bounds: derivation.bounds), throwsArgumentError);
      expect(() => ImageRegionDerivation(region: region, input: derivation.input,
        bounds: ImageRegionBounds(left: 1, top: 0, right: 20, bottom: 10)), throwsArgumentError);
      expect(() => ImageRegionSnapshot(regionId: '../bad', revision: 1, source: source,
        pixelWidth: 20, pixelHeight: 10, geometry: region.geometry, recordedAt: region.recordedAt), throwsArgumentError);
    });
  });
}
