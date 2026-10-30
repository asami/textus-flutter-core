import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  group('generated draft generation', () {
    for (final operation in GeneratedDraftOperation.values) {
      test('ready ${operation.name} captures exact input, prompt and model', () async {
        // Given a real service and a controlled provider with an actual ready model.
        final provider = _Provider();
        const raw = '\n  日本語の生成結果😀。 \n';
        provider.onGenerate = (request, prompt, model) async => _success(text: raw);
        final service = _service(provider);
        final bytes = Uint8List.fromList([10, 20, 30]);
        final source = operation == GeneratedDraftOperation.imageDescription
            ? _imageSource()
            : _textSource();
        final request = GeneratedDraftRequest(id: 'request-${operation.name}',
          operation: operation, source: source,
          imageBytes: operation == GeneratedDraftOperation.imageDescription ? bytes : null);
        // When the caller mutates its buffer and explicitly generates one draft.
        bytes[0] = 99;
        final attempt = await service.generate(request);
        final workspace = GeneratedDraftWorkspace().append(attempt).decide(
          GeneratedDraftDecision(attemptId: attempt.id,
            kind: GeneratedDraftDecisionKind.accept, recordedAt: attempt.completedAt));
        final reloaded = GeneratedDraftWorkspace.fromJson(
          jsonDecode(jsonEncode(workspace.toJson())));
        // Then captured immutable input and raw evidence survive explicit adoption/reload.
        expect(provider.requests.single, same(request));
        expect(provider.promptRequests.single, same(request));
        expect(provider.probeOperations, [operation]);
        expect(provider.probeLanguages, ['ja']);
        expect(provider.prompts.single, attempt.prompt);
        expect(provider.promptCalls, 1);
        expect(provider.expectedModels, ['actual-ja-model']);
        expect(attempt.source, same(source));
        expect(attempt.providerId, provider.id);
        expect(attempt.promptTemplate, provider.promptTemplate);
        expect(attempt.status, GeneratedDraftStatus.success);
        expect(attempt.availability!.modelName, 'actual-ja-model');
        expect(attempt.modelName, 'actual-ja-model');
        expect(attempt.rawText, raw);
        expect(attempt.startedAt.isUtc, isTrue);
        expect(attempt.completedAt.isBefore(attempt.startedAt), isFalse);
        expect(attempt.errorCode, isNull);
        expect(attempt.errorMessage, isNull);
        expect(provider.prepareCalls, 0);
        expect(provider.cancelIds, isEmpty);
        expect(reloaded.toJson(), workspace.toJson());
        expect(reloaded.pending, isEmpty);
        expect(reloaded.attempts.single.rawText, raw);
        if (operation == GeneratedDraftOperation.imageDescription) {
          expect(provider.requests.single.imageBytes, orderedEquals([10, 20, 30]));
          expect(reloaded.attempts.single.source.text, isNull);
        } else {
          expect(provider.requests.single.imageBytes, isNull);
          expect(reloaded.attempts.single.source.text, ' \n原文😀をそのまま保持する。 ');
        }
        expect(service.isBusy, isFalse);
      });
    }

    final blockedStates = {
      GeneratedDraftAvailabilityState.unsupported: 'unsupportedOperation',
      GeneratedDraftAvailabilityState.unavailable: 'providerUnavailable',
      GeneratedDraftAvailabilityState.downloadable: 'preparationRequired',
      GeneratedDraftAvailabilityState.preparing: 'providerPreparing',
    };
    for (final entry in blockedStates.entries) {
      test('${entry.key.name} reports its reason without inference or preparation', () async {
        // Given a provider reporting this non-ready operation/language state.
        final provider = _Provider()..state = entry.key;
        final service = _service(provider);
        // When generation is explicitly requested without changing readiness.
        final attempt = await service.generate(_request('blocked'));
        // Then the distinct failure retains its truthful reason and calls no inference.
        expect(attempt.status, GeneratedDraftStatus.failed);
        expect(attempt.errorCode, entry.value);
        expect(attempt.errorMessage, 'この操作の状態: ${entry.key.name}');
        expect(attempt.availability!.state, entry.key);
        expect(attempt.modelName, isNull);
        expect(attempt.rawText, isNull);
        expect(attempt.prompt, isNull);
        expect(provider.requests, isEmpty);
        expect(provider.promptCalls, 0);
        expect(provider.prepareCalls, 0);
        expect(GeneratedDraftWorkspace(attempts: [attempt]).pending, isEmpty);
        expect(service.isBusy, isFalse);
      });
    }

    test('busy guard begins before probing and used request IDs cannot be retried', () async {
      // Given a readiness probe held pending by the borrowed provider.
      final provider = _Provider();
      final probe = Completer<GeneratedDraftAvailability>();
      provider.onProbe = (operation, language) => probe.future;
      final service = _service(provider);
      final request = _request('first');
      // When one generation starts and overlapping operations try to enter.
      final running = service.generate(request);
      // Then every competing service operation is rejected before another probe.
      expect(service.isBusy, isTrue);
      expect(() => service.generate(_request('overlap')), throwsStateError);
      expect(() => service.availability(operation: request.operation), throwsStateError);
      expect(() => service.prepare(operation: request.operation), throwsStateError);
      expect(provider.probeOperations, [request.operation]);
      // Given the original ready probe is now allowed to finish normally.
      probe.complete(provider.snapshot(request.operation, 'ja'));
      final attempt = await running;
      provider.onProbe = null;
      // When the caller reuses its completed ID, then uses the previously blocked fresh ID.
      expect(() => service.generate(request), throwsStateError);
      final fresh = await service.generate(_request('overlap'));
      // Then rejection consumed no fresh ID and only the two real requests inferred.
      expect(attempt.status, GeneratedDraftStatus.success);
      expect(fresh.status, GeneratedDraftStatus.success);
      expect(provider.requests.map((value) => value.id), ['first', 'overlap']);
      expect(service.isBusy, isFalse);
    });

    test('2048 Unicode scalar values succeed without truncating surrogate pairs', () async {
      // Given a ready provider returning exactly 2048 supplementary characters.
      final provider = _Provider();
      final raw = List.filled(2048, '😀').join();
      provider.onGenerate = (request, prompt, model) async => _success(text: raw);
      final service = _service(provider);
      // When the real service applies its public output limit.
      final attempt = await service.generate(_request('unicode-limit'));
      // Then the scalar limit accepts the whole unchanged 4096-code-unit response.
      expect(attempt.status, GeneratedDraftStatus.success);
      expect(attempt.rawText, raw);
      expect(attempt.rawText!.length, 4096);
      expect(attempt.rawText!.runes.length, 2048);
    });

    test('wrong actual model is explicit and retains raw output and cleanup', () async {
      // Given an available model that changes at actual provider generation.
      final provider = _Provider();
      const raw = '\n 別モデルの実際の出力。 ';
      provider.onGenerate = (request, prompt, model) async => _success(
        text: raw, modelName: 'changed-model', cleanup: ['native release failed']);
      final service = _service(provider);
      // When the provider returns success for the wrong actual model.
      final attempt = await service.generate(_request('wrong-model'));
      // Then model drift becomes a failed draft without guessing/truncating evidence.
      expect(provider.expectedModels, ['actual-ja-model']);
      expect(attempt.status, GeneratedDraftStatus.failed);
      expect(attempt.errorCode, 'modelChanged');
      expect(attempt.errorMessage, isNotEmpty);
      expect(attempt.modelName, 'changed-model');
      expect(attempt.availability!.modelName, 'actual-ja-model');
      expect(attempt.rawText, raw);
      expect(attempt.cleanupFailures, ['native release failed']);
      expect(GeneratedDraftWorkspace(attempts: [attempt]).pending, isEmpty);
    });

    test('oversize output fails with the complete raw response retained', () async {
      // Given a ready provider returning 2049 Unicode scalar values and cleanup evidence.
      final raw = List.filled(2049, '😀').join();
      final provider = _Provider();
      provider.onGenerate = (request, prompt, model) async => _success(
        text: raw, cleanup: ['cleanup warning']);
      final service = _service(provider);
      // When the service receives the excessive provider response.
      final attempt = await service.generate(_request('too-large'));
      // Then it records an explicit failure without truncation or pending adoption.
      expect(attempt.status, GeneratedDraftStatus.failed);
      expect(attempt.errorCode, 'outputTooLarge');
      expect(attempt.errorMessage, contains('2048'));
      expect(attempt.rawText, raw);
      expect(attempt.modelName, 'actual-ja-model');
      expect(attempt.cleanupFailures, ['cleanup warning']);
      expect(GeneratedDraftWorkspace(attempts: [attempt]).pending, isEmpty);
    });

    for (final status in [GeneratedDraftStatus.failed, GeneratedDraftStatus.canceled]) {
      test('provider ${status.name} preserves original diagnostics and raw text', () async {
        // Given an actual provider failure/cancellation with a blank raw response.
        final provider = _Provider();
        provider.onGenerate = (request, prompt, model) async => GeneratedDraftProviderOutput(
          status: status, text: ' \n', modelName: 'reported-model',
          errorCode: 'native-${status.name}', errorMessage: '実際の詳細説明',
          cleanupFailures: ['first cleanup', 'second cleanup']);
        final service = _service(provider);
        // When the provider reaches its terminal response through the real service.
        final attempt = await service.generate(_request('native-result'));
        final reloaded = GeneratedDraftWorkspace.fromJson(jsonDecode(jsonEncode(
          GeneratedDraftWorkspace(attempts: [attempt]).toJson())));
        // Then status/code/message/raw/model and cleanup all survive without fallback.
        expect(attempt.status, status);
        expect(attempt.errorCode, 'native-${status.name}');
        expect(attempt.errorMessage, '実際の詳細説明');
        expect(attempt.rawText, ' \n');
        expect(attempt.modelName, 'reported-model');
        expect(attempt.prompt, provider.prompts.single);
        expect(attempt.cleanupFailures, ['first cleanup', 'second cleanup']);
        expect(reloaded.attempts.single.toJson(), attempt.toJson());
        expect(reloaded.pending, isEmpty);
        expect(provider.prepareCalls, 0);
      });
    }

    test('thrown provider failure preserves its description and allows a fresh ID', () async {
      // Given a ready provider whose first generation throws an actual diagnostic.
      final provider = _Provider();
      provider.onGenerate = (request, prompt, model) async {
        throw StateError('native engine failed: 日本語の詳細');
      };
      final service = _service(provider);
      // When the first request fails and a fresh request is explicitly submitted.
      final failed = await service.generate(_request('failed'));
      provider.onGenerate = null;
      final succeeded = await service.generate(_request('fresh'));
      // Then failure evidence remains explicit and no terminal state blocks fresh work.
      expect(failed.status, GeneratedDraftStatus.failed);
      expect(failed.errorCode, 'providerFailure');
      expect(failed.errorMessage, contains('native engine failed: 日本語の詳細'));
      expect(failed.availability, isNotNull);
      expect(failed.prompt, isNotNull);
      expect(failed.rawText, isNull);
      expect(failed.modelName, isNull);
      expect(succeeded.status, GeneratedDraftStatus.success);
      expect(() => service.generate(_request('failed')), throwsStateError);
      expect(service.isBusy, isFalse);
    });

    test('probe and prompt exceptions keep only evidence actually obtained', () async {
      // Given a provider whose availability probe fails before any prompt exists.
      final provider = _Provider();
      provider.onProbe = (operation, language) async => throw StateError('probe failed');
      final service = _service(provider);
      // When that request fails, then a fresh request fails while capturing its prompt.
      final probeFailure = await service.generate(_request('probe-failure'));
      provider.onProbe = null;
      provider.onPrompt = (request) => throw StateError('prompt template failed');
      final promptFailure = await service.generate(_request('prompt-failure'));
      // Then failures expose original descriptions with nullable unavailable evidence.
      expect(probeFailure.errorCode, 'providerFailure');
      expect(probeFailure.errorMessage, contains('probe failed'));
      expect(probeFailure.availability, isNull);
      expect(probeFailure.prompt, isNull);
      expect(promptFailure.errorCode, 'providerFailure');
      expect(promptFailure.errorMessage, contains('prompt template failed'));
      expect(promptFailure.availability!.state, GeneratedDraftAvailabilityState.available);
      expect(promptFailure.prompt, isNull);
      expect(provider.requests, isEmpty);
      expect(provider.prepareCalls, 0);
      expect(service.isBusy, isFalse);
    });
  });

  group('explicit preparation and readiness', () {
    test('downloadable preparation probes first and holds busy through re-probe', () async {
      // Given a downloadable model and an explicit preparation held by the provider.
      final provider = _Provider()..state = GeneratedDraftAvailabilityState.downloadable;
      final entered = Completer<void>();
      final preparation = Completer<void>();
      final reprobeEntered = Completer<void>();
      final reprobe = Completer<GeneratedDraftAvailability>();
      provider.onPrepare = () async {
        entered.complete();
        await preparation.future;
        provider.state = GeneratedDraftAvailabilityState.available;
      };
      provider.onProbe = (operation, language) {
        if (provider.probeOperations.length == 2) {
          reprobeEntered.complete();
          return reprobe.future;
        }
        return Future.value(provider.snapshot(operation, language));
      };
      final service = _service(provider);
      // When preparation is explicitly requested and its download remains pending.
      final preparing = service.prepare(operation: GeneratedDraftOperation.textSummary);
      await entered.future;
      // Then it probed before preparing, holds the serial guard and has no cancel target.
      expect(provider.events, ['probe', 'prepare']);
      expect(service.isBusy, isTrue);
      expect(() => service.generate(_request('overlap')), throwsStateError);
      expect(() => service.prepare(operation: GeneratedDraftOperation.textSummary), throwsStateError);
      expect(await service.cancel(), isFalse);
      expect(provider.cancelIds, isEmpty);
      // Given the explicit download can finish while its readiness re-probe is still pending.
      preparation.complete();
      await reprobeEntered.future;
      // When a second readiness call tries to overlap the unfinished re-probe.
      expect(() => service.availability(operation: GeneratedDraftOperation.textSummary),
          throwsStateError);
      // Then busy lasts until the same operation/language has actually been re-probed.
      expect(service.isBusy, isTrue);
      reprobe.complete(provider.snapshot(GeneratedDraftOperation.textSummary, 'ja'));
      final ready = await preparing;
      expect(ready.state, GeneratedDraftAvailabilityState.available);
      expect(ready.modelName, 'actual-ja-model');
      expect(provider.events, ['probe', 'prepare', 'probe']);
      expect(provider.probeOperations, [GeneratedDraftOperation.textSummary,
        GeneratedDraftOperation.textSummary]);
      expect(provider.probeLanguages, ['ja', 'ja']);
      expect(provider.prepareCalls, 1);
      expect(provider.requests, isEmpty);
      expect(service.isBusy, isFalse);
    });

    for (final state in [
      GeneratedDraftAvailabilityState.unsupported,
      GeneratedDraftAvailabilityState.unavailable,
      GeneratedDraftAvailabilityState.preparing,
      GeneratedDraftAvailabilityState.available,
    ]) {
      test('explicit prepare returns ${state.name} without invoking preparation', () async {
        // Given the provider truthfully reports a state that cannot request a download.
        final provider = _Provider()..state = state;
        final service = _service(provider);
        // When the caller explicitly requests preparation for image description in Japanese.
        final snapshot = await service.prepare(
          operation: GeneratedDraftOperation.imageDescription, language: 'ja');
        // Then one truthful probe is returned without preparation or generation.
        expect(snapshot.state, state);
        expect(snapshot.operation, GeneratedDraftOperation.imageDescription);
        expect(snapshot.language, 'ja');
        expect(provider.probeOperations, [GeneratedDraftOperation.imageDescription]);
        expect(provider.events, ['probe']);
        expect(provider.prepareCalls, 0);
        expect(provider.requests, isEmpty);
        expect(service.isBusy, isFalse);
      });
    }

    test('ordinary readiness probe holds busy and performs no preparation', () async {
      // Given a downloadable provider with its readiness response held pending.
      final provider = _Provider()..state = GeneratedDraftAvailabilityState.downloadable;
      final probe = Completer<GeneratedDraftAvailability>();
      provider.onProbe = (operation, language) => probe.future;
      final service = _service(provider);
      // When a caller probes readiness and another invocation tries to enter.
      final running = service.availability(operation: GeneratedDraftOperation.textSummary);
      expect(() => service.generate(_request('overlap')), throwsStateError);
      expect(await service.cancel(), isFalse);
      probe.complete(provider.snapshot(GeneratedDraftOperation.textSummary, 'ja'));
      final snapshot = await running;
      // Then probing reports downloadable unchanged, with no hidden provider mutation.
      expect(snapshot.state, GeneratedDraftAvailabilityState.downloadable);
      expect(provider.prepareCalls, 0);
      expect(provider.requests, isEmpty);
      expect(provider.cancelIds, isEmpty);
      expect(service.isBusy, isFalse);
    });

    for (final mismatch in ['provider', 'operation', 'language']) {
      test('rejects $mismatch availability mismatch before inference or preparation', () async {
        // Given a provider returning a snapshot for a different public identity.
        final provider = _Provider();
        provider.onProbe = (operation, language) async => GeneratedDraftAvailability(
          providerId: mismatch == 'provider' ? 'different' : provider.id,
          operation: mismatch == 'operation'
              ? GeneratedDraftOperation.imageDescription : operation,
          language: mismatch == 'language' ? 'en' : language,
          state: GeneratedDraftAvailabilityState.available,
          modelName: 'actual-ja-model');
        final service = _service(provider);
        // When readiness, explicit preparation and generation encounter that snapshot.
        await expectLater(service.availability(operation: GeneratedDraftOperation.textSummary),
          throwsStateError);
        await expectLater(service.prepare(operation: GeneratedDraftOperation.textSummary),
          throwsStateError);
        final attempt = await service.generate(_request('mismatch'));
        // Then identity mismatch cannot be treated as readiness or successful generation.
        expect(attempt.status, GeneratedDraftStatus.failed);
        expect(attempt.errorCode, 'providerFailure');
        expect(attempt.errorMessage, contains('identity'));
        expect(attempt.availability, isNull);
        expect(provider.requests, isEmpty);
        expect(provider.prepareCalls, 0);
        expect(service.isBusy, isFalse);
      });
    }

    test('preparation exceptions release busy without claiming a ready model', () async {
      // Given a downloadable model whose explicit preparation actually fails.
      final provider = _Provider()..state = GeneratedDraftAvailabilityState.downloadable;
      provider.onPrepare = () async => throw StateError('download failed');
      final service = _service(provider);
      // When explicit preparation fails and the caller probes its actual state again.
      await expectLater(service.prepare(operation: GeneratedDraftOperation.textSummary),
        throwsA(isA<StateError>().having((error) => error.message, 'message', 'download failed')));
      final snapshot = await service.availability(operation: GeneratedDraftOperation.textSummary);
      // Then no inferred availability replaces the still-downloadable actual state.
      expect(snapshot.state, GeneratedDraftAvailabilityState.downloadable);
      expect(provider.prepareCalls, 1);
      expect(provider.probeOperations, hasLength(2));
      expect(provider.requests, isEmpty);
      expect(service.isBusy, isFalse);
    });
  });

  group('generated draft cancellation', () {
    test('cancel during a pending probe never starts generation', () async {
      // Given a generation awaiting its initial readiness snapshot.
      final provider = _Provider();
      final probe = Completer<GeneratedDraftAvailability>();
      provider.onProbe = (operation, language) => probe.future;
      provider.onCancel = (id) async => false;
      final service = _service(provider);
      final running = service.generate(_request('cancel-probe'));
      // When cancellation is requested before that probe reports an available model.
      expect(await service.cancel(), isFalse);
      expect(service.isBusy, isTrue);
      probe.complete(provider.snapshot(GeneratedDraftOperation.textSummary, 'ja'));
      final attempt = await running;
      // Then cancellation wins without invoking prompts or inference after the probe.
      expect(provider.cancelIds, ['cancel-probe']);
      expect(provider.requests, isEmpty);
      expect(provider.promptCalls, 0);
      expect(provider.prepareCalls, 0);
      expect(attempt.status, GeneratedDraftStatus.canceled);
      expect(attempt.errorCode, 'canceled');
      expect(attempt.errorMessage, isNotEmpty);
      expect(attempt.availability!.state, GeneratedDraftAvailabilityState.available);
      expect(attempt.prompt, isNull);
      expect(attempt.rawText, isNull);
      expect(GeneratedDraftWorkspace(attempts: [attempt]).pending, isEmpty);
      expect(service.isBusy, isFalse);
    });

    for (final cancellation in ['supported', 'unsupported', 'throws']) {
      test('$cancellation cancellation retains busy and defeats late success', () async {
        // Given actual generation held pending after readiness and prompt capture.
        final provider = _Provider();
        final entered = Completer<void>();
        final result = Completer<GeneratedDraftProviderOutput>();
        provider.onGenerate = (request, prompt, model) {
          entered.complete();
          return result.future;
        };
        provider.onCancel = (id) async {
          if (cancellation == 'throws') throw StateError('native cancel release failed');
          return cancellation == 'supported';
        };
        final service = _service(provider);
        final running = service.generate(_request('cancel-generation'));
        await entered.future;
        // When cancellation settles but the actual generation still has not ended.
        final cancelResult = await service.cancel();
        // Then the exact ID was targeted and the serial guard remains held.
        expect(cancelResult, cancellation == 'supported');
        expect(provider.cancelIds, ['cancel-generation']);
        expect(service.isBusy, isTrue);
        expect(() => service.generate(_request('premature')), throwsStateError);
        expect(() => service.prepare(operation: GeneratedDraftOperation.textSummary), throwsStateError);
        // Given the provider still returns a late successful raw response and cleanup.
        const raw = ' 遅れて返った日本語の出力。\n';
        result.complete(_success(text: raw, cleanup: ['provider cleanup failed']));
        // When generation actually completes, a fresh request is then submitted.
        final attempt = await running;
        provider.onGenerate = null;
        final fresh = await service.generate(_request('fresh-after-cancel'));
        final idleCancel = await service.cancel();
        final workspace = GeneratedDraftWorkspace(attempts: [attempt, fresh]);
        // Then canceled evidence cannot be adopted and stale cancel never reaches fresh work.
        expect(attempt.status, GeneratedDraftStatus.canceled);
        expect(attempt.errorCode, 'canceled');
        expect(attempt.errorMessage, contains('cancel-generation'));
        expect(attempt.rawText, raw);
        expect(attempt.modelName, 'actual-ja-model');
        expect(attempt.prompt, provider.prompts.first);
        expect(attempt.cleanupFailures.first, 'provider cleanup failed');
        if (cancellation == 'throws') {
          expect(attempt.cleanupFailures.last, contains('native cancel release failed'));
          expect(attempt.cleanupFailures, hasLength(2));
        } else {
          expect(attempt.cleanupFailures, ['provider cleanup failed']);
        }
        expect(fresh.status, GeneratedDraftStatus.success);
        expect(workspace.pending.map((value) => value.id), ['fresh-after-cancel']);
        expect(() => workspace.decide(GeneratedDraftDecision(attemptId: attempt.id,
            kind: GeneratedDraftDecisionKind.accept, recordedAt: attempt.completedAt)),
          throwsArgumentError);
        expect(() => service.generate(_request('cancel-generation')), throwsStateError);
        expect(provider.cancelIds, ['cancel-generation']);
        expect(provider.prepareCalls, 0);
        expect(idleCancel, isFalse);
        expect(service.isBusy, isFalse);
      });
    }

    test('completion waits for pending cancellation cleanup and repeated cancel shares target', () async {
      // Given a generation and a provider cancellation whose cleanup both remain pending.
      final provider = _Provider();
      final entered = Completer<void>();
      final output = Completer<GeneratedDraftProviderOutput>();
      final canceled = Completer<bool>();
      provider.onGenerate = (request, prompt, model) {
        entered.complete();
        return output.future;
      };
      provider.onCancel = (id) => canceled.future;
      final service = _service(provider);
      final running = service.generate(_request('cleanup-pending'));
      await entered.future;
      // When generation returns late success while cancel cleanup is still unsettled.
      final firstCancel = service.cancel();
      final repeatedCancel = service.cancel();
      var generationCompleted = false;
      final observed = running.then((attempt) {
        generationCompleted = true;
        return attempt;
      });
      output.complete(_success(text: 'raw output before cleanup'));
      await Future<void>.delayed(Duration.zero);
      // Then the final attempt and busy release wait for actual cancellation settlement.
      expect(repeatedCancel, same(firstCancel));
      expect(provider.cancelIds, ['cleanup-pending']);
      expect(generationCompleted, isFalse);
      expect(service.isBusy, isTrue);
      expect(() => service.generate(_request('too-early')), throwsStateError);
      // Given the pending native cancellation cleanup now reports its actual failure.
      canceled.completeError(StateError('cancel cleanup finally failed'));
      // When both observed operations are awaited to completion.
      expect(await firstCancel, isFalse);
      final attempt = await observed;
      // Then failure diagnostics survive alongside canceled disposition and raw output.
      expect(attempt.status, GeneratedDraftStatus.canceled);
      expect(attempt.rawText, 'raw output before cleanup');
      expect(attempt.cleanupFailures.single, contains('cancel cleanup finally failed'));
      expect(generationCompleted, isTrue);
      expect(service.isBusy, isFalse);
    });
  });

  group('generated draft descriptors and clocks', () {
    test('invalid static provider descriptors reject construction without work', () {
      // Given providers with non-exact or blank static identity/template descriptors.
      final invalid = [
        _Provider(providerId: ' '), _Provider(providerId: ' provider'),
        _Provider(template: ''), _Provider(template: 'template\u0000'),
      ];
      // When each provider is bound to a service.
      void bind(_Provider provider) => GeneratedDraftService(provider: provider);
      // Then invalid descriptors fail before any readiness/preparation/generation call.
      for (final provider in invalid) {
        expect(() => bind(provider), throwsArgumentError);
        expect(provider.events, isEmpty);
      }
    });

    for (final badClock in ['local', 'backward', 'throws']) {
      test('$badClock clock is explicit and still releases busy', () async {
        // Given a provider and a clock that cannot supply an honest UTC interval.
        final provider = _Provider();
        var reads = 0;
        final service = GeneratedDraftService(provider: provider, clock: () {
          reads++;
          if (badClock == 'local') return DateTime(2026, 10, 30);
          if (badClock == 'throws') throw StateError('clock unavailable');
          return reads == 1 ? _time : _time.subtract(const Duration(seconds: 1));
        });
        // When generation tries to record its actual start/completion timestamps.
        await expectLater(service.generate(_request('bad-clock')), throwsStateError);
        // Then no timestamp is fabricated and subsequent readiness can run normally.
        expect(service.isBusy, isFalse);
        expect(await service.cancel(), isFalse);
        expect(provider.cancelIds, isEmpty);
        final snapshot = await service.availability(operation: GeneratedDraftOperation.textSummary);
        expect(snapshot.state, GeneratedDraftAvailabilityState.available);
        expect(service.isBusy, isFalse);
      });
    }
  });
}

