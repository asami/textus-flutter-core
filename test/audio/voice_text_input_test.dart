import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  test('explicit stop recognizes transient bytes without a store or material', () async {
    // Given a fresh field-input lifetime and separate native-operation doubles.
    final audio = _Audio();
    final cleanup = _Cleanup();
    final session = VoiceTextInputSession(
      runtime: audio,
      speech: audio,
      cleanup: cleanup,
    );
    expect(audio.recordings, 0);
    // When recording is explicitly started and stopped.
    await session.startRecording();
    expect(session.state, VoiceTextInputState.recording);
    expect(audio.recognitions, 0);
    final transcript = await session.stopAndTranscribe();
    // Then final text is returned automatically, with no generation or persistence.
    expect(transcript.text, 'ええと、第7巻です。あと第8巻もあります。');
    expect(audio.recognitions, 1);
    expect(cleanup.calls, 0);
    expect(session.state, VoiceTextInputState.idle);
    final result = await session.cleanup(transcript.text);
    expect(result.source, transcript.text);
    expect(result.text, '第7巻です。あと第8巻もあります。');
    await session.close();
    await session.close();
    expect(audio.disposals, 1);
    expect(cleanup.disposals, 1);
  });

  test('closing during recognition rejects its late completion', () async {
    // Given pending recognition and an otherwise usable input session.
    final audio = _Audio()..gate = Completer<AudioProviderTranscript>();
    final cleanup = _Cleanup();
    final session = VoiceTextInputSession(
      runtime: audio,
      speech: audio,
      cleanup: cleanup,
    );
    await session.startRecording();
    final stopping = session.stopAndTranscribe();
    final rejected = expectLater(stopping, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    // When the caller retires and a native result arrives afterwards.
    await session.close();
    audio.gate!.complete(AudioProviderTranscript(text: '遅れて届いた文字列'));
    // Then no live session accepts that result or further work.
    await rejected;
    expect(session.state, VoiceTextInputState.closed);
    await expectLater(session.cleanup('入力'), throwsStateError);
  });

  test('busy operations cannot mix cleanup with microphone capture', () async {
    // Given an active microphone.
    final audio = _Audio();
    final cleanup = _Cleanup();
    final session = VoiceTextInputSession(
      runtime: audio,
      speech: audio,
      cleanup: cleanup,
    );
    await session.startRecording();
    // When conversion is requested before stop.
    await expectLater(session.cleanup('原文'), throwsStateError);
    // Then no inference starts and closing releases the microphone owner.
    expect(cleanup.calls, 0);
    await session.close();
    expect(audio.disposals, 1);
  });
}

class _Audio
    implements AudioRuntimeProvider, TransientAudioTranscriptionProvider {
  int recordings = 0, recognitions = 0, disposals = 0;
  Completer<AudioProviderTranscript>? gate;
  @override
  String get id => 'controlled-speech';
  @override
  bool get isSupported => true;
  @override
  Future<void> startRecording(AudioRecordingConfiguration configuration) async {
    recordings++;
  }

  @override
  Future<CapturedAudio> stopRecording() async => CapturedAudio(
    bytes: Uint8List.fromList([1, 2, 3]),
    capturedAt: DateTime.utc(2026),
  );
  @override
  Future<AudioProviderTranscript> transcribeCaptured(
    Uint8List bytes, {
    String locale = 'ja-JP',
  }) async {
    expect(bytes, [1, 2, 3]);
    expect(locale, 'ja-JP');
    recognitions++;
    return gate != null
        ? gate!.future
        : AudioProviderTranscript(text: 'ええと、第7巻です。あと第8巻もあります。');
  }

  @override
  Future<AudioProviderAvailability> availability(String locale) async =>
      AudioProviderAvailability(
        providerId: id,
        locale: locale,
        state: AudioProviderState.available,
      );
  @override
  Future<AudioProviderAvailability> prepare(String locale) =>
      availability(locale);
  @override
  Future<void> dispose() async {
    disposals++;
  }

  @override
  Future<void> cancel() async {}
  @override
  Future<void> cancelRecording() async {}
  @override
  Future<void> play(Uint8List bytes) async {}
  @override
  Future<void> stopPlayback() async {}
  @override
  Future<AudioProviderTranscript> transcribe(AudioTranscriptionInput input) =>
      throw UnimplementedError();
}

class _Cleanup implements VoiceTextCleanupProvider {
  int calls = 0, disposals = 0;
  @override
  Future<VoiceTextCleanupAvailability> availability() async =>
      const VoiceTextCleanupAvailability(
        state: VoiceTextCleanupState.available,
        providerId: 'controlled',
        modelName: 'controlled-model',
      );
  @override
  Future<void> prepare() async {}
  @override
  Future<VoiceTextCleanupResult> cleanup(String text) async {
    calls++;
    return VoiceTextCleanupResult(
      source: text,
      text: '第7巻です。あと第8巻もあります。',
      providerId: 'controlled',
      modelName: 'controlled-model',
    );
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}
