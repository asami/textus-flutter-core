import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('retained source-bound region histories', () {
    test('two revisions retain prior extraction quotation comment and audio associations', () {
      // Given a source-bound first revision with independently retained histories.
      final first = _snapshot(1);
      final extracted = _extraction(first);
      final quote = _text('quote1', origin: RegionTextOrigin.ocr, report: extracted.id, confirmed: true);
      final comment = _text('comment1', text: 'human comment');
      final audio = RegionAudioLink(audioMaterialId: 'audio', regionRevision: 1, recordedAt: _at(4));
      final oldEntry = ImageRegionEntry(snapshots: [first], extractions: [extracted],
        quotations: [quote], comments: [comment], audioLinks: [audio]);
      final old = ImageRegionWorkspace(regions: [oldEntry]);
      final second = _snapshot(2);
      final secondExtraction = _extraction(second, id: 'comparison2');
      // When geometry, extraction and explicit human histories append revision two.
      final next = ImageRegionWorkspace(regions: [ImageRegionEntry(snapshots: [first, second],
        extractions: [extracted, secondExtraction], quotations: [quote,
          _text('quote2', revision: 2, second: 14, text: 'new source text', confirmed: true)],
        comments: [comment, _text('comment2', revision: 2, second: 14, text: 'new comment')], audioLinks: [audio])]);
      ImageRegionWorkspace.requireRetainedPrefix(old, next);
      // Then previous links stay on revision one and no old result is retargeted.
      final entry = next.regions.single;
      expect(entry.extractions.first.derivation.region.revision, 1);
      expect(entry.quotations.first.regionRevision, 1);
      expect(entry.comments.first.regionRevision, 1);
      expect(entry.audioLinks.single.regionRevision, 1);
      expect(entry.snapshots.last.geometry, isNot(first.geometry));
      expect(entry.snapshots.last.source, first.source);
      expect(entry.quotations.last.regionRevision, 2);
      expect(() => entry.snapshots.clear(), throwsUnsupportedError);
      expect(() => entry.extractions.clear(), throwsUnsupportedError);
      expect(() => entry.quotations.clear(), throwsUnsupportedError);
      expect(() => entry.comments.clear(), throwsUnsupportedError);
      expect(() => entry.audioLinks.clear(), throwsUnsupportedError);
      expect(() => next.regions.clear(), throwsUnsupportedError);
    });

    test('quotation and comment clears remain independent exact append-only values', () {
      // Given distinct original quotation and human comment values.
      final q = _text('q', text: ' quotation \n ', confirmed: true);
      final c = _text('c', text: ' comment \n ');
      final snapshots = [_snapshot(1)];
      final quotes = [q];
      final comments = [c];
      final old = ImageRegionWorkspace(regions: [ImageRegionEntry(snapshots: snapshots,
        quotations: quotes, comments: comments)]);
      // When explicit clears append to the two histories and input lists mutate.
      final quoteClear = _text('qclear', second: 6, text: '', confirmed: true);
      final commentClear = _text('cclear', second: 7, text: '');
      final next = ImageRegionWorkspace(regions: [ImageRegionEntry(snapshots: snapshots,
        quotations: [q, quoteClear], comments: [c, commentClear])]);
      snapshots.clear(); quotes.clear(); comments.clear();
      ImageRegionWorkspace.requireRetainedPrefix(old, next);
      // Then each original and its exact clear survive without cross-history edits.
      expect(next.regions.single.quotations.map((v) => v.text), [' quotation \n ', '']);
      expect(next.regions.single.comments.map((v) => v.text), [' comment \n ', '']);
      expect(old.regions.single.quotations.single.text, ' quotation \n ');
      expect(old.regions.single.comments.single.text, ' comment \n ');
    });

    test('rebind deletion reorder stale extraction and retained-entry mutation reject', () {
      // Given two retained regions and a first region with two geometry revisions.
      final first = _snapshot(1);
      final second = _snapshot(2);
      final extraction = _extraction(first);
      final entry = ImageRegionEntry(snapshots: [first, second], extractions: [extraction],
        quotations: [_text('q', confirmed: true)]);
      final other = ImageRegionEntry(snapshots: [_snapshot(1, regionId: 'other')]);
      final old = ImageRegionWorkspace(regions: [entry, other]);
      // When replacements delete, reorder or modify retained source-bound data.
      final mutation = ImageRegionWorkspace(regions: [ImageRegionEntry(snapshots: [first, second],
        extractions: [extraction], quotations: [_text('q', text: 'mutated', confirmed: true)]), other]);
      final deletedSnapshot = ImageRegionWorkspace(regions: [ImageRegionEntry(snapshots: [first]), other]);
      // Then append-only enforcement rejects each otherwise individually valid replacement.
      expect(() => ImageRegionWorkspace.requireRetainedPrefix(old, ImageRegionWorkspace(regions: [entry])), throwsArgumentError);
      expect(() => ImageRegionWorkspace.requireRetainedPrefix(old, ImageRegionWorkspace(regions: [other, entry])), throwsArgumentError);
      expect(() => ImageRegionWorkspace.requireRetainedPrefix(old, mutation), throwsArgumentError);
      expect(() => ImageRegionWorkspace.requireRetainedPrefix(old, deletedSnapshot), throwsArgumentError);
      expect(() => ImageRegionEntry(snapshots: [first, _snapshot(2, source: _source('replacement'))]), throwsArgumentError);
      expect(() => ImageRegionEntry(snapshots: [first, _snapshot(3)]), throwsArgumentError);
      expect(() => ImageRegionEntry(snapshots: [first, _snapshot(2, second: 0)]), throwsArgumentError);
      expect(() => ImageRegionEntry(snapshots: [first], extractions: [_extraction(_snapshot(1, regionId: 'other'))]), throwsArgumentError);
      expect(() => ImageRegionEntry(snapshots: [first], extractions: [extraction, extraction]), throwsArgumentError);
      expect(() => ImageRegionWorkspace(regions: [entry, entry]), throwsArgumentError);
      final oldWire = ImageRegionWorkspaceCodec.encode(old);
      ImageRegionWorkspace.requireRetainedPrefix(old, ImageRegionWorkspaceCodec.decode(oldWire));
    });

    test('only explicit confirmed source-attributed text can become a quotation', () {
      // Given executed OCR/AI outputs and a distinct raw failed extraction.
      final snapshot = _snapshot(1);
      final ocr = _extraction(snapshot);
      final ai = _extraction(snapshot, id: 'ai', ai: true);
      final failed = _extraction(snapshot, id: 'failed', executed: false);
      // When human adoption resolves exact reports with compatible executed output.
      final entry = ImageRegionEntry(snapshots: [snapshot], extractions: [ocr, ai, failed],
        quotations: [_text('q', text: ' corrected verbatim ', origin: RegionTextOrigin.ocr,
          report: ocr.id, confirmed: true)],
        comments: [_text('c', text: ' edited suggestion ', origin: RegionTextOrigin.ai, report: ai.id)]);
      // Then intent is retained while raw text remains unchanged and invalid sources reject.
      expect(entry.quotations.single.text, ' corrected verbatim ');
      expect(ocr.comparison.runs.single.attempts.single.result.text, ' raw OCR ');
      expect(entry.comments.single.text, ' edited suggestion ');
      expect(ImageRegionEntry(snapshots: [snapshot], extractions: [ocr, ai]).quotations, isEmpty);
      for (final text in [
        _text('unconfirmed'),
        _text('unknown', origin: RegionTextOrigin.ocr, report: 'missing', confirmed: true),
        _text('wrongOutput', origin: RegionTextOrigin.ai, report: ocr.id, confirmed: true),
        _text('notExecuted', origin: RegionTextOrigin.ocr, report: failed.id, confirmed: true),
        _text('beforeReport', origin: RegionTextOrigin.ocr, report: ocr.id, second: 2, confirmed: true),
      ]) {
        expect(() => ImageRegionEntry(snapshots: [snapshot], extractions: [ocr, ai, failed], quotations: [text]), throwsArgumentError);
      }
      expect(() => ImageRegionEntry(snapshots: [snapshot, _snapshot(2)], extractions: [ocr], quotations: [
        _text('stale', revision: 2, second: 14, origin: RegionTextOrigin.ocr, report: ocr.id, confirmed: true)]), throwsArgumentError);
      expect(() => ImageRegionEntry(snapshots: [snapshot], quotations: [_text('same', confirmed: true)],
        comments: [_text('same')]), throwsArgumentError);
      expect(() => ImageRegionEntry(snapshots: [snapshot], comments: [_text('later', second: 6), _text('earlier', second: 5)]), throwsArgumentError);
      expect(() => RegionTextRevision(id: 'bad', regionRevision: 1, text: '', recordedAt: _at(5),
        origin: RegionTextOrigin.manual, sourceReportId: 'unexpected'), throwsArgumentError);
      expect(() => RegionTextRevision(id: 'bad', regionRevision: 1, text: '', recordedAt: _at(5),
        origin: RegionTextOrigin.transcript, audioMaterialId: 'audio', sourceReportId: 'report', transcriptRevisionIndex: 0), throwsArgumentError);
      expect(() => RegionTextRevision(id: 'bad', regionRevision: 1, text: '', recordedAt: _at(5),
        origin: RegionTextOrigin.transcript, audioMaterialId: 'audio', transcriptRevisionIndex: -1), throwsArgumentError);
    });

    test('transcript report and retained index resolve only matching original and time', () {
      // Given the caller-owned exact audio original, successful report and correction.
      final review = _audioReview();
      final link = RegionAudioLink(audioMaterialId: 'audio', regionRevision: 1, recordedAt: _at(4));
      final reportText = _text('fromReport', second: 8, text: 'quoted audio', origin: RegionTextOrigin.transcript,
        report: 'audioReport', audio: 'audio', confirmed: true);
      final correctedText = _text('fromIndex', second: 9, text: '', origin: RegionTextOrigin.transcript,
        audio: 'audio', index: 0);
      final workspace = ImageRegionWorkspace(regions: [ImageRegionEntry(snapshots: [_snapshot(1)],
        quotations: [reportText], comments: [correctedText], audioLinks: [link])]);
      // When source links resolve through the existing separate audio review map.
      workspace.validateAudioReviews({'audio': review});
      // Then the workspace stores only identities and rejects missing or rebound reviews.
      expect(ImageRegionWorkspaceCodec.encode(workspace).toString(), isNot(contains('durationMilliseconds')));
      expect(() => workspace.validateAudioReviews({}), throwsArgumentError);
      expect(() => workspace.validateAudioReviews({'audio': _audioReview(id: 'otherAudio')}), throwsArgumentError);
      expect(() => workspace.validateAudioReviews({'audio': _audioReview(reportId: 'otherReport')}), throwsArgumentError);
      expect(() => workspace.validateAudioReviews({'audio': _audioReview(reportSecond: 10)}), throwsArgumentError);
      final missingIndex = ImageRegionWorkspace(regions: [ImageRegionEntry(snapshots: [_snapshot(1)], audioLinks: [link],
        comments: [_text('missingIndex', second: 9, origin: RegionTextOrigin.transcript, audio: 'audio', index: 1)])]);
      expect(() => missingIndex.validateAudioReviews({'audio': review}), throwsArgumentError);
      final earlyIndex = ImageRegionWorkspace(regions: [ImageRegionEntry(snapshots: [_snapshot(1)], audioLinks: [link],
        comments: [_text('earlyIndex', second: 6, origin: RegionTextOrigin.transcript, audio: 'audio', index: 0)])]);
      expect(() => earlyIndex.validateAudioReviews({'audio': review}), throwsArgumentError);
      expect(() => ImageRegionEntry(snapshots: [_snapshot(1), _snapshot(2)], audioLinks: [link],
        comments: [_text('wrongRegion', revision: 2, second: 14, origin: RegionTextOrigin.transcript, audio: 'audio', index: 0)]), throwsArgumentError);
      expect(() => ImageRegionEntry(snapshots: [_snapshot(1)], audioLinks: [link, link]), throwsArgumentError);
      expect(() => ImageRegionWorkspace(regions: [workspace.regions.single,
        ImageRegionEntry(snapshots: [_snapshot(1, regionId: 'other')], audioLinks: [link])]), throwsArgumentError);
    });
  });

  group('strict detached region workspace persistence', () {
    test('exact roundtrip is isolated from caller and returned JSON mutation', () {
      // Given all region histories and deeply nested original metadata.
      final snapshot = _snapshot(1);
      final extraction = _extraction(snapshot);
      final workspace = ImageRegionWorkspace(regions: [ImageRegionEntry(snapshots: [snapshot],
        extractions: [extraction], quotations: [_text('q', confirmed: true)], comments: [_text('c')],
        audioLinks: [RegionAudioLink(audioMaterialId: 'audio', regionRevision: 1, recordedAt: _at(4))])]);
      final expected = ImageRegionWorkspaceCodec.encode(workspace);
      // When JSON crosses text encoding, decodes, and the caller mutates both wire snapshots.
      final wire = _copy(expected);
      final decoded = ImageRegionWorkspaceCodec.decode(wire);
      final returned = ImageRegionWorkspaceCodec.encode(decoded);
      (wire['regions'] as List).clear();
      (((returned['regions'] as List).single as Map)['quotations'] as List).clear();
      // Then all exact source histories and nullable wire fields remain detached.
      expect(ImageRegionWorkspaceCodec.encode(decoded), expected);
      expect(ImageRegionWorkspaceCodec.encode(workspace), expected);
      final quote = decoded.regions.single.quotations.single.toJson();
      expect(quote.keys.toSet(), {'id', 'regionRevision', 'text', 'recordedAt', 'origin',
        'sourceReportId', 'audioMaterialId', 'transcriptRevisionIndex', 'sourceConfirmed'});
      expect(quote['sourceReportId'], isNull);
      expect(decoded.regions.single.snapshots.single.recordedAt.isUtc, isTrue);
    });

    test('malformed current and future schemas are distinct with no empty fallback', () {
      // Given a current schema with nested source, extraction and text values.
      final snapshot = _snapshot(1);
      final valid = ImageRegionWorkspaceCodec.encode(ImageRegionWorkspace(regions: [ImageRegionEntry(
        snapshots: [snapshot], extractions: [_extraction(snapshot)], quotations: [_text('q', confirmed: true)],
        audioLinks: [RegionAudioLink(audioMaterialId: 'audio', regionRevision: 1, recordedAt: _at(4))]) ]));
      final mutations = <void Function(Map<String, Object?>)>[
        (j) => j['schemaVersion'] = true,
        (j) => j['schemaVersion'] = 1.0,
        (j) => j['schemaVersion'] = 0,
        (j) => j['extra'] = null,
        (j) => j.remove('regions'),
        (j) => _entryWire(j)['extra'] = null,
        (j) => (_entryWire(j)['snapshots'] as List).clear(),
        (j) => _snapshotWire(j)['pixelWidth'] = false,
        (j) => _snapshotWire(j)['revision'] = 2,
        (j) => _snapshotWire(j)['recordedAt'] = '2026-10-28T00:00:00',
        (j) => _snapshotWire(j)['recordedAt'] = '2026-02-30T00:00:00Z',
        (j) => (_snapshotWire(j)['geometry'] as Map)['width'] = double.infinity,
        (j) => (_snapshotWire(j)['geometry'] as Map)['shape'] = 'circle',
        (j) => (_snapshotWire(j)['source'] as Map)['unknown'] = true,
        (j) => ((_entryWire(j)['extractions'] as List).single as Map)['unknown'] = true,
        (j) => (((_entryWire(j)['extractions'] as List).single as Map)['derivation'] as Map)['maskMethod'] = 'unknown',
        (j) => (((_entryWire(j)['extractions'] as List).single as Map)['comparison'] as Map)['unknown'] = true,
        (j) => ((_entryWire(j)['quotations'] as List).single as Map)['sourceConfirmed'] = 1,
        (j) => ((_entryWire(j)['quotations'] as List).single as Map)['unknown'] = true,
        (j) => ((_entryWire(j)['audioLinks'] as List).single as Map)['regionRevision'] = true,
        (j) => ((_entryWire(j)['audioLinks'] as List).single as Map)['unknown'] = true,
      ];
      // When each malformed current payload and a future version are decoded.
      // Then current errors are FormatException and future data stays unsupported.
      for (final mutation in mutations) {
        final wire = _copy(valid);
        mutation(wire);
        expect(() => ImageRegionWorkspaceCodec.decode(wire), throwsFormatException);
      }
      final future = <String, Object?>{'schemaVersion': 2, 'futureOpaque': [1, true]};
      expect(() => ImageRegionWorkspaceCodec.decode(future), throwsUnsupportedError);
      expect(future, {'schemaVersion': 2, 'futureOpaque': [1, true]});
      expect(ImageRegionWorkspaceCodec.encode(ImageRegionWorkspace()), {'schemaVersion': 1, 'regions': []});
    });

    test('raw comparison resolves exact origin after file-store reopen without workspace adoption', () async {
      // Given an original, ellipse derivation and raw OCR with no adopted workspace.
      final directory = await Directory.systemTemp.createTemp('region-unadopted-spec-');
      addTearDown(() => directory.delete(recursive: true));
      final store = FileCaptureStore(directory.path);
      final image = img.Image(width: 8, height: 6, numChannels: 3);
      img.fill(image, color: img.ColorRgb8(10, 20, 30));
      final originalBytes = Uint8List.fromList(img.encodePng(image));
      final source = await store.saveMaterial(bytes: originalBytes, mediaType: 'image/png', capturedAt: _at(0));
      final service = ImageRegionService(store: store, clock: () => _at(2), recognition: ImageRecognitionService(
        clock: () => _at(3), registry: RecognitionProviderRegistry(providers: [_Standard()])));
      final snapshot = ImageRegionSnapshot(regionId: 'unadoptedRegion', revision: 1, source: source,
        pixelWidth: 8, pixelHeight: 6, geometry: ImageRegionGeometry(shape: ImageRegionShape.ellipse,
          x: .125, y: 0, width: .75, height: 1), recordedAt: _at(1));
      final derivation = await service.derive(snapshot);
      final derivedBytes = await service.readDerived(derivation);
      final extraction = await service.recognize(derivation);
      // When a new store and service resolve origin solely from the persisted raw comparison.
      final reopened = FileCaptureStore(directory.path);
      final reopenedService = ImageRegionService(store: reopened, recognition: ImageRecognitionService(
        registry: RecognitionProviderRegistry(providers: [_Standard()])));
      final report = await reopenedService.reports.findById(extraction.id);
      final restored = await reopenedService.findDerivation(report!.material.id);
      // Then full exact lineage and raw output survive independently of current UI selection.
      expect(await reopened.listDocumentIds('region_workspaces'), isEmpty);
      expect(restored!.toJson(), derivation.toJson());
      expect(restored.input, report.material);
      expect(restored.region.source, source);
      expect(restored.region.toJson(), snapshot.toJson());
      expect([restored.region.pixelWidth, restored.region.pixelHeight], [8, 6]);
      expect(restored.region.frameVersion, 'exifUprightV1');
      expect(restored.bounds, ImageRegionBounds(left: 1, top: 0, right: 7, bottom: 6));
      expect(restored.maskMethod, 'ellipsePixelCenterWhiteV1');
      expect(await reopened.readMaterial(restored.region.source), orderedEquals(originalBytes));
      expect(await reopenedService.readDerived(restored), orderedEquals(derivedBytes));
      expect(RecognitionReportCodec.encode(report), RecognitionReportCodec.encode(extraction.comparison));
      expect(report.runs.single.attempts.single.result.text, 'fixture');
      expect(await reopened.readDocument(ImageRegionService.derivationsCollection, report.material.id), derivation.toJson());
    });

    test('new FileCaptureStore instance reopens workspace original derived bytes and raw comparison', () async {
      // Given a real file store and actual Core decode/derive/recognition services.
      final directory = await Directory.systemTemp.createTemp('region-workspace-spec-');
      addTearDown(() => directory.delete(recursive: true));
      final store = FileCaptureStore(directory.path);
      final image = img.Image(width: 4, height: 4, numChannels: 3);
      img.fill(image, color: img.ColorRgb8(10, 20, 30));
      final originalBytes = Uint8List.fromList(img.encodePng(image));
      final source = await store.saveMaterial(bytes: originalBytes, mediaType: 'image/png', capturedAt: _at(0));
      final service = ImageRegionService(store: store, clock: () => _at(2), recognition: ImageRecognitionService(
        clock: () => _at(3), registry: RecognitionProviderRegistry(providers: [_Standard()])));
      final snapshot = ImageRegionSnapshot(regionId: 'region', revision: 1, source: source,
        pixelWidth: 4, pixelHeight: 4, geometry: ImageRegionGeometry(shape: ImageRegionShape.ellipse,
          x: 0, y: 0, width: 1, height: 1), recordedAt: _at(1));
      final derivation = await service.derive(snapshot);
      final extraction = await service.recognize(derivation);
      final derivedBytes = await service.readDerived(derivation);
      final workspace = ImageRegionWorkspace(regions: [ImageRegionEntry(snapshots: [snapshot],
        extractions: [extraction], quotations: [_text('q', text: 'fixture', origin: RegionTextOrigin.ocr,
          report: extraction.id, confirmed: true)])]);
      // When the document is saved and reopened using an independent store instance.
      await store.saveDocument('region_workspaces', 'draft', ImageRegionWorkspaceCodec.encode(workspace));
      final reopened = FileCaptureStore(directory.path);
      final document = await reopened.readDocument('region_workspaces', 'draft');
      final decoded = ImageRegionWorkspaceCodec.decode(document!);
      final report = await LocalRecognitionRepository(store: reopened).findById(extraction.id);
      // Then histories, source bytes and exact crop bytes remain independently durable.
      expect(ImageRegionWorkspaceCodec.encode(decoded), ImageRegionWorkspaceCodec.encode(workspace));
      expect(await reopened.readMaterial(source), orderedEquals(originalBytes));
      expect(await reopened.readMaterial(derivation.input), orderedEquals(derivedBytes));
      expect(RecognitionReportCodec.encode(report!), RecognitionReportCodec.encode(extraction.comparison));
      expect(await reopened.readDocument('region_workspaces', 'oldDraftAbsent'), isNull);
      expect(decoded.regions.single.quotations.single.text, 'fixture');
      expect(decoded.regions.single.extractions.single.derivation.input.id, isNot(source.id));
    });
  });
}

