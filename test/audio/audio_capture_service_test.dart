import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('original audio service', () {
    late Directory directory;
    late _Store store;
    late _Provider provider;
    late AudioCaptureService service;

    setUp(() async {
      // Given a fresh test-owned filesystem directory and inert providers.
      directory = await Directory.systemTemp.createTemp('core-audio-service-');
      // When a service borrows the durable store and controlled providers.
      store = _Store(FileCaptureStore(directory.path));
      provider = _Provider();
      service = AudioCaptureService(
        runtime: provider,
        transcription: provider,
        store: store,
        now: () => _time,
      );
      // Then construction performs no recording, inference, download or import.
      expect(await directory.exists(), isTrue);
      expect(provider.starts + provider.prepares + provider.inputs.length, 0);
      expect(store.imports, 0);
    });

    tearDown(() async {
      // Given the borrowed service and its test-owned storage directory.
      // When service cleanup finishes and that exact test directory is removed.
      await service.dispose();
      await directory.delete(recursive: true);
      // Then the fixture leaves no owned files or provider ownership claim.
      expect(await directory.exists(), isFalse);
      expect(service.state, AudioCaptureState.disposed);
    });

    test('record-stop saves identical WAV before success and survives store restart', () async {
      // Given a canonical runtime original and an explicit one-second limit.
      final expected = provider.captured.bytes;
      // When recording starts, explicitly stops and a restarted store reads it.
      await service.startRecording(
        configuration: AudioRecordingConfiguration(maxDurationSeconds: 1),
      );
      expect(service.state, AudioCaptureState.recording);
      final original = await service.stopRecording();
      final reopened = FileCaptureStore(directory.path);
      final read = await reopened.readMaterial(original.material);
      // Then exact durable bytes and sample-derived provenance precede reference success.
      expect(read, orderedEquals(expected));
      expect(store.imports, 1);
      expect(store.saved.single, original.material);
      expect(original.durationMilliseconds, 1000);
      expect(original.material.mediaType, 'audio/wav');
      expect(original.material.capturedAt, _time);
      expect(original.material.originalName, 'source.wav');
      expect(provider.limit, 1);
      expect(service.pendingOriginal, isNull);
      expect(service.state, AudioCaptureState.idle);
    });

    test('cancel imports nothing and releases recording guard', () async {
      // Given an explicitly started original recording.
      await service.startRecording();
      // When the caller cancels and starts a fresh recording afterward.
      await service.cancelRecording();
      await service.startRecording();
      await service.cancelRecording();
      // Then neither cancelled recording creates a durable original or stale state.
      expect(store.imports, 0);
      expect(provider.starts, 2);
      expect(provider.recordingCancels, 2);
      expect(service.pendingOriginal, isNull);
      expect(service.state, AudioCaptureState.idle);
      expect(await directory.list().toList(), isEmpty);
    });

    test(
      'failed import retains exact bytes and retry does not recapture',
      () async {
        // Given an explicit recording and a real observable import failure.
        store.importError = const FileSystemException('storage unavailable');
        await service.startRecording();
        // When stop fails, another start/cancel is attempted and import is retried.
        await expectLater(
          service.stopRecording(),
          throwsA(isA<FileSystemException>()),
        );
        final pending = service.pendingOriginal!;
        expect(() => service.startRecording(), throwsStateError);
        expect(() => service.cancelRecording(), throwsStateError);
        pending.bytes[44] = 9;
        store.importError = null;
        final original = await service.retryPendingOriginal();
        // Then the same immutable capture persists without another microphone operation.
        expect(provider.starts, 1);
        expect(provider.stops, 1);
        expect(store.imports, 2);
        expect(
          await store.readMaterial(original.material),
          orderedEquals(provider.captured.bytes),
        );
        expect(service.pendingOriginal, isNull);
        expect(service.state, AudioCaptureState.idle);
      },
    );

    test('unsupported recording and actual permission errors are observable without fake IO', () async {
      // Given unsupported runtime capability, then an actual permission failure.
      provider.supported = false;
      // When recording is requested on both unsupported and denied branches.
      expect(
        () => service.startRecording(),
        throwsA(
          isA<AudioProviderException>().having(
            (error) => error.code,
            'code',
            'unsupported',
          ),
        ),
      );
      provider.supported = true;
      provider.startError = AudioProviderException(
        'permissionDenied',
        'actual permission denial',
      );
      await expectLater(
        service.startRecording(),
        throwsA(
          isA<AudioProviderException>().having(
            (error) => error.message,
            'message',
            'actual permission denial',
          ),
        ),
      );
      // Then no unsupported/denied operation imports bytes or pretends recording success.
      expect(provider.starts, 1);
      expect(store.imports, 0);
      expect(service.state, AudioCaptureState.idle);
    });

    test('malformed runtime WAV is rejected before store import', () async {
      // Given a runtime stop which returns a truncated non-WAV original.
      provider.captured = CapturedAudio(
        bytes: Uint8List.fromList([1, 2, 3]),
        capturedAt: _time,
      );
      await service.startRecording();
      // When the caller explicitly stops recording.
      await expectLater(service.stopRecording(), throwsFormatException);
      // Then invalid audio cannot become a durable material reference or retry original.
      expect(store.imports, 0);
      expect(service.pendingOriginal, isNull);
      expect(service.state, AudioCaptureState.idle);
    });

    test('shared guard rejects overlaps and store callback reentrancy', () async {
      // Given an original and an active recording held beyond start completion.
      final original = await _capture(service);
      await service.startRecording();
      // When every ordinary operation and a synchronous save callback tries another start.
      expect(() => service.startRecording(), throwsStateError);
      expect(() => service.playOriginal(original), throwsStateError);
      expect(() => service.transcribe(original), throwsStateError);
      expect(() => service.prepareTranscription(), throwsStateError);
      expect(() => service.availability(), throwsStateError);
      var reentrantBlocked = false;
      store.onImport = () {
        // Given a callback during the still-held durable-save boundary.
        expect(service.state, AudioCaptureState.saving);
        // When it attempts a second recording synchronously.
        expect(() => service.startRecording(), throwsStateError);
        // Then the operation guard rejects it before runtime work.
        reentrantBlocked = true;
      };
      await service.stopRecording();
      // Then recording/save remain exclusive even through provider/store callbacks.
      expect(reentrantBlocked, isTrue);
      expect(provider.starts, 2);
      expect(service.state, AudioCaptureState.idle);
    });

    test('saved-input repeated ASR uses exact original bytes locale and no reimport', () async {
      // Given a durable original and a backward wall clock clamped by provenance.
      final original = await _capture(service);
      service = AudioCaptureService(
        runtime: provider,
        transcription: provider,
        store: store,
        now: () => _time.subtract(const Duration(days: 1)),
      );
      // When that same saved original is recognized twice with the exact requested locale.
      final first = await service.transcribe(original, locale: 'en-US');
      final second = await service.transcribe(original, locale: 'en-US');
      // Then inputs share original provenance/exact bytes, identities differ and clocks cannot regress.
      expect(store.imports, 1);
      expect(provider.starts, 1);
      expect(provider.inputs.length, 2);
      for (final input in provider.inputs) {
        expect(input.original, same(original));
        expect(input.bytes, orderedEquals(provider.captured.bytes));
        expect(input.locale, 'en-US');
      }
      expect(first.text, ' 日本語 \n');
      expect(second.text, first.text);
      expect(first.status, AudioTranscriptStatus.success);
      expect(first.providerId, provider.id);
      expect(first.locale, 'en-US');
      expect(first.id, matches(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$'));
      expect(first.id, isNot(second.id));
      expect(first.startedAt, original.material.capturedAt);
      expect(first.completedAt.isBefore(first.startedAt), isFalse);
      expect(second.startedAt.isBefore(first.completedAt), isFalse);
      expect(first.elapsedMilliseconds, greaterThanOrEqualTo(0));
      expect(store.documentWrites, 0);
    });

    test('provider failure and unavailable outcomes retain actual diagnostics and current text', () async {
      // Given saved audio, selected manual text and an actual provider failure.
      final original = await _capture(service);
      final current = AudioTranscriptReview(original: original)
          .correct('mine', recordedAt: _time);
      provider.transcribeError = AudioProviderException(
        'actualFailure',
        ' 実際の失敗 ',
      );
      // When inference fails and the same provider later reports unavailable.
      final failed = await service.transcribe(original);
      provider.ready = AudioProviderState.unavailable;
      final unavailable = await service.transcribe(original);
      final review = current.appendReport(failed).appendReport(unavailable);
      // Then typed failures preserve original/current text and never synthesize success.
      expect(failed.status, AudioTranscriptStatus.failed);
      expect(failed.text, isNull);
      expect(failed.errorCode, 'actualFailure');
      expect(failed.errorMessage, ' 実際の失敗 ');
      expect(unavailable.status, AudioTranscriptStatus.unavailable);
      expect(unavailable.errorMessage, 'actual readiness diagnostic');
      expect(provider.inputs.length, 1);
      expect(review.currentText, 'mine');
      expect(review.original, original);
      expect(
        await store.readMaterial(original.material),
        orderedEquals(provider.captured.bytes),
      );
    });

    test('store input and nonprovider exceptions propagate without fabricated failure reports', () async {
      // Given saved audio and failures outside the provider diagnostic contract.
      final original = await _capture(service);
      store.readError = const FileSystemException('original missing');
      // When storage fails, inconsistent bytes return, or a provider throws a programming error.
      await expectLater(
        service.transcribe(original),
        throwsA(isA<FileSystemException>()),
      );
      store.readError = null;
      store.readReplacement = Uint8List(1);
      await expectLater(service.transcribe(original), throwsFormatException);
      store.readReplacement = null;
      provider.transcribeError = StateError('unexpected provider bug');
      await expectLater(service.transcribe(original), throwsStateError);
      // Then invalid input never reaches inference and nonprovider failures remain exceptions.
      expect(provider.inputs.length, 1);
      expect(store.imports, 1);
      expect(service.state, AudioCaptureState.idle);
    });

    test('playback receives exact saved bytes and missing read fails before runtime work', () async {
      // Given a durable original and a controlled playback completion gate.
      final original = await _capture(service);
      provider.playGate = Completer<void>();
      // When playback is requested, stopped explicitly, then the original becomes unreadable.
      final playback = service.playOriginal(original);
      final cancelled = expectLater(playback, throwsStateError);
      await provider.playEntered.future;
      expect(service.state, AudioCaptureState.playing);
      expect(() => service.transcribe(original), throwsStateError);
      await service.stopPlayback();
      await cancelled;
      store.readError = const FileSystemException('original missing');
      await expectLater(
        service.playOriginal(original),
        throwsA(isA<FileSystemException>()),
      );
      // Then playback uses original bytes without import/model work and absence never reaches runtime.
      expect(provider.played.single, orderedEquals(provider.captured.bytes));
      expect(provider.playStops, 1);
      expect(provider.played.length, 1);
      expect(store.imports, 1);
      expect(provider.prepares + provider.inputs.length, 0);
      expect(service.state, AudioCaptureState.idle);
    });

    test('explicit preparation excludes record play and inference until completion', () async {
      // Given saved audio and a delayed explicit model preparation.
      final original = await _capture(service);
      provider.prepareGate = Completer<void>();
      // When preparation is held while other ordinary operations are attempted.
      final preparing = service.prepareTranscription(locale: 'ja-JP');
      await provider.prepareEntered.future;
      expect(() => service.startRecording(), throwsStateError);
      expect(() => service.playOriginal(original), throwsStateError);
      expect(() => service.transcribe(original), throwsStateError);
      provider.prepareGate!.complete();
      final ready = await preparing;
      // Then only the explicit preparation ran and the shared guard reopens afterward.
      expect(ready.state, AudioProviderState.available);
      expect(provider.prepares, 1);
      expect(provider.inputs, isEmpty);
      expect(service.state, AudioCaptureState.idle);
    });

    test('cancel during delayed start rejects late success and permits a fresh recording', () async {
      // Given a native start future whose success is deliberately delayed.
      provider.startGate = Completer<void>();
      // When cancel interrupts that start and native work later completes.
      final starting = service.startRecording();
      final rejected = expectLater(starting, throwsStateError);
      await provider.startEntered.future;
      await service.cancelRecording();
      await rejected;
      provider.startGate = null;
      await service.startRecording();
      await service.cancelRecording();
      // Then stale start cannot publish success, and cleanup releases the guard.
      expect(provider.starts, 2);
      expect(provider.recordingCancels, 2);
      expect(store.imports, 0);
      expect(service.state, AudioCaptureState.idle);
    });

    test('dispose during delayed transcription rejects late success and preserves borrowed ownership', () async {
      // Given borrowed providers and a saved-input inference held in native work.
      final original = await _capture(service);
      provider.transcribeGate = Completer<void>();
      // When disposal cancels native work and its delayed final result arrives.
      final recognizing = service.transcribe(original);
      final rejected = expectLater(recognizing, throwsStateError);
      await provider.transcribeEntered.future;
      final disposal = service.dispose();
      expect(service.dispose(), same(disposal));
      await disposal;
      await rejected;
      // Then no late success escapes, cleanup runs and borrowed providers remain owned by caller.
      expect(service.state, AudioCaptureState.disposed);
      expect(provider.transcriptionCancels, 1);
      expect(provider.disposals, 0);
      expect(() => service.startRecording(), throwsStateError);
      expect(() => service.transcribe(original), throwsStateError);
      expect(
        await store.readMaterial(original.material),
        orderedEquals(provider.captured.bytes),
      );
    });

    test('dispose while saving disallows late reference success and awaits durable IO', () async {
      // Given explicit recording and a durable-import operation delayed by storage.
      await service.startRecording();
      store.saveGate = Completer<void>();
      // When stop begins import, disposal becomes terminal, and IO later finishes.
      final stopping = service.stopRecording();
      final rejected = expectLater(stopping, throwsStateError);
      await store.saveEntered.future;
      var completed = false;
      final disposal = service.dispose().then((_) => completed = true);
      expect(completed, isFalse);
      store.saveGate!.complete();
      await disposal;
      await rejected;
      // Then disposal awaits storage cleanup and no stale original reference is published.
      expect(completed, isTrue);
      expect(store.saved.length, 1);
      expect(service.state, AudioCaptureState.disposed);
      expect(provider.recordingCancels, 1);
      expect(provider.disposals, 0);
    });

    test('actual Android adapter disposal during durable save awaits IO without idle cleanup failure', () async {
      // Given the actual default adapter, a mocked channel and delayed durable storage.
      const channel = MethodChannel('org.textus.flutter.core/audio');
      final native = _ServiceNativeProtocol();
      final adapter = AndroidAudioProvider(channel: channel, isAndroid: true);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, native.respond);
      service = AudioCaptureService(
        runtime: adapter,
        transcription: adapter,
        store: store,
        ownsProviders: true,
      );
      addTearDown(() async {
        // Given this test's owned service and channel registration.
        // When terminal service cleanup completes and its mock is removed.
        await service.dispose();
        messenger.setMockMethodCallHandler(channel, null);
        // Then repeated cleanup remains terminal without leaving a channel fixture.
        expect(service.state, AudioCaptureState.disposed);
      });
      await service.startRecording();
      store.saveGate = Completer<void>();
      // When stop has returned native bytes, disposal overlaps their durable save.
      final stopping = service.stopRecording();
      final rejected = expectLater(stopping, throwsStateError);
      await store.saveEntered.future;
      var disposed = false;
      final disposal = service.dispose().then((_) => disposed = true);
      expect(disposed, isFalse);
      expect(service.state, AudioCaptureState.disposed);
      expect(native.calls.map((call) => call.method), [
        'startRecording',
        'stopRecording',
      ]);
      store.saveGate!.complete();
      await disposal;
      await rejected;
      // Then idle adapter cleanup succeeds, IO finishes exactly and no late reference is published.
      expect(disposed, isTrue);
      expect(store.imports, 1);
      expect(store.saved.length, 1);
      expect(
        await store.readMaterial(store.saved.single),
        orderedEquals(_wave()),
      );
      expect(service.pendingOriginal!.bytes, orderedEquals(_wave()));
      expect(native.calls.map((call) => call.method), [
        'startRecording',
        'stopRecording',
        'dispose',
      ]);
    });

    test('actual Android adapter disposal before playback read awaits IO and never starts playback', () async {
      // Given an exact durable original and the actual default adapter with a mocked channel.
      const channel = MethodChannel('org.textus.flutter.core/audio');
      final native = _ServiceNativeProtocol();
      final adapter = AndroidAudioProvider(channel: channel, isAndroid: true);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, native.respond);
      service = AudioCaptureService(
        runtime: adapter,
        transcription: adapter,
        store: store,
        ownsProviders: true,
      );
      addTearDown(() async {
        // Given this test's owned adapter service and native mock registration.
        // When repeated terminal cleanup completes and the channel fixture is removed.
        await service.dispose();
        messenger.setMockMethodCallHandler(channel, null);
        // Then no fixture work can reopen the disposed service.
        expect(service.state, AudioCaptureState.disposed);
      });
      final original = await _capture(service);
      store.readGate = Completer<void>();
      // When playback awaits the original read and disposal precedes its completion.
      final playback = service.playOriginal(original);
      final rejected = expectLater(playback, throwsStateError);
      await store.readEntered.future;
      var disposed = false;
      final disposal = service.dispose().then((_) => disposed = true);
      expect(disposed, isFalse);
      expect(native.calls.map((call) => call.method), [
        'startRecording',
        'stopRecording',
      ]);
      store.readGate!.complete();
      await disposal;
      await rejected;
      // Then idle stop cleanup has no channel effect, no stale play begins and saved bytes stay exact.
      expect(disposed, isTrue);
      expect(service.state, AudioCaptureState.disposed);
      expect(store.imports, 1);
      expect(
        await store.readMaterial(original.material),
        orderedEquals(_wave()),
      );
      expect(native.calls.map((call) => call.method), [
        'startRecording',
        'stopRecording',
        'dispose',
      ]);
    });

    test('CANCEL-1 invalid and duplicate cancellation preserves original and guards', () async {
      // Given idle, recording, saving, playing and pending-original contexts.
      expect(() => service.cancelTranscription(), throwsStateError);
      await service.startRecording();
      expect(() => service.cancelTranscription(), throwsStateError);
      store.saveGate = Completer<void>();
      final saving = service.stopRecording();
      await store.saveEntered.future;
      expect(() => service.cancelTranscription(), throwsStateError);
      store.saveGate!.complete();
      final original = await saving;
      provider.playGate = Completer<void>();
      final playing = service.playOriginal(original);
      final playRejected = expectLater(playing, throwsStateError);
      await provider.playEntered.future;
      expect(() => service.cancelTranscription(), throwsStateError);
      await service.stopPlayback();
      await playRejected;
      await service.startRecording();
      store.importError = StateError('held original');
      await expectLater(
        service.stopRecording(),
        throwsA(same(store.importError)),
      );
      final pending = service.pendingOriginal;
      expect(() => service.cancelTranscription(), throwsStateError);
      store.importError = null;
      await service.retryPendingOriginal();
      provider.availabilityGate = Completer<void>();
      provider.cancelGate = Completer<void>();
      // When an owned readiness check is cancelled and a duplicate is attempted.
      final checking = service.availability();
      final rejected = expectLater(checking, throwsStateError);
      final cancelling = service.cancelTranscription();
      expect(() => service.cancelTranscription(), throwsStateError);
      provider.cancelGate!.complete();
      await cancelling;
      await rejected;
      await service.dispose();
      // Then rejected contexts did no provider cancellation and disposal stays terminal.
      expect(provider.transcriptionCancels, 1);
      expect(pending!.bytes, orderedEquals(provider.captured.bytes));
      expect(() => service.cancelTranscription(), throwsStateError);
      expect(provider.disposals, 0);
    });

    test('CANCEL-2 delayed probe and preparation cancel nonterminally and reuse provider', () async {
      // Given an explicitly held capability check with no model preparation.
      provider.availabilityGate = Completer<void>();
      final checking = service.availability();
      final checkRejected = expectLater(checking, throwsStateError);
      // When cancellation settles the probe and then a held preparation.
      await service.cancelTranscription();
      await checkRejected;
      provider.availabilityGate = null;
      provider.prepareGate = Completer<void>();
      final preparing = service.prepareTranscription();
      final prepareRejected = expectLater(preparing, throwsStateError);
      await provider.prepareEntered.future;
      await service.cancelTranscription();
      await prepareRejected;
      final ready = await service.availability();
      // Then no stale readiness escapes, provider is reusable and never disposed.
      expect(ready.state, AudioProviderState.available);
      expect(provider.transcriptionCancels, 2);
      expect(provider.prepares, 1);
      expect(provider.disposals, 0);
      expect(service.state, AudioCaptureState.idle);
    });

    test('CANCEL-3 held saved-input recognition returns no report and reuses original', () async {
      // Given one actual durable original and a held saved-input ASR operation.
      final original = await _capture(service);
      provider.transcribeGate = Completer<void>();
      final recognizing = service.transcribe(original);
      final rejected = expectLater(recognizing, throwsStateError);
      await provider.transcribeEntered.future;
      // When explicit cancellation settles inference and later recognition succeeds.
      await service.cancelTranscription();
      await rejected;
      final report = await service.transcribe(original);
      // Then the same exact original works with no reimport, recapture or disposal.
      expect(report.original, same(original));
      expect(report.text, ' 日本語 \n');
      expect(store.imports, 1);
      expect(provider.starts, 1);
      expect(
        provider.inputs.every((input) => identical(input.original, original)),
        isTrue,
      );
      expect(provider.transcriptionCancels, 1);
      expect(provider.disposals, 0);
    });

    test(
      'CANCEL-4 pending original read settles without launching inference',
      () async {
        // Given exact saved bytes and a held original read before recognition starts.
        final original = await _capture(service);
        store.readGate = Completer<void>();
        final recognizing = service.transcribe(original);
        final rejected = expectLater(recognizing, throwsStateError);
        await store.readEntered.future;
        // When cancellation waits for that read even after provider cleanup.
        var finished = false;
        final cancelling = service.cancelTranscription().then(
          (_) => finished = true,
        );
        await Future<void>.delayed(Duration.zero);
        expect(finished, isFalse);
        expect(() => service.availability(), throwsStateError);
        store.readGate!.complete();
        await cancelling;
        await rejected;
        // Then no inference launches and the original remains durably exact.
        expect(provider.inputs, isEmpty);
        expect(
          await store.readMaterial(original.material),
          orderedEquals(provider.captured.bytes),
        );
        expect(store.imports, 1);
        expect(finished, isTrue);
      },
    );

    test('CANCEL-5 cleanup failure retains identity and stack and awaits prior settlement', () async {
      // Given a held readiness check and a cleanup failure with a distinctive stack.
      provider.availabilityGate = Completer<void>();
      provider.releaseOnCancel = false;
      final failure = StateError('actual cancellation failure');
      final failureStack = StackTrace.fromString(
        'controlled cancellation stack',
      );
      provider.cancelError = failure;
      provider.cancelStack = failureStack;
      final checking = service.availability();
      final rejected = expectLater(checking, throwsStateError);
      var settled = false;
      Object? caught;
      StackTrace? caughtStack;
      // When cleanup fails before the prior check is allowed to finish.
      final cancelling = service.cancelTranscription().then<void>(
        (_) => settled = true,
        onError: (Object error, StackTrace stack) {
          caught = error;
          caughtStack = stack;
          settled = true;
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(settled, isFalse);
      expect(() => service.availability(), throwsStateError);
      expect(() => service.cancelTranscription(), throwsStateError);
      provider.availabilityGate!.complete();
      await cancelling;
      await rejected;
      provider.cancelError = null;
      final ready = await service.availability();
      // Then the first actual failure/stack survives and ordinary work resumes after settlement.
      expect(caught, same(failure));
      expect(caughtStack.toString(), failureStack.toString());
      expect(ready.state, AudioProviderState.available);
      expect(provider.disposals, 0);
      expect(provider.transcriptionCancels, 1);
    });

    test('CANCEL-6 terminal disposal during cancellation never reopens service', () async {
      // Given a held check and held cancellation on borrowed dependencies.
      provider.availabilityGate = Completer<void>();
      provider.cancelGate = Completer<void>();
      final checking = service.availability();
      final checkRejected = expectLater(checking, throwsStateError);
      final cancelling = service.cancelTranscription();
      final cancelRejected = expectLater(cancelling, throwsStateError);
      // When terminal disposal overlaps cleanup and all pending gates complete.
      final disposal = service.dispose();
      provider.cancelGate!.complete();
      await disposal;
      await checkRejected;
      await cancelRejected;
      // Then neither completion publishes success or restores idle/provider ownership.
      expect(service.state, AudioCaptureState.disposed);
      expect(() => service.availability(), throwsStateError);
      expect(provider.disposals, 0);
      expect(provider.transcriptionCancels, 2);
    });

    test('owned identical provider is disposed once while borrowed defaults stay inert', () async {
      // Given a shared owned runtime/transcriber and inert unsupported default factory.
      service = AudioCaptureService(
        runtime: provider,
        transcription: provider,
        store: store,
        ownsProviders: true,
      );
      // When repeated service disposal and explicit default creation occur.
      final first = service.dispose();
      final second = service.dispose();
      await first;
      await second;
      final defaults = await openDefaultAudioCaptureService(store: store);
      final readiness = await defaults.availability();
      await defaults.dispose();
      // Then shared ownership closes exactly once and factory/probe performs no storage work.
      expect(first, same(second));
      expect(provider.disposals, 1);
      expect(readiness.state, AudioProviderState.unavailable);
      expect(store.imports, 0);
      expect(store.documentWrites, 0);
    });
  });
}

final _time = DateTime.utc(2026, 10, 9);
Uint8List _wave() => PcmWaveAudio.encode(
  Uint8List.fromList(List.generate(32000, (index) => index % 256)),
);

Future<OriginalAudio> _capture(AudioCaptureService service) async {
  // Given an idle service and a controlled original recording provider.
  expect(service.state, AudioCaptureState.idle);
  // When recording explicitly starts and stops through durable import.
  await service.startRecording();
  final original = await service.stopRecording();
  // Then callers receive an audio reference only after the guard returns idle.
  expect(original.material.mediaType, 'audio/wav');
  expect(original.durationMilliseconds, 1000);
  expect(service.state, AudioCaptureState.idle);
  return original;
}

final class _Provider
    implements AudioRuntimeProvider, AudioTranscriptionProvider {
  bool supported = true;
  CapturedAudio captured = CapturedAudio(
    bytes: _wave(),
    capturedAt: _time,
    originalName: 'source.wav',
  );
  AudioProviderState ready = AudioProviderState.available;
  Completer<void>? availabilityGate;
  Completer<void>? cancelGate;
  Object? cancelError;
  StackTrace? cancelStack;
  bool releaseOnCancel = true;
  Object? startError;
  Object? transcribeError;
  Completer<void>? startGate;
  Completer<void>? playGate;
  Completer<void>? prepareGate;
  Completer<void>? transcribeGate;
  final startEntered = Completer<void>();
  final playEntered = Completer<void>();
  final prepareEntered = Completer<void>();
  final transcribeEntered = Completer<void>();
  final inputs = <AudioTranscriptionInput>[];
  final played = <Uint8List>[];
  int starts = 0;
  int stops = 0;
  int recordingCancels = 0;
  int playStops = 0;
  int prepares = 0;
  int transcriptionCancels = 0;
  int disposals = 0;
  int? limit;
  @override
  String get id => 'controlled-provider';
  @override
  bool get isSupported => supported;

  @override
  Future<void> startRecording(AudioRecordingConfiguration configuration) async {
    // Given an explicit recording configuration delivered to this controlled runtime.
    expect(configuration.maxDurationSeconds, inInclusiveRange(1, 120));
    // When native start is recorded and optionally held or failed.
    starts++;
    limit = configuration.maxDurationSeconds;
    if (!startEntered.isCompleted) startEntered.complete();
    if (startGate != null) await startGate!.future;
    if (startError != null) throw startError!;
    // Then successful controlled starts preserve the caller's duration exactly.
    expect(limit, configuration.maxDurationSeconds);
  }

  @override
  Future<CapturedAudio> stopRecording() async {
    // Given a prior explicit start and the provider's controlled original.
    expect(starts, greaterThan(0));
    // When explicit stop returns the existing capture without another start.
    stops++;
    // Then the same snapshot object carries the runtime result.
    expect(stops, lessThanOrEqualTo(starts));
    return captured;
  }

  @override
  Future<void> cancelRecording() async {
    // Given a caller cleanup request, including disposal during save.
    // When pending starts are unblocked and cancellation is counted.
    recordingCancels++;
    if (startGate != null && !startGate!.isCompleted) startGate!.complete();
    // Then the cancellation is observable and cannot import material itself.
    expect(recordingCancels, greaterThan(0));
    expect(startGate == null || startGate!.isCompleted, isTrue);
  }

  @override
  Future<void> play(Uint8List bytes) async {
    // Given exact canonical saved bytes delivered by the service.
    expect(PcmWaveAudio.parse(bytes).durationMilliseconds, 1000);
    // When playback snapshots bytes and remains active until its gate completes.
    played.add(Uint8List.fromList(bytes));
    if (!playEntered.isCompleted) playEntered.complete();
    if (playGate != null) await playGate!.future;
    // Then the controlled player retains the exact invocation snapshot.
    expect(played.last, orderedEquals(bytes));
  }

  @override
  Future<void> stopPlayback() async {
    // Given an active controlled playback operation.
    expect(played, isNotEmpty);
    // When the explicit stop releases its completion gate.
    playStops++;
    if (playGate != null && !playGate!.isCompleted) playGate!.complete();
    // Then the stop is counted and playback is unblocked.
    expect(playStops, greaterThan(0));
    expect(playGate == null || playGate!.isCompleted, isTrue);
  }

  @override
  Future<AudioProviderAvailability> availability(String locale) async {
    // Given the current exact-locale readiness of the controlled provider.
    // When capability is inspected without changing model readiness.
    if (availabilityGate != null) await availabilityGate!.future;
    final result = AudioProviderAvailability(
      providerId: id,
      locale: locale,
      state: ready,
      reason: ready == AudioProviderState.available
          ? null
          : 'actual readiness diagnostic',
    );
    // Then the snapshot identifies the actual provider and requested locale.
    expect(result.providerId, id);
    expect(result.locale, locale);
    return result;
  }

  @override
  Future<AudioProviderAvailability> prepare(String locale) async {
    // Given explicit preparation intent and an optional native delay.
    // When preparation is counted and its native gate completes.
    prepares++;
    if (!prepareEntered.isCompleted) prepareEntered.complete();
    if (prepareGate != null) await prepareGate!.future;
    ready = AudioProviderState.available;
    final result = await availability(locale);
    // Then only explicit preparation establishes controlled available readiness.
    expect(prepares, greaterThan(0));
    expect(result.state, AudioProviderState.available);
    return result;
  }

  @override
  Future<AudioProviderTranscript> transcribe(
    AudioTranscriptionInput input,
  ) async {
    // Given saved-input provenance delivered to the controlled ASR boundary.
    expect(input.bytes.length, input.original.material.byteLength);
    // When the input is retained and optional failure/delay is applied.
    inputs.add(input);
    if (!transcribeEntered.isCompleted) transcribeEntered.complete();
    if (transcribeGate != null) await transcribeGate!.future;
    if (transcribeError != null) throw transcribeError!;
    final result = AudioProviderTranscript(text: ' 日本語 \n');
    // Then success returns exact final text rather than a microphone acquisition.
    expect(result.text, ' 日本語 \n');
    expect(inputs.last, same(input));
    return result;
  }

  @override
  Future<void> cancel() async {
    // Given active preparation/recognition and optional cleanup delay or actual failure.
    // When explicit cleanup is counted, optionally held, and releases owned provider gates.
    transcriptionCancels++;
    if (cancelGate != null) await cancelGate!.future;
    if (releaseOnCancel) {
      for (final gate in [availabilityGate, transcribeGate, prepareGate]) {
        if (gate != null && !gate.isCompleted) gate.complete();
      }
    }
    if (cancelError != null) {
      Error.throwWithStackTrace(
        cancelError!,
        cancelStack ?? StackTrace.current,
      );
    }
    // Then cleanup is observable and enabled release leaves every native gate settled.
    expect(transcriptionCancels, greaterThan(0));
    if (releaseOnCancel) {
      expect(availabilityGate == null || availabilityGate!.isCompleted, isTrue);
      expect(transcribeGate == null || transcribeGate!.isCompleted, isTrue);
      expect(prepareGate == null || prepareGate!.isCompleted, isTrue);
    }
  }

  @override
  Future<void> dispose() async {
    // Given explicit ownership disposal of this shared controlled provider.
    // When its disposal counter advances.
    disposals++;
    // Then the service contract must close the identical provider exactly once.
    expect(disposals, 1);
  }
}

final class _Store implements LocalCaptureStore {
  _Store(this.delegate);
  final LocalCaptureStore delegate;
  Object? importError;
  Object? readError;
  Uint8List? readReplacement;
  Completer<void>? saveGate;
  Completer<void>? readGate;
  final saveEntered = Completer<void>();
  final readEntered = Completer<void>();
  void Function()? onImport;
  final saved = <CaptureMaterialReference>[];
  int imports = 0;
  int documentWrites = 0;
  @override
  Future<CaptureMaterialReference> saveMaterial({
    required Uint8List bytes,
    required String mediaType,
    required DateTime capturedAt,
    String? originalName,
  }) async {
    // Given an exact WAV invocation and existing durable storage implementation.
    final snapshot = Uint8List.fromList(bytes);
    expect(mediaType, 'audio/wav');
    // When import intent is observed, optionally delayed/failed, then delegated to disk.
    imports++;
    onImport?.call();
    if (!saveEntered.isCompleted) saveEntered.complete();
    if (saveGate != null) await saveGate!.future;
    if (importError != null) throw importError!;
    final reference = await delegate.saveMaterial(
      bytes: snapshot,
      mediaType: mediaType,
      capturedAt: capturedAt,
      originalName: originalName,
    );
    saved.add(reference);
    // Then actual durable bytes are exact before the helper returns a reference.
    expect(await delegate.readMaterial(reference), orderedEquals(snapshot));
    expect(reference.byteLength, snapshot.length);
    return reference;
  }

  @override
  Future<Uint8List> readMaterial(CaptureMaterialReference reference) async {
    // Given logical audio provenance and an optional real read/input failure.
    expect(reference.mediaType, 'audio/wav');
    // When saved bytes are optionally held by a read gate, without importing a replacement.
    if (readGate != null) {
      if (!readEntered.isCompleted) readEntered.complete();
      await readGate!.future;
    }
    if (readError != null) throw readError!;
    if (readReplacement != null) return Uint8List.fromList(readReplacement!);
    final bytes = await delegate.readMaterial(reference);
    // Then ordinary durable reads match the reference length.
    expect(bytes.length, reference.byteLength);
    return bytes;
  }

  @override
  Future<void> saveDocument(
    String collection,
    String id,
    Map<String, Object?> document,
  ) async {
    // Given an explicit opaque-document write independent of audio report return.
    // When the existing durable store is used by a caller.
    documentWrites++;
    await delegate.saveDocument(collection, id, document);
    // Then the document write is real and observable through its existing boundary.
    expect(await delegate.readDocument(collection, id), document);
  }

  @override
  Future<Map<String, Object?>?> readDocument(
    String collection,
    String id,
  ) async {
    // Given caller-owned logical document collection and identity.
    // When the unchanged existing store reads the opaque document.
    final document = await delegate.readDocument(collection, id);
    // Then absent data is null and any returned document has string JSON keys.
    expect(document, anyOf(isNull, isA<Map<String, Object?>>()));
    return document;
  }

  @override
  Future<List<String>> listDocumentIds(String collection) async {
    // Given a caller-owned opaque document collection.
    // When its existing durable store lists retained identities.
    final ids = await delegate.listDocumentIds(collection);
    // Then the result remains sorted and contains safe logical identities.
    expect(ids, orderedEquals(List<String>.of(ids)..sort()));
    for (final id in ids) {
      expect(id, matches(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$'));
    }
    return ids;
  }
}

final class _ServiceNativeProtocol {
  final calls = <MethodCall>[];
  String? sessionId;

  Future<Object?> respond(MethodCall call) async {
    // Given a real encoded invocation from the default Android adapter.
    final arguments = call.arguments as Map;
    final session = arguments['sessionId'];
    expect(session, matches(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$'));
    sessionId ??= session as String;
    // When the fixture records explicit recording, stop and terminal disposal responses.
    calls.add(call);
    final expectedKeys = <String>{
      'sessionId',
      if (call.method == 'startRecording') 'maxDurationSeconds',
    };
    // Then only this adapter's session and exact method arguments cross the channel.
    expect(session, sessionId);
    expect(arguments.keys.toSet(), expectedKeys);
    if (call.method == 'startRecording') {
      expect(arguments['maxDurationSeconds'], 120);
      return null;
    }
    if (call.method == 'stopRecording') {
      return {
        'bytes': _wave(),
        'capturedAt': _time.toIso8601String(),
        'originalName': 'source.wav',
      };
    }
    if (call.method == 'dispose') return null;
    throw StateError(
      'Unexpected native work during delayed storage: ${call.method}',
    );
  }
}
