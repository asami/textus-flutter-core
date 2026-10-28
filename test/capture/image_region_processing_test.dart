import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('canonical upright region processing', () {
    // Independent EXIF corner expectations: original A B / C D.
    const orientations = <int, List<int>>{
      1: [0, 1, 2, 3], 2: [1, 0, 3, 2], 3: [3, 2, 1, 0], 4: [2, 3, 0, 1],
      5: [0, 2, 1, 3], 6: [2, 0, 3, 1], 7: [3, 1, 2, 0], 8: [1, 3, 0, 2],
    };
    for (final orientation in orientations.entries) {
      test('EXIF ${orientation.key} has independent block layout and unchanged JPEG original', () async {
        // Given an encoded nonsquare JPEG with four known color blocks and EXIF.
        final store = _Store();
        final raster = _blocks()..exif.imageIfd.orientation = orientation.key;
        final bytes = Uint8List.fromList(img.encodeJpg(raster, quality: 100));
        final source = await _save(store, bytes, 'image/jpeg');
        final service = _service(store);
        // When canonical display and a full-frame derivation use the same original.
        final frame = await service.loadFrame(source);
        final derivation = await service.derive(_region(source, frame.pixelWidth, frame.pixelHeight));
        final png = img.decodePng(frame.pngBytes)!;
        final crop = img.decodePng(await service.readDerived(derivation))!;
        // Then all corners match independent EXIF expectations exactly once.
        expect(frame.pixelWidth, orientation.key >= 5 ? 16 : 32);
        expect(frame.pixelHeight, orientation.key >= 5 ? 32 : 16);
        for (var i = 0; i < 4; i++) {
          final x = i.isEven ? png.width ~/ 4 : png.width * 3 ~/ 4;
          final y = i < 2 ? png.height ~/ 4 : png.height * 3 ~/ 4;
          _expectColor(png.getPixel(x, y), _colors[orientation.value[i]], tolerance: 12);
          _expectColor(crop.getPixel(x, y), _colors[orientation.value[i]], tolerance: 12);
        }
        expect(png.exif.imageIfd.hasOrientation, isFalse);
        expect(crop.exif.imageIfd.hasOrientation, isFalse);
        expect(await store.readMaterial(source), orderedEquals(bytes));
        final returned = frame.pngBytes;
        returned.fillRange(0, returned.length, 0);
        expect(frame.pngBytes.take(4), [137, 80, 78, 71]);
      });
    }

    test('rectangle rounds outward and ellipse whites only outside original-frame centers', () async {
      // Given a real PNG whose pixels encode their source coordinates.
      final store = _Store();
      final raster = img.Image(width: 8, height: 6, numChannels: 4);
      for (var y = 0; y < 6; y++) {
        for (var x = 0; x < 8; x++) { raster.setPixelRgba(x, y, x * 20, y * 30, 70, 255); }
      }
      final originalBytes = Uint8List.fromList(img.encodePng(raster));
      final source = await _save(store, originalBytes, 'image/png');
      final service = _service(store, clock: () => _at(0));
      final rectangle = _region(source, 8, 6, geometry: ImageRegionGeometry(
        shape: ImageRegionShape.rectangle, x: .2, y: .2, width: .5, height: .5));
      final ellipse = _region(source, 8, 6, geometry: ImageRegionGeometry(
        shape: ImageRegionShape.ellipse, x: .125, y: 0, width: .75, height: 1));
      // When distinct crops are derived without resizing or replacing originals.
      final rect = await service.derive(rectangle);
      final oval = await service.derive(ellipse);
      final rectBytes = await service.readDerived(rect);
      final rectImage = img.decodePng(rectBytes)!;
      final ovalImage = img.decodePng(await service.readDerived(oval))!;
      // Then bounds, exact retained pixels, white mask and actual saved references agree.
      expect(rect.bounds, ImageRegionBounds(left: 1, top: 1, right: 6, bottom: 5));
      expect([rectImage.width, rectImage.height], [5, 4]);
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 5; x++) { _expectColor(rectImage.getPixel(x, y), [(x + 1) * 20, (y + 1) * 30, 70]); }
      }
      expect([ovalImage.width, ovalImage.height], [6, 6]);
      _expectColor(ovalImage.getPixel(0, 0), [255, 255, 255]);
      expect(ovalImage.getPixel(0, 0).a, 255);
      _expectColor(ovalImage.getPixel(3, 3), [80, 90, 70]);
      expect(rect.input.mediaType, 'image/png');
      expect(rect.input.byteLength, rectBytes.length);
      expect(rect.input.id, isNot(source.id));
      expect(oval.input.id, isNot(rect.input.id));
      expect(rect.input.capturedAt, rectangle.recordedAt);
      expect(rect.maskMethod, 'rectangleBoundsV1');
      expect(oval.maskMethod, 'ellipsePixelCenterWhiteV1');
      expect(await store.readMaterial(source), orderedEquals(originalBytes));
    });

    test('resource header corrupt animated and unsupported failures stay observable', () async {
      // Given saved PNGs, a real animated PNG, corrupt bytes and resource bounds.
      final store = _Store();
      final source = await _save(store, Uint8List.fromList(img.encodePng(_blocks())), 'image/png');
      final animation = _blocks();
      animation.addFrame(_blocks());
      final animated = await _save(store, Uint8List.fromList(img.encodePng(animation)), 'image/png');
      final corrupt = await _save(store, Uint8List.fromList([137, 80, 78, 71, 0]), 'image/png');
      final unsupported = await _save(store, Uint8List.fromList([1, 2, 3]), 'image/gif');
      // When unsupported or excessive inputs enter the public service.
      // Then explicit failures retain manual work and never silently resize.
      await expectLater(_service(store, maxEncodedBytes: 5).loadFrame(source), throwsUnsupportedError);
      await expectLater(_service(store, maxPixels: 10).loadFrame(source), throwsUnsupportedError);
      await expectLater(_service(store).loadFrame(animated), throwsUnsupportedError);
      await expectLater(_service(store).loadFrame(corrupt), throwsFormatException);
      await expectLater(_service(store).loadFrame(unsupported), throwsUnsupportedError);
      await expectLater(_service(store).derive(_region(source, 33, 16)), throwsStateError);
      expect(() => _service(store, maxPixels: 0), throwsArgumentError);
      expect(() => _service(store, maxEncodedBytes: 0), throwsArgumentError);
      expect(store.materials.length, 4);
    });

    test('store length return-provenance failures and busy guard release after failures', () async {
      // Given one valid source and a store capable of controlled failures/delays.
      final store = _Store();
      final source = await _save(store, Uint8List.fromList(img.encodePng(_blocks())), 'image/png');
      final service = _service(store);
      store.badReadLength = true;
      // When a failed read is followed by a blocked operation and a failed save.
      await expectLater(service.loadFrame(source), throwsStateError);
      store.badReadLength = false;
      store.readGate = Completer<void>();
      final loading = service.loadFrame(source);
      await expectLater(service.availability(), throwsStateError);
      store.readGate!.complete();
      await loading;
      store.readGate = null;
      store.failMaterialSave = true;
      await expectLater(service.derive(_region(source, 32, 16)), throwsStateError);
      store.failMaterialSave = false;
      store.badSavedReference = true;
      await expectLater(service.derive(_region(source, 32, 16)), throwsStateError);
      store.badSavedReference = false;
      final derivation = await service.derive(_region(source, 32, 16));
      store.badReadLength = true;
      await expectLater(service.readDerived(derivation), throwsStateError);
      store.badReadLength = false;
      // Then subsequent work succeeds and the original remains exact.
      expect((await service.loadFrame(source)).pixelWidth, 32);
      expect((await service.readDerived(derivation)).length, derivation.input.byteLength);
      expect(store.materials[source.id]!.length, source.byteLength);
    });
  });

  group('durable region provenance independent of adoption', () {
    test('derive saves an exact independently reloadable record before returning', () async {
      // Given an original and an ellipse snapshot without any workspace adoption.
      final store = _Store();
      final originalBytes = Uint8List.fromList(img.encodePng(_blocks()));
      final source = await _save(store, originalBytes, 'image/png');
      final snapshot = _region(source, 32, 16, geometry: ImageRegionGeometry(
        shape: ImageRegionShape.ellipse, x: .125, y: .25, width: .5, height: .5));
      final service = _service(store);
      // When derivation returns and a separate service resolves the saved input id.
      final derivation = await service.derive(snapshot);
      final cropBytes = await service.readDerived(derivation);
      final document = await store.readDocument(ImageRegionService.derivationsCollection, derivation.input.id);
      final reopened = _service(store);
      store.failMaterialRead = true;
      final restored = await reopened.findDerivation(derivation.input.id);
      store.failMaterialRead = false;
      // Then exact origin, frame, geometry, bounds, mask and input survive without byte reads.
      expect(document, derivation.toJson());
      expect(restored!.toJson(), derivation.toJson());
      expect(restored.region.toJson(), snapshot.toJson());
      expect(restored.region.source, source);
      expect(restored.region.frameVersion, 'exifUprightV1');
      expect(restored.bounds, ImageRegionBounds(left: 4, top: 4, right: 20, bottom: 12));
      expect(restored.maskMethod, 'ellipsePixelCenterWhiteV1');
      expect(restored.input, derivation.input);
      expect(await reopened.readDerived(restored), orderedEquals(cropBytes));
      expect(await store.readMaterial(source), orderedEquals(originalBytes));
      expect(await store.listDocumentIds(ImageRegionService.derivationsCollection), [derivation.input.id]);
    });

    test('absent unsafe malformed and mismatched lookups fail precisely and release the guard', () async {
      // Given one valid durable record and controlled metadata read failures.
      final store = _Store();
      final source = await _save(store, Uint8List.fromList(img.encodePng(_blocks())), 'image/png');
      final service = _service(store);
      final derivation = await service.derive(_region(source, 32, 16));
      final key = '${ImageRegionService.derivationsCollection}/${derivation.input.id}';
      final valid = derivation.toJson();
      // When absence and unsafe ids are queried, no unrelated document is read.
      expect(await service.findDerivation('absent'), isNull);
      store.documentReads.clear();
      for (final id in ['', '../escape', 'with/slash', 'space id', '_leading', List.filled(129, 'a').join()]) {
        await expectLater(service.findDerivation(id), throwsArgumentError);
      }
      expect(store.documentReads, isEmpty);
      final mutations = <void Function(Map<String, Object?>)>[
        (json) => json['unknown'] = true,
        (json) => json['maskMethod'] = 'unknown',
        (json) => (json['region'] as Map)['frameVersion'] = 'futureFrame',
        (json) => (json['bounds'] as Map)['right'] = 31,
        (json) => (json['input'] as Map)['id'] = 'differentInput',
      ];
      for (final mutation in mutations) {
        final document = Map<String, Object?>.from(jsonDecode(jsonEncode(valid)) as Map);
        mutation(document);
        store.documents[key] = document;
        await expectLater(service.findDerivation(derivation.input.id), throwsFormatException);
        store.documents[key] = valid;
        expect((await service.findDerivation(derivation.input.id))!.toJson(), valid);
      }
      store.failDocumentRead = true;
      await expectLater(service.findDerivation(derivation.input.id), throwsStateError);
      store.failDocumentRead = false;
      store.documentReadGate = Completer<void>();
      final finding = service.findDerivation(derivation.input.id);
      await expectLater(service.availability(), throwsStateError);
      store.documentReadGate!.complete();
      final restored = await finding;
      store.documentReadGate = null;
      // Then corruption and IO remain observable and later selected-record lookup recovers.
      expect(restored!.toJson(), valid);
      expect((await service.findDerivation(derivation.input.id))!.toJson(), valid);
      expect(store.documentReads, everyElement(key));
    });

    test('metadata save failure returns no derivation and preserves bytes before fresh recovery', () async {
      // Given a retained original and a store that rejects provenance writes.
      final store = _Store();
      final originalBytes = Uint8List.fromList(img.encodePng(_blocks()));
      final source = await _save(store, originalBytes, 'image/png');
      final service = _service(store);
      final snapshot = _region(source, 32, 16);
      final before = store.materials.keys.toSet();
      store.failDocumentSave = true;
      // When PNG storage succeeds but its metadata write fails, then the caller sees failure.
      await expectLater(service.derive(snapshot), throwsStateError);
      final failedInputId = store.materials.keys.singleWhere((id) => !before.contains(id));
      final failedCropBytes = Uint8List.fromList(store.materials[failedInputId]!);
      expect(await service.findDerivation(failedInputId), isNull);
      expect(await store.listDocumentIds(ImageRegionService.derivationsCollection), isEmpty);
      expect(await store.readMaterial(source), orderedEquals(originalBytes));
      // When persistence recovers, a subsequent actual derive uses a fresh reference.
      store.failDocumentSave = false;
      final recovered = await service.derive(snapshot);
      // Then neither original nor failed crop is deleted or rewritten and provenance is complete.
      expect(recovered.input.id, isNot(failedInputId));
      expect(recovered.input.id, isNot(source.id));
      expect((await service.findDerivation(recovered.input.id))!.toJson(), recovered.toJson());
      expect(await service.findDerivation(failedInputId), isNull);
      expect(store.materials[failedInputId], orderedEquals(failedCropBytes));
      expect(await service.readDerived(recovered), orderedEquals(failedCropBytes));
      expect(await store.readMaterial(source), orderedEquals(originalBytes));
      expect(store.materials.length, 3);
    });
  });

  group('explicit source-bound region OCR', () {
    test('standard first exact crop and durable raw empty output with explicit AI supplement', () async {
      // Given actual recognition orchestration with controlled standard/AI providers.
      final store = _Store();
      final calls = <String>[];
      final standard = _Provider(calls: calls);
      final enhanced = _Provider(calls: calls, enhanced: true);
      final service = _service(store, providers: [standard, enhanced]);
      final source = await _save(store, Uint8List.fromList(img.encodePng(_blocks())), 'image/png');
      final crop = await service.derive(_region(source, 32, 16, geometry: ImageRegionGeometry(
        shape: ImageRegionShape.rectangle, x: 0, y: 0, width: .5, height: .5)));
      final bytes = await service.readDerived(crop);
      // When standard recognition runs, followed by an explicit AI request.
      final empty = await service.recognize(crop);
      final context = RecognitionOperationContext(sourceRole: 'exact role', targetKinds: ['quotation'], instructions: ' exact intent ');
      final supplemented = await service.recognize(crop, supplementWithLocalAi: true, operationContext: context);
      final reloaded = await service.reports.findById(empty.id);
      // Then standard remains primary, completed-empty survives and AI stays separate.
      expect(calls, [RecognitionConfigurations.standardProviderId,
        RecognitionConfigurations.standardProviderId, RecognitionConfigurations.enhancedProviderId]);
      expect(empty.comparison.runs.single.attempts.single.result.text, '');
      expect(empty.comparison.runs.single.status, RecognitionRunStatus.completed);
      expect(empty.comparison.operationContext!.sourceRole, 'region');
      expect(empty.comparison.operationContext!.targetKinds, ['quotation']);
      expect(standard.inputs.first.material, crop.input);
      expect(standard.inputs.first.bytes, orderedEquals(bytes));
      expect(enhanced.inputs.single.material, crop.input);
      expect(enhanced.inputs.single.bytes, orderedEquals(bytes));
      expect(standard.inputs.last.operationContext, same(context));
      expect(supplemented.comparison.runs.map((r) => r.desiredConfigurationId),
        [RecognitionSettings.androidStandard, RecognitionSettings.pixelEnhanced]);
      expect(supplemented.comparison.runs.last.attempts.last.result.interpretation, 'separate suggestion');
      expect(RecognitionReportCodec.encode(reloaded!), RecognitionReportCodec.encode(empty.comparison));
      expect(ImageRegionExtraction.fromJson(empty.toJson()).id, empty.id);
      expect(standard.preparations + enhanced.preparations, 0);
      expect(ImageRegionEntry(snapshots: [crop.region], extractions: [empty, supplemented]).quotations, isEmpty);
    });

    test('unavailable failed and fallback attempts remain raw and failed durable save releases guard', () async {
      // Given a failing standard provider and unavailable optional AI.
      final store = _Store();
      final calls = <String>[];
      final standard = _Provider(calls: calls)..failure = true;
      final enhanced = _Provider(calls: calls, enhanced: true)..unavailable = true;
      final service = _service(store, providers: [standard, enhanced]);
      final source = await _save(store, Uint8List.fromList(img.encodePng(_blocks())), 'image/png');
      final crop = await service.derive(_region(source, 32, 16));
      // When recognition records a fallback, then persistence fails and recovers.
      final result = await service.recognize(crop, supplementWithLocalAi: true);
      store.failDocumentSave = true;
      await expectLater(service.recognize(crop), throwsStateError);
      store.failDocumentSave = false;
      standard.failure = false;
      standard.unavailable = true;
      final unavailable = await service.recognize(crop);
      final states = await service.availability();
      // Then failures differ from completed-empty and nonexecuted metadata remains.
      expect(result.comparison.runs.first.status, RecognitionRunStatus.failed);
      expect(result.comparison.runs.first.attempts.single.result.text, isNull);
      expect(result.comparison.runs.first.attempts.single.result.failures.single.code, 'recognitionFailed');
      expect(result.comparison.runs.last.hasFallback, isTrue);
      expect(result.comparison.runs.last.attempts.last.executed, isFalse);
      expect(result.comparison.runs.last.fallbackReason, contains('fixture unavailable'));
      expect(unavailable.comparison.runs.single.status, RecognitionRunStatus.unavailable);
      expect(unavailable.comparison.runs.single.attempts.single.executed, isFalse);
      expect(states.every((s) => s.state == RecognitionProviderState.unavailable), isTrue);
      expect(standard.preparations + enhanced.preparations, 0);
    });

    test('preparation requires an explicit request and caller Nano replacement is retained', () async {
      // Given a caller-supplied Nano provider with downloadable state.
      final store = _Store();
      final enhanced = _Provider(calls: [], enhanced: true)..downloadable = true;
      // When defaults open and readiness is probed before explicit preparation.
      final service = await openDefaultImageRegionService(store: store, additionalProviders: [enhanced]);
      final before = await service.availability();
      expect(enhanced.preparations, 0);
      final after = await service.prepareProvider(RecognitionConfigurations.enhancedProviderId);
      // Then the caller replacement is prepared exactly once with actual readiness.
      expect(before.singleWhere((s) => s.providerId == enhanced.descriptor.id).state, RecognitionProviderState.downloadable);
      expect(after.state, RecognitionProviderState.available);
      expect(enhanced.preparations, 1);
    });
  });
}

