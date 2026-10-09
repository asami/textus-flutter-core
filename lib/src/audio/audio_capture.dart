import 'dart:typed_data';

import '../capture/capture_material.dart';

/// Explicit recording duration limit; native capture retains samples until stop.
final class AudioRecordingConfiguration {
  /// Requires an integer duration of 1 through 120 seconds.
  AudioRecordingConfiguration({this.maxDurationSeconds = 120}) {
    if (maxDurationSeconds < 1 || maxDurationSeconds > 120) {
      throw ArgumentError.value(maxDurationSeconds, 'maxDurationSeconds');
    }
  }

  /// Maximum microphone capture duration in seconds.
  final int maxDurationSeconds;
}

/// Unsaved original WAV returned only by an explicit recording stop.
final class CapturedAudio {
  /// Snapshots the bytes and normalizes the capture time to UTC.
  CapturedAudio({
    required Uint8List bytes,
    required DateTime capturedAt,
    this.originalName,
  }) : _bytes = Uint8List.fromList(bytes),
       capturedAt = capturedAt.toUtc();

  final Uint8List _bytes;

  /// Detached original WAV bytes.
  Uint8List get bytes => Uint8List.fromList(_bytes);

  /// UTC time at which recording began.
  final DateTime capturedAt;

  /// Descriptive name, never a storage path.
  final String? originalName;
}

/// Durable audio reference with duration derived from its original samples.
final class OriginalAudio {
  /// Requires audio media and a positive duration of at most 120 seconds.
  OriginalAudio({required this.material, required this.durationMilliseconds}) {
    if (!material.mediaType.startsWith('audio/') ||
        durationMilliseconds <= 0 ||
        durationMilliseconds > 120000) {
      throw ArgumentError('Expected audio and a duration in 1..120000 ms');
    }
  }

  /// Unchanged original in the caller's local capture store.
  final CaptureMaterialReference material;

  /// Whole milliseconds derived from the saved sample count.
  final int durationMilliseconds;

  @override
  bool operator ==(Object other) =>
      other is OriginalAudio &&
      material == other.material &&
      durationMilliseconds == other.durationMilliseconds;

  @override
  int get hashCode => Object.hash(material, durationMilliseconds);
}

/// Capability state for an exact provider and recognition locale.
enum AudioProviderState {
  /// Local inference is ready.
  available,

  /// An explicit preparation can download the model.
  downloadable,

  /// A model download is already in progress.
  downloading,

  /// This provider cannot recognize this locale on the current device.
  unavailable,
}

/// Actual provider capability; availability is not an inference result.
final class AudioProviderAvailability {
  /// Validates identity and locale without causing preparation or inference.
  AudioProviderAvailability({
    required String providerId,
    required String locale,
    required this.state,
    this.reason,
  }) : providerId = _token(providerId),
       locale = _locale(locale);

  /// Safe actual provider identity.
  final String providerId;

  /// Exact requested recognition locale.
  final String locale;

  /// Actual current model capability.
  final AudioProviderState state;

  /// Optional actual platform explanation.
  final String? reason;
}

/// Shared capture, replay and recognition service lifecycle state.
enum AudioCaptureState {
  /// No work is active.
  idle,

  /// Recording is active or is awaiting an explicit stop/cancel.
  recording,

  /// Original import is active.
  saving,

  /// Original playback is active.
  playing,

  /// Capability inspection or explicit model preparation is active.
  preparing,

  /// Recognition of saved input is active.
  transcribing,

  /// The service is terminally disposed.
  disposed,
}

/// Replaceable original recording and playback runtime.
abstract interface class AudioRuntimeProvider {
  /// Whether recording and playback have platform support.
  bool get isSupported;

  /// Starts microphone capture only on explicit caller intent.
  Future<void> startRecording(AudioRecordingConfiguration configuration);

  /// Stops and returns captured original WAV; empty capture fails.
  Future<CapturedAudio> stopRecording();

  /// Cancels unsaved capture and awaits native cleanup.
  Future<void> cancelRecording();

  /// Plays supplied original bytes until completion or explicit stop.
  Future<void> play(Uint8List bytes);

  /// Stops playback and awaits cleanup.
  Future<void> stopPlayback();

  /// Idempotently releases owned platform resources.
  Future<void> dispose();
}

/// Replaceable saved-input transcription provider, independent of the microphone.
abstract interface class AudioTranscriptionProvider {
  /// Safe actual provider identity recorded in reports.
  String get id;

  /// Checks exact-locale readiness without downloading a model.
  Future<AudioProviderAvailability> availability(String locale);

  /// Explicitly prepares a model and returns its resulting actual readiness.
  Future<AudioProviderAvailability> prepare(String locale);

  /// Recognizes only the saved bytes in the immutable request.
  Future<AudioProviderTranscript> transcribe(AudioTranscriptionInput input);

  /// Cancels pending preparation/inference and awaits cleanup.
  Future<void> cancel();

  /// Idempotently releases owned provider resources.
  Future<void> dispose();
}

/// Defensive snapshot of saved original bytes, reference and exact locale.
final class AudioTranscriptionInput {
  /// Rejects invalid locale, nonaudio provenance and inconsistent byte lengths.
  AudioTranscriptionInput({
    required Uint8List bytes,
    required this.original,
    required String locale,
  }) : _bytes = Uint8List.fromList(bytes),
       locale = _locale(locale) {
    if (_bytes.length != original.material.byteLength) {
      throw ArgumentError('Transcription bytes differ from original length');
    }
  }

  final Uint8List _bytes;

  /// Detached bytes from the unchanged saved original.
  Uint8List get bytes => Uint8List.fromList(_bytes);

  /// Exact original provenance.
  final OriginalAudio original;

  /// Exact requested locale, preserved in the report.
  final String locale;
}

/// Provider output containing exact final text and opaque immutable JSON.
final class AudioProviderTranscript {
  /// Preserves text including Unicode and whitespace; blank success is invalid.
  AudioProviderTranscript({
    required this.text,
    Map<String, Object?> extensions = const {},
  }) : extensions = CaptureMaterialReference(
         id: 'extensions',
         mediaType: 'application/json',
         byteLength: 1,
         capturedAt: DateTime.utc(1970),
         extensions: extensions,
       ).extensions {
    if (text.trim().isEmpty) throw ArgumentError('Final transcript is blank');
  }

  /// Exact provider final text.
  final String text;

  /// Deeply immutable JSON metadata.
  final Map<String, Object?> extensions;
}

/// Observable native/platform failure with unmodified diagnostic code/message.
final class AudioProviderException implements Exception {
  /// Requires a nonblank platform failure code.
  AudioProviderException(this.code, this.message) {
    if (code.trim().isEmpty) throw ArgumentError('Failure code is blank');
  }

  /// Actual provider failure code.
  final String code;

  /// Actual provider diagnostic message, when provided.
  final String? message;

  @override
  String toString() => 'AudioProviderException($code, $message)';
}

String _token(String value) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(value)) {
    throw ArgumentError.value(value, 'id', 'unsafe identity');
  }
  return value;
}

String _locale(String value) {
  if (!RegExp(r'^[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$').hasMatch(value)) {
    throw ArgumentError.value(value, 'locale', 'invalid language tag');
  }
  return value;
}
