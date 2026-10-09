import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('original and raw recognition values', () {
    test('P1 defensive values preserve empty completed stages and ordinary equality', () {
      // Given caller-owned bytes and raw provider lists.
      final bytes = Uint8List.fromList([1, 2, 3]);
      final photo = _photo(bytes: bytes);
      final codes = [RecognizedImageBarcode(value: ' 978 raw ', format: 'ean13')];
      final candidates = [RecognitionCandidate(kind: 'opaque', value: 'proposal')];
      final failures = [ImageRecognitionFailure(
        stage: ImageRecognitionStage.text, code: 'native', message: 'native description',
      )];
      final result = ImageRecognitionResult(
        text: '', barcodes: codes, barcodeCompleted: true, interpretation: '',
        candidates: candidates, candidateOrganizationCompleted: true, failures: failures,
      );
      final previous = [result];
      final input = ImageRecognitionInput(material: _material(), bytes: bytes, previousResults: previous);
      // When all caller lists and returned byte copies are mutated.
      bytes[0] = 99;
      photo.bytes[1] = 99;
      input.bytes[2] = 99;
      codes.clear(); candidates.clear(); failures.clear(); previous.clear();
      final equivalent = _photo();
      // Then immutable values retain original content, UTC and successful empties.
      expect(photo.bytes, [1, 2, 3]);
      expect(input.bytes, [1, 2, 3]);
      expect(photo, equivalent);
      expect(photo.hashCode, equivalent.hashCode);
      expect(photo.capturedAt.isUtc, isTrue);
      expect(photo, isNot(_photo(name: 'other.jpg')));
      expect(photo, isNot(_photo(bytes: Uint8List.fromList([3, 2, 1]))));
      expect(result.text, ''); expect(result.interpretation, '');
      expect(result.hasSuccessfulOutput, isTrue);
      expect(ImageRecognitionResult(barcodeCompleted: true).hasSuccessfulOutput, isTrue);
      expect(ImageRecognitionResult(candidateOrganizationCompleted: true).hasSuccessfulOutput, isTrue);
      expect(ImageRecognitionResult().hasSuccessfulOutput, isFalse);
      expect(result.barcodes.single, RecognizedImageBarcode(value: ' 978 raw ', format: 'ean13'));
      expect(result.barcodes.single.hashCode, RecognizedImageBarcode(value: ' 978 raw ', format: 'ean13').hashCode);
      expect(result.candidates.single, RecognitionCandidate(kind: 'opaque', value: 'proposal'));
      expect(result.candidates.single.hashCode, RecognitionCandidate(kind: 'opaque', value: 'proposal').hashCode);
      expect(result.failures.single, ImageRecognitionFailure(
        stage: ImageRecognitionStage.text, code: 'native', message: 'native description',
      ));
      expect(result.failures.single.hashCode, ImageRecognitionFailure(
        stage: ImageRecognitionStage.text, code: 'native', message: 'native description',
      ).hashCode);
      expect(() => result.barcodes.clear(), throwsUnsupportedError);
      expect(() => result.candidates.clear(), throwsUnsupportedError);
      expect(() => result.failures.clear(), throwsUnsupportedError);
      expect(input.previousResults.single, same(result));
      expect(() => input.previousResults.clear(), throwsUnsupportedError);
      expect(_photo(type: 'IMAGE/PNG').mediaType, 'IMAGE/PNG');
    });

    test('P1 invalid image and completion values reject before acquisition', () {
      // Given invalid lengths, MIME tokens, labels and completion combinations.
      final constructors = <void Function()>[
        () => _photo(bytes: Uint8List(0)),
        for (final type in ['image', 'image/ png', 'text/plain', 'image/']) () => _photo(type: type),
        () => ImageRecognitionInput(material: _material(), bytes: Uint8List(2)),
        () => ImageRecognitionInput(material: _material(type: 'text/plain'), bytes: Uint8List(3)),
        () => RecognizedImageBarcode(value: ' ', format: 'ean13'),
        () => RecognizedImageBarcode(value: 'x', format: ''),
        () => RecognitionCandidate(kind: '', value: 'x'),
        () => RecognitionCandidate(kind: 'x', value: ' '),
        () => ImageRecognitionFailure(stage: ImageRecognitionStage.provider, code: '', message: 'x'),
        () => ImageRecognitionFailure(stage: ImageRecognitionStage.provider, code: 'x', message: ' '),
        () => ImageRecognitionResult(barcodes: [RecognizedImageBarcode(value: 'x', format: 'raw')]),
        () => ImageRecognitionResult(candidates: [RecognitionCandidate(kind: 'raw', value: 'x')]),
      ];
      // When each invalid public value is constructed.
      for (final construct in constructors) {
        // Given this invalid constructor branch from the finite value matrix.
        // When the public constructor admits the value.
        // Then constructor validation remains observable.
        expect(construct, throwsArgumentError);
      }
    });
  });

  group('durable photo orchestration', () {
    late Directory directory;
    late _Store store;
    late _Camera camera;
    late _Provider standard;
    late _Provider enhanced;
    late PhotoCaptureService service;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('photo-service-spec-');
      store = _Store(FileCaptureStore(directory.path));
      camera = _Camera(); standard = _Provider(); enhanced = _Provider(enhanced: true);
      service = PhotoCaptureService(
        camera: CameraService(provider: camera),
        recognition: ImageRecognitionService(registry: RecognitionProviderRegistry(providers: [standard, enhanced])),
        store: store,
      );
    });
    tearDown(() async { await directory.delete(recursive: true); });

    group('durable per-operation context', () {
      for (final command in ['capture', 'recover', 'recognize', 'compare']) {
        test('OC3 $command persists exact context and saved-original ownership', () async {
          // Given a real file store, a recovered photo or saved original, and opaque intent.
          final context = RecognitionOperationContext(sourceRole: ' exact role $command ',
            targetKinds: ['opaque'], instructions: ' exact instructions ',
            extensions: {'unknown': [null, true, 1.5]});
          CaptureMaterialReference? original;
          if (command == 'recover') camera.recoveredPhoto = _photo();
          if (command == 'recognize' || command == 'compare') {
            original = (await service.captureOriginal())!;
          }
          final importsBefore = store.imports;
          // When this public recognition command receives the operation's context.
          final RecognitionComparison? report = switch (command) {
            'capture' => await service.capture(desiredConfigurationId: 'androidStandard', operationContext: context),
            'recover' => await service.recover(desiredConfigurationId: 'androidStandard', operationContext: context),
            'recognize' => await service.recognize(original!, desiredConfigurationId: 'androidStandard', operationContext: context),
            _ => await service.compare(original!, operationContext: context),
          };
          final accepted = report!;
          final reopenedStore = FileCaptureStore(directory.path);
          final reopened = (await LocalRecognitionRepository(store: reopenedStore).findById(accepted.id))!;
          // Then exact durable intent, raw stages, metadata and ownership survive a fresh reopen.
          expect(accepted.operationContext, context); expect(reopened.operationContext, context);
          expect(RecognitionReportCodec.encode(reopened), RecognitionReportCodec.encode(accepted));
          expect(standard.inputs.single.operationContext, same(context));
          expect(standard.inputs.single.material, same(accepted.material));
          expect(standard.inputs.single.bytes, [1, 2, 3]);
          expect(reopened.runs.first.attempts.first.result.text, 'raw OCR');
          expect(await reopenedStore.readMaterial(reopened.material), [1, 2, 3]);
          expect(reopened.material.originalName, 'original.jpg');
          expect(reopened.material.capturedAt, _time);
          expect(store.imports, importsBefore + (original == null ? 1 : 0));
          expect(store.writes, 1); expect(standard.prepares + enhanced.prepares, 0);
          if (command == 'compare') {
            // Given the comparison's shared standard and actual enhanced stages.
            // When input provenance and object sharing are observed after restart.
            // Then one original and the same intent feed the real earlier-result chain.
            expect(enhanced.inputs.single.operationContext, same(context));
            expect(enhanced.inputs.single.previousResults.single, same(accepted.runs.first.attempts.single.result));
            expect(reopened.runs.first.attempts.single, same(reopened.runs.last.attempts.first));
          }
        });
      }

      test('OC3 cancelled contextual capture and empty recovery leave no reports or sticky intent', () async {
        // Given a cancelled camera and an empty lost-photo recovery with caller intent.
        camera.photo = null;
        final context = RecognitionOperationContext(sourceRole: 'cancelled',
          targetKinds: ['opaque'], instructions: 'requested');
        // When both contextual acquisition APIs cancel, then a legacy capture succeeds.
        final cancelled = await service.capture(desiredConfigurationId: 'androidStandard', operationContext: context);
        final recovered = await service.recover(desiredConfigurationId: 'androidStandard', operationContext: context);
        // Then cancellation has no import, provider or report side effects.
        expect(cancelled, isNull); expect(recovered, isNull);
        expect(store.imports, 0); expect(store.writes, 0); expect(standard.inputs, isEmpty);
        expect(await service.reports.listForMaterial('absent'), isEmpty);
        // Given the same service after cancellation and a new available original.
        camera.photo = _photo();
        // When the next caller omits context.
        final legacy = (await service.capture(desiredConfigurationId: 'androidStandard'))!;
        // Then absence survives the durable report and no previous intent leaks.
        expect(legacy.operationContext, isNull); expect(standard.inputs.single.operationContext, isNull);
        expect(legacy.extensions.containsKey(RecognitionOperationContext.extensionKey), isFalse);
        expect((await service.reports.findById(legacy.id))!.operationContext, isNull);
        expect(store.imports, 1); expect(store.writes, 1);
      });

      for (final stage in ['read', 'report']) {
        test('OC3 held $stage retains context rejects overlaps and returns only after durable write', () async {
          // Given one saved original and this finite held read or report-write boundary.
          final original = (await service.captureOriginal())!;
          final context = RecognitionOperationContext(sourceRole: 'held-$stage',
            targetKinds: ['opaque'], instructions: 'start intent');
          final gate = Completer<void>();
          store.gateStage = stage; store.operationGate = gate;
          var settled = false;
          // When contextual recognition starts and all contextual commands attempt overlap.
          final pending = service.recognize(original, desiredConfigurationId: 'androidStandard', operationContext: context);
          final observed = pending.then((report) { settled = true; return report; });
          await store.operationStarted.future;
          await expectLater(service.capture(desiredConfigurationId: 'androidStandard', operationContext: context), throwsStateError);
          await expectLater(service.recover(desiredConfigurationId: 'androidStandard', operationContext: context), throwsStateError);
          await expectLater(service.recognize(original, desiredConfigurationId: 'androidStandard', operationContext: context), throwsStateError);
          await expectLater(service.compare(original, operationContext: context), throwsStateError);
          // Then no report is returned before the held durable boundary completes.
          expect(settled, isFalse);
          expect(await store.delegate.listDocumentIds(LocalRecognitionRepository.collection), isEmpty);
          // Given the same accepted operation and now released finite store gate.
          store.gateStage = null; gate.complete();
          // When the caller settles and the report is reopened independently.
          final accepted = await observed;
          final reopened = (await LocalRecognitionRepository(store: FileCaptureStore(directory.path)).findById(accepted.id))!;
          // Then only one durable report exists, exact context survived, and imports did not repeat.
          expect(reopened.operationContext, context); expect(standard.inputs.single.operationContext, same(context));
          expect(await store.delegate.listDocumentIds(LocalRecognitionRepository.collection), [accepted.id]);
          expect(store.imports, 1); expect(camera.captures, 1); expect(camera.recoveries, 0);
          expect(store.writes, 1); expect(standard.prepares + enhanced.prepares, 0);
        });

        test('OC3 contextual $stage error remains exact and next absent request recovers', () async {
          // Given a saved original and this controlled actual store failure.
          final original = (await service.captureOriginal())!;
          final context = RecognitionOperationContext(sourceRole: 'failed-$stage',
            targetKinds: ['opaque'], instructions: 'requested intent');
          final failure = FileSystemException('actual $stage failure');
          store.failureStage = stage; store.failure = failure;
          // When contextual recognition reaches the failing boundary.
          await expectLater(service.recognize(original, desiredConfigurationId: 'androidStandard',
            operationContext: context), throwsA(same(failure)));
          // Then the failure is observable and no successful durable report is invented.
          expect(await store.delegate.listDocumentIds(LocalRecognitionRepository.collection), isEmpty);
          expect(await store.delegate.readMaterial(original), [1, 2, 3]);
          // Given the released failure boundary on the same service.
          store.failureStage = null;
          // When a fresh request on that saved original omits context.
          final next = await service.recognize(original, desiredConfigurationId: 'androidStandard');
          // Then guard recovery preserves absence and the original without another import.
          expect(next.operationContext, isNull); expect(standard.inputs.last.operationContext, isNull);
          expect((await service.reports.findById(next.id))!.operationContext, isNull);
          expect(store.imports, 1); expect(camera.captures, 1);
        });
      }
    });

    group('durable original-only acquisition', () {
      test('R1 saved reads preserve exact metadata and bytes without readiness or acquisition', () async {
        // Given an original-only saved reference and unsupported/unavailable dependencies.
        final material = (await service.captureOriginal())!;
        camera.supported = false;
        standard.state = RecognitionProviderState.unavailable;
        enhanced.state = RecognitionProviderState.unavailable;
        // When the saved original is read once through the public guarded API.
        final bytes = await service.readOriginal(material);
        // Then the same reference reaches the store once without any readiness or report work.
        expect(store.lastReadReference, same(material)); expect(store.reads, 1);
        expect(bytes, [1, 2, 3]); expect(material, same(store.saved.single));
        expect(material.mediaType, 'image/jpeg'); expect(material.originalName, 'original.jpg');
        expect(material.capturedAt, _time); expect(material.byteLength, 3);
        expect(camera.captures, 1); expect(camera.recoveries, 0); expect(store.imports, 1);
        expect(store.writes, 0); expect(standard.probes + enhanced.probes, 0);
        expect(standard.prepares + enhanced.prepares, 0);
        expect(standard.inputs, isEmpty); expect(enhanced.inputs, isEmpty);
        // Given caller-owned returned bytes and a fresh service over the same durable root.
        bytes[0] = 99;
        final reopened = PhotoCaptureService(camera: CameraService(provider: camera),
          recognition: ImageRecognitionService(registry: RecognitionProviderRegistry(providers: [standard, enhanced])),
          store: FileCaptureStore(directory.path));
        // When both the original service and the fresh service explicitly reread.
        final repeated = await service.readOriginal(material);
        final fresh = await reopened.readOriginal(material);
        // Then mutation never rewrites persisted bytes or creates a report/cache/readiness effect.
        expect(repeated, [1, 2, 3]); expect(fresh, [1, 2, 3]); expect(store.reads, 2);
        expect(await store.delegate.listDocumentIds(LocalRecognitionRepository.collection), isEmpty);
        expect(camera.captures, 1); expect(camera.recoveries, 0); expect(store.imports, 1);
        expect(standard.probes + enhanced.probes, 0); expect(standard.prepares + enhanced.prepares, 0);
      });

      test('R2 held actual original read excludes every public photo operation until settlement', () async {
        // Given a durable original and an observed finite read gate in its borrowed store.
        final material = (await service.captureOriginal())!;
        store.gateStage = 'read'; store.operationGate = Completer<void>();
        // When the public read enters actual store IO and owns the shared guard.
        final first = service.readOriginal(material);
        await store.operationStarted.future;
        final competitors = <Future<Object?> Function()>[
          service.captureOriginal, service.recoverOriginal,
          () => service.capture(desiredConfigurationId: 'androidStandard'),
          () => service.recover(desiredConfigurationId: 'androidStandard'),
          () => service.recognize(material, desiredConfigurationId: 'androidStandard'),
          () => service.compare(material), service.availability,
          () => service.prepareProvider('mlkitStandard'), () => service.readOriginal(material),
        ];
        for (final competitor in competitors) {
          // Given this direct public competitor while the actual original read remains held.
          // When it requests the same runtime.
          // Then Core rejects before any competing acquisition/readiness/storage/inference.
          await expectLater(competitor(), throwsStateError);
          expect(camera.captures, 1); expect(camera.recoveries, 0);
          expect(store.imports, 1); expect(store.reads, 1); expect(store.writes, 0);
          expect(standard.probes + enhanced.probes, 0); expect(standard.prepares + enhanced.prepares, 0);
          expect(standard.inputs, isEmpty); expect(enhanced.inputs, isEmpty);
        }
        // Given only the admitted read gate is released.
        store.operationGate!.complete();
        // When the original future settles and another explicit read follows.
        final bytes = await first;
        final next = await service.readOriginal(material);
        // Then the guard releases after successful IO and both reads preserve the original.
        expect(bytes, [1, 2, 3]); expect(next, [1, 2, 3]); expect(store.reads, 2);
        expect(await store.delegate.listDocumentIds(LocalRecognitionRepository.collection), isEmpty);
      });

      for (final boundary in ['injected', 'missing', 'length']) {
        test('R2 $boundary read failure remains observable and releases shared ownership', () async {
          // Given a durable original/report and this exact failing read boundary.
          final report = (await service.capture(desiredConfigurationId: 'androidStandard'))!;
          final retained = report.material;
          final actual = FileSystemException('actual original read failure');
          final reference = boundary == 'injected' ? retained : CaptureMaterialReference(
            id: boundary == 'missing' ? 'missing-original' : retained.id,
            mediaType: retained.mediaType, byteLength: boundary == 'length' ? retained.byteLength + 1 : retained.byteLength,
            capturedAt: retained.capturedAt, originalName: retained.originalName);
          if (boundary == 'injected') { store.failureStage = 'read'; store.failure = actual; }
          final imports = store.imports; final writes = store.writes;
          // When the guarded public read encounters the injected or actual file-store failure.
          await expectLater(service.readOriginal(reference), boundary == 'injected'
            ? throwsA(same(actual)) : boundary == 'missing' ? throwsA(isA<FileSystemException>()) : throwsFormatException);
          // Then failure preserves original/report ownership and performs no new acquisition or write.
          expect(store.imports, imports); expect(store.writes, writes); expect(camera.captures, 1);
          expect(await store.delegate.readMaterial(retained), [1, 2, 3]);
          expect(RecognitionReportCodec.encode((await service.reports.findById(report.id))!),
            RecognitionReportCodec.encode(report));
          // Given explicit fixture recovery after the failed read.
          store.failureStage = null;
          // When the same public runtime rereads its retained original.
          final next = await service.readOriginal(retained);
          // Then finally released ownership admits unchanged saved bytes.
          expect(next, [1, 2, 3]); expect(store.imports, imports); expect(store.writes, writes);
        });
      }

      test('A1 capture persists exact original once without provider or report work', () async {
        // Given an unchanged image and a caller-owned real file store.
        camera.photo = _photo(type: 'IMAGE/PNG', name: ' page original.png ');
        // When the original-only API returns its imported reference.
        final material = (await service.captureOriginal())!;
        final reopened = FileCaptureStore(directory.path);
        // Then the actual saved reference and bytes survive a fresh store reader.
        expect(material, same(store.saved.single));
        expect(material.mediaType, 'IMAGE/PNG');
        expect(material.originalName, ' page original.png ');
        expect(material.capturedAt, _time);
        expect(material.capturedAt.isUtc, isTrue);
        expect(material.byteLength, 3);
        expect(await reopened.readMaterial(material), [1, 2, 3]);
        expect(camera.captures, 1); expect(camera.recoveries, 0);
        expect(store.imports, 1); expect(store.reads, 0); expect(store.writes, 0);
        expect(standard.probes, 0); expect(enhanced.probes, 0);
        expect(standard.prepares, 0); expect(enhanced.prepares, 0);
        expect(standard.inputs, isEmpty); expect(enhanced.inputs, isEmpty);
        expect(await reopened.listDocumentIds(LocalRecognitionRepository.collection), isEmpty);
      });

      test('A2 recovery consumes one exact lost original and empty acquisition does no IO', () async {
        // Given a one-shot recovered image, independently of the capture result.
        camera.recoveredPhoto = _photo(bytes: Uint8List.fromList([7, 8, 9]),
          type: 'image/png', name: 'recovered.png');
        camera.photo = null;
        // When recovery consumes the image and subsequent recovery/capture cancel.
        final material = (await service.recoverOriginal())!;
        final empty = await service.recoverOriginal();
        final cancelled = await service.captureOriginal();
        // Then only the recovered original was imported, unchanged and without inference.
        expect(empty, isNull); expect(cancelled, isNull);
        expect(material, same(store.saved.single));
        expect(material.mediaType, 'image/png');
        expect(material.originalName, 'recovered.png');
        expect(material.capturedAt, _time); expect(material.capturedAt.isUtc, isTrue);
        expect(await FileCaptureStore(directory.path).readMaterial(material), [7, 8, 9]);
        expect(camera.captures, 1); expect(camera.recoveries, 2);
        expect(store.imports, 1); expect(store.reads, 0); expect(store.writes, 0);
        expect(standard.probes, 0); expect(enhanced.probes, 0);
        expect(standard.prepares, 0); expect(enhanced.prepares, 0);
        expect(standard.inputs, isEmpty); expect(enhanced.inputs, isEmpty);
        expect(await service.reports.listForMaterial(material.id), isEmpty);
        // Given a new explicit supported capture after both empty operations.
        camera.photo = _photo();
        // When the caller captures again.
        final next = await service.captureOriginal();
        // Then cancellation released the shared guard without deleting the recovered image.
        expect(next, isNotNull);
        expect(await store.delegate.readMaterial(material), [7, 8, 9]);
      });

      for (final action in ['capture', 'recover']) {
        for (final boundary in ['permission', 'camera', 'import', 'unsupported']) {
          test('A3 $action forwards exact $boundary failure and releases original ownership', () async {
            // Given an already accepted original and this actual failing boundary.
            final retained = (await service.captureOriginal())!;
            final actual = boundary == 'permission'
              ? PlatformException(code: 'camera_access_denied', message: 'actual permission failure')
              : FileSystemException('actual $boundary failure');
            camera.recoveredPhoto = _photo();
            if (boundary == 'unsupported') {
              camera.supported = false;
            } else if (boundary == 'import') {
              store.failureStage = 'import'; store.failure = actual;
            } else {
              camera.error = actual;
            }
            // When the selected original-only operation fails once.
            final failed = action == 'capture' ? service.captureOriginal() : service.recoverOriginal();
            await expectLater(failed, boundary == 'unsupported' ? throwsUnsupportedError : throwsA(same(actual)));
            // Then no reference, report or provider result was fabricated or retried.
            expect(store.saved, [retained]);
            expect(store.imports, boundary == 'import' ? 2 : 1);
            expect(store.reads, 0); expect(store.writes, 0);
            expect(camera.captures, action == 'capture' && boundary != 'unsupported' ? 2 : 1);
            expect(camera.recoveries, action == 'recover' && boundary != 'unsupported' ? 1 : 0);
            expect(standard.probes, 0); expect(enhanced.probes, 0);
            expect(standard.prepares, 0); expect(enhanced.prepares, 0);
            expect(standard.inputs, isEmpty); expect(enhanced.inputs, isEmpty);
            expect(await store.delegate.listDocumentIds(LocalRecognitionRepository.collection), isEmpty);
            // Given the failing fixture boundary now admits another explicit action.
            camera.error = null; camera.supported = true;
            store.failureStage = null; camera.recoveredPhoto = _photo();
            // When the same API is invoked again.
            final next = action == 'capture' ? await service.captureOriginal() : await service.recoverOriginal();
            // Then the guard recovered and the previously owned image remains unchanged.
            expect(next, isNotNull);
            expect(await store.delegate.readMaterial(retained), [1, 2, 3]);
          });
        }
      }

      for (final action in ['capture', 'recover']) {
        for (final boundary in ['camera', 'import']) {
          test('A4 held original $action $boundary excludes all photo and readiness operations', () async {
            // Given this original-only action held at acquisition or durable import.
            final cameraGate = Completer<CapturedPhoto?>();
            final importGate = Completer<void>();
            camera.recoveredPhoto = _photo();
            if (boundary == 'camera') {
              if (action == 'capture') { camera.gate = cameraGate; }
              else { camera.recoveryGate = cameraGate; }
            } else {
              store.gateStage = 'import'; store.operationGate = importGate;
            }
            // When the admitted operation owns the shared service guard.
            final first = action == 'capture' ? service.captureOriginal() : service.recoverOriginal();
            await (boundary == 'import' ? store.operationStarted.future
              : action == 'capture' ? camera.captureStarted.future : camera.recoveryStarted.future);
            final overlaps = <Future<Object?> Function()>[
              service.captureOriginal, service.recoverOriginal,
              () => service.capture(desiredConfigurationId: 'androidStandard'),
              () => service.recover(desiredConfigurationId: 'androidStandard'),
              () => service.recognize(_material(), desiredConfigurationId: 'androidStandard'),
              () => service.compare(_material()), service.availability,
              () => service.prepareProvider('mlkitStandard'),
              () => service.readOriginal(_material()),
            ];
            for (final overlap in overlaps) {
              // Given a competing public photo/readiness operation while import is owned.
              // When that operation is requested.
              // Then it rejects before any competing work starts.
              await expectLater(overlap(), throwsStateError);
            }
            // Given only the admitted finite acquisition/import gate is released.
            if (boundary == 'camera') { cameraGate.complete(_photo()); }
            else { importGate.complete(); }
            // When the admitted operation finishes durability.
            final material = (await first)!;
            // Then exactly one camera action/import completed and no recognition work ran.
            expect(store.imports, 1); expect(store.saved.single, same(material));
            expect(camera.captures, action == 'capture' ? 1 : 0);
            expect(camera.recoveries, action == 'recover' ? 1 : 0);
            expect(store.reads, 0); expect(store.writes, 0);
            expect(standard.probes, 0); expect(enhanced.probes, 0);
            expect(standard.prepares, 0); expect(enhanced.prepares, 0);
            expect(standard.inputs, isEmpty); expect(enhanced.inputs, isEmpty);
            expect(await store.delegate.readMaterial(material), [1, 2, 3]);
          });
        }
      }

      for (final action in ['capture', 'recover']) {
        test('A4 held $action cancellation releases the original-only guard', () async {
          // Given a pending original-only camera action.
          final gate = Completer<CapturedPhoto?>();
          if (action == 'capture') { camera.gate = gate; }
          else { camera.recoveryGate = gate; }
          // When the camera cancels after the action has started.
          final first = action == 'capture' ? service.captureOriginal() : service.recoverOriginal();
          await (action == 'capture' ? camera.captureStarted.future : camera.recoveryStarted.future);
          gate.complete(null);
          final cancelled = await first;
          // Then cancellation performs no import or provider work.
          expect(cancelled, isNull); expect(store.imports, 0);
          expect(store.reads, 0); expect(store.writes, 0);
          expect(standard.probes, 0); expect(enhanced.probes, 0);
          expect(standard.inputs, isEmpty); expect(enhanced.inputs, isEmpty);
          // Given a subsequent explicit original acquisition.
          camera.gate = null; camera.recoveryGate = null; camera.recoveredPhoto = _photo();
          // When the same API runs again.
          final next = action == 'capture' ? await service.captureOriginal() : await service.recoverOriginal();
          // Then released ownership permits one durable original.
          expect(next, isNotNull); expect(store.imports, 1);
        });
      }

      test('A5 later explicit recognition and comparison preserve original and fallback lineage', () async {
        // Given an original-only saved reference and an unavailable enhanced provider.
        enhanced.state = RecognitionProviderState.unavailable;
        final material = (await service.captureOriginal())!;
        // When the caller explicitly recognizes and compares that saved original later.
        final recognized = await service.recognize(material, desiredConfigurationId: 'pixelEnhanced');
        final compared = await service.compare(material);
        final reopened = LocalRecognitionRepository(store: FileCaptureStore(directory.path));
        // Then camera/import remain once, both raw reports are durable, and fallback intent survives.
        expect(camera.captures, 1); expect(camera.recoveries, 0); expect(store.imports, 1);
        expect(recognized.material, same(material)); expect(compared.material, same(material));
        expect(recognized.runs.single.desiredConfigurationId, 'pixelEnhanced');
        expect(recognized.runs.single.actualConfigurationId, 'androidStandard');
        expect(recognized.runs.single.fallbackReason, isNotEmpty);
        expect(compared.runs.map((run) => run.desiredConfigurationId), ['androidStandard', 'pixelEnhanced']);
        expect(compared.runs.last.actualConfigurationId, 'androidStandard');
        expect(compared.runs.last.fallbackReason, isNotEmpty);
        expect(compared.runs.first.attempts.single, same(compared.runs.last.attempts.first));
        expect(compared.runs.first.attempts.single.result.text, 'raw OCR');
        expect(compared.runs.last.attempts.last.executed, isFalse);
        expect(standard.inputs, hasLength(2)); expect(enhanced.inputs, isEmpty);
        expect(standard.prepares, 0); expect(enhanced.prepares, 0);
        for (final input in standard.inputs) {
          // Given this explicitly recorded recognition input.
          // When its material identity and image bytes are observed.
          // Then inference used the unchanged original-only material.
          expect(input.material, same(material)); expect(input.bytes, [1, 2, 3]);
        }
        expect(RecognitionReportCodec.encode((await reopened.findById(recognized.id))!),
          RecognitionReportCodec.encode(recognized));
        expect(RecognitionReportCodec.encode((await reopened.findById(compared.id))!),
          RecognitionReportCodec.encode(compared));
        expect(await reopened.listForMaterial(material.id), hasLength(2));
        expect(await FileCaptureStore(directory.path).readMaterial(material), [1, 2, 3]);
      });
    });

    test('P2 cancellation and empty recovery perform no IO and allow a next capture', () async {
      // Given a camera that cancels and has no lost photo.
      camera.photo = null;
      // When acquisition and recovery return no photo.
      final cancelled = await service.capture(desiredConfigurationId: RecognitionSettings.androidStandard);
      final recovered = await service.recover(desiredConfigurationId: RecognitionSettings.androidStandard);
      // Then no storage or recognition ran and the service can be reused.
      expect(cancelled, isNull); expect(recovered, isNull);
      expect(store.imports, 0); expect(store.reads, 0); expect(store.writes, 0);
      expect(standard.inputs, isEmpty);
      camera.photo = _photo();
      expect(await service.capture(desiredConfigurationId: RecognitionSettings.androidStandard), isNotNull);
    });

    test('P3 capture is durable before return and comparison reuses the saved original', () async {
      // Given a real file store and two providers over unchanged image bytes.
      camera.photo = _photo();
      // When capture completes, then restart and repeated recognition use its reference.
      final captured = (await service.capture(desiredConfigurationId: RecognitionSettings.androidStandard))!;
      final restarted = LocalRecognitionRepository(store: FileCaptureStore(directory.path));
      final durable = await restarted.findById(captured.id);
      final single = await service.recognize(captured.material,
        desiredConfigurationId: RecognitionSettings.pixelEnhanced);
      final compared = await service.compare(captured.material);
      // Then original metadata, durable history, import counts and provider inputs agree.
      expect(durable, isNotNull);
      expect(RecognitionReportCodec.encode(durable!), RecognitionReportCodec.encode(captured));
      expect(captured.material.originalName, 'original.jpg');
      expect(captured.material.mediaType, 'image/jpeg');
      expect(captured.material.capturedAt, _time);
      expect(await store.delegate.readMaterial(captured.material), [1, 2, 3]);
      expect(store.imports, 1); expect(camera.captures, 1); expect(camera.recoveries, 0);
      expect(store.reads, 6); expect(store.writes, 3);
      expect(single.material.id, captured.material.id);
      expect(compared.material.id, captured.material.id);
      expect(compared.runs.map((row) => row.desiredConfigurationId),
        [RecognitionSettings.androidStandard, RecognitionSettings.pixelEnhanced]);
      for (final input in [...standard.inputs, ...enhanced.inputs]) {
        // Given this recorded provider input from a saved-original operation.
        // When its source identity and bytes are observed.
        // Then each provider retained the same unchanged original.
        expect(input.material, captured.material); expect(input.bytes, [1, 2, 3]);
      }
      expect(enhanced.inputs.last.previousResults.single.text, 'raw OCR');
      expect((await restarted.listForMaterial(captured.material.id)).length, 3);
    });

    test('P4 camera errors and unsupported acquisition are observable and reusable', () async {
      // Given a permission-like provider exception and a camera support toggle.
      final permission = StateError('permission denied by camera');
      camera.error = permission;
      // When capture fails, recovery fails, and an unsupported capture is requested.
      final capture = service.capture(desiredConfigurationId: RecognitionSettings.androidStandard);
      await expectLater(capture, throwsA(same(permission)));
      await expectLater(service.recover(desiredConfigurationId: RecognitionSettings.androidStandard), throwsA(same(permission)));
      camera.error = null; camera.supported = false;
      await expectLater(service.capture(desiredConfigurationId: RecognitionSettings.androidStandard), throwsUnsupportedError);
      // Then no original or inference was fabricated and a supported retry succeeds.
      expect(store.imports, 0); expect(standard.inputs, isEmpty);
      expect(camera.captures, 1); expect(camera.recoveries, 1);
      expect(service.isSupported, isFalse);
      camera.supported = true;
      expect(await service.capture(desiredConfigurationId: RecognitionSettings.androidStandard), isNotNull);
    });

    test('P4 overlapping photo and camera operations reject while the first is pending', () async {
      // Given a held camera future and a service with no stored material yet.
      final gate = Completer<CapturedPhoto?>();
      camera.gate = gate;
      final cameraService = CameraService(provider: camera);
      // When a capture holds the photo service and direct camera operations overlap.
      final first = service.capture(desiredConfigurationId: RecognitionSettings.androidStandard);
      await expectLater(service.capture(desiredConfigurationId: RecognitionSettings.androidStandard), throwsStateError);
      await expectLater(service.recover(desiredConfigurationId: RecognitionSettings.androidStandard), throwsStateError);
      await expectLater(service.compare(_material()), throwsStateError);
      final direct = cameraService.capture();
      await expectLater(cameraService.capture(), throwsStateError);
      await expectLater(cameraService.recover(), throwsStateError);
      gate.complete(null);
      // Then both pending operations finish and guards release after cancellation.
      expect(await first, isNull); expect(await direct, isNull);
      camera.gate = null;
      expect(await cameraService.recover(), isNull);
      expect(await service.capture(desiredConfigurationId: RecognitionSettings.androidStandard), isNotNull);
    });

    test('P5 invalid selection has zero camera import read or inference effects', () async {
      // Given valid services and invalid requested configurations.
      final calls = <Future<Object?> Function()>[
        () => service.capture(desiredConfigurationId: 'unknown'),
        () => service.recover(desiredConfigurationId: 'unknown'),
        () => service.recognize(_material(), desiredConfigurationId: 'unknown'),
        () => service.compare(_material(), configurationIds: []),
        () => service.compare(_material(), configurationIds: ['androidStandard', 'androidStandard']),
      ];
      // When each invalid selection is requested.
      for (final call in calls) {
        // Given this invalid photo-operation selection.
        // When it is requested through the public facade.
        // Then it fails before reaching acquisition or storage.
        await expectLater(call(), throwsArgumentError);
      }
      // Then validation precedes every camera and store boundary.
      expect(camera.captures, 0); expect(camera.recoveries, 0);
      expect(store.imports, 0); expect(store.reads, 0); expect(store.writes, 0);
      expect(standard.inputs, isEmpty);
    });

    test('P5 import read and report save errors retain originals and permit later saves', () async {
      // Given a real store with one injected failure at each durability boundary.
      final error = FileSystemException('controlled IO failure');
      for (final stage in ['import', 'read', 'report']) {
        // Given this injected durability boundary and the retained original inventory.
        store.failureStage = stage; store.failure = error;
        final importsBefore = store.saved.length;
        // When capture encounters this storage failure and then retries.
        await expectLater(service.capture(desiredConfigurationId: RecognitionSettings.androidStandard), throwsA(same(error)));
        final retained = store.saved.skip(importsBefore).toList();
        store.failureStage = null;
        final retry = await service.capture(desiredConfigurationId: RecognitionSettings.androidStandard);
        // Then the failure fabricated no report and every imported original remains intact.
        expect(retry, isNotNull);
        expect(retained.length, stage == 'import' ? 0 : 1);
        for (final original in retained) {
          // Given an original already imported before the failed boundary.
          // When its durable bytes are reopened.
          // Then failed report work did not rewrite the original.
          expect(await store.delegate.readMaterial(original), [1, 2, 3]);
        }
        expect(await service.reports.findById(retry!.id), isNotNull);
      }
    });

    test('P6 recognition exceptions persist source failure and retry gets a new identity', () async {
      // Given a standard provider that throws after the original has been saved.
      standard.error = StateError('native source failure');
      // When capture records failure and a later recognition retries that original.
      final failed = (await service.capture(desiredConfigurationId: RecognitionSettings.androidStandard))!;
      standard.error = null;
      final retried = await service.recognize(failed.material, desiredConfigurationId: RecognitionSettings.androidStandard);
      final restarted = await LocalRecognitionRepository(store: FileCaptureStore(directory.path)).findById(failed.id);
      // Then failure is durable, raw output is absent, and retry preserves the original identity.
      expect(failed.runs.single.status, RecognitionRunStatus.failed);
      expect(failed.runs.single.attempts.single.executed, isTrue);
      expect(failed.runs.single.attempts.single.result.text, isNull);
      expect(restarted!.runs.single.attempts.single.result.failures.single.message, contains('native source failure'));
      expect(restarted.runs.single.attempts.single.result.failures.single.code, 'recognitionFailed');
      expect(retried.id, isNot(failed.id)); expect(retried.material, failed.material);
      expect(retried.runs.single.status, RecognitionRunStatus.completed);
      expect(store.imports, 1);
      expect(await store.delegate.readMaterial(failed.material), [1, 2, 3]);
    });
  });
  group('photo readiness facade and optional native registration', () {
    late Directory directory;
    late FileCaptureStore store;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('photo-readiness-spec-');
      store = FileCaptureStore(directory.path);
    });
    tearDown(() async {
      debugDefaultTargetPlatformOverride = null;
      await directory.delete(recursive: true);
    });

    test('N8 configuration availability and preparation delegate exactly', () async {
      // Given a caller-owned recognition catalog and a downloadable provider.
      final provider = _Provider()..state = RecognitionProviderState.downloadable;
      final recognition = ImageRecognitionService(registry: RecognitionProviderRegistry(providers: [provider]));
      final photos = PhotoCaptureService(camera: CameraService(provider: _Camera()), recognition: recognition, store: store);
      // When the facade exposes configuration, probes and explicitly prepares the exact ID.
      final snapshots = await photos.availability();
      final prepared = await photos.prepareProvider('mlkitStandard');
      await expectLater(photos.prepareProvider('unknown'), throwsArgumentError);
      // Then catalog identity, forwarded readiness and preparation/reprobe counts are preserved.
      expect(photos.configurations, same(recognition.configurations));
      expect(() => photos.configurations.clear(), throwsUnsupportedError);
      expect(snapshots.first.providerId, 'mlkitStandard');
      expect(snapshots.first.state, RecognitionProviderState.downloadable);
      expect(snapshots.last.reason, 'providerNotRegistered');
      expect(prepared.providerId, 'mlkitStandard');
      expect(prepared.state, RecognitionProviderState.available);
      expect(provider.probes, 3); expect(provider.prepares, 1);
      expect(provider.inputs, isEmpty);
    });

    for (final held in ['probe', 'prepare']) {
      test('N8 held $held blocks capture recovery recognition comparison and readiness', () async {
        // Given a photo facade holding this exact forwarded recognition operation.
        final gate = Completer<void>();
        final provider = _Provider()..state = RecognitionProviderState.downloadable;
        if (held == 'probe') { provider.probeGate = gate; } else { provider.prepareGate = gate; }
        final camera = _Camera();
        final photos = PhotoCaptureService(camera: CameraService(provider: camera),
          recognition: ImageRecognitionService(registry: RecognitionProviderRegistry(providers: [provider])), store: store);
        final first = held == 'probe' ? photos.availability() : photos.prepareProvider('mlkitStandard');
        await (held == 'probe' ? provider.probeStarted.future : provider.prepareStarted.future);
        // When every photo operation tries to overlap the shared facade guard.
        await expectLater(photos.capture(desiredConfigurationId: 'androidStandard'), throwsStateError);
        await expectLater(photos.recover(desiredConfigurationId: 'androidStandard'), throwsStateError);
        await expectLater(photos.captureOriginal(), throwsStateError);
        await expectLater(photos.recoverOriginal(), throwsStateError);
        await expectLater(photos.recognize(_material(), desiredConfigurationId: 'androidStandard'), throwsStateError);
        await expectLater(photos.compare(_material()), throwsStateError);
        await expectLater(photos.availability(), throwsStateError);
        await expectLater(photos.prepareProvider('mlkitStandard'), throwsStateError);
        // Given the same observed held probe/preparation branch and no saved source reads.
        // When a public saved-original read competes with that existing owner.
        // Then it rejects before entering the borrowed store.
        await expectLater(photos.readOriginal(_material()), throwsStateError);
        // Given only the admitted readiness gate is released.
        gate.complete(); await first;
        provider.probeGate = null; provider.prepareGate = null;
        expect(provider.inputs, isEmpty);
        expect(provider.prepares, held == 'probe' ? 0 : 1);
        // The fixture becomes externally ready for the subsequent eligible capture.
        provider.state = RecognitionProviderState.available;
        final next = await photos.capture(desiredConfigurationId: 'androidStandard');
        // Then overlaps performed no camera work and released ownership admits a durable next capture.
        expect(camera.captures, 1); expect(camera.recoveries, 0);
        expect(provider.inputs.length, 1);
        expect(await photos.reports.findById(next!.id), isNotNull);
      });
    }

    for (final stage in ['camera', 'import', 'read', 'inference', 'report']) {
      test('N8 photo $stage ownership rejects probe and preparation until completion', () async {
        // Given capture held at this acquisition, storage or native inference boundary.
        final gate = Completer<void>();
        final cameraGate = Completer<CapturedPhoto?>();
        final camera = _Camera();
        final localStore = _Store(store);
        final provider = _Provider();
        Future<void> started;
        if (stage == 'camera') {
          camera.gate = cameraGate; started = camera.captureStarted.future;
        } else if (stage == 'inference') {
          provider.recognitionGate = gate; started = provider.recognitionStarted.future;
        } else {
          localStore.gateStage = stage; localStore.operationGate = gate; started = localStore.operationStarted.future;
        }
        final photos = PhotoCaptureService(camera: CameraService(provider: camera),
          recognition: ImageRecognitionService(registry: RecognitionProviderRegistry(providers: [provider])), store: localStore);
        final first = photos.capture(desiredConfigurationId: 'androidStandard');
        await started;
        // When readiness operations overlap the existing photo operation.
        await expectLater(photos.availability(), throwsStateError);
        await expectLater(photos.prepareProvider('mlkitStandard'), throwsStateError);
        await expectLater(photos.captureOriginal(), throwsStateError);
        await expectLater(photos.recoverOriginal(), throwsStateError);
        final readsBefore = localStore.reads;
        // Given this observed acquisition/import/read/inference/report owner.
        // When a public original read competes with its shared guard.
        // Then no additional store read starts.
        await expectLater(photos.readOriginal(_material()), throwsStateError);
        expect(localStore.reads, readsBefore);
        // Given only the admitted operation gate is released.
        if (stage == 'camera') { cameraGate.complete(_photo()); } else { gate.complete(); }
        // When original recognition settles and readiness is explicitly reprobed.
        final saved = await first;
        final ready = await photos.availability();
        // Then readiness was excluded from all photo boundaries and works after durable completion.
        expect(saved, isNotNull);
        expect(await photos.reports.findById(saved!.id), isNotNull);
        expect(ready.first.state, RecognitionProviderState.available);
        expect(provider.prepares, 0);
        expect(provider.inputs.length, 1);
        expect(await store.readMaterial(saved.material), [1, 2, 3]);
      });
    }

    test('N8 preparation failure forwards the real error and shared guard recovers', () async {
      // Given a downloadable provider with an actual preparation failure.
      final actual = StateError('native download failed');
      final provider = _Provider()
        ..state = RecognitionProviderState.downloadable
        ..prepareError = actual;
      final photos = PhotoCaptureService(camera: CameraService(provider: _Camera()),
        recognition: ImageRecognitionService(registry: RecognitionProviderRegistry(providers: [provider])), store: store);
      // When facade preparation fails and then an explicit retry completes.
      await expectLater(photos.prepareProvider('mlkitStandard'), throwsA(same(actual)));
      provider.prepareError = null;
      final next = await photos.prepareProvider('mlkitStandard');
      // Then the original error was visible and both recognition/photo guards recovered.
      expect(next.state, RecognitionProviderState.available);
      expect(provider.prepares, 2); expect(provider.inputs, isEmpty);
    });

    test('N8 default registry includes Nano and materializes one explicit replacement once', () async {
      // Given the unsupported default platform and a one-shot extension iterable.
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final defaults = await openDefaultPhotoCaptureService(store: store);
      final replacement = _Provider(enhanced: true);
      var iterations = 0;
      Iterable<ImageRecognitionProvider> additions() sync* {
        iterations++;
        if (iterations != 1) {
          throw StateError('extension iterable was consumed twice');
        }
        yield replacement;
      }
      // When defaults and an explicit single-Nano replacement are opened and probed.
      final defaultSnapshots = await defaults.availability();
      final overridden = await openDefaultPhotoCaptureService(store: store, additionalProviders: additions());
      final overrideSnapshots = await overridden.availability();
      // Then factory defaults are registered, replacement wins and no iterable is reread.
      expect(defaultSnapshots.map((item) => item.providerId), ['mlkitStandard', 'geminiNano']);
      expect(defaultSnapshots.last.reason, 'unsupportedPlatform');
      expect(overrideSnapshots.last.state, RecognitionProviderState.available);
      expect(replacement.probes, 1); expect(iterations, 1);
      expect(overrideSnapshots.length, 2);
    });

    for (final duplicates in ['twoNano', 'standardCollision']) {
      test('N8 $duplicates is a true duplicate rejected before store or provider work', () async {
        // Given either two explicit Nano replacements or a collision with default standard.
        final providers = duplicates == 'twoNano'
          ? [_Provider(enhanced: true), _Provider(enhanced: true)] : [_Provider()];
        // When the default factory admits this extension list.
        await expectLater(openDefaultPhotoCaptureService(store: store, additionalProviders: providers), throwsArgumentError);
        // Then the existing duplicate-ID rule still rejects with no native operations.
        for (final provider in providers) {
          // Given this provider from the rejected duplicate declaration.
          // When its operation counters are observed.
          // Then no preparation, probe or inference happened.
          expect(provider.probes, 0); expect(provider.prepares, 0); expect(provider.inputs, isEmpty);
        }
      });
    }

    test('N8 default standard route remains durable without the Nano companion', () async {
      // Given non-Web Android, real ML Kit channel replies and no Nano channel registration.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const textChannel = MethodChannel('google_mlkit_text_recognizer');
      const barcodeChannel = MethodChannel('google_mlkit_barcode_scanning');
      const nanoChannel = MethodChannel('org.textus.flutter.core/genai.v1');
      final nativeCalls = <String>[];
      messenger.setMockMethodCallHandler(nanoChannel, null);
      messenger.setMockMethodCallHandler(textChannel, (call) async {
        nativeCalls.add(call.method);
        return call.method == 'vision#startTextRecognizer' ? {'text': ' raw standard ', 'blocks': <Object?>[]} : null;
      });
      messenger.setMockMethodCallHandler(barcodeChannel, (call) async {
        nativeCalls.add(call.method);
        return call.method == 'vision#startBarcodeScanner' ? <Object?>[] : null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(textChannel, null);
        messenger.setMockMethodCallHandler(barcodeChannel, null);
      });
      final material = await store.saveMaterial(bytes: Uint8List.fromList([1, 2, 3]), mediaType: 'image/jpeg', capturedAt: _time);
      final photos = await openDefaultPhotoCaptureService(store: store);
      // When both default routes compare the same saved original.
      final report = await photos.compare(material);
      final reopened = await LocalRecognitionRepository(store: FileCaptureStore(directory.path)).findById(report.id);
      // Then standard completes, unavailable Nano falls back and durable source data remains intact.
      expect(report.runs.first.status, RecognitionRunStatus.completed);
      expect(report.runs.last.actualConfigurationId, 'androidStandard');
      expect(report.runs.last.desiredConfigurationId, 'pixelEnhanced');
      expect(report.runs.last.fallbackReason, contains('nativeBridgeUnavailable'));
      expect(report.runs.first.attempts.single, same(report.runs.last.attempts.first));
      expect(report.runs.last.attempts.last.executed, isFalse);
      expect(report.runs.first.attempts.single.result.text, ' raw standard ');
      expect(nativeCalls.where((method) => method == 'vision#startTextRecognizer').length, 1);
      expect(nativeCalls.where((method) => method == 'vision#startBarcodeScanner').length, 1);
      expect(RecognitionReportCodec.encode(reopened!), RecognitionReportCodec.encode(report));
      expect(await store.readMaterial(material), [1, 2, 3]);
    });
  });
}