final _time = DateTime.utc(2026, 10, 28);
DateTime _at(int seconds) => _time.add(Duration(seconds: seconds));
const _colors = <List<int>>[[240, 10, 20], [10, 220, 30], [20, 30, 230], [230, 210, 20]];
img.Image _blocks() {
  final result = img.Image(width: 32, height: 16, numChannels: 3);
  for (var y = 0; y < 16; y++) {
    for (var x = 0; x < 32; x++) {
      final c = _colors[(y < 8 ? 0 : 2) + (x < 16 ? 0 : 1)];
      result.setPixelRgb(x, y, c[0], c[1], c[2]);
    }
  }
  return result;
}
void _expectColor(img.Pixel pixel, List<int> color, {int tolerance = 0}) {
  expect(pixel.r, closeTo(color[0], tolerance));
  expect(pixel.g, closeTo(color[1], tolerance));
  expect(pixel.b, closeTo(color[2], tolerance));
}
Future<CaptureMaterialReference> _save(_Store store, Uint8List bytes, String mime) =>
    store.saveMaterial(bytes: bytes, mediaType: mime, capturedAt: _time);
ImageRegionSnapshot _region(CaptureMaterialReference source, int width, int height, {ImageRegionGeometry? geometry}) =>
    ImageRegionSnapshot(regionId: 'region', revision: 1, source: source, pixelWidth: width,
      pixelHeight: height, geometry: geometry ?? ImageRegionGeometry(shape: ImageRegionShape.rectangle,
        x: 0, y: 0, width: 1, height: 1), recordedAt: _at(1));
