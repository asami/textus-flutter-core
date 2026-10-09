import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('per-operation generic intent and shared raw stages', () {
    test('OC2 every executed stage shares exact context and successive calls stay independent', () async {
      // Given real service chains, mutable caller metadata and a static provenance provider.
      final standard = _Provider()..mutateReturnedBytes = true;
      final enhanced = _Provider.enhanced();
      final provider = _ProvenanceProvider(enhanced, {'instructions': 'static base'});
      final service = _service([standard, provider]);
      final extensions = <String, Object?>{'trace': <Object?>['exact']};
      final firstContext = RecognitionOperationContext(sourceRole: ' role one ',
        targetKinds: [' opaque/kind '], instructions: ' first operation ', extensions: extensions);
      final secondContext = RecognitionOperationContext(sourceRole: 'role two',
        targetKinds: ['other'], instructions: 'second operation');
      final original = _input();
      // When two contextual calls and then a legacy call execute both shared routes.
      (extensions['trace'] as List).clear();
      final reports = <RecognitionComparison>[];
      for (final context in [firstContext, secondContext, null]) {
        final report = await service.recognize(input: ImageRecognitionInput(
          material: original.material, bytes: original.bytes, operationContext: context),
          configurationIds: ['androidStandard', 'pixelEnhanced']);
        reports.add(report);
        // Then each real stage sees the same immutable intent and actual earlier raw output.
        expect(standard.inputs.last.operationContext, same(context));
        expect(enhanced.inputs.last.operationContext, same(context));
        expect(standard.inputs.last.bytes, [1, 2, 3]);
        expect(enhanced.inputs.last.bytes, [1, 2, 3]);
        expect(standard.inputs.last.previousResults, isEmpty);
        expect(enhanced.inputs.last.previousResults.single, same(standard.output));
        expect(report.runs.first.attempts.single, same(report.runs.last.attempts.first));
        expect(report.runs.last.attempts.last.inputAttemptIds, [report.runs.first.attempts.single.id]);
        expect(report.operationContext, context);
        expect(report.extensions.containsKey(RecognitionOperationContext.extensionKey), context != null);
        expect(report.extensions['providerProvenance'], {'geminiNano': {'instructions': 'static base'}});
      }
      // Given the three completed, independently requested operations.
      // When counters and each durable-ready raw report are observed.
      // Then no context leaks or preparation occurs and exact requested metadata remains.
      expect(standard.inputs.length, 3); expect(enhanced.inputs.length, 3);
      expect(standard.prepares + enhanced.prepares, 0);
      expect(reports.first.operationContext!.extensions, {'trace': ['exact']});
      expect(reports[1].operationContext, secondContext); expect(reports.last.operationContext, isNull);
    });

    for (final outcome in ['unavailable', 'failed']) {
      test('OC2 $outcome enhancement retains requested context with truthful fallback', () async {
        // Given this concrete enhancement failure and one requested opaque context.
        final standard = _Provider();
        final enhanced = _Provider.enhanced();
        if (outcome == 'unavailable') {
          enhanced.state = RecognitionProviderState.unavailable;
        } else {
          enhanced.recognitionError = StateError('actual enhanced failure');
        }
        final context = RecognitionOperationContext(sourceRole: 'role',
          targetKinds: ['unseen-kind'], instructions: 'requested only');
        final service = _service([standard, enhanced]);
        final original = _input();
        // When the enhanced route is requested on the exact saved original input.
        final report = await service.recognize(input: ImageRecognitionInput(
          material: original.material, bytes: original.bytes, operationContext: context),
          configurationIds: ['pixelEnhanced']);
        // Then request metadata survives without claiming enhancement execution or preparation.
        expect(report.operationContext, context);
        expect(report.extensions[RecognitionOperationContext.extensionKey], context.toJson());
        expect(standard.inputs.single.operationContext, same(context));
        expect(report.runs.single.actualConfigurationId, 'androidStandard');
        expect(report.runs.single.hasFallback, isTrue);
        expect(report.runs.single.attempts.last.executed, outcome == 'failed');
        expect(report.runs.single.attempts.last.result.failures.single.code,
          outcome == 'failed' ? 'recognitionFailed' : 'providerUnavailable');
        expect(enhanced.inputs.length, outcome == 'failed' ? 1 : 0);
        expect(standard.prepares + enhanced.prepares, 0);
        if (outcome == 'failed') {
          // Given the actually executed unsuccessful enhanced attempt.
          // When its received input is inspected.
          // Then it retains this request and the real earlier standard output.
          expect(enhanced.inputs.single.operationContext, same(context));
          expect(enhanced.inputs.single.previousResults.single, same(standard.output));
        }
      });
    }
  });
  group('catalog and readiness snapshots', () {
    test('C1 registries configurations and capabilities are immutable snapshots', () {
      // Given mutable registration, capability and chain inputs.
      final caps = [RecognitionCapability.ocr];
      final descriptor = RecognitionProviderDescriptor(id: 'custom', label: 'Custom', capabilities: caps);
      final requirement = RecognitionProviderRequirement(providerId: 'custom', capabilities: caps);
      final providers = [_Provider(id: 'custom', capabilities: caps)];
      final registry = RecognitionProviderRegistry(providers: providers);
      final chain = [requirement];
      final configuration = RecognitionConfiguration(id: 'customRoute', label: 'Custom route', providers: chain);
      final configurations = [configuration];
      final service = ImageRecognitionService(registry: registry, configurations: configurations);
      // When caller collections change after registration and catalog construction.
      caps.clear(); providers.clear(); chain.clear(); configurations.clear();
      // Then public snapshots retain their values and reject mutation.
      expect(registry.providers.length, 1); expect(registry.find('custom'), same(registry.providers.single));
      expect(registry.find('missing'), isNull); expect(registry.descriptors.single.id, 'custom');
      expect(descriptor.capabilities, {RecognitionCapability.ocr});
      expect(requirement.capabilities, {RecognitionCapability.ocr});
      expect(service.configurations.single.providers.single, same(requirement));
      expect(() => registry.providers.clear(), throwsUnsupportedError);
      expect(() => registry.descriptors.clear(), throwsUnsupportedError);
      expect(() => descriptor.capabilities.clear(), throwsUnsupportedError);
      expect(() => requirement.capabilities.clear(), throwsUnsupportedError);
      expect(() => configuration.providers.clear(), throwsUnsupportedError);
      expect(() => service.configurations.clear(), throwsUnsupportedError);
      expect(() => RecognitionConfigurations.all.clear(), throwsUnsupportedError);
      expect(RecognitionConfigurations.androidStandard.id, RecognitionSettings.androidStandard);
      expect(RecognitionConfigurations.pixelEnhanced.id, RecognitionSettings.pixelEnhanced);
      expect(RecognitionConfigurations.pixelEnhanced.fallbackConfigurationId, RecognitionSettings.androidStandard);
    });

    test('C1 unsafe duplicate missing cyclic and nonprefix declarations reject', () {
      // Given providers and valid prefix chains for malformed catalog variants.
      final provider = _Provider();
      final prefix = _config('short', ['a']);
      final full = _config('full', ['a', 'b'], fallback: 'short');
      final invalid = <void Function()>[
        () => RecognitionProviderRegistry(providers: [provider, provider]),
        () => RecognitionProviderDescriptor(id: '../bad', label: 'x', capabilities: [RecognitionCapability.ocr]),
        () => RecognitionProviderDescriptor(id: 'ok', label: ' ', capabilities: [RecognitionCapability.ocr]),
        () => RecognitionProviderDescriptor(id: 'ok', label: 'x', capabilities: []),
        () => RecognitionProviderRequirement(providerId: 'bad/id', capabilities: [RecognitionCapability.ocr]),
        () => RecognitionProviderRequirement(providerId: 'ok', capabilities: []),
        () => RecognitionProviderAvailability(providerId: '../x', state: RecognitionProviderState.available),
        () => RecognitionProviderAvailability(providerId: 'ok', state: RecognitionProviderState.unavailable),
        () => RecognitionProviderAvailability(providerId: 'ok', state: RecognitionProviderState.available, reason: ' '),
        () => RecognitionProviderAvailability(providerId: 'ok', state: RecognitionProviderState.available, modelName: ''),
        () => _config('../bad', ['a']),
        () => _config('empty', []),
        () => _config('duplicates', ['a', 'a']),
        () => _config('self', ['a'], fallback: 'self'),
        () => _service([provider], configurations: [prefix, prefix]),
        () => _service([provider], configurations: [full]),
        () => _service([provider], configurations: [_config('short', ['b']), full]),
        () => _service([provider], configurations: [prefix, _config('full', ['a'], fallback: 'short')]),
        () => _service([provider], configurations: [
          _config('short', ['a'], fallback: 'full'), full,
        ]),
        () => _service([provider], configurations: [
          RecognitionConfiguration(id: 'short', label: 'Short', providers: [
            RecognitionProviderRequirement(providerId: 'a', capabilities: [RecognitionCapability.barcodes]),
          ]), full,
        ]),
      ];
      // When each invalid public declaration is admitted.
      for (final construct in invalid) {
        // Given this malformed registry/configuration declaration.
        // When the public constructor admits it.
        // Then the catalog rejects the conflicting contract.
        expect(construct, throwsArgumentError);
      }
      expect(_service([provider], configurations: [prefix, full]).configurations.length, 2);
    });

    test('C1 invalid selection never probes and missing required capability is unavailable', () async {
      // Given a registered standard provider offering only OCR.
      final provider = _Provider(capabilities: [RecognitionCapability.ocr]);
      final service = _service([provider]);
      // When invalid selections and then a capability-incomplete route are requested.
      for (final ids in <List<String>>[[], ['unknown'], ['androidStandard', 'androidStandard']]) {
        // Given this invalid route selection and an unused provider.
        // When the recognition operation admits the selection.
        // Then selection rejects before native probing or inference.
        await expectLater(service.recognize(input: _input(), configurationIds: ids), throwsArgumentError);
      }
      // Then rejected selections had no calls, and platform support does not supply barcodes.
      expect(provider.probes, 0); expect(provider.inputs, isEmpty); expect(provider.prepares, 0);
      final report = await service.recognize(input: _input(), configurationIds: ['androidStandard']);
      expect(report.runs.single.actualConfigurationId, isNull);
      expect(report.runs.single.attempts.single.availability.reason, 'missingCapabilities');
      expect(provider.inputs, isEmpty);
    });

    test('C2 readiness probes first configured providers and extras once without inference', () async {
      // Given all four historical states plus a configured missing enhancement.
      final standard = _Provider(state: RecognitionProviderState.downloadable);
      final available = _Provider(id: 'extraAvailable');
      final preparing = _Provider(id: 'extraPreparing', state: RecognitionProviderState.preparing);
      final unavailable = _Provider(id: 'extraUnavailable', state: RecognitionProviderState.unavailable);
      final service = _service([standard, available, preparing, unavailable]);
      // When availability is explicitly requested.
      final snapshots = await service.availability();
      // Then snapshots are immutable, ordered and truthful without downloads or inference.
      expect(snapshots.map((item) => item.providerId),
        ['mlkitStandard', 'geminiNano', 'extraAvailable', 'extraPreparing', 'extraUnavailable']);
      expect(snapshots.map((item) => item.state), [
        RecognitionProviderState.downloadable, RecognitionProviderState.unavailable,
        RecognitionProviderState.available, RecognitionProviderState.preparing, RecognitionProviderState.unavailable,
      ]);
      expect(snapshots[1].reason, 'providerNotRegistered');
      expect(snapshots[1].capabilities, isEmpty); expect(snapshots[1].modelName, isNull);
      expect(snapshots.last.reason, 'controlled unavailable');
      expect(() => snapshots.clear(), throwsUnsupportedError);
      expect(() => snapshots.first.capabilities.clear(), throwsUnsupportedError);
      for (final provider in [standard, available, preparing, unavailable]) {
        // Given this registered provider from the completed readiness-only operation.
        // When its call counters are observed.
        // Then it was probed once and never prepared or recognized.
        expect(provider.probes, 1); expect(provider.prepares, 0); expect(provider.inputs, isEmpty);
      }
    });

    test('C2 failed and conflicting probes expose reasons and retain descriptor snapshots', () async {
      // Given native probe errors, conflicting identity, capabilities and a changed descriptor.
      final failed = _Provider(id: 'failed')..probeError = StateError('native model probe failed');
      final identity = _Provider(id: 'identity')..snapshotId = 'other';
      final capability = _Provider(id: 'capability', capabilities: [RecognitionCapability.ocr])
        ..snapshotCapabilities = [RecognitionCapability.imageInterpretation];
      final changed = _Provider(id: 'changed');
      final service = _service([failed, identity, capability, changed]);
      changed.descriptor = RecognitionProviderDescriptor(id: 'changed', label: 'New label', capabilities: _standardCaps);
      // When readiness is probed against the frozen registration descriptors.
      final snapshots = await service.availability();
      // Then every conflicting probe is unavailable with its actual descriptive reason.
      expect(snapshots.firstWhere((item) => item.providerId == 'failed').reason, contains('native model probe failed'));
      for (final id in ['identity', 'capability', 'changed']) {
        // Given this conflicting registration/probe branch.
        // When its historical snapshot is selected.
        // Then the conflict remains unavailable with a descriptive reason.
        final snapshot = snapshots.firstWhere((item) => item.providerId == id);
        expect(snapshot.state, RecognitionProviderState.unavailable);
        expect(snapshot.reason, contains(id));
      }
      expect(service.registry.descriptors.last.label, 'Controlled changed');
      for (final provider in [failed, identity, capability, changed]) {
        // Given this provider from the failed/conflicting probe matrix.
        // When its downstream operation counters are observed.
        // Then probing did not prepare or infer.
        expect(provider.prepares, 0); expect(provider.inputs, isEmpty);
      }
    });

    test('C3 preparation only downloads explicit downloadable models and reprobes', () async {
      // Given available, preparing, unavailable and downloadable providers.
      final available = _Provider(id: 'available');
      final preparing = _Provider(id: 'preparing', state: RecognitionProviderState.preparing);
      final unavailable = _Provider(id: 'unavailable', state: RecognitionProviderState.unavailable);
      final downloadable = _Provider(id: 'downloadable', state: RecognitionProviderState.downloadable);
      final service = _service([available, preparing, unavailable, downloadable]);
      // When explicit preparation is requested for each state and an unknown ID.
      final ready = await service.prepareProvider('available');
      final busy = await service.prepareProvider('preparing');
      await expectLater(service.prepareProvider('unavailable'), throwsUnsupportedError);
      await expectLater(service.prepareProvider('unknown'), throwsArgumentError);
      final downloaded = await service.prepareProvider('downloadable');
      // Then only the downloadable provider prepares and readiness comes from a second probe.
      expect(ready.state, RecognitionProviderState.available);
      expect(busy.state, RecognitionProviderState.preparing);
      expect(downloaded.state, RecognitionProviderState.available);
      expect(downloadable.probes, 2); expect(downloadable.prepares, 1);
      for (final provider in [available, preparing, unavailable]) {
        // Given this non-downloadable preparation branch.
        // When its preparation counter is observed.
        // Then no download was requested.
        expect(provider.prepares, 0);
      }
      expect(downloadable.inputs, isEmpty);
    });

    test('C3 overlap and preparation exceptions release the shared service guard', () async {
      // Given a held explicit preparation that will fail with a native error.
      final provider = _Provider(state: RecognitionProviderState.downloadable);
      final gate = Completer<void>(); provider.prepareGate = gate;
      final error = StateError('download failed');
      final service = _service([provider]);
      // When the preparation is pending and all public operations try to overlap.
      final first = service.prepareProvider('mlkitStandard');
      final failure = expectLater(first, throwsA(same(error)));
      await provider.prepareStarted.future;
      await expectLater(service.availability(), throwsStateError);
      await expectLater(service.prepareProvider('mlkitStandard'), throwsStateError);
      await expectLater(service.recognize(input: _input(), configurationIds: ['androidStandard']), throwsStateError);
      gate.completeError(error); await failure;
      provider.prepareGate = null;
      // Then the original exception propagates and an explicit next preparation succeeds.
      expect((await service.prepareProvider('mlkitStandard')).state, RecognitionProviderState.available);
      expect(provider.prepares, 2);
      expect((await service.availability()).first.state, RecognitionProviderState.available);
    });
  });

  group('same original comparison and fallback', () {
    test('Q1 capability-incomplete occurrences cannot reuse or poison executed work', () async {
      for (final ids in <List<String>>[
        ['ocrOnly', 'ocrAndBarcodes'], ['ocrAndBarcodes', 'ocrOnly'],
      ]) {
        for (final descriptorHasBarcodes in [false, true]) {
          // Given two requirements for one provider with OCR-only offered readiness.
          final provider = _Provider(id: 'custom', capabilities:
            descriptorHasBarcodes ? _standardCaps : [RecognitionCapability.ocr])
            ..snapshotCapabilities = [RecognitionCapability.ocr]
            ..snapshotModelName = 'controlled OCR model'
            ..output = ImageRecognitionResult(text: ' raw OCR ');
          final source = _input();
          final service = _service([provider], configurations: _capabilityRoutes());
          // When both routes compare the original in either requested row order.
          final report = await service.recognize(input: source, configurationIds: ids);
          // Then the supported occurrence executes once and the unsupported one stays distinct.
          final weaker = report.runs.firstWhere((row) => row.desiredConfigurationId == 'ocrOnly');
          final stronger = report.runs.firstWhere((row) => row.desiredConfigurationId == 'ocrAndBarcodes');
          final executed = weaker.attempts.single;
          final skipped = stronger.attempts.single;
          expect(report.runs.map((row) => row.desiredConfigurationId), ids);
          expect(provider.probes, 1); expect(provider.inputs.length, 1); expect(provider.prepares, 0);
          expect(weaker.actualConfigurationId, 'ocrOnly'); expect(weaker.status, RecognitionRunStatus.completed);
          expect(executed.executed, isTrue); expect(executed.result, same(provider.output));
          expect(executed.result.barcodeCompleted, isFalse);
          expect(stronger.actualConfigurationId, isNull); expect(stronger.actualProviderIds, isEmpty);
          expect(stronger.status, RecognitionRunStatus.unavailable); expect(stronger.hasFallback, isFalse);
          expect(stronger.fallbackReason, isNull);
          expect(skipped, isNot(same(executed))); expect(skipped.id, isNot(executed.id));
          expect(skipped.executed, isFalse); expect(skipped.elapsed, Duration.zero);
          expect(skipped.availability.state, RecognitionProviderState.unavailable);
          expect(skipped.availability.reason, 'missingCapabilities');
          expect(skipped.availability.capabilities, {RecognitionCapability.ocr});
          expect(skipped.availability.modelName, 'controlled OCR model');
          expect(skipped.result.failures.single.code, 'providerUnavailable');
          expect(skipped.result.failures.single.message, 'missingCapabilities');
          expect(skipped.result.hasSuccessfulOutput, isFalse); expect(skipped.inputAttemptIds, isEmpty);
          expect(report.material, same(source.material));
          expect(executed.materialId, source.material.id); expect(skipped.materialId, source.material.id);
          expect(provider.inputs.single.material, same(source.material));
          expect(provider.inputs.single.bytes, [1, 2, 3]); expect(source.bytes, [1, 2, 3]);
          expect(provider.inputs.single.previousResults, isEmpty);
        }
      }
    });

    test('Q2 eligible capability requirements share identical successful work', () async {
      for (final ids in <List<String>>[
        ['ocrOnly', 'ocrAndBarcodes'], ['ocrAndBarcodes', 'ocrOnly'],
      ]) {
        // Given one ready provider completing OCR and barcodes for both requirements.
        final provider = _Provider(id: 'custom');
        final source = _input();
        final service = _service([provider], configurations: _capabilityRoutes());
        // When both eligible routes compare the original in either row order.
        final report = await service.recognize(input: source, configurationIds: ids);
        // Then capability differences share the same invocation, result and recorded duration.
        final first = report.runs.first.attempts.single;
        final second = report.runs.last.attempts.single;
        expect(provider.probes, 1); expect(provider.inputs.length, 1); expect(provider.prepares, 0);
        expect(first, same(second)); expect(first.id, second.id); expect(first.executed, isTrue);
        expect(first.result, same(second.result)); expect(first.result, same(provider.output));
        expect(first.result.text, ' raw OCR '); expect(first.result.barcodeCompleted, isTrue);
        expect(first.elapsed, second.elapsed); expect(first.elapsed.isNegative, isFalse);
        expect(report.runs.map((row) => row.desiredConfigurationId), ids);
        for (final row in report.runs) {
          // Given this compatible selected row over shared successful work.
          // When its actual route and timing are observed.
          // Then it retains completion and the identical performed duration.
          expect(row.actualConfigurationId, row.desiredConfigurationId);
          expect(row.actualProviderIds, ['custom']); expect(row.status, RecognitionRunStatus.completed);
          expect(row.hasFallback, isFalse); expect(row.fallbackReason, isNull); expect(row.elapsed, first.elapsed);
        }
        expect(report.material, same(source.material)); expect(first.materialId, source.material.id);
        expect(provider.inputs.single.material, same(source.material));
        expect(provider.inputs.single.bytes, [1, 2, 3]); expect(source.bytes, [1, 2, 3]);
        expect(first.inputAttemptIds, isEmpty); expect(provider.inputs.single.previousResults, isEmpty);
      }
    });

    test('Q3 eligible capability requirements share identical executed failure', () async {
      for (final ids in <List<String>>[
        ['ocrOnly', 'ocrAndBarcodes'], ['ocrAndBarcodes', 'ocrOnly'],
      ]) {
        // Given one ready provider whose inference throws a descriptive native exception.
        final provider = _Provider(id: 'custom')..recognitionError = StateError('controlled shared inference failed');
        final source = _input();
        final service = _service([provider], configurations: _capabilityRoutes());
        // When both eligible routes compare the original in either row order.
        final report = await service.recognize(input: source, configurationIds: ids);
        // Then performed failed work is shared with its real failure and duration.
        final first = report.runs.first.attempts.single;
        final second = report.runs.last.attempts.single;
        expect(provider.probes, 1); expect(provider.inputs.length, 1); expect(provider.prepares, 0);
        expect(first, same(second)); expect(first.id, second.id); expect(first.executed, isTrue);
        expect(first.result, same(second.result)); expect(first.result.hasSuccessfulOutput, isFalse);
        expect(first.result.failures.single.code, 'recognitionFailed');
        expect(first.result.failures.single.message, contains('controlled shared inference failed'));
        expect(first.result.failures.single, same(second.result.failures.single));
        expect(first.availability.state, RecognitionProviderState.available);
        expect(first.elapsed, second.elapsed); expect(first.elapsed.isNegative, isFalse);
        expect(report.runs.map((row) => row.desiredConfigurationId), ids);
        for (final row in report.runs) {
          // Given this compatible selected row over shared failed work.
          // When its actual route and timing are observed.
          // Then it retains failed recognition on its executed route.
          expect(row.actualConfigurationId, row.desiredConfigurationId);
          expect(row.actualProviderIds, ['custom']); expect(row.status, RecognitionRunStatus.failed);
          expect(row.hasFallback, isFalse); expect(row.fallbackReason, isNull); expect(row.elapsed, first.elapsed);
        }
        expect(report.material, same(source.material)); expect(first.materialId, source.material.id);
        expect(provider.inputs.single.material, same(source.material));
        expect(provider.inputs.single.bytes, [1, 2, 3]); expect(source.bytes, [1, 2, 3]);
        expect(first.inputAttemptIds, isEmpty); expect(provider.inputs.single.previousResults, isEmpty);
      }
    });

    test('Q4 unavailable occurrences retain independent nonexecuted records', () async {
      for (final ids in <List<String>>[
        ['ocrOnly', 'ocrAndBarcodes'], ['ocrAndBarcodes', 'ocrOnly'],
      ]) {
        // Given one unavailable provider with its descriptive readiness reason.
        final provider = _Provider(id: 'custom', state: RecognitionProviderState.unavailable);
        final source = _input();
        final service = _service([provider], configurations: _capabilityRoutes());
        // When both routes compare the original in either row order.
        final report = await service.recognize(input: source, configurationIds: ids);
        // Then one probe produces separate skipped identities without preparation or inference.
        final first = report.runs.first.attempts.single;
        final second = report.runs.last.attempts.single;
        expect(provider.probes, 1); expect(provider.inputs, isEmpty); expect(provider.prepares, 0);
        expect(first, isNot(same(second))); expect(first.id, isNot(second.id));
        expect(report.runs.map((row) => row.desiredConfigurationId), ids);
        expect(report.material, same(source.material)); expect(source.bytes, [1, 2, 3]);
        for (final row in report.runs) {
          // Given this independently skipped unavailable row.
          // When its attempt and route are observed.
          // Then it claims no performed work or actual configuration.
          final attempt = row.attempts.single;
          expect(row.actualConfigurationId, isNull); expect(row.actualProviderIds, isEmpty);
          expect(row.status, RecognitionRunStatus.unavailable); expect(row.elapsed, Duration.zero);
          expect(row.hasFallback, isFalse); expect(row.fallbackReason, isNull);
          expect(attempt.executed, isFalse); expect(attempt.elapsed, Duration.zero);
          expect(attempt.materialId, source.material.id); expect(attempt.inputAttemptIds, isEmpty);
          expect(attempt.availability.state, RecognitionProviderState.unavailable);
          expect(attempt.availability.reason, 'controlled unavailable');
          expect(attempt.availability.capabilities, _standardCaps.toSet());
          expect(attempt.result.hasSuccessfulOutput, isFalse);
          expect(attempt.result.failures.single.code, 'providerUnavailable');
          expect(attempt.result.failures.single.message, 'controlled unavailable');
        }
      }
    });

    test('C4 common standard attempt is shared in either row order with defensive input', () async {
      // Given controlled standard and enhancement providers and one original.
      for (final ids in <List<String>>[
        ['androidStandard', 'pixelEnhanced'], ['pixelEnhanced', 'androidStandard'],
      ]) {
        // Given this requested row order over controlled standard and enhancement providers.
        final standard = _Provider()..mutateReturnedBytes = true;
        final enhanced = _Provider.enhanced();
        final source = _input();
        final service = _service([standard, enhanced]);
        // When both rows recognize the saved original in this requested order.
        final report = await service.recognize(input: source, configurationIds: ids);
        final first = report.runs[0].attempts.first;
        final second = report.runs[1].attempts.first;
        final enhancedRun = report.runs.firstWhere((row) => row.desiredConfigurationId == 'pixelEnhanced');
        // Then standard ran once, shared identity and raw provenance survive, and no bytes were changed.
        expect(report.runs.map((row) => row.desiredConfigurationId), ids);
        expect(first, same(second)); expect(standard.inputs.length, 1);
        expect(enhanced.inputs.length, 1); expect(enhanced.inputs.single.bytes, [1, 2, 3]);
        expect(source.bytes, [1, 2, 3]); expect(standard.inputs.single.bytes, [1, 2, 3]);
        expect(enhanced.inputs.single.previousResults.single, same(first.result));
        expect(enhanced.inputs.single.previousResults.single.text, ' raw OCR ');
        expect(enhancedRun.actualConfigurationId, 'pixelEnhanced');
        expect(enhancedRun.actualProviderIds, ['mlkitStandard', 'geminiNano']);
        expect(enhancedRun.attempts.last.inputAttemptIds, [first.id]);
        expect(enhancedRun.elapsed, first.elapsed + enhancedRun.attempts.last.elapsed);
        expect(report.runs.firstWhere((row) => row.desiredConfigurationId == 'androidStandard').elapsed, first.elapsed);
        expect(enhancedRun.status, RecognitionRunStatus.completed);
        expect(first.elapsed.isNegative, isFalse); expect(enhancedRun.elapsed.isNegative, isFalse);
        expect(first.startedAt.isUtc, isTrue); expect(report.createdAt.isUtc, isTrue);
        final unique = {report.id, first.id, enhancedRun.attempts.last.id};
        expect(unique.length, 3);
        expect(unique.every((id) => RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(id)), isTrue);
        expect(standard.probes, 1); expect(enhanced.probes, 1);
      }
    });

    test('C5 missing and not ready enhancement explicitly fall back without changing desired settings', () async {
      // Given durably acknowledged enhanced intent and every nonready enhancement state.
      final storage = _SettingsMemory();
      final settings = SettingsLifecycleController(registry: RecognitionSettings.registry(), storage: storage,
        resetDefinitions: RecognitionSettings.definitions);
      addTearDown(settings.dispose);
      await settings.load(); settings.setValue(RecognitionSettings.configuration.id, RecognitionSettings.pixelEnhanced);
      await settings.retrySave();
      final savedPreference = storage.record;
      for (final state in <RecognitionProviderState?>[
        null, RecognitionProviderState.unavailable, RecognitionProviderState.downloadable, RecognitionProviderState.preparing,
      ]) {
        // Given this nonready enhancement state and the durably retained desired preference.
        final standard = _Provider();
        final enhanced = state == null ? null : (_Provider.enhanced()..state = state);
        // When the enhanced desired configuration is requested with this readiness snapshot.
        final report = await _service([standard, ?enhanced]).recognize(
          input: _input(), configurationIds: [settings.snapshot.value(RecognitionSettings.configuration)],
        );
        final run = report.runs.single;
        // Then actual standard fallback has a reason and retains its nonexecuted enhancement trace.
        expect(run.desiredConfigurationId, 'pixelEnhanced'); expect(run.actualConfigurationId, 'androidStandard');
        expect(run.hasFallback, isTrue); expect(run.fallbackReason, isNotEmpty);
        expect(run.actualProviderIds, ['mlkitStandard']); expect(run.status, RecognitionRunStatus.completed);
        expect(run.attempts.last.executed, isFalse); expect(run.attempts.last.elapsed, Duration.zero);
        expect(run.attempts.last.result.failures.single.stage, ImageRecognitionStage.availability);
        expect(enhanced?.inputs ?? [], isEmpty); expect(enhanced?.prepares ?? 0, 0);
        expect(settings.snapshot.value(RecognitionSettings.configuration), 'pixelEnhanced');
        expect(storage.record, savedPreference);
      }
    });

    test('C5 failed and empty enhancement keep overhead and truthful standard fallback', () async {
      // Given an enhanced provider with an exception or no completed stage.
      for (final empty in [false, true]) {
        // Given this explicit failed or empty enhancement branch.
        final enhanced = _Provider.enhanced();
        if (empty) { enhanced.output = ImageRecognitionResult(); }
        else { enhanced.recognitionError = StateError('native enhancement failed'); }
        // When the entire desired enhanced route executes.
        final report = await _service([_Provider(), enhanced]).recognize(input: _input(), configurationIds: ['pixelEnhanced']);
        final run = report.runs.single;
        // Then the failed executed stage stays timed in the trace while standard remains completed.
        expect(run.actualConfigurationId, 'androidStandard'); expect(run.status, RecognitionRunStatus.completed);
        expect(run.attempts.last.executed, isTrue); expect(run.attempts.last.result.hasSuccessfulOutput, isFalse);
        expect(run.attempts.last.result.failures.single.code, empty ? 'emptyResult' : 'recognitionFailed');
        expect(run.fallbackReason, contains(empty ? 'emptyResult' : 'native enhancement failed'));
        expect(run.elapsed, run.attempts.first.elapsed + run.attempts.last.elapsed);
        expect(run.attempts.last.elapsed.isNegative, isFalse);
      }
    });

    test('C6 unavailable standard skips enhancement and has no false actual fallback', () async {
      // Given an unavailable first provider and a ready enhancement.
      final standard = _Provider(state: RecognitionProviderState.unavailable);
      final enhanced = _Provider.enhanced();
      // When an enhanced route is requested.
      final report = await _service([standard, enhanced]).recognize(input: _input(), configurationIds: ['pixelEnhanced']);
      final run = report.runs.single;
      // Then no provider executed and no standard route was falsely reported as used.
      expect(run.actualConfigurationId, isNull); expect(run.actualProviderIds, isEmpty);
      expect(run.fallbackReason, isNull); expect(run.hasFallback, isFalse);
      expect(run.status, RecognitionRunStatus.unavailable); expect(run.elapsed, Duration.zero);
      expect(standard.inputs, isEmpty); expect(enhanced.inputs, isEmpty);
      expect(run.attempts.last.availability.state, RecognitionProviderState.available);
      expect(run.attempts.last.result.failures.single.code, 'dependencyUnavailable');
    });

    test('C6 failed standard is an executed route and partial standard still reaches enhancement', () async {
      // Given failed and partial standard raw outputs followed by a successful enhancement.
      final textFailure = ImageRecognitionFailure(stage: ImageRecognitionStage.text, code: 'textRecognitionFailed', message: 'native OCR failed');
      final barcodeFailure = ImageRecognitionFailure(stage: ImageRecognitionStage.barcode, code: 'barcodeRecognitionFailed', message: 'native barcode failed');
      final standard = _Provider()..output = ImageRecognitionResult(failures: [textFailure, barcodeFailure]);
      final enhanced = _Provider.enhanced();
      final service = _service([standard, enhanced]);
      // When standard fails both stages, then a partial standard result enters an enhanced route.
      final failed = await service.recognize(input: _input(), configurationIds: ['androidStandard']);
      standard.output = ImageRecognitionResult(text: ' raw OCR ', failures: [barcodeFailure]);
      final partial = await service.recognize(input: _input(), configurationIds: ['pixelEnhanced']);
      // Then route choice and accuracy are distinct and raw earlier failure is never overwritten.
      expect(failed.runs.single.actualConfigurationId, 'androidStandard');
      expect(failed.runs.single.status, RecognitionRunStatus.failed);
      expect(partial.runs.single.actualConfigurationId, 'pixelEnhanced');
      expect(partial.runs.single.status, RecognitionRunStatus.partial);
      expect(enhanced.inputs.single.previousResults.single.failures, [barcodeFailure]);
      expect(partial.runs.single.attempts.first.result.interpretation, isNull);
      expect(partial.runs.single.attempts.last.result.text, isNull);
      expect(partial.runs.single.attempts.last.result.interpretation, ' raw interpretation ');
      expect(partial.runs.single.attempts.first.result.failures, [barcodeFailure]);
    });

    test('C6 incomplete and unsuccessful generated stages remain visible', () async {
      // Given a provider that completes interpretation only, then records an explicit failed generated stage.
      final enhanced = _Provider.enhanced()..output = ImageRecognitionResult(interpretation: 'suggestion');
      final service = _service([_Provider(), enhanced]);
      // When partial and unsuccessful enhancement outputs are produced.
      final partial = await service.recognize(input: _input(), configurationIds: ['pixelEnhanced']);
      enhanced.output = ImageRecognitionResult(failures: [ImageRecognitionFailure(
        stage: ImageRecognitionStage.interpretation, code: 'generationFailed', message: 'native generation failed',
      )]);
      final failed = await service.recognize(input: _input(), configurationIds: ['pixelEnhanced']);
      // Then successful partial output selects enhancement while no output selects explicit fallback.
      expect(partial.runs.single.actualConfigurationId, 'pixelEnhanced');
      expect(partial.runs.single.status, RecognitionRunStatus.partial);
      expect(partial.runs.single.attempts.last.result.candidateOrganizationCompleted, isFalse);
      expect(failed.runs.single.actualConfigurationId, 'androidStandard');
      expect(failed.runs.single.attempts.last.result.failures.single.code, 'generationFailed');
    });

    test('C7 custom chains share prefixes and never reuse incompatible prior inputs', () async {
      // Given two different prefixes feeding one common tail and a fallback of the first prefix.
      final a = _Provider(id: 'a', capabilities: [RecognitionCapability.ocr]);
      final b = _Provider(id: 'b', capabilities: [RecognitionCapability.ocr]);
      final tail = _Provider(id: 'tail', capabilities: [RecognitionCapability.ocr]);
      final service = _service([a, b, tail], configurations: [
        _config('prefix', ['a']), _config('extended', ['a', 'tail'], fallback: 'prefix'),
        _config('other', ['b', 'tail']),
      ]);
      // When extended, prefix and independently fed tail routes compare the same original.
      final report = await service.recognize(input: _input(), configurationIds: ['extended', 'prefix', 'other']);
      // Then only identical prefixes share work and the tail receives distinct source attempt IDs.
      expect(a.inputs.length, 1); expect(b.inputs.length, 1); expect(tail.inputs.length, 2);
      expect(report.runs[0].attempts.first, same(report.runs[1].attempts.first));
      expect(report.runs[0].attempts.last.id, isNot(report.runs[2].attempts.last.id));
      expect(report.runs[0].attempts.last.inputAttemptIds, [report.runs[0].attempts.first.id]);
      expect(report.runs[2].attempts.last.inputAttemptIds, [report.runs[2].attempts.first.id]);
      expect(tail.inputs[0].previousResults.single, same(report.runs[0].attempts.first.result));
      expect(tail.inputs[1].previousResults.single, same(report.runs[2].attempts.first.result));
    });

    test('C7 invalid colliding generators and provider errors leave the guard reusable', () async {
      // Given a controllable ID generator and a provider that later throws.
      var mode = 'invalid'; var sequence = 0;
      String generate() => switch (mode) {
        'invalid' => '../invalid', 'collision' => 'same', _ => 'new-${sequence++}',
      };
      final provider = _Provider();
      final service = ImageRecognitionService(registry: RecognitionProviderRegistry(providers: [provider]), idGenerator: generate);
      // When invalid and colliding IDs fail, then a valid provider exception is persisted.
      await expectLater(service.recognize(input: _input(), configurationIds: ['androidStandard']), throwsStateError);
      mode = 'collision';
      await expectLater(service.recognize(input: _input(), configurationIds: ['androidStandard']), throwsStateError);
      mode = 'valid'; provider.recognitionError = StateError('controlled recognition exception');
      final failed = await service.recognize(input: _input(), configurationIds: ['androidStandard']);
      provider.recognitionError = null;
      final next = await service.recognize(input: _input(), configurationIds: ['androidStandard']);
      // Then errors remain visible and every next operation can acquire the service guard.
      expect(failed.runs.single.status, RecognitionRunStatus.failed);
      expect(failed.runs.single.attempts.single.result.failures.single.message, contains('controlled recognition exception'));
      expect(next.runs.single.status, RecognitionRunStatus.completed);
      expect(next.id, isNot(failed.id));
    });
  });
  group('generic provider provenance and durable native comparison', () {
    late Directory directory;
    late FileCaptureStore store;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('recognition-provenance-spec-');
      store = FileCaptureStore(directory.path);
    });
    tearDown(() async {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('org.textus.flutter.core/genai.v1'), null);
      await directory.delete(recursive: true);
    });

    test('N7 optional metadata is deeply frozen before probes and persists across restart with shared work', () async {
      for (final ids in <List<String>>[
        ['androidStandard', 'pixelEnhanced'], ['pixelEnhanced', 'androidStandard'],
      ]) {
        // Given mutable generic configuration provenance and participating old-interface providers.
        final nested = <String, Object?>{'languages': <Object?>[' exact language '], 'options': {'count': 2}};
        final metadata = <String, Object?>{'configuration': nested, 'unknownSetting': null};
        final standard = _Provider();
        final optional = _ProvenanceProvider(standard, metadata, onProbe: () {
          (nested['languages'] as List).clear();
          (nested['options'] as Map)['count'] = 99;
          metadata['later'] = true;
        });
        final enhanced = _Provider.enhanced();
        final material = await store.saveMaterial(bytes: Uint8List.fromList([1, 2, 3]), mediaType: 'image/jpeg', capturedAt: DateTime.utc(2026, 10, 6));
        // When both selected routes execute and their real report is saved and reopened on restart.
        final report = await _service([optional, enhanced]).recognize(
          input: ImageRecognitionInput(material: material, bytes: await store.readMaterial(material)), configurationIds: ids,
        );
        await LocalRecognitionRepository(store: store).save(report);
        final restarted = await LocalRecognitionRepository(store: FileCaptureStore(directory.path)).findById(report.id);
        final provenance = report.extensions['providerProvenance'] as Map;
        final frozen = (provenance['mlkitStandard'] as Map)['configuration'] as Map;
        // Then original configuration is durable, immutable and independent of the native probe's mutation.
        expect(report.extensions, {'providerProvenance': {'mlkitStandard': {
          'configuration': {'languages': [' exact language '], 'options': {'count': 2}}, 'unknownSetting': null,
        }}});
        expect(() => provenance.clear(), throwsUnsupportedError);
        expect(() => frozen.clear(), throwsUnsupportedError);
        expect(() => (frozen['languages'] as List).clear(), throwsUnsupportedError);
        expect(() => (frozen['options'] as Map)['count'] = 3, throwsUnsupportedError);
        expect(RecognitionReportCodec.encode(restarted!), RecognitionReportCodec.encode(report));
        expect(restarted.extensions, report.extensions);
        expect(standard.probes, 1); expect(standard.inputs.length, 1);
        expect(enhanced.inputs.length, 1);
        expect(report.runs.first.attempts.first, same(report.runs.last.attempts.first));
        expect(restarted.runs.first.attempts.first, same(restarted.runs.last.attempts.first));
        expect(restarted.runs.every((run) => run.status == RecognitionRunStatus.completed), isTrue);
        expect(restarted.runs.first.attempts.first.result.text, ' raw OCR ');
        expect(await store.readMaterial(material), [1, 2, 3]);
      }
    });

    test('N7 old provider interfaces preserve empty extensions and ordinary durable cache behavior', () async {
      // Given only existing providers without the optional provenance interface.
      final standard = _Provider();
      final enhanced = _Provider.enhanced();
      final material = await store.saveMaterial(bytes: Uint8List.fromList([1, 2, 3]), mediaType: 'image/jpeg', capturedAt: DateTime.utc(2026, 10, 6));
      // When both routes recognize and the actual report is durably reopened.
      final report = await _service([standard, enhanced]).recognize(
        input: ImageRecognitionInput(material: material, bytes: await store.readMaterial(material)),
        configurationIds: ['androidStandard', 'pixelEnhanced'],
      );
      await LocalRecognitionRepository(store: store).save(report);
      final reopened = await LocalRecognitionRepository(store: FileCaptureStore(directory.path)).findById(report.id);
      // Then the unchanged extension wire remains empty while performed work is still shared.
      expect(report.extensions, isEmpty); expect(reopened!.extensions, isEmpty);
      expect(RecognitionReportCodec.encode(reopened), RecognitionReportCodec.encode(report));
      expect(standard.inputs.length, 1); expect(enhanced.inputs.length, 1);
      expect(report.runs.first.attempts.first, same(report.runs.last.attempts.first));
      expect(reopened.runs.first.attempts.first, same(reopened.runs.last.attempts.first));
      expect(reopened.runs.last.attempts.last.result.interpretation, ' raw interpretation ');
    });

    test('N7 invalid finite JSON metadata fails before every probe preparation and inference and permits recovery', () async {
      final cyclic = <Object?>[]; cyclic.add(cyclic);
      for (final invalid in <Object?>[
        double.nan, double.infinity, double.negativeInfinity, Object(), DateTime.utc(2026),
        <Object?, Object?>{1: 'non-string key'}, cyclic,
      ]) {
        // Given this invalid optional configuration value and otherwise ready providers.
        final standard = _Provider();
        final enhanced = _Provider.enhanced()..state = RecognitionProviderState.downloadable;
        final optional = _ProvenanceProvider(enhanced, {'configuration': invalid});
        final service = _service([standard, optional]);
        // When availability, explicit preparation and comparison each admit the invalid metadata.
        await expectLater(service.availability(), throwsArgumentError);
        await expectLater(service.prepareProvider('geminiNano'), throwsArgumentError);
        await expectLater(service.recognize(input: _input(), configurationIds: ['androidStandard', 'pixelEnhanced']), throwsArgumentError);
        // Then invalid metadata fails before all native work without poisoning the guard.
        expect(standard.probes, 0); expect(enhanced.probes, 0);
        expect(enhanced.prepares, 0); expect(standard.inputs, isEmpty); expect(enhanced.inputs, isEmpty);
        optional.metadata = {'configuration': {'finite': 2}};
        // Given corrected finite metadata within the same service instance.
        // When explicit preparation and comparison are retried.
        await service.prepareProvider('geminiNano');
        final recovered = await service.recognize(input: _input(), configurationIds: ['androidStandard', 'pixelEnhanced']);
        // Then guard recovery restores normal shared work and snapshots the corrected configuration.
        expect(recovered.runs.last.actualConfigurationId, 'pixelEnhanced');
        expect(standard.inputs.length, 1); expect(enhanced.inputs.length, 1);
        expect(recovered.runs.first.attempts.first, same(recovered.runs.last.attempts.first));
        expect(recovered.extensions, {'providerProvenance': {'geminiNano': {'configuration': {'finite': 2}}}});
      }
    });

    final scenarios = <({String id, String? text, String state, String? error, String actual, RecognitionRunStatus status})>[
      (id: 'success', text: '{"interpretation":" visible image ","candidates":[{"kind":"opaque","value":" candidate "},{"kind":"opaque","value":" candidate "}]}', state: 'available', error: null, actual: 'pixelEnhanced', status: RecognitionRunStatus.completed),
      (id: 'interpretationOnly', text: '{"interpretation":" visible image ","candidates":[{"kind":"ok","value":"x"},{"kind":"","value":"bad"}]}', state: 'available', error: 'invalidGeneratedCandidates', actual: 'pixelEnhanced', status: RecognitionRunStatus.partial),
      (id: 'candidatesOnly', text: '{"interpretation":null,"candidates":[{"kind":"opaque","value":" candidate "}]}', state: 'available', error: 'invalidInterpretation', actual: 'pixelEnhanced', status: RecognitionRunStatus.partial),
      (id: 'wholeInvalid', text: 'actual malformed generated output', state: 'available', error: 'invalidGeneratedResponse', actual: 'androidStandard', status: RecognitionRunStatus.completed),
      (id: 'nativeFailure', text: null, state: 'available', error: 'nativeFailure', actual: 'androidStandard', status: RecognitionRunStatus.completed),
      (id: 'unavailable', text: null, state: 'unavailable', error: 'providerUnavailable', actual: 'androidStandard', status: RecognitionRunStatus.completed),
      (id: 'modelChanged', text: '{"interpretation":"visible","candidates":[]}', state: 'available', error: 'modelChanged', actual: 'androidStandard', status: RecognitionRunStatus.completed),
      (id: 'cleanup', text: '{"interpretation":" visible image ","candidates":[]}', state: 'available', error: 'cleanupFailed', actual: 'pixelEnhanced', status: RecognitionRunStatus.partial),
    ];
    for (final scenario in scenarios) {
      test('N9 real Dart Nano ${scenario.id} compares and durably reopens both routes', () async {
        for (final ids in <List<String>>[
          ['androidStandard', 'pixelEnhanced'], ['pixelEnhanced', 'androidStandard'],
        ]) {
          // Given this native Nano outcome, exact instructions and one real saved original in this row order.
          debugDefaultTargetPlatformOverride = TargetPlatform.android;
          final nativeCalls = <MethodCall>[];
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('org.textus.flutter.core/genai.v1'), (call) async {
              nativeCalls.add(call);
              if (call.method == 'probe') {
                return {'state': scenario.state, 'modelName': scenario.state == 'available' ? 'actual historical model' : null,
                  'reason': scenario.state == 'unavailable' ? 'actual device feature unavailable' : null};
              }
              if (scenario.id == 'nativeFailure') {
                throw PlatformException(code: 'nativeFailure', message: 'actual quota error',
                  details: {'nativeThrowable': 'quota detail', 'cleanupFailures': ['actual close failure']});
              }
              return {'text': scenario.text, 'modelName': scenario.id == 'modelChanged' ? 'changed actual model' : 'actual historical model',
                'cleanupFailures': scenario.id == 'cleanup' ? ['actual close failure'] : <String>[]};
            },
          );
          final standard = _Provider()..output = ImageRecognitionResult(text: ' raw OCR ', barcodeCompleted: true,
            barcodes: [RecognizedImageBarcode(format: 'ean13', value: ' 978 raw source ')]);
          final instructions = ' Exact generic instructions for ${scenario.id}. ';
          final nano = GeminiNanoImageRecognitionProvider(instructions: instructions);
          final material = await store.saveMaterial(bytes: Uint8List.fromList([1, 2, 3]), mediaType: 'image/jpeg', capturedAt: DateTime.utc(2026, 10, 6));
          // When the real adapter participates in comparison and the actual report is saved/restarted.
          final report = await _service([standard, nano]).recognize(
            input: ImageRecognitionInput(material: material, bytes: await store.readMaterial(material)), configurationIds: ids,
          );
          await LocalRecognitionRepository(store: store).save(report);
          final reopened = await LocalRecognitionRepository(store: FileCaptureStore(directory.path)).findById(report.id);
          final standardRow = report.runs.firstWhere((run) => run.desiredConfigurationId == 'androidStandard');
          final enhanced = report.runs.firstWhere((run) => run.desiredConfigurationId == 'pixelEnhanced');
          final attempt = enhanced.attempts.last;
          // Then raw standard work is shared once while desired/actual/fallback and durable provenance remain truthful.
          expect(report.runs.map((run) => run.desiredConfigurationId), ids);
          expect(standard.inputs.length, 1);
          expect(standardRow.attempts.single, same(enhanced.attempts.first));
          expect(standardRow.status, RecognitionRunStatus.completed);
          expect(enhanced.desiredConfigurationId, 'pixelEnhanced');
          expect(enhanced.actualConfigurationId, scenario.actual);
          expect(enhanced.status, scenario.status);
          expect(enhanced.hasFallback, scenario.actual == 'androidStandard');
          expect(enhanced.actualProviderIds, scenario.actual == 'androidStandard' ? ['mlkitStandard'] : ['mlkitStandard', 'geminiNano']);
          expect(attempt.executed, scenario.state == 'available');
          expect(attempt.availability.modelName, scenario.state == 'available' ? 'actual historical model' : null);
          expect(attempt.inputAttemptIds, [standardRow.attempts.single.id]);
          expect(enhanced.elapsed, standardRow.elapsed + attempt.elapsed);
          expect(attempt.elapsed.isNegative, isFalse);
          expect(standardRow.attempts.single.result.text, ' raw OCR ');
          expect(standardRow.attempts.single.result.barcodes.single.value, ' 978 raw source ');
          expect(attempt.result.text, isNull); expect(attempt.result.barcodes, isEmpty);
          expect(report.extensions, {'providerProvenance': {'geminiNano': {
            'promptTemplate': 'textus-image-recognition-v1', 'instructions': instructions,
          }}});
          expect(nativeCalls.where((call) => call.method == 'probe').length, 1);
          expect(nativeCalls.where((call) => call.method == 'prepare'), isEmpty);
          expect(RecognitionReportCodec.encode(reopened!), RecognitionReportCodec.encode(report));
          expect(reopened.runs.first.attempts.first, same(reopened.runs.last.attempts.first));
          expect(await store.readMaterial(material), [1, 2, 3]);
          if (scenario.state == 'available') {
            // Given an actually executed enhancement in this scenario.
            final arguments = nativeCalls.last.arguments as Map;
            // When its original/prompt/model arguments are observed.
            // Then the original and earlier raw source feed Nano without replacing standard output.
            expect(nativeCalls.where((call) => call.method == 'recognize').length, 1);
            expect(arguments['bytes'], [1, 2, 3]);
            expect(arguments['expectedModelName'], 'actual historical model');
            expect(arguments['prompt'], contains(instructions));
            expect(arguments['prompt'], contains(' raw OCR '));
            expect(arguments['prompt'], contains(' 978 raw source '));
          } else {
            // Given an unavailable enhancement in this scenario.
            // When performed native methods and timing are observed.
            // Then no inference or enhanced time is claimed.
            expect(nativeCalls.where((call) => call.method == 'recognize'), isEmpty);
            expect(attempt.elapsed, Duration.zero);
          }
          if (scenario.error != null) {
            // Given this explicit failed stage or native operation.
            // When its persisted attempt/fallback is examined.
            // Then the failure stays visible alongside preserved standard raw data.
            expect(attempt.result.failures.first.code, scenario.error);
            if (scenario.actual == 'androidStandard') {
              // Given a failed or unavailable enhancement requiring standard fallback.
              // When actual route selection is observed.
              // Then it has no selected enhanced success and retains the failure reason.
              expect(attempt.result.hasSuccessfulOutput, isFalse);
              expect(enhanced.fallbackReason, contains(scenario.error!));
            }
            if (scenario.id == 'wholeInvalid') {
              // Given invalid whole generated text.
              // When durable failure evidence is observed.
              // Then the failed raw text remains verbatim descriptive evidence.
              expect(attempt.result.failures.first.message, contains(scenario.text!));
            }
            if (scenario.id == 'nativeFailure') {
              // Given native quota failure and its failed close.
              // When failure stages are observed after restart.
              // Then both the primary detail and cleanup failure survive.
              expect(attempt.result.failures.first.message, contains('actual quota error'));
              expect(attempt.result.failures.first.message, contains('quota detail'));
              expect(attempt.result.failures.last.stage, ImageRecognitionStage.cleanup);
              expect(attempt.result.failures.last.message, 'actual close failure');
            }
          } else {
            // Given the fully successful generated response.
            // When selected enhanced raw stages are observed.
            // Then interpretation and opaque duplicate candidates are retained verbatim.
            expect(attempt.result.failures, isEmpty);
            expect(attempt.result.interpretation, ' visible image ');
            expect(attempt.result.candidateOrganizationCompleted, isTrue);
            expect(attempt.result.candidates.map((candidate) => candidate.value), [' candidate ', ' candidate ']);
          }
        }
      });
    }
  });
}

