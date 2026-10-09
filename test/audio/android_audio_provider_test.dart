import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

// Protocol mocks below make no Android microphone, hardware or model claim.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.textus.flutter.core/audio');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _NativeProtocol native;

  setUp(() {
    native = _NativeProtocol();
    messenger.setMockMethodCallHandler(channel, native.respond);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('Android audio channel protocol', () {
    test('failed pending recording cleanup still disposes natively once and retains its error', () async {
      // Given a real adapter with pending native stop and a gated failing recording cancel.
      final provider = AndroidAudioProvider(channel: channel, isAndroid: true);
      await provider.startRecording(AudioRecordingConfiguration());
      native.gateMethod = 'stopRecording';
      native.gate = Completer<void>();
      native.cleanupGateMethod = 'cancelRecording';
      native.cleanupGate = Completer<void>();
      native.failureMethod = 'cancelRecording';
      native.failure = PlatformException(
        code: 'recordingCleanupFailed',
        message: 'actual recording cleanup failure',
      );
      final stopping = provider.stopRecording();
      final oldRejected = expectLater(stopping, throwsStateError);
      await native.entered.future;
      // When cancellation and repeated terminal disposal wait for the failing cleanup response.
      final cleanup = provider.cancelRecording();
      final cleanupRejected = expectLater(
        cleanup,
        throwsA(
          isA<AudioProviderException>()
              .having((error) => error.code, 'code', 'recordingCleanupFailed')
              .having(
                (error) => error.message,
                'message',
                'actual recording cleanup failure',
              ),
        ),
      );
      await native.cleanupEntered.future;
      var settled = false;
      final disposal = provider.dispose();
      expect(provider.dispose(), same(disposal));
      final disposalRejected = expectLater(
        disposal.whenComplete(() => settled = true),
        throwsA(
          isA<AudioProviderException>()
              .having((error) => error.code, 'code', 'recordingCleanupFailed')
              .having(
                (error) => error.message,
                'message',
                'actual recording cleanup failure',
              ),
        ),
      );
      expect(settled, isFalse);
      expect(native.calls.where((call) => call.method == 'dispose'), isEmpty);
      native.cleanupGate!.complete();
      await cleanupRejected;
      await disposalRejected;
      await oldRejected;
      // Then failure remains observable, old capture cannot succeed and native dispose still runs once.
      expect(settled, isTrue);
      expect(provider.dispose(), same(disposal));
      expect(native.calls.map((call) => call.method), [
        'startRecording',
        'stopRecording',
        'cancelRecording',
        'dispose',
      ]);
      expect(() => provider.cancelRecording(), throwsStateError);
      expect(
        () => provider.startRecording(AudioRecordingConfiguration()),
        throwsStateError,
      );
    });

    test('failed pending playback cleanup still disposes natively once and retains its error', () async {
      // Given real adapter playback and a gated native stop that fails with actual diagnostics.
      final provider = AndroidAudioProvider(channel: channel, isAndroid: true);
      native.gateMethod = 'play';
      native.gate = Completer<void>();
      native.cleanupGateMethod = 'stopPlayback';
      native.cleanupGate = Completer<void>();
      native.failureMethod = 'stopPlayback';
      native.failure = PlatformException(
        code: 'playbackCleanupFailed',
        message: 'actual playback cleanup failure',
      );
      final playing = provider.play(_wave());
      final oldRejected = expectLater(playing, throwsStateError);
      await native.entered.future;
      // When stop and repeated disposal overlap before the failing cleanup gate is released.
      final cleanup = provider.stopPlayback();
      final cleanupRejected = expectLater(
        cleanup,
        throwsA(
          isA<AudioProviderException>()
              .having((error) => error.code, 'code', 'playbackCleanupFailed')
              .having(
                (error) => error.message,
                'message',
                'actual playback cleanup failure',
              ),
        ),
      );
      await native.cleanupEntered.future;
      var settled = false;
      final disposal = provider.dispose();
      expect(provider.dispose(), same(disposal));
      final disposalRejected = expectLater(
        disposal.whenComplete(() => settled = true),
        throwsA(
          isA<AudioProviderException>()
              .having((error) => error.code, 'code', 'playbackCleanupFailed')
              .having(
                (error) => error.message,
                'message',
                'actual playback cleanup failure',
              ),
        ),
      );
      expect(settled, isFalse);
      expect(native.calls.where((call) => call.method == 'dispose'), isEmpty);
      native.cleanupGate!.complete();
      await cleanupRejected;
      await disposalRejected;
      await oldRejected;
      // Then disposal retains stop failure, rejects stale playback and attempts native disposal once.
      expect(settled, isTrue);
      expect(provider.dispose(), same(disposal));
      expect(native.calls.map((call) => call.method), [
        'play',
        'stopPlayback',
        'dispose',
      ]);
      expect(() => provider.stopPlayback(), throwsStateError);
      expect(() => provider.play(_wave()), throwsStateError);
    });

    test('idle cleanup is inert and disposed cleanup still rejects', () async {
      // Given an alive idle default adapter with a counted native channel.
      final provider = AndroidAudioProvider(channel: channel, isAndroid: true);
      // When recording and playback cleanup are requested repeatedly without active work.
      await provider.cancelRecording();
      await provider.cancelRecording();
      await provider.stopPlayback();
      await provider.stopPlayback();
      // Then cleanup has no native effects, and terminal disposal retains rejection.
      expect(native.calls, isEmpty);
      await provider.dispose();
      expect(native.calls.map((call) => call.method), ['dispose']);
      expect(() => provider.cancelRecording(), throwsStateError);
      expect(() => provider.stopPlayback(), throwsStateError);
    });

    test('cancel during delayed recording stop rejects captured success and permits fresh recording', () async {
      // Given a started recording whose native stop response is held.
      final provider = AndroidAudioProvider(channel: channel, isAndroid: true);
      await provider.startRecording(AudioRecordingConfiguration());
      native.gateMethod = 'stopRecording';
      native.gate = Completer<void>();
      // When cancellation interrupts stop before its captured bytes return.
      final stopping = provider.stopRecording();
      final rejected = expectLater(
        stopping,
        throwsA(
          isA<AudioProviderException>().having(
            (error) => error.code,
            'code',
            'cancelled',
          ),
        ),
      );
      await native.entered.future;
      expect(() => provider.availability('ja-JP'), throwsStateError);
      expect(() => provider.stopPlayback(), throwsStateError);
      await provider.cancelRecording();
      await rejected;
      native.gateMethod = null;
      await provider.startRecording(AudioRecordingConfiguration());
      await provider.cancelRecording();
      // Then the original stop cannot publish captured success and one cancel belongs to each recording.
      expect(
        native.calls.where((call) => call.method == 'stopRecording').length,
        1,
      );
      expect(
        native.calls.where((call) => call.method == 'startRecording').length,
        2,
      );
      expect(
        native.calls.where((call) => call.method == 'cancelRecording').length,
        2,
      );
      await provider.dispose();
    });

    test('equivalent recording cancels join cleanup and disposal waits before native dispose', () async {
      // Given a started recording with a deliberately delayed native cancellation.
      final provider = AndroidAudioProvider(channel: channel, isAndroid: true);
      await provider.startRecording(AudioRecordingConfiguration());
      native.cleanupGateMethod = 'cancelRecording';
      native.cleanupGate = Completer<void>();
      // When repeated cancel callers and disposal overlap the same pending cleanup.
      final first = provider.cancelRecording();
      final second = provider.cancelRecording();
      expect(second, same(first));
      await native.cleanupEntered.future;
      var disposed = false;
      final disposal = provider.dispose().then((_) => disposed = true);
      expect(
        () => provider.startRecording(AudioRecordingConfiguration()),
        throwsStateError,
      );
      expect(native.calls.where((call) => call.method == 'dispose'), isEmpty);
      expect(disposed, isFalse);
      native.cleanupGate!.complete();
      await first;
      await second;
      await disposal;
      // Then cancellation completes once without a second interrupt and terminal disposal follows it.
      expect(disposed, isTrue);
      expect(native.calls.map((call) => call.method), [
        'startRecording',
        'cancelRecording',
        'dispose',
      ]);
    });

    test('equivalent playback stops join cleanup and disposal awaits pending playback', () async {
      // Given playback and its native cleanup held by independent completion gates.
      final provider = AndroidAudioProvider(channel: channel, isAndroid: true);
      native.gateMethod = 'play';
      native.gate = Completer<void>();
      native.cleanupGateMethod = 'stopPlayback';
      native.cleanupGate = Completer<void>();
      final playing = provider.play(_wave());
      final rejected = expectLater(playing, throwsStateError);
      await native.entered.future;
      // When repeated stop callers overlap disposal before native cleanup completes.
      final first = provider.stopPlayback();
      final second = provider.stopPlayback();
      expect(second, same(first));
      await native.cleanupEntered.future;
      var disposed = false;
      final disposal = provider.dispose().then((_) => disposed = true);
      expect(native.calls.where((call) => call.method == 'dispose'), isEmpty);
      expect(disposed, isFalse);
      native.cleanupGate!.complete();
      await first;
      await second;
      await rejected;
      await disposal;
      // Then late playback is rejected, stop runs once and dispose waits for both completions.
      expect(disposed, isTrue);
      expect(native.calls.map((call) => call.method), [
        'play',
        'stopPlayback',
        'dispose',
      ]);
    });

    test('every method uses exact args and one instance session without original paths', () async {
      // Given an Android adapter, canonical saved original and valid native protocol responses.
      final provider = AndroidAudioProvider(channel: channel, isAndroid: true);
      final input = _input();
      // When callers explicitly probe, prepare, record, replay and recognize saved bytes.
      final availability = await provider.availability('ja-JP');
      final prepared = await provider.prepare('ja-JP');
      await provider.startRecording(
        AudioRecordingConfiguration(maxDurationSeconds: 2),
      );
      final captured = await provider.stopRecording();
      await provider.play(input.bytes);
      final transcript = await provider.transcribe(input);
      await provider.dispose();
      // Then exact response values and only logical session/bytes/configuration cross the bridge.
      expect(availability.state, AudioProviderState.available);
      expect(prepared.locale, 'ja-JP');
      expect(captured.bytes, orderedEquals(_wave()));
      expect(captured.capturedAt, _time);
      expect(captured.originalName, 'recording.wav');
      expect(transcript.text, ' 日本語\n ');
      expect(transcript.extensions, {
        'actual': <Object?>[1, null],
      });
      expect(native.calls.map((call) => call.method), [
        'availability',
        'prepare',
        'startRecording',
        'stopRecording',
        'play',
        'transcribe',
        'dispose',
      ]);
      final sessions = native.calls
          .map((call) => (call.arguments as Map)['sessionId'])
          .toSet();
      expect(sessions.length, 1);
      expect(sessions.single, matches(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$'));
      final transcription = native.calls.singleWhere(
        (call) => call.method == 'transcribe',
      );
      expect((transcription.arguments as Map).keys.toSet(), {
        'sessionId',
        'bytes',
        'locale',
      });
      expect(
        (transcription.arguments as Map)['bytes'],
        orderedEquals(input.bytes),
      );
      expect((native.calls[2].arguments as Map)['maxDurationSeconds'], 2);
    });

    test('per-instance sessions prevent one caller commands from identifying another', () async {
      // Given two inert adapters sharing a native channel but separate logical ownership.
      final first = AndroidAudioProvider(channel: channel, isAndroid: true);
      final second = AndroidAudioProvider(channel: channel, isAndroid: true);
      // When both inspect readiness and only the first is disposed.
      await first.availability('ja-JP');
      await second.availability('en-US');
      await first.dispose();
      final secondReady = await second.availability('en-US');
      await second.dispose();
      // Then each instance uses its unique stable session and the second remains usable.
      final firstId = (native.calls[0].arguments as Map)['sessionId'];
      final secondId = (native.calls[1].arguments as Map)['sessionId'];
      expect(firstId, isNot(secondId));
      expect((native.calls[2].arguments as Map)['sessionId'], firstId);
      expect((native.calls[3].arguments as Map)['sessionId'], secondId);
      expect(secondReady.locale, 'en-US');
      expect(secondReady.state, AudioProviderState.available);
    });

    test('nonAndroid and MissingPlugin readiness are unavailable with no fake runtime success', () async {
      // Given an unsupported platform and then an Android channel with no native registration.
      final unsupported = AndroidAudioProvider(
        channel: channel,
        isAndroid: false,
      );
      // When readiness, explicit recording and explicit preparation are requested.
      final unsupportedReady = await unsupported.availability('ja-JP');
      await expectLater(
        unsupported.startRecording(AudioRecordingConfiguration()),
        throwsA(
          isA<AudioProviderException>().having(
            (error) => error.code,
            'code',
            'unsupported',
          ),
        ),
      );
      await unsupported.dispose();
      expect(native.calls, isEmpty);
      messenger.setMockMethodCallHandler(channel, null);
      final missing = AndroidAudioProvider(channel: channel, isAndroid: true);
      final missingReady = await missing.availability('ja-JP');
      final missingPrepared = await missing.prepare('ja-JP');
      await expectLater(
        missing.startRecording(AudioRecordingConfiguration()),
        throwsA(
          isA<AudioProviderException>().having(
            (error) => error.code,
            'code',
            'missingPlugin',
          ),
        ),
      );
      await missing.dispose();
      // Then truthful capability preserves unavailable branches and explicit runtime work fails.
      expect(unsupported.isSupported, isFalse);
      expect(unsupportedReady.state, AudioProviderState.unavailable);
      expect(missingReady.state, AudioProviderState.unavailable);
      expect(missingPrepared.state, AudioProviderState.unavailable);
      expect(missingReady.reason, isNotEmpty);
    });

    test(
      'platform permission and preparation failures preserve exact diagnostics',
      () async {
        // Given actual native platform diagnostics on explicit recording/preparation.
        final provider = AndroidAudioProvider(
          channel: channel,
          isAndroid: true,
        );
        native.failureMethod = 'startRecording';
        native.failure = PlatformException(
          code: 'permissionDenied',
          message: ' 実際の権限拒否 ',
        );
        // When recording fails and preparation subsequently fails with its own diagnostics.
        await expectLater(
          provider.startRecording(AudioRecordingConfiguration()),
          throwsA(
            isA<AudioProviderException>()
                .having((error) => error.code, 'code', 'permissionDenied')
                .having((error) => error.message, 'message', ' 実際の権限拒否 '),
          ),
        );
        native.failureMethod = 'prepare';
        native.failure = PlatformException(
          code: 'downloadFailed',
          message: 'actual model failure',
        );
        await expectLater(
          provider.prepare('ja-JP'),
          throwsA(
            isA<AudioProviderException>()
                .having((error) => error.code, 'code', 'downloadFailed')
                .having(
                  (error) => error.message,
                  'message',
                  'actual model failure',
                ),
          ),
        );
        await provider.dispose();
        // Then native failures neither synthesize capture bytes nor successful readiness.
        expect(
          native.calls.where((call) => call.method == 'stopRecording'),
          isEmpty,
        );
        expect(
          native.calls.where((call) => call.method == 'transcribe'),
          isEmpty,
        );
      },
    );

    test('strict native capture rejects wrong keys types times and malformed WAV', () async {
      // Given a valid captured map and each invalid native response variant.
      final valid = _captureMap();
      final invalid = <Object?>[
        null,
        {...valid, 'unknown': 1},
        {...valid}..remove('originalName'),
        {
          ...valid,
          'bytes': <int>[1, 2],
        },
        {...valid, 'capturedAt': 1},
        {...valid, 'capturedAt': '2026-10-09T00:00:00Z'},
        {...valid, 'capturedAt': '2026-10-09T09:00:00.000+09:00'},
        {...valid, 'originalName': true},
        {...valid, 'bytes': Uint8List(2)},
      ];
      // When each response is returned to a freshly started adapter's explicit stop.
      for (final response in invalid) {
        final provider = AndroidAudioProvider(
          channel: channel,
          isAndroid: true,
        );
        native.stopResponse = response;
        await provider.startRecording(AudioRecordingConfiguration());
        // Then malformed responses fail rather than create a captured original.
        await expectLater(provider.stopRecording(), throwsFormatException);
        await provider.dispose();
      }
      expect(
        native.calls.where((call) => call.method == 'stopRecording').length,
        invalid.length,
      );
    });

    test('strict readiness and final transcript reject contradictory response values', () async {
      // Given an Android adapter and a saved-input request with exact provenance.
      final provider = AndroidAudioProvider(channel: channel, isAndroid: true);
      // When native readiness contradicts provider/locale or text output is malformed.
      for (final response in <Object?>[
        {
          'providerId': 'foreign',
          'locale': 'ja-JP',
          'state': 'available',
          'reason': null,
        },
        {
          'providerId': provider.id,
          'locale': 'en-US',
          'state': 'available',
          'reason': null,
        },
        {
          'providerId': provider.id,
          'locale': 'ja-JP',
          'state': 'success',
          'reason': null,
        },
        {
          'providerId': provider.id,
          'locale': 'ja-JP',
          'state': 'available',
          'reason': 1,
        },
      ]) {
        native.readinessOverride = response;
        await expectLater(
          provider.availability('ja-JP'),
          throwsFormatException,
        );
      }
      native.readinessOverride = null;
      for (final response in <Object?>[
        {'text': '', 'extensions': <String, Object?>{}},
        {'text': 1, 'extensions': <String, Object?>{}},
        {'text': 'real', 'extensions': <Object?>[]},
        {'text': 'real', 'extensions': <String, Object?>{}, 'partial': true},
      ]) {
        native.transcriptOverride = response;
        await expectLater(provider.transcribe(_input()), throwsFormatException);
      }
      await provider.dispose();
      // Then no readiness contradiction or blank/partial output becomes provider success.
      expect(
        native.calls.where((call) => call.method == 'transcribe').length,
        4,
      );
    });

    test('overlapping inference is rejected and explicit cancellation blocks late success', () async {
      // Given a saved-input inference held in a mocked native response.
      final provider = AndroidAudioProvider(channel: channel, isAndroid: true);
      native.gateMethod = 'transcribe';
      native.gate = Completer<void>();
      // When another operation is attempted and explicit cancellation releases native work.
      final recognizing = provider.transcribe(_input());
      final rejected = expectLater(
        recognizing,
        throwsA(
          isA<AudioProviderException>().having(
            (error) => error.code,
            'code',
            'cancelled',
          ),
        ),
      );
      await native.entered.future;
      expect(() => provider.availability('ja-JP'), throwsStateError);
      expect(
        () => provider.startRecording(AudioRecordingConfiguration()),
        throwsStateError,
      );
      expect(() => provider.play(_wave()), throwsStateError);
      await provider.cancel();
      await rejected;
      final ready = await provider.availability('ja-JP');
      await provider.dispose();
      // Then cancellation prevents stale final success and returns the bridge to usable idle state.
      expect(ready.state, AudioProviderState.available);
      expect(
        native.calls
            .where((call) => call.method == 'cancelTranscription')
            .length,
        1,
      );
      expect(
        native.calls.where((call) => call.method == 'transcribe').length,
        1,
      );
    });

    test('dispose during preparation rejects late success and sends native dispose once', () async {
      // Given delayed explicit native preparation owned by one adapter.
      final provider = AndroidAudioProvider(channel: channel, isAndroid: true);
      native.gateMethod = 'prepare';
      native.gate = Completer<void>();
      // When repeated disposal cancels preparation before its delayed readiness arrives.
      final preparing = provider.prepare('ja-JP');
      final rejected = expectLater(preparing, throwsStateError);
      await native.entered.future;
      final disposal = provider.dispose();
      expect(provider.dispose(), same(disposal));
      await disposal;
      await rejected;
      // Then exactly one native disposal occurs and terminal providers reject later operations.
      expect(native.calls.where((call) => call.method == 'dispose').length, 1);
      expect(() => provider.availability('ja-JP'), throwsStateError);
      expect(
        () => provider.startRecording(AudioRecordingConfiguration()),
        throwsStateError,
      );
    });

    test(
      'cancel during native start unblocks recording without late success',
      () async {
        // Given a delayed native recording start and explicit cancellation intent.
        final provider = AndroidAudioProvider(
          channel: channel,
          isAndroid: true,
        );
        native.gateMethod = 'startRecording';
        native.gate = Completer<void>();
        // When cancel is issued while the start response remains pending.
        final starting = provider.startRecording(AudioRecordingConfiguration());
        final rejected = expectLater(
          starting,
          throwsA(
            isA<AudioProviderException>().having(
              (error) => error.code,
              'code',
              'cancelled',
            ),
          ),
        );
        await native.entered.future;
        await provider.cancelRecording();
        await rejected;
        native.gateMethod = null;
        await provider.startRecording(AudioRecordingConfiguration());
        await provider.cancelRecording();
        await provider.dispose();
        // Then the stale native start is observable as cancellation and a new start is possible.
        expect(
          native.calls.where((call) => call.method == 'startRecording').length,
          2,
        );
        expect(
          native.calls.where((call) => call.method == 'cancelRecording').length,
          2,
        );
      },
    );

    test('explicit playback stop completes cleanup without publishing stale playback success', () async {
      // Given a canonical saved-original playback held by a native completion gate.
      final provider = AndroidAudioProvider(channel: channel, isAndroid: true);
      native.gateMethod = 'play';
      native.gate = Completer<void>();
      // When explicit stop interrupts playback and the delayed native callback arrives.
      final playing = provider.play(_wave());
      final rejected = expectLater(
        playing,
        throwsA(
          isA<AudioProviderException>().having(
            (error) => error.code,
            'code',
            'cancelled',
          ),
        ),
      );
      await native.entered.future;
      await provider.stopPlayback();
      await rejected;
      final ready = await provider.availability('ja-JP');
      await provider.dispose();
      // Then only the owning session receives stop and the operation guard is reusable.
      final play = native.calls.singleWhere((call) => call.method == 'play');
      final stop = native.calls.singleWhere(
        (call) => call.method == 'stopPlayback',
      );
      expect(
        (stop.arguments as Map)['sessionId'],
        (play.arguments as Map)['sessionId'],
      );
      expect(ready.state, AudioProviderState.available);
      expect((play.arguments as Map)['bytes'], orderedEquals(_wave()));
    });
  });
}

final _time = DateTime.utc(2026, 10, 9);
Uint8List _wave() => PcmWaveAudio.encode(Uint8List(32000));
AudioTranscriptionInput _input() => AudioTranscriptionInput(
  bytes: _wave(),
  original: OriginalAudio(
    material: CaptureMaterialReference(
      id: 'original',
      mediaType: 'audio/wav',
      byteLength: 32044,
      capturedAt: _time,
    ),
    durationMilliseconds: 1000,
  ),
  locale: 'ja-JP',
);
Map<String, Object?> _captureMap() => {
  'bytes': _wave(),
  'capturedAt': _time.toIso8601String(),
  'originalName': 'recording.wav',
};

final class _NativeProtocol {
  final calls = <MethodCall>[];
  final entered = Completer<void>();
  String? gateMethod;
  Completer<void>? gate;
  String? cleanupGateMethod;
  Completer<void>? cleanupGate;
  final cleanupEntered = Completer<void>();
  String? failureMethod;
  PlatformException? failure;
  Object? stopResponse = _captureMap();
  Object? readinessOverride;
  Object? transcriptOverride;

  Future<Object?> respond(MethodCall call) async {
    // Given a real encoded channel invocation with logical per-provider session identity.
    final arguments = call.arguments as Map;
    expect(
      arguments['sessionId'],
      matches(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$'),
    );
    final fields = switch (call.method) {
      'availability' || 'prepare' => {'locale'},
      'startRecording' => {'maxDurationSeconds'},
      'play' => {'bytes'},
      'transcribe' => {'bytes', 'locale'},
      _ => <String>{},
    };
    final expected = <String>{'sessionId', ...fields};
    // When explicit commands are counted, independently held for work/cleanup,
    // failed or used to release the matching native work.
    calls.add(call);
    if (call.method == cleanupGateMethod) {
      if (!cleanupEntered.isCompleted) cleanupEntered.complete();
      await cleanupGate!.future;
    }
    if (call.method == gateMethod) {
      if (!entered.isCompleted) entered.complete();
      await gate!.future;
    }
    if ([
      'dispose',
      'cancelRecording',
      'cancelTranscription',
      'stopPlayback',
    ].contains(call.method)) {
      if (gate != null && !gate!.isCompleted) gate!.complete();
    }
    if (call.method == failureMethod) throw failure!;
    // Then the protocol carries only admitted fields; mocks establish no real device capability.
    expect(arguments.keys.toSet(), expected);
    if (call.method == 'availability' || call.method == 'prepare') {
      return readinessOverride ??
          {
            'providerId': 'android-basic-speech',
            'locale': arguments['locale'],
            'state': 'available',
            'reason': null,
          };
    }
    if (call.method == 'stopRecording') return stopResponse;
    if (call.method == 'transcribe') {
      return transcriptOverride ??
          {
            'text': ' 日本語\n ',
            'extensions': {
              'actual': <Object?>[1, null],
            },
          };
    }
    return null;
  }
}