ImageRegionService _service(_Store store, {DateTime Function()? clock, int maxEncodedBytes = 33554432,
  int maxPixels = 32000000, List<ImageRecognitionProvider>? providers}) => ImageRegionService(
    store: store, clock: clock ?? () => _at(2), maxEncodedBytes: maxEncodedBytes, maxPixels: maxPixels,
    recognition: ImageRecognitionService(clock: () => _at(3), registry: RecognitionProviderRegistry(
      providers: providers ?? [_Provider(calls: [])])));

final class _Provider implements ImageRecognitionProvider {
  _Provider({required this.calls, this.enhanced = false});
  final List<String> calls;
  final bool enhanced;
  final inputs = <ImageRecognitionInput>[];
  int preparations = 0;
  bool failure = false;
  bool unavailable = false;
  bool downloadable = false;
  @override
  RecognitionProviderDescriptor get descriptor => RecognitionProviderDescriptor(
    id: enhanced ? RecognitionConfigurations.enhancedProviderId : RecognitionConfigurations.standardProviderId,
    label: 'Fixture provider', capabilities: enhanced
      ? {RecognitionCapability.imageInterpretation, RecognitionCapability.candidateOrganization}
      : {RecognitionCapability.ocr, RecognitionCapability.barcodes});
  @override
  Future<RecognitionProviderAvailability> availability() async => RecognitionProviderAvailability(
    providerId: descriptor.id, capabilities: descriptor.capabilities,
    state: unavailable ? RecognitionProviderState.unavailable : downloadable
      ? RecognitionProviderState.downloadable : RecognitionProviderState.available,
    reason: unavailable ? 'fixture unavailable' : null);
  @override
  Future<void> prepare() async { preparations++; downloadable = false; }
  @override
  Future<ImageRecognitionResult> recognize(ImageRecognitionInput input) async {
    calls.add(descriptor.id); inputs.add(input);
    if (failure) throw StateError('fixture failure');
    return enhanced ? ImageRecognitionResult(interpretation: 'separate suggestion', candidateOrganizationCompleted: true)
      : ImageRecognitionResult(text: '', barcodeCompleted: true);
  }
}

