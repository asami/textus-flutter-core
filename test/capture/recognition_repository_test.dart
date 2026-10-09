import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  group('version1 comparison schema and identity', () {
    test('OC3 known context and unknown namespace detach while legacy absence stays exact', () {
      // Given rich shared raw stages, requested intent, and unrelated nested extension data.
      final context = RecognitionOperationContext(sourceRole: ' opaque role ',
        targetKinds: ['opaque', 'unknown/kind'], instructions: ' exact request ',
        extensions: {'future': [true, null, 2.5]});
      final report = _report(extensions: {
        RecognitionOperationContext.extensionKey: context.toJson(),
        'futureNamespace': {'unknown': [null, false, ' verbatim ']},
      });
      final legacy = _report(extensions: {'futureNamespace': [1]});
      // When encoding and decoding both reports, then mutating the detached contextual wire.
      final wire = RecognitionReportCodec.encode(report);
      final decoded = RecognitionReportCodec.decode(wire);
      final legacyWire = RecognitionReportCodec.encode(legacy);
      final old = RecognitionReportCodec.decode(legacyWire);
      _map(_map(wire['extensions'])[RecognitionOperationContext.extensionKey])['instructions'] = 'caller mutation';
      // Then version1 structure, raw source sharing and exact metadata remain independent.
      expect(wire.keys.toSet(), {'version', 'id', 'material', 'createdAt', 'runs', 'extensions'});
      expect(wire['version'], 1); expect(decoded.operationContext, context);
      expect(report.operationContext, context);
      expect(decoded.extensions['futureNamespace'], {'unknown': [null, false, ' verbatim ']});
      expect(decoded.runs.first.attempts.first, same(decoded.runs.last.attempts.first));
      expect(decoded.runs.last.attempts.last.inputAttemptIds, ['standard-attempt']);
      expect(RecognitionReportCodec.encode(decoded), RecognitionReportCodec.encode(report));
      expect(old.operationContext, isNull);
      expect(old.extensions.containsKey(RecognitionOperationContext.extensionKey), isFalse);
      expect(RecognitionReportCodec.encode(old), legacyWire);
    });

    test('OC3 malformed present namespace rejects direct construction and codec decode', () {
      // Given complete raw reports and a finite matrix of invalid known namespaces.
      final context = RecognitionOperationContext(sourceRole: 'role',
        targetKinds: ['opaque'], instructions: 'requested').toJson();
      final malformed = <Object?>[
        null, [], 'not metadata', {...context, 'schemaVersion': 2},
        {...context, 'schemaVersion': true}, {...context, 'schemaVersion': 1.0},
        {...context, 'unknown': 1}, {...context}..remove('instructions'),
        {...context, 'sourceRole': ' '}, {...context, 'targetKinds': []},
        {...context, 'targetKinds': ['opaque', 'opaque']}, {...context, 'targetKinds': [1]},
        {...context, 'extensions': null}, {...context, 'extensions': {'invalid': double.infinity}},
      ];
      // When each present malformed namespace crosses the direct and wire value boundaries.
      for (final value in malformed) {
        final wire = RecognitionReportCodec.encode(_report());
        _map(wire['extensions'])[RecognitionOperationContext.extensionKey] = value;
        // Then constructor failures are ArgumentError and persisted decode failures are FormatException.
        expect(() => _report(extensions: {RecognitionOperationContext.extensionKey: value}), throwsArgumentError);
        expect(() => RecognitionReportCodec.decode(wire), throwsFormatException);
      }
    });

    test('D1 rich roundtrip restores shared attempts and deeply immutable extensions', () {
      // Given raw stages, every failure enum, source IDs and mutable finite extensions.
      final extensions = <String, Object?>{
        'unknown': <Object?>[null, true, 1.5, <String, Object?>{'empty': <Object?>[]}],
      };
      final report = _report(extensions: extensions);
      // When encoding, decoding and caller mutation occur independently.
      final encoded = RecognitionReportCodec.encode(report);
      final decoded = RecognitionReportCodec.decode(encoded);
      (extensions['unknown'] as List).clear();
      (_map(encoded['extensions'])['unknown'] as List).clear();
      _attempt(encoded)['inputAttemptIds'] = ['changed'];
      // Then detached wire data and restored sharing preserve every raw field and source.
      expect(decoded.runs[0].attempts.first, same(decoded.runs[1].attempts.first));
      expect(decoded.runs[1].attempts.last.inputAttemptIds, ['standard-attempt']);
      expect(decoded.createdAt, _time); expect(decoded.createdAt.isUtc, isTrue);
      expect(decoded.runs.first.attempts.first.startedAt, _time);
      expect(decoded.runs.first.attempts.first.elapsed, const Duration(microseconds: 7));
      expect(decoded.runs[1].elapsed, const Duration(microseconds: 18));
      expect(decoded.runs.first.attempts.first.result.text, ' raw OCR ');
      expect(decoded.runs.first.attempts.first.result.barcodes.single.value, ' 978 raw ');
      expect(decoded.runs[1].attempts.last.result.interpretation, 'raw interpretation');
      expect(decoded.runs[1].attempts.last.result.candidates.single.kind, 'opaque');
      expect(decoded.runs[1].attempts.last.result.failures.map((item) => item.stage), ImageRecognitionStage.values);
      expect(decoded.extensions['unknown'], [null, true, 1.5, <String, Object?>{'empty': <Object?>[]}]);
      expect(report.extensions['unknown'], decoded.extensions['unknown']);
      expect(() => decoded.extensions['new'] = 1, throwsUnsupportedError);
      expect(() => (decoded.extensions['unknown'] as List).clear(), throwsUnsupportedError);
      expect(() => _map((decoded.extensions['unknown'] as List).last)['new'] = 1, throwsUnsupportedError);
      expect(() => decoded.runs.clear(), throwsUnsupportedError);
      expect(() => decoded.runs.first.attempts.clear(), throwsUnsupportedError);
      expect(() => decoded.runs.first.actualProviderIds.clear(), throwsUnsupportedError);
      expect(() => decoded.runs[1].attempts.last.inputAttemptIds.clear(), throwsUnsupportedError);
      expect(RecognitionReportCodec.encode(decoded), RecognitionReportCodec.encode(report));
    });

    test('D1 all readiness states and nullable empty partial outputs survive the exact schema', () {
      // Given all readiness states and completed empty versus failed raw outcomes.
      final results = [
        ImageRecognitionResult(text: ''), ImageRecognitionResult(barcodeCompleted: true),
        ImageRecognitionResult(interpretation: ''), ImageRecognitionResult(candidateOrganizationCompleted: true),
        ImageRecognitionResult(text: 'partial', failures: [ImageRecognitionFailure(
          stage: ImageRecognitionStage.barcode, code: 'nativeCode', message: 'native description',
        )]),
        ImageRecognitionResult(failures: [ImageRecognitionFailure(
          stage: ImageRecognitionStage.provider, code: 'nativeCode', message: 'native description',
        )]),
      ];
      // When every state and raw output is serialized and reloaded.
      for (final state in RecognitionProviderState.values) {
        final report = _single(state: state, result: state == RecognitionProviderState.available
          ? results.first : ImageRecognitionResult());
        final decoded = RecognitionReportCodec.decode(RecognitionReportCodec.encode(report));
        // Then historical readiness, null model and execution flags remain unchanged.
        expect(RecognitionReportCodec.encode(decoded), RecognitionReportCodec.encode(report));
        expect(decoded.runs.single.attempts.single.availability.state, state);
        expect(decoded.runs.single.attempts.single.availability.modelName, isNull);
        expect(decoded.runs.single.attempts.single.executed, state == RecognitionProviderState.available);
      }
      for (final result in results) {
        final report = _single(result: result);
        final wire = RecognitionReportCodec.encode(report);
        expect(RecognitionReportCodec.encode(RecognitionReportCodec.decode(wire)), wire);
        expect(_map(_attempt(wire)['result']).keys.toSet(), {
          'text', 'barcodes', 'barcodeCompleted', 'interpretation', 'candidates',
          'candidateOrganizationCompleted', 'failures',
        });
      }
    });

    test('D1 fallback roundtrip keeps desired selection failure overhead and shared standard route', () {
      // Given one shared standard attempt and an executed unsuccessful enhancement.
      final standard = _standard();
      final failed = RecognitionProviderAttempt(id: 'failed-enhancement', providerId: 'geminiNano', materialId: 'original',
        availability: RecognitionProviderAvailability(providerId: 'geminiNano', state: RecognitionProviderState.available,
          capabilities: [RecognitionCapability.imageInterpretation, RecognitionCapability.candidateOrganization]),
        startedAt: _time, elapsed: const Duration(microseconds: 11), executed: true,
        inputAttemptIds: [standard.id], result: ImageRecognitionResult(failures: [ImageRecognitionFailure(
          stage: ImageRecognitionStage.interpretation, code: 'generationFailed', message: 'native generation failed',
        )]));
      final report = RecognitionComparison(id: 'fallback', material: _material(), createdAt: _time, runs: [
        RecognitionRun(desiredConfigurationId: 'androidStandard', actualConfigurationId: 'androidStandard',
          actualProviderIds: ['mlkitStandard'], attempts: [standard]),
        RecognitionRun(desiredConfigurationId: 'pixelEnhanced', actualConfigurationId: 'androidStandard',
          actualProviderIds: ['mlkitStandard'], fallbackReason: 'geminiNano: native generation failed', attempts: [standard, failed]),
      ]);
      // When the version1 report is encoded and reloaded.
      final decoded = RecognitionReportCodec.decode(RecognitionReportCodec.encode(report));
      final fallback = decoded.runs.last;
      // Then actual fallback, raw failure trace and cumulative shared timing survive restart.
      expect(fallback.desiredConfigurationId, 'pixelEnhanced'); expect(fallback.actualConfigurationId, 'androidStandard');
      expect(fallback.fallbackReason, 'geminiNano: native generation failed'); expect(fallback.hasFallback, isTrue);
      expect(fallback.status, RecognitionRunStatus.completed); expect(fallback.elapsed, const Duration(microseconds: 18));
      expect(fallback.attempts.first, same(decoded.runs.first.attempts.first));
      expect(fallback.attempts.last.result.failures.single.code, 'generationFailed');
    });

    test('D2 malformed schema enum times completion and provenance reject without rewrite', () {
      // Given a complete valid shared-attempt report and mutations of every wire boundary.
      final malformed = <Map<String, Object?>>[
        _bad((map) => map['version'] = 2), _bad((map) => map['version'] = true),
        _bad((map) => map['version'] = 1.0), _bad((map) => map.remove('extensions')),
        _bad((map) => map['extra'] = true), _bad((map) => map['id'] = '../bad'),
        _bad((map) => map['runs'] = {}), _bad((map) => map['runs'] = []),
        _bad((map) => map['extensions'] = []), _bad((map) => map['material'] = null),
        _bad((map) => _map(map['material'])['extra'] = 1),
        _bad((map) => _map(map['material'])['byteLength'] = 0),
        _bad((map) => _map(map['material'])['id'] = 'other-original'),
        for (final time in ['no time', '2026-02-31T01:02:03Z', '2026-10-06T24:00:00Z',
          '2026-10-06T01:02:03', '2026-10-06T01:02:03+24:00', '2026-10-06T01:02:03+09:60'])
          _bad((map) => map['createdAt'] = time),
        _bad((map) => _row(map).remove('fallbackReason')),
        _bad((map) => _row(map)['extra'] = true),
        _bad((map) => _row(map)['desiredConfigurationId'] = ''),
        _bad((map) => _row(map)['actualProviderIds'] = ['unknown']),
        _bad((map) => _row(map)['actualProviderIds'] = ['mlkitStandard', 'mlkitStandard']),
        _bad((map) => _row(map)['actualConfigurationId'] = null),
        _bad((map) => _row(map)['fallbackReason'] = 'unrequested fallback'),
        _bad((map) => _row(map)['actualConfigurationId'] = 'other'),
        _bad((map) => _row(map)['attempts'] = []),
        _bad((map) => _attempt(map).remove('inputAttemptIds')),
        _bad((map) => _attempt(map)['extra'] = null),
        _bad((map) => _attempt(map)['startedAt'] = '2026-02-30T01:02:03Z'),
        _bad((map) => _attempt(map)['materialId'] = 'other-original'),
        _bad((map) => _attempt(map)['providerId'] = 'other-provider'),
        for (final duration in <Object>[-1, 1.5, true, '1'])
          _bad((map) => _attempt(map)['elapsedMicroseconds'] = duration),
        _bad((map) => _attempt(map)['executed'] = 1),
        _bad((map) => _attempt(map)['executed'] = false),
        _bad((map) => _attempt(map)['inputAttemptIds'] = ['unknown']),
        _bad((map) => _attempt(map)['inputAttemptIds'] = ['enhanced-attempt']),
        _bad((map) => _attempt(map)['inputAttemptIds'] = ['standard-attempt']),
        _bad((map) => _attempt(map, row: 1, index: 1)['inputAttemptIds'] = ['standard-attempt', 'standard-attempt']),
        _bad((map) => _attempt(map, row: 1, index: 1)['id'] = 'standard-attempt'),
        _bad((map) => _row(map, 1)['actualProviderIds'] = ['geminiNano', 'mlkitStandard']),
        _bad((map) => _map(_attempt(map)['availability'])['state'] = 'ready'),
        _bad((map) => _map(_attempt(map)['availability'])['capabilities'] = ['ocr', 'ocr']),
        _bad((map) => _map(_attempt(map)['availability'])['capabilities'] = ['unknown']),
        _bad((map) => _map(_attempt(map)['availability'])['modelName'] = ''),
        _bad((map) => _map(_attempt(map)['availability'])['reason'] = true),
        _bad((map) => _map(_attempt(map)['availability'])['state'] = 'unavailable'),
        _bad((map) => _map(_attempt(map)['result'])['barcodeCompleted'] = false),
        _bad((map) => _map(_attempt(map)['result'])['text'] = false),
        _bad((map) => _map(_attempt(map)['result'])['barcodes'] = {}),
        _bad((map) => _map((_map(_attempt(map)['result'])['barcodes'] as List).first)['format'] = ''),
        _bad((map) => _map(_attempt(map, row: 1, index: 1)['result'])['candidateOrganizationCompleted'] = false),
        _bad((map) => _map((_map(_attempt(map, row: 1, index: 1)['result'])['failures'] as List).first)['stage'] = 'unknown'),
        _bad((map) => _map((_map(_attempt(map, row: 1, index: 1)['result'])['failures'] as List).first)['code'] = ''),
        _bad((map) => _map(_attempt(map, row: 1)['result'])['text'] = 'contradictory duplicate'),
        _bad((map) => _attempt(map, row: 1)['elapsedMicroseconds'] = 7.0),
        _bad((map) => _row(map, 1)['desiredConfigurationId'] = 'androidStandard'),
        _bad((map) => map['extensions'] = <String, Object?>{'nonfinite': double.infinity}),
        _bad((map) => map['extensions'] = <String, Object?>{'object': Object()}),
      ];
      final cyclic = <String, Object?>{}; cyclic['self'] = cyclic;
      malformed.add(_bad((map) => map['extensions'] = cyclic));
      // When each malformed document is decoded.
      for (final document in malformed) {
        // Then errors stay visible as format failures with no normalization or migration.
        expect(() => RecognitionReportCodec.decode(document), throwsFormatException);
      }
    });

    test('D2 public report invariants reject conflicting identities and out of order sources', () {
      // Given valid stages for direct constructor ownership and provenance violations.
      final standard = _standard();
      final enhanced = _enhanced();
      final tail = RecognitionProviderAttempt(id: 'tail', providerId: 'tail', materialId: 'original',
        availability: RecognitionProviderAvailability(providerId: 'tail', state: RecognitionProviderState.available),
        startedAt: _time, elapsed: Duration.zero, executed: true, result: ImageRecognitionResult(text: ''),
        inputAttemptIds: ['enhanced-attempt', 'standard-attempt']);
      final cyclic = <String, Object?>{}; cyclic['self'] = cyclic;
      final constructors = <void Function()>[
        () => RecognitionProviderAttempt(id: 'bad/id', providerId: 'mlkitStandard', materialId: 'original',
          availability: standard.availability, startedAt: _time, elapsed: Duration.zero,
          executed: true, result: standard.result),
        () => RecognitionProviderAttempt(id: 'x', providerId: 'mlkitStandard', materialId: 'original',
          availability: standard.availability, startedAt: _time, elapsed: const Duration(microseconds: -1),
          executed: true, result: standard.result),
        () => RecognitionRun(desiredConfigurationId: 'x', actualConfigurationId: null,
          fallbackReason: 'false fallback', attempts: [standard]),
        () => RecognitionRun(desiredConfigurationId: 'x', actualConfigurationId: 'x',
          actualProviderIds: [], attempts: [standard]),
        () => RecognitionComparison(id: 'x', material: _material(), createdAt: _time, runs: [
          RecognitionRun(desiredConfigurationId: 'x', attempts: [standard, enhanced, tail]),
        ]),
        () => RecognitionComparison(id: 'x', material: _material(), createdAt: _time, runs: [
          RecognitionRun(desiredConfigurationId: 'a', attempts: [standard]),
          RecognitionRun(desiredConfigurationId: 'b', attempts: [_standard()]),
        ]),
        () => _report(extensions: cyclic),
        () => _report(extensions: {'bad': double.nan}),
      ];
      // When directly constructed reports violate the immutable public contracts.
      for (final construct in constructors) {
        // Then the value boundary rejects each violation before persistence.
        expect(construct, throwsArgumentError);
      }
    });
  });

  group('durable original-linked history', () {
    late Directory directory;
    late FileCaptureStore store;
    late CaptureMaterialReference material;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('recognition-repository-spec-');
      store = FileCaptureStore(directory.path);
      material = await store.saveMaterial(bytes: Uint8List.fromList([1, 2, 3]),
        mediaType: 'image/jpeg', capturedAt: _time, originalName: 'original.jpg');
    });
    tearDown(() async { await directory.delete(recursive: true); });

    test('OC3 fresh repository preserves context raw stages and legacy absence', () async {
      // Given one real saved original, rich raw stages and distinct contextual and old reports.
      final context = RecognitionOperationContext(sourceRole: 'saved role',
        targetKinds: ['opaque'], instructions: 'persist exact intent', extensions: {'future': [null, 1.5]});
      final contextual = _report(id: 'contextual', material: material, extensions: {
        RecognitionOperationContext.extensionKey: context.toJson(), 'unknown': {'raw': true},
      });
      final legacy = _report(id: 'legacy', material: material);
      final repository = LocalRecognitionRepository(store: store);
      // When both reports save and a fresh repository opens the same actual file root.
      await repository.save(contextual); await repository.save(legacy);
      final reopened = LocalRecognitionRepository(store: FileCaptureStore(directory.path));
      final loaded = (await reopened.findById(contextual.id))!;
      final old = (await reopened.findById(legacy.id))!;
      // Then exact context, unknown extension, raw failures/timing/source IDs and absence survive.
      expect(loaded.operationContext, context);
      expect(RecognitionReportCodec.encode(loaded), RecognitionReportCodec.encode(contextual));
      expect(loaded.runs.first.attempts.first, same(loaded.runs.last.attempts.first));
      expect(loaded.runs.last.attempts.last.result.failures.map((failure) => failure.stage), ImageRecognitionStage.values);
      expect(loaded.runs.last.attempts.last.inputAttemptIds, ['standard-attempt']);
      expect(loaded.extensions['unknown'], {'raw': true});
      expect(old.operationContext, isNull); expect(RecognitionReportCodec.encode(old), RecognitionReportCodec.encode(legacy));
      expect(await FileCaptureStore(directory.path).readMaterial(material), [1, 2, 3]);
    });

    test('OC3 malformed stored context remains observable and cannot be overwritten by save', () async {
      // Given a real report file with a present unsupported context namespace.
      final accepted = _report(material: material);
      final repository = LocalRecognitionRepository(store: store);
      await repository.save(accepted);
      final malformed = RecognitionReportCodec.encode(accepted);
      _map(malformed['extensions'])[RecognitionOperationContext.extensionKey] = {
        'schemaVersion': 2, 'sourceRole': 'role', 'targetKinds': ['opaque'],
        'instructions': 'requested', 'extensions': <String, Object?>{},
      };
      final file = _documentFile(directory, accepted.id);
      final contents = jsonEncode(malformed); await file.writeAsString(contents, flush: true);
      // When direct read, history listing and a replacement save encounter the malformed context.
      await expectLater(repository.findById(accepted.id), throwsFormatException);
      await expectLater(repository.listForMaterial(material.id), throwsFormatException);
      await expectLater(repository.save(accepted), throwsFormatException);
      // Then stored bytes and original remain exact with no migration, overwrite or absence conversion.
      expect(await file.readAsString(), contents);
      expect(await store.readMaterial(material), [1, 2, 3]);
    });

    test('D3 restart preserves originals comparison sharing and sorted per-material history', () async {
      // Given a real store with equal-time and older comparisons for one original plus another original.
      final repository = LocalRecognitionRepository(store: store);
      final other = await store.saveMaterial(bytes: Uint8List.fromList([4]), mediaType: 'image/png', capturedAt: _time);
      final reports = [
        _report(id: 'b', material: material), _report(id: 'a', material: material),
        _report(id: 'older', material: material, createdAt: _time.subtract(const Duration(days: 1))),
        _report(id: 'other', material: other),
      ];
      // When reports save durably and a new repository reopens the same root.
      for (final report in reports) { await repository.save(report); }
      final restarted = LocalRecognitionRepository(store: FileCaptureStore(directory.path));
      final history = await restarted.listForMaterial(material.id);
      final loaded = (await restarted.findById('a'))!;
      // Then sort order is deterministic, original bytes stay unchanged and absence alone is null.
      expect(history.map((item) => item.id), ['a', 'b', 'older']);
      expect((await restarted.listForMaterial(other.id)).single.id, 'other');
      expect(await restarted.findById('absent'), isNull);
      expect(loaded.runs[0].attempts.first, same(loaded.runs[1].attempts.first));
      expect(RecognitionReportCodec.encode(loaded), RecognitionReportCodec.encode(reports[1]));
      expect(await store.readMaterial(material), [1, 2, 3]);
      expect(await FileCaptureStore(directory.path).readMaterial(other), [4]);
      expect(material.originalName, 'original.jpg');
      expect(() => history.clear(), throwsUnsupportedError);
    });

    test('D4 same ID original or creation time conflicts preserve old durable bytes', () async {
      // Given one durable comparison and another valid original in the same store.
      final repository = LocalRecognitionRepository(store: store);
      final accepted = _report(material: material);
      await repository.save(accepted);
      final file = _documentFile(directory, accepted.id);
      final before = await file.readAsBytes();
      final other = await store.saveMaterial(bytes: Uint8List.fromList([4]), mediaType: 'image/png', capturedAt: _time);
      // When same-ID saves try to change ownership or creation time.
      await expectLater(repository.save(_report(material: other)), throwsArgumentError);
      await expectLater(repository.save(_report(material: material, createdAt: _time.add(const Duration(seconds: 1)))), throwsArgumentError);
      // Then both conflicts preserve accepted report bytes and both original files.
      expect(await file.readAsBytes(), before);
      expect(await store.readMaterial(material), [1, 2, 3]);
      expect(await store.readMaterial(other), [4]);
      expect((await repository.findById(accepted.id))!.material, material);
    });

    test('D4 corrupt nonobject unsupported and mismatched documents remain observable', () async {
      // Given a durable original and a manually corrupted listed report file.
      final repository = LocalRecognitionRepository(store: store);
      final valid = RecognitionReportCodec.encode(_report(material: material));
      final file = _documentFile(directory, 'report');
      await file.parent.create(recursive: true);
      final corruptions = [
        '{broken', '[]', jsonEncode({...valid, 'version': 9}), jsonEncode({...valid, 'id': 'other'}),
      ];
      // When each corrupt document is read directly and through material history listing.
      for (final content in corruptions) {
        await file.writeAsString(content, flush: true);
        await expectLater(repository.findById('report'), throwsFormatException);
        await expectLater(repository.listForMaterial(material.id), throwsFormatException);
        // Then corruption is never converted into absence or silently rewritten.
        expect(await file.readAsString(), content);
        expect(await store.readMaterial(material), [1, 2, 3]);
      }
    });

    test('D4 ordered failed saves recover while original old bytes and read errors stay visible', () async {
      // Given a durable report and a held first failing replacement on a forwarding store.
      final accepted = _report(material: material);
      await LocalRecognitionRepository(store: store).save(accepted);
      final oldBytes = await _documentFile(directory, 'report').readAsBytes();
      final forwarding = _FaultStore(store);
      final repository = LocalRecognitionRepository(store: forwarding);
      final gate = Completer<void>(); forwarding.writeGate = gate;
      final error = FileSystemException('controlled report write failure');
      // When two saves queue and the first write fails before the second can begin.
      final first = repository.save(_report(material: material, extensions: {'replacement': true}));
      final failure = expectLater(first, throwsA(same(error)));
      final second = repository.save(_report(id: 'next', material: material));
      await forwarding.writeStarted.future;
      expect(forwarding.writeIds, ['report']);
      forwarding.writeGate = null; gate.completeError(error);
      await failure; await second;
      forwarding.readError = error;
      await expectLater(repository.findById('report'), throwsA(same(error)));
      forwarding.readError = null; forwarding.materialError = error;
      await expectLater(repository.save(_report(id: 'read-failed', material: material)), throwsA(same(error)));
      forwarding.materialError = null;
      forwarding.listedIds = ['disappeared'];
      await expectLater(repository.listForMaterial(material.id), throwsFormatException);
      forwarding.listedIds = null; forwarding.readError = UnsupportedError('unsupported storage');
      await expectLater(repository.findById('report'), throwsUnsupportedError);
      forwarding.readError = null;
      // Then queued order, durable preservation, disappearance and IO failures are explicit.
      expect(forwarding.writeIds, ['report', 'next']);
      expect(await _documentFile(directory, 'report').readAsBytes(), oldBytes);
      expect((await repository.findById('next'))!.id, 'next');
      expect(await repository.findById('read-failed'), isNull);
      expect(await store.readMaterial(material), [1, 2, 3]);
      await repository.save(_report(id: 'recovered', material: material));
      expect(await repository.findById('recovered'), isNotNull);
    });
  });
}