final _time = DateTime.utc(2026, 10, 28);
DateTime _at(int seconds) => _time.add(Duration(seconds: seconds));
CaptureMaterialReference _source([String id = 'photo']) => CaptureMaterialReference(id: id,
  mediaType: 'image/png', byteLength: 20, capturedAt: _at(0), extensions: {'nested': <Object?>[null, true, 1.5]});
ImageRegionSnapshot _snapshot(int revision, {String regionId = 'region', CaptureMaterialReference? source, int? second}) =>
    ImageRegionSnapshot(regionId: regionId, revision: revision, source: source ?? _source(), pixelWidth: 20,
      pixelHeight: 10, geometry: ImageRegionGeometry(shape: ImageRegionShape.rectangle,
        x: revision == 1 ? 0 : .1, y: 0, width: .5, height: .5), recordedAt: _at(second ?? (revision == 1 ? 1 : 10)));
RegionTextRevision _text(String id, {int revision = 1, int second = 5, String text = ' exact text ',
  RegionTextOrigin origin = RegionTextOrigin.manual, String? report, String? audio, int? index, bool confirmed = false}) =>
    RegionTextRevision(id: id, regionRevision: revision, text: text, recordedAt: _at(second), origin: origin,
      sourceReportId: report, audioMaterialId: audio, transcriptRevisionIndex: index, sourceConfirmed: confirmed);