final class _Store implements LocalCaptureStore {
  final materials = <String, Uint8List>{};
  final documents = <String, Map<String, Object?>>{};
  int serial = 0;
  bool badReadLength = false;
  bool failMaterialSave = false;
  bool badSavedReference = false;
  bool failDocumentSave = false;
  bool failDocumentRead = false;
  bool failMaterialRead = false;
  final documentReads = <String>[];
  Completer<void>? readGate;
  Completer<void>? documentReadGate;
  @override
  Future<CaptureMaterialReference> saveMaterial({required Uint8List bytes, required String mediaType,
    required DateTime capturedAt, String? originalName}) async {
    if (failMaterialSave) throw StateError('fixture save failed');
    final id = 'material${serial++}';
    materials[id] = Uint8List.fromList(bytes);
    return CaptureMaterialReference(id: id, mediaType: badSavedReference ? 'image/jpeg' : mediaType,
      byteLength: bytes.length, capturedAt: capturedAt, originalName: originalName);
  }
  @override
  Future<Uint8List> readMaterial(CaptureMaterialReference reference) async {
    if (failMaterialRead) throw StateError('fixture material read failed');
    if (readGate != null) await readGate!.future;
    final bytes = materials[reference.id]!;
    return badReadLength ? Uint8List(1) : Uint8List.fromList(bytes);
  }
  @override
  Future<void> saveDocument(String collection, String id, Map<String, Object?> document) async {
    if (failDocumentSave) throw StateError('fixture report save failed');
    documents['$collection/$id'] = Map<String, Object?>.from(jsonDecode(jsonEncode(document)) as Map);
  }
  @override
  Future<Map<String, Object?>?> readDocument(String collection, String id) async {
    documentReads.add('$collection/$id');
    if (failDocumentRead) throw StateError('fixture metadata read failed');
    if (documentReadGate != null) await documentReadGate!.future;
    final value = documents['$collection/$id'];
    return value == null ? null : Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);
  }
  @override
  Future<List<String>> listDocumentIds(String collection) async => documents.keys
    .where((key) => key.startsWith('$collection/')).map((key) => key.substring(collection.length + 1)).toList()..sort();
}