const _standardCaps = [RecognitionCapability.ocr, RecognitionCapability.barcodes];
List<RecognitionConfiguration> _capabilityRoutes() => [
  RecognitionConfiguration(id: 'ocrOnly', label: 'OCR only', providers: [
    RecognitionProviderRequirement(providerId: 'custom', capabilities: [RecognitionCapability.ocr]),
  ]),
  RecognitionConfiguration(id: 'ocrAndBarcodes', label: 'OCR and barcodes', providers: [
    RecognitionProviderRequirement(providerId: 'custom', capabilities: _standardCaps),
  ]),
];
ImageRecognitionInput _input() => ImageRecognitionInput(
  material: CaptureMaterialReference(id: 'original', mediaType: 'image/jpeg', byteLength: 3, capturedAt: DateTime.utc(2026, 10, 6)),
  bytes: Uint8List.fromList([1, 2, 3]),
);
RecognitionConfiguration _config(String id, List<String> ids, {String? fallback}) => RecognitionConfiguration(
  id: id, label: id, fallbackConfigurationId: fallback,
  providers: ids.map((id) => RecognitionProviderRequirement(providerId: id, capabilities: [RecognitionCapability.ocr])),
);
ImageRecognitionService _service(List<ImageRecognitionProvider> providers, {List<RecognitionConfiguration>? configurations}) =>
    ImageRecognitionService(registry: RecognitionProviderRegistry(providers: providers), configurations: configurations,
      clock: () => DateTime.utc(2026, 10, 6));