final _time = DateTime.utc(2026, 10, 30, 1);

GeneratedDraftService _service(_Provider provider) {
  var tick = 0;
  return GeneratedDraftService(provider: provider,
    clock: () => _time.add(Duration(microseconds: tick++)));
}

GeneratedDraftSource _textSource() => GeneratedDraftSource(id: 'text-origin',
  materialId: '原資料', revision: 'revision-1', kind: GeneratedDraftSourceKind.text,
  text: ' \n原文😀をそのまま保持する。 ',
  metadata: {'transcript': {'reportId': '報告', 'revisionIndex': 3}});

GeneratedDraftSource _imageSource() => GeneratedDraftSource(id: 'image-origin',
  materialId: 'region-image', revision: 'revision-1', kind: GeneratedDraftSourceKind.image,
  parentMaterialId: 'parent-image', regionId: 'region', regionRevision: 2,
  metadata: {'annotationRevision': '注記改訂一'});

GeneratedDraftRequest _request(String id) => GeneratedDraftRequest(id: id,
  operation: GeneratedDraftOperation.textSummary, source: _textSource());

GeneratedDraftProviderOutput _success({
  String text = '生成された要約。',
  String modelName = 'actual-ja-model',
  Iterable<String> cleanup = const [],
}) => GeneratedDraftProviderOutput(status: GeneratedDraftStatus.success,
  text: text, modelName: modelName, cleanupFailures: cleanup);