final _time = DateTime.utc(2026, 10, 6, 1, 2, 3);
CaptureMaterialReference _material() => CaptureMaterialReference(id: 'original', mediaType: 'image/jpeg',
  byteLength: 3, capturedAt: _time, originalName: 'original.jpg');
RecognitionProviderAttempt _standard({String materialId = 'original'}) => RecognitionProviderAttempt(
  id: 'standard-attempt', providerId: 'mlkitStandard', materialId: materialId,
  availability: RecognitionProviderAvailability(providerId: 'mlkitStandard', state: RecognitionProviderState.available,
    capabilities: [RecognitionCapability.ocr, RecognitionCapability.barcodes]),
  startedAt: _time, elapsed: const Duration(microseconds: 7), executed: true,
  result: ImageRecognitionResult(text: ' raw OCR ', barcodeCompleted: true,
    barcodes: [RecognizedImageBarcode(value: ' 978 raw ', format: 'ean13')]),
);
RecognitionProviderAttempt _enhanced({String materialId = 'original'}) => RecognitionProviderAttempt(
  id: 'enhanced-attempt', providerId: 'geminiNano', materialId: materialId,
  availability: RecognitionProviderAvailability(providerId: 'geminiNano', state: RecognitionProviderState.available,
    capabilities: [RecognitionCapability.imageInterpretation, RecognitionCapability.candidateOrganization], modelName: 'reported native model'),
  startedAt: _time, elapsed: const Duration(microseconds: 11), executed: true, inputAttemptIds: ['standard-attempt'],
  result: ImageRecognitionResult(interpretation: 'raw interpretation', candidateOrganizationCompleted: true,
    candidates: [RecognitionCandidate(kind: 'opaque', value: 'raw suggestion')],
    failures: ImageRecognitionStage.values.map((stage) => ImageRecognitionFailure(
      stage: stage, code: 'native-${stage.name}', message: 'native ${stage.name} description',
    ))),
);
RecognitionComparison _report({String id = 'report', CaptureMaterialReference? material,
  DateTime? createdAt, Map<String, Object?> extensions = const {}}) {
  final original = material ?? _material();
  final standard = _standard(materialId: original.id);
  final enhanced = _enhanced(materialId: original.id);
  return RecognitionComparison(id: id, material: original, createdAt: createdAt ?? _time, extensions: extensions, runs: [
    RecognitionRun(desiredConfigurationId: 'androidStandard', actualConfigurationId: 'androidStandard',
      actualProviderIds: ['mlkitStandard'], attempts: [standard]),
    RecognitionRun(desiredConfigurationId: 'pixelEnhanced', actualConfigurationId: 'pixelEnhanced',
      actualProviderIds: ['mlkitStandard', 'geminiNano'], attempts: [standard, enhanced]),
  ]);
}
RecognitionComparison _single({RecognitionProviderState state = RecognitionProviderState.available,
  required ImageRecognitionResult result}) {
  final executed = state == RecognitionProviderState.available;
  return RecognitionComparison(id: 'single', material: _material(), createdAt: _time, runs: [RecognitionRun(
    desiredConfigurationId: 'androidStandard', actualConfigurationId: executed ? 'androidStandard' : null,
    actualProviderIds: executed ? ['mlkitStandard'] : [], attempts: [RecognitionProviderAttempt(
      id: 'attempt', providerId: 'mlkitStandard', materialId: 'original', startedAt: _time,
      elapsed: executed ? const Duration(microseconds: 1) : Duration.zero, executed: executed, result: result,
      availability: RecognitionProviderAvailability(providerId: 'mlkitStandard', state: state,
        reason: state == RecognitionProviderState.unavailable ? 'native unavailable' : null),
    )],
  )]);
}
Map<String, Object?> _map(Object? value) => value as Map<String, Object?>;
Map<String, Object?> _row(Map<String, Object?> map, [int index = 0]) => _map((map['runs'] as List)[index]);
Map<String, Object?> _attempt(Map<String, Object?> map, {int row = 0, int index = 0}) =>
  _map((_row(map, row)['attempts'] as List)[index]);