final class _Provider implements ImageRecognitionProvider {
  _Provider({String id = 'mlkitStandard', Iterable<RecognitionCapability> capabilities = _standardCaps,
    this.state = RecognitionProviderState.available})
    : descriptor = RecognitionProviderDescriptor(id: id, label: 'Controlled $id', capabilities: capabilities),
      output = ImageRecognitionResult(text: ' raw OCR ', barcodeCompleted: true);
  _Provider.enhanced() : descriptor = RecognitionProviderDescriptor(id: 'geminiNano', label: 'Controlled enhancement', capabilities: [
    RecognitionCapability.imageInterpretation, RecognitionCapability.candidateOrganization,
  ]), state = RecognitionProviderState.available,
    output = ImageRecognitionResult(interpretation: ' raw interpretation ', candidateOrganizationCompleted: true,
      candidates: [RecognitionCandidate(kind: 'opaque', value: 'raw suggestion')]);
  @override
  RecognitionProviderDescriptor descriptor;
  RecognitionProviderState state;
  ImageRecognitionResult output;
  String? snapshotId;
  Iterable<RecognitionCapability>? snapshotCapabilities;
  String? snapshotModelName;
  Object? probeError;
  Object? recognitionError;
  Completer<void>? prepareGate;
  final prepareStarted = Completer<void>();
  bool mutateReturnedBytes = false;
  int probes = 0; int prepares = 0;
  final inputs = <ImageRecognitionInput>[];
  @override
  Future<RecognitionProviderAvailability> availability() async {
    probes++;
    if (probeError != null) { throw probeError!; }
    return RecognitionProviderAvailability(providerId: snapshotId ?? descriptor.id, state: state,
      capabilities: snapshotCapabilities ?? descriptor.capabilities,
      reason: state == RecognitionProviderState.unavailable ? 'controlled unavailable' : null,
      modelName: snapshotModelName);
  }
  @override
  Future<void> prepare() async {
    prepares++;
    if (!prepareStarted.isCompleted) { prepareStarted.complete(); }
    if (prepareGate != null) { await prepareGate!.future; }
    state = RecognitionProviderState.available;
  }
  @override
  Future<ImageRecognitionResult> recognize(ImageRecognitionInput input) async {
    inputs.add(input);
    if (mutateReturnedBytes) { input.bytes[0] = 99; }
    if (recognitionError != null) { throw recognitionError!; }
    return output;
  }
}
final class _SettingsMemory implements SettingsStorage {
  String? record;
  @override
  Future<String?> read() async => record;
  @override
  Future<void> write(String record) async { this.record = record; }
}

final class _ProvenanceProvider implements ImageRecognitionProvider, ImageRecognitionProviderProvenance {
  _ProvenanceProvider(this.delegate, this.metadata, {this.onProbe});
  final _Provider delegate;
  Map<String, Object?> metadata;
  final void Function()? onProbe;
  @override
  RecognitionProviderDescriptor get descriptor => delegate.descriptor;
  @override
  Map<String, Object?> get provenance => metadata;
  @override
  Future<RecognitionProviderAvailability> availability() {
    onProbe?.call();
    return delegate.availability();
  }
  @override
  Future<void> prepare() => delegate.prepare();
  @override
  Future<ImageRecognitionResult> recognize(ImageRecognitionInput input) => delegate.recognize(input);
}
