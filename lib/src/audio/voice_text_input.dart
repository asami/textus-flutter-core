import 'package:flutter/foundation.dart';

import 'android_audio_provider.dart';
import 'ios_audio_provider.dart';
import 'audio_capture.dart';
import 'voice_text_cleanup.dart';

enum VoiceTextInputState {
  idle,
  preparing,
  recording,
  transcribing,
  cleaning,
  closed,
}

/// One transient field-input lifetime. No store, material or delivery is needed.
final class VoiceTextInputSession {
  factory VoiceTextInputSession({
    required AudioRuntimeProvider runtime,
    required TransientAudioTranscriptionProvider speech,
    required VoiceTextCleanupProvider cleanup,
  }) => VoiceTextInputSession._(runtime, speech, cleanup);

  VoiceTextInputSession._(this._runtime, this._speech, this._cleanup);

  /// Creates independent native adapters for one dialog; construction is inert.
  factory VoiceTextInputSession.platform() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      final audio = IosAudioProvider();
      return VoiceTextInputSession(
        runtime: audio,
        speech: audio,
        cleanup: NativeVoiceTextCleanupProvider(),
      );
    }
    final audio = AndroidAudioProvider();
    return VoiceTextInputSession(
      runtime: audio,
      speech: audio,
      cleanup: NativeVoiceTextCleanupProvider(),
    );
  }

  final AudioRuntimeProvider _runtime;
  final TransientAudioTranscriptionProvider _speech;
  final VoiceTextCleanupProvider _cleanup;
  VoiceTextInputState _state = VoiceTextInputState.idle;
  VoiceTextInputState get state => _state;
  bool _busy = false;
  Future<void>? _closing;

  Future<AudioProviderAvailability> speechAvailability() => _operate(
    VoiceTextInputState.preparing,
    () => _speech.availability('ja-JP'),
  );
  Future<AudioProviderAvailability> prepareSpeech() =>
      _operate(VoiceTextInputState.preparing, () => _speech.prepare('ja-JP'));
  Future<VoiceTextCleanupAvailability> cleanupAvailability() =>
      _operate(VoiceTextInputState.preparing, _cleanup.availability);
  Future<void> prepareCleanup() =>
      _operate(VoiceTextInputState.preparing, _cleanup.prepare);

  Future<void> startRecording() => _operate(
    VoiceTextInputState.recording,
    () => _runtime.startRecording(AudioRecordingConfiguration()),
    hold: true,
  );

  /// Stop automatically recognizes the complete unsaved WAV and drops the bytes.
  Future<AudioProviderTranscript> stopAndTranscribe() {
    if (_busy || _state != VoiceTextInputState.recording) {
      throw StateError('Recording start must complete before stop');
    }
    return _operate(VoiceTextInputState.transcribing, () async {
      final captured = await _runtime.stopRecording();
      _alive();
      return _speech.transcribeCaptured(captured.bytes);
    }, stopping: true);
  }

  Future<VoiceTextCleanupResult> cleanup(String text) =>
      _operate(VoiceTextInputState.cleaning, () => _cleanup.cleanup(text));

  Future<T> _operate<T>(
    VoiceTextInputState next,
    Future<T> Function() action, {
    bool hold = false,
    bool stopping = false,
  }) async {
    _alive();
    if (_busy || (_state != VoiceTextInputState.idle && !stopping)) {
      throw StateError('Voice input is busy');
    }
    _busy = true;
    _state = next;
    var success = false;
    try {
      final value = await action();
      _alive();
      success = true;
      return value;
    } finally {
      _busy = false;
      if (_state != VoiceTextInputState.closed && (!hold || !success)) {
        _state = VoiceTextInputState.idle;
      }
    }
  }

  void _alive() {
    if (_state == VoiceTextInputState.closed) {
      throw StateError('Voice input closed');
    }
  }

  /// Terminal retirement fences every late result before releasing native work.
  Future<void> close() {
    if (_closing != null) return _closing!;
    _state = VoiceTextInputState.closed;
    return _closing = Future.wait<void>([
      Future.sync(_runtime.dispose),
      if (!identical(_runtime, _speech)) Future.sync(_speech.dispose),
      Future.sync(_cleanup.dispose),
    ]).then((_) {});
  }
}