final class _Provider implements GeneratedDraftProvider {
  _Provider({this.providerId = 'test-provider', this.template = 'prompt-template-v1'});

  final String providerId;
  final String template;
  GeneratedDraftAvailabilityState state = GeneratedDraftAvailabilityState.available;
  Future<GeneratedDraftAvailability> Function(GeneratedDraftOperation, String)? onProbe;
  Future<void> Function()? onPrepare;
  String Function(GeneratedDraftRequest)? onPrompt;
  Future<GeneratedDraftProviderOutput> Function(GeneratedDraftRequest, String, String?)? onGenerate;
  Future<bool> Function(String)? onCancel;
  final List<String> events = [];
  final List<GeneratedDraftOperation> probeOperations = [];
  final List<String> probeLanguages = [];
  final List<GeneratedDraftRequest> promptRequests = [];
  final List<GeneratedDraftRequest> requests = [];
  final List<String> prompts = [];
  final List<String?> expectedModels = [];
  final List<String> cancelIds = [];
  int prepareCalls = 0;
  int promptCalls = 0;

  @override
  String get id => providerId;

  @override
  String get promptTemplate => template;

  GeneratedDraftAvailability snapshot(GeneratedDraftOperation operation, String language) =>
      GeneratedDraftAvailability(providerId: id, operation: operation,
        language: language, state: state,
        modelName: state == GeneratedDraftAvailabilityState.available ? 'actual-ja-model' : null,
        reason: state == GeneratedDraftAvailabilityState.available ? null : 'この操作の状態: ${state.name}');

  @override
  Future<GeneratedDraftAvailability> availability({
    required GeneratedDraftOperation operation,
    required String language,
  }) {
    events.add('probe');
    probeOperations.add(operation);
    probeLanguages.add(language);
    return onProbe?.call(operation, language) ?? Future.value(snapshot(operation, language));
  }

  @override
  Future<void> prepare() async {
    events.add('prepare');
    prepareCalls++;
    await onPrepare?.call();
  }

  @override
  String promptFor(GeneratedDraftRequest request) {
    events.add('prompt');
    promptCalls++;
    promptRequests.add(request);
    return onPrompt?.call(request) ?? ' 正確な入力: ${request.source.text ?? request.source.materialId}\n';
  }

  @override
  Future<GeneratedDraftProviderOutput> generate(GeneratedDraftRequest request, {
    required String prompt,
    String? expectedModelName,
  }) {
    events.add('generate');
    requests.add(request);
    prompts.add(prompt);
    expectedModels.add(expectedModelName);
    return onGenerate?.call(request, prompt, expectedModelName) ?? Future.value(_success());
  }

  @override
  Future<bool> cancel(String requestId) {
    events.add('cancel');
    cancelIds.add(requestId);
    return onCancel?.call(requestId) ?? Future.value(true);
  }
}