Map<String, Object?> _bad(void Function(Map<String, Object?>) mutate) {
  final map = _map(jsonDecode(jsonEncode(RecognitionReportCodec.encode(_report()))));
  mutate(map); return map;
}
File _documentFile(Directory directory, String id) => File(
  '${directory.path}${Platform.pathSeparator}documents${Platform.pathSeparator}${LocalRecognitionRepository.collection}${Platform.pathSeparator}$id.json',
);
final class _FaultStore implements LocalCaptureStore {
  _FaultStore(this.delegate);
  final LocalCaptureStore delegate;
  Object? readError; Object? materialError;
  List<String>? listedIds;
  Completer<void>? writeGate;
  final writeStarted = Completer<void>();
  final writeIds = <String>[];
  @override
  Future<CaptureMaterialReference> saveMaterial({required Uint8List bytes, required String mediaType,
    required DateTime capturedAt, String? originalName}) => delegate.saveMaterial(bytes: bytes,
      mediaType: mediaType, capturedAt: capturedAt, originalName: originalName);
  @override
  Future<Uint8List> readMaterial(CaptureMaterialReference reference) async {
    if (materialError != null) throw materialError!;
    return delegate.readMaterial(reference);
  }
  @override
  Future<Map<String, Object?>?> readDocument(String collection, String id) async {
    if (readError != null) throw readError!;
    return delegate.readDocument(collection, id);
  }
  @override
  Future<List<String>> listDocumentIds(String collection) async => listedIds ?? await delegate.listDocumentIds(collection);
  @override
  Future<void> saveDocument(String collection, String id, Map<String, Object?> document) async {
    writeIds.add(id);
    if (!writeStarted.isCompleted) writeStarted.complete();
    if (writeGate != null) await writeGate!.future;
    await delegate.saveDocument(collection, id, document);
  }
}