ImageRegionExtraction _extraction(ImageRegionSnapshot region, {String id = 'comparison', bool ai = false, bool executed = true}) {
  final derivedAt = region.recordedAt.add(const Duration(seconds: 1));
  final input = CaptureMaterialReference(id: 'crop_$id', mediaType: 'image/png', byteLength: 10, capturedAt: derivedAt);
  final providerId = ai ? 'aiProvider' : 'ocrProvider';
  final attempt = RecognitionProviderAttempt(id: 'attempt_$id', providerId: providerId, materialId: input.id,
    availability: RecognitionProviderAvailability(providerId: providerId,
      state: executed ? RecognitionProviderState.available : RecognitionProviderState.unavailable,
      reason: executed ? null : 'fixture unavailable', capabilities: ai
        ? {RecognitionCapability.imageInterpretation, RecognitionCapability.candidateOrganization} : {RecognitionCapability.ocr}),
    startedAt: derivedAt.add(const Duration(seconds: 1)), elapsed: Duration.zero, executed: executed,
    result: !executed ? ImageRecognitionResult() : ai ? ImageRecognitionResult(interpretation: ' raw AI ', candidateOrganizationCompleted: true)
      : ImageRecognitionResult(text: ' raw OCR '));
  return ImageRegionExtraction(derivation: ImageRegionDerivation(region: region, input: input,
    bounds: region.geometry.boundsFor(pixelWidth: region.pixelWidth, pixelHeight: region.pixelHeight)),
    comparison: RecognitionComparison(id: id, material: input, createdAt: derivedAt.add(const Duration(seconds: 1)),
      runs: [RecognitionRun(desiredConfigurationId: 'route', actualConfigurationId: executed ? 'route' : null,
        actualProviderIds: executed ? [providerId] : [], attempts: [attempt])]));
}
AudioTranscriptReview _audioReview({String id = 'audio', String reportId = 'audioReport', int reportSecond = 6}) {
  final original = OriginalAudio(material: CaptureMaterialReference(id: id, mediaType: 'audio/wav',
    byteLength: 100, capturedAt: _at(2)), durationMilliseconds: 1000);
  final report = AudioTranscriptReport(id: reportId, original: original, providerId: 'speech', locale: 'ja-JP',
    startedAt: _at(3), completedAt: _at(reportSecond), elapsedMilliseconds: 1, status: AudioTranscriptStatus.success, text: ' original transcript ');
  return AudioTranscriptReview(original: original, reports: [report], revisions: [TranscriptRevision(
    text: ' corrected transcript ', recordedAt: _at(reportSecond + 1), source: TranscriptRevisionSource.manual, reportId: reportId)]);
}
Map<String, Object?> _copy(Map<String, Object?> value) => Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);
Map _entryWire(Map<String, Object?> json) => (json['regions'] as List).single as Map;
Map _snapshotWire(Map<String, Object?> json) => (_entryWire(json)['snapshots'] as List).single as Map;

final class _Standard implements ImageRecognitionProvider {
  @override
  RecognitionProviderDescriptor get descriptor => RecognitionProviderDescriptor(id: RecognitionConfigurations.standardProviderId,
    label: 'Fixture OCR', capabilities: {RecognitionCapability.ocr, RecognitionCapability.barcodes});
  @override
  Future<RecognitionProviderAvailability> availability() async => RecognitionProviderAvailability(providerId: descriptor.id,
    state: RecognitionProviderState.available, capabilities: descriptor.capabilities);
  @override
  Future<void> prepare() async => throw StateError('Preparation was not requested');
  @override
  Future<ImageRecognitionResult> recognize(ImageRecognitionInput input) async => ImageRecognitionResult(text: 'fixture', barcodeCompleted: true);
}