final _time = DateTime.utc(2026, 10, 6, 1, 2, 3);
CapturedPhoto _photo({Uint8List? bytes, String type = 'image/jpeg', String name = 'original.jpg'}) => CapturedPhoto(
  bytes: bytes ?? Uint8List.fromList([1, 2, 3]), mediaType: type, capturedAt: _time.toLocal(), originalName: name,
);
CaptureMaterialReference _material({String type = 'image/jpeg'}) => CaptureMaterialReference(
  id: 'original', mediaType: type, byteLength: 3, capturedAt: _time,
);
final class _Camera implements CameraProvider {
  bool supported = true;
  CapturedPhoto? photo = _photo();
  CapturedPhoto? recoveredPhoto;
  Object? error;
  Completer<CapturedPhoto?>? gate;
  Completer<CapturedPhoto?>? recoveryGate;
  int captures = 0;
  int recoveries = 0;
  final captureStarted = Completer<void>();
  final recoveryStarted = Completer<void>();
  @override
  bool get isSupported => supported;
  @override
  Future<CapturedPhoto?> capturePhoto() async {
    captures++;
    if (!captureStarted.isCompleted) { captureStarted.complete(); }
    if (error != null) { throw error!; }
    return gate == null ? photo : gate!.future;
  }
  @override
  Future<CapturedPhoto?> recoverLostPhoto() async {
    recoveries++;
    if (!recoveryStarted.isCompleted) { recoveryStarted.complete(); }
    if (error != null) { throw error!; }
    if (recoveryGate != null) { return recoveryGate!.future; }
    final recovered = recoveredPhoto;
    recoveredPhoto = null;
    return recovered;
  }
}
final class _Provider implements ImageRecognitionProvider {
  _Provider({bool enhanced = false}) : descriptor = enhanced
    ? RecognitionProviderDescriptor(id: 'geminiNano', label: 'Controlled enhancement', capabilities: {
        RecognitionCapability.imageInterpretation, RecognitionCapability.candidateOrganization,
      })
    : RecognitionProviderDescriptor(id: 'mlkitStandard', label: 'Controlled standard', capabilities: {
        RecognitionCapability.ocr, RecognitionCapability.barcodes,
      });
  @override
  final RecognitionProviderDescriptor descriptor;
  Object? error;
  Object? prepareError;
  RecognitionProviderState state = RecognitionProviderState.available;
  Completer<void>? probeGate;
  Completer<void>? prepareGate;
  Completer<void>? recognitionGate;
  final probeStarted = Completer<void>();
  final prepareStarted = Completer<void>();
  final recognitionStarted = Completer<void>();
  int probes = 0;
  int prepares = 0;
  final inputs = <ImageRecognitionInput>[];
  @override
  Future<RecognitionProviderAvailability> availability() async {
    probes++;
    if (!probeStarted.isCompleted) { probeStarted.complete(); }
    if (probeGate != null) { await probeGate!.future; }
    return RecognitionProviderAvailability(
      providerId: descriptor.id, state: state, capabilities: descriptor.capabilities,
      reason: state == RecognitionProviderState.unavailable ? 'not supported here' : null,
    );
  }
  @override
  Future<void> prepare() async {
    prepares++;
    if (!prepareStarted.isCompleted) { prepareStarted.complete(); }
    if (prepareGate != null) { await prepareGate!.future; }
    if (prepareError != null) { throw prepareError!; }
    state = RecognitionProviderState.available;
  }
  @override
  Future<ImageRecognitionResult> recognize(ImageRecognitionInput input) async {
    inputs.add(input);
    if (!recognitionStarted.isCompleted) { recognitionStarted.complete(); }
    if (recognitionGate != null) { await recognitionGate!.future; }
    if (error != null) { throw error!; }
    return descriptor.id == 'mlkitStandard'
      ? ImageRecognitionResult(text: 'raw OCR', barcodeCompleted: true)
      : ImageRecognitionResult(interpretation: 'raw interpretation', candidateOrganizationCompleted: true);
  }
}
final class _Store implements LocalCaptureStore {
  _Store(this.delegate);
  final LocalCaptureStore delegate;
  int imports = 0;
  int reads = 0;
  int writes = 0;
  CaptureMaterialReference? lastReadReference;
  String? failureStage;
  Object? failure;
  String? gateStage;
  Completer<void>? operationGate;
  final operationStarted = Completer<void>();
  final saved = <CaptureMaterialReference>[];
  @override
  Future<CaptureMaterialReference> saveMaterial({required Uint8List bytes, required String mediaType,
    required DateTime capturedAt, String? originalName}) async {
    imports++;
    await _hold('import');
    if (failureStage == 'import') { throw failure!; }
    final reference = await delegate.saveMaterial(bytes: bytes, mediaType: mediaType,
      capturedAt: capturedAt, originalName: originalName);
    saved.add(reference);
    return reference;
  }
  @override
  Future<Uint8List> readMaterial(CaptureMaterialReference reference) async {
    reads++;
    lastReadReference = reference;
    await _hold('read');
    if (failureStage == 'read') { throw failure!; }
    return delegate.readMaterial(reference);
  }
  @override
  Future<void> saveDocument(String collection, String id, Map<String, Object?> document) async {
    writes++;
    await _hold('report');
    if (failureStage == 'report') { throw failure!; }
    await delegate.saveDocument(collection, id, document);
  }
  @override
  Future<Map<String, Object?>?> readDocument(String collection, String id) => delegate.readDocument(collection, id);
  @override
  Future<List<String>> listDocumentIds(String collection) => delegate.listDocumentIds(collection);
  Future<void> _hold(String stage) async {
    if (gateStage != stage) { return; }
    if (!operationStarted.isCompleted) { operationStarted.complete(); }
    await operationGate!.future;
  }
}
