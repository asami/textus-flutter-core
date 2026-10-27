import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../repository/file_capture_store.dart';
import '../repository/local_capture_store.dart';
import 'android_audio_provider.dart';
import 'audio_capture.dart';
import 'audio_transcript.dart';
import 'pcm_wave_audio.dart';

/// Saves original audio before returning provenance and recognizes saved bytes.
///
/// Dependencies are borrowed by default. All ordinary operations share one
/// guard; stop, cancel and dispose interrupt their matching active operation.
final class AudioCaptureService {
  /// Creates a service without capture, inference or model preparation.
  factory AudioCaptureService({
    required AudioRuntimeProvider runtime,
    required AudioTranscriptionProvider transcription,
    required LocalCaptureStore store,
    DateTime Function()? now,
    bool ownsProviders = false,
  }) => AudioCaptureService._(
    runtime,
    transcription,
    store,
    now ?? DateTime.now,
    ownsProviders,
  );

  AudioCaptureService._(
    this._runtime,
    this._transcription,
    this._store,
    this._now,
    this.ownsProviders,
  );

  final AudioRuntimeProvider _runtime;
  final AudioTranscriptionProvider _transcription;
  final LocalCaptureStore _store;
  final DateTime Function() _now;
  final Set<Future<void>> _settling = {};
  AudioCaptureState _state = AudioCaptureState.idle;
  CapturedAudio? _pendingOriginal;
  Future<void>? _recordStart;
  Future<void>? _disposal;
  DateTime? _lastTime;
  int _generation = 0;
  bool _interrupting = false;

  /// Whether disposal also disposes the supplied provider instances.
  final bool ownsProviders;

  /// Current shared operation/lifecycle state.
  AudioCaptureState get state => _state;

  /// Platform runtime support without triggering platform work.
  bool get isSupported => _runtime.isSupported;

  /// Immutable captured WAV retained after a failed durable import.
  CapturedAudio? get pendingOriginal => _pendingOriginal;

  /// Checks exact-locale readiness without downloading or recognizing.
  Future<AudioProviderAvailability> availability({String locale = 'ja-JP'}) =>
      _operate(
        AudioCaptureState.preparing,
        () async => _checkedAvailability(
          await _transcription.availability(locale),
          locale,
        ),
      );

  /// Explicitly prepares recognition; all other work is excluded while pending.
  Future<AudioProviderAvailability> prepareTranscription({
    String locale = 'ja-JP',
  }) => _operate(
    AudioCaptureState.preparing,
    () async =>
        _checkedAvailability(await _transcription.prepare(locale), locale),
  );

  /// Starts capture and retains recording state after this future completes.
  Future<void> startRecording({AudioRecordingConfiguration? configuration}) {
    final token = _begin(AudioCaptureState.recording);
    if (!_runtime.isSupported) {
      _state = AudioCaptureState.idle;
      throw AudioProviderException(
        'unsupported',
        'Audio recording is unsupported',
      );
    }
    final task = _start(token, configuration ?? AudioRecordingConfiguration());
    _recordStart = task;
    return _track(task);
  }

  Future<void> _start(
    int token,
    AudioRecordingConfiguration configuration,
  ) async {
    try {
      await _runtime.startRecording(configuration);
      _check(token);
    } catch (_) {
      if (token == _generation &&
          !_interrupting &&
          _state != AudioCaptureState.disposed) {
        _state = AudioCaptureState.idle;
      }
      rethrow;
    }
  }

  /// Stops capture, validates WAV and durably imports exact original bytes.
  Future<OriginalAudio> stopRecording() {
    _requireActive(AudioCaptureState.recording);
    _interrupting = true;
    _state = AudioCaptureState.saving;
    final token = _generation;
    return _track(_stop(token));
  }

  Future<OriginalAudio> _stop(int token) async {
    try {
      await _recordStart;
      _check(token);
      final captured = await _runtime.stopRecording();
      _check(token);
      PcmWaveAudio.parse(captured.bytes);
      _pendingOriginal = captured;
      return await _savePending(token);
    } finally {
      _finish(token);
    }
  }

  /// Retries retained bytes without capturing or changing the original.
  Future<OriginalAudio> retryPendingOriginal() {
    if (_pendingOriginal == null) throw StateError('No pending original');
    final token = _begin(AudioCaptureState.saving, allowPending: true);
    return _track(_retry(token));
  }

  Future<OriginalAudio> _retry(int token) async {
    try {
      return await _savePending(token);
    } finally {
      _finish(token);
    }
  }

  Future<OriginalAudio> _savePending(int token) async {
    final captured = _pendingOriginal!;
    final bytes = captured.bytes;
    final wave = PcmWaveAudio.parse(bytes);
    final material = await _store.saveMaterial(
      bytes: bytes,
      mediaType: 'audio/wav',
      capturedAt: captured.capturedAt,
      originalName: captured.originalName,
    );
    _check(token);
    if (material.mediaType != 'audio/wav' ||
        material.byteLength != bytes.length ||
        material.capturedAt != captured.capturedAt ||
        material.originalName != captured.originalName) {
      throw StateError('Store returned inconsistent original provenance');
    }
    final original = OriginalAudio(
      material: material,
      durationMilliseconds: wave.durationMilliseconds,
    );
    _pendingOriginal = null;
    return original;
  }

  /// Cancels active unsaved recording; retained failed imports cannot be erased.
  Future<void> cancelRecording() {
    if (_pendingOriginal != null) {
      throw StateError('Retry the pending original first');
    }
    _requireActive(AudioCaptureState.recording);
    _interrupting = true;
    final token = ++_generation;
    return _track(_cancelRecording(token));
  }

  Future<void> _cancelRecording(int token) async {
    try {
      await _runtime.cancelRecording();
      try {
        await _recordStart;
      } catch (_) {
        /* Start was interrupted. */
      }
      _check(token);
    } finally {
      _finish(token);
    }
  }

  /// Reads and plays the unchanged saved original until completion or stop.
  Future<void> playOriginal(OriginalAudio original) =>
      _operate(AudioCaptureState.playing, () async {
        final token = _generation;
        final bytes = await _read(original);
        _check(token);
        await _runtime.play(bytes);
      });

  /// Explicitly stops playback and prevents stale completion publication.
  Future<void> stopPlayback() {
    _requireActive(AudioCaptureState.playing);
    _interrupting = true;
    final token = ++_generation;
    return _track(_stopPlayback(token, List<Future<void>>.of(_settling)));
  }

  Future<void> _stopPlayback(int token, List<Future<void>> prior) async {
    try {
      await _runtime.stopPlayback();
      await Future.wait(prior);
      _check(token);
    } finally {
      _finish(token);
    }
  }

  /// Cancels an active readiness check, preparation or recognition nonterminally.
  /// Awaiting cleanup also awaits prior IO/provider settlement, even on failure.
  Future<void> cancelTranscription() {
    if (_pendingOriginal != null ||
        _interrupting ||
        (_state != AudioCaptureState.preparing &&
            _state != AudioCaptureState.transcribing)) {
      throw StateError('No interruptible transcription operation');
    }
    _interrupting = true;
    final token = ++_generation;
    final prior = List<Future<void>>.of(_settling);
    return _track(_cancelTranscription(token, prior));
  }

  Future<void> _cancelTranscription(int token, List<Future<void>> prior) async {
    Object? failure;
    StackTrace? failureStack;
    try {
      try {
        await _transcription.cancel();
      } catch (error, stack) {
        failure = error;
        failureStack = stack;
      }
      await Future.wait(prior);
      if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
      _check(token);
    } finally {
      _finish(token);
    }
  }

  /// Recognizes exact saved input and returns a caller-owned composition report.
  /// Store/input errors propagate; only provider failures become typed reports.
  Future<AudioTranscriptReport> transcribe(
    OriginalAudio original, {
    String locale = 'ja-JP',
  }) => _operate(AudioCaptureState.transcribing, () async {
    final token = _generation;
    final input = AudioTranscriptionInput(
      bytes: await _read(original),
      original: original,
      locale: locale,
    );
    _check(token);
    final startedAt = _clock(original.material.capturedAt);
    final watch = Stopwatch()..start();
    AudioProviderTranscript? result;
    AudioTranscriptStatus status = AudioTranscriptStatus.success;
    String? code;
    String? message;
    try {
      final ready = _checkedAvailability(
        await _transcription.availability(locale),
        locale,
      );
      _check(token);
      if (ready.state != AudioProviderState.available) {
        status = AudioTranscriptStatus.unavailable;
        code = 'unavailable';
        message = ready.reason ?? ready.state.name;
      } else {
        result = await _transcription.transcribe(input);
        _check(token);
      }
    } on AudioProviderException catch (error) {
      _check(token);
      code = error.code;
      message = error.message;
      status = switch (code) {
        'cancelled' => AudioTranscriptStatus.cancelled,
        'unavailable' ||
        'unsupported' ||
        'missingPlugin' => AudioTranscriptStatus.unavailable,
        _ => AudioTranscriptStatus.failed,
      };
    } finally {
      watch.stop();
    }
    _check(token);
    return AudioTranscriptReport(
      id: _reportId(),
      original: original,
      providerId: _transcription.id,
      locale: locale,
      startedAt: startedAt,
      completedAt: _clock(startedAt),
      elapsedMilliseconds: watch.elapsedMilliseconds,
      status: status,
      text: result?.text,
      errorCode: code,
      errorMessage: message,
      extensions: result?.extensions ?? const {},
    );
  });

  Future<Uint8List> _read(OriginalAudio original) async {
    final bytes = await _store.readMaterial(original.material);
    if (bytes.length != original.material.byteLength ||
        PcmWaveAudio.parse(bytes).durationMilliseconds !=
            original.durationMilliseconds) {
      throw const FormatException(
        'Saved original length or duration is inconsistent',
      );
    }
    return bytes;
  }

  AudioProviderAvailability _checkedAvailability(
    AudioProviderAvailability value,
    String locale,
  ) {
    if (value.providerId != _transcription.id || value.locale != locale) {
      throw const FormatException(
        'Provider availability provenance is inconsistent',
      );
    }
    return value;
  }

  Future<T> _operate<T>(AudioCaptureState state, Future<T> Function() action) {
    final token = _begin(state);
    return _track(_run(token, action));
  }

  Future<T> _run<T>(int token, Future<T> Function() action) async {
    try {
      final result = await action();
      _check(token);
      return result;
    } finally {
      _finish(token);
    }
  }

  int _begin(AudioCaptureState state, {bool allowPending = false}) {
    if (_state != AudioCaptureState.idle || _interrupting) {
      throw StateError('Audio service is busy or disposed');
    }
    if (!allowPending && _pendingOriginal != null) {
      throw StateError(
        'Retry the pending original before starting another operation',
      );
    }
    _state = state;
    return ++_generation;
  }

  void _requireActive(AudioCaptureState expected) {
    if (_state != expected || _interrupting) {
      throw StateError('No interruptible ${expected.name} operation');
    }
  }

  void _check(int token) {
    if (_state == AudioCaptureState.disposed || token != _generation) {
      throw StateError('Audio operation was cancelled or disposed');
    }
  }

  void _finish(int token) {
    if (token == _generation && _state != AudioCaptureState.disposed) {
      _state = AudioCaptureState.idle;
      _interrupting = false;
    }
  }

  Future<T> _track<T>(Future<T> task) {
    late final Future<void> settled;
    settled = task
        .then<void>((_) {}, onError: (Object _, StackTrace _) {})
        .whenComplete(() => _settling.remove(settled));
    _settling.add(settled);
    return task;
  }

  DateTime _clock(DateTime floor) {
    var value = _now().toUtc();
    if (value.isBefore(floor)) value = floor;
    if (_lastTime != null && value.isBefore(_lastTime!)) value = _lastTime!;
    return _lastTime = value;
  }

  /// Terminally cancels active work, awaits cleanup and disposes owned providers.
  /// Identical runtime/transcription instances are disposed exactly once.
  Future<void> dispose() {
    if (_disposal != null) return _disposal!;
    final completion = Completer<void>();
    _disposal = completion.future;
    final previous = _state;
    _state = AudioCaptureState.disposed;
    ++_generation;
    _dispose(previous).then(
      completion.complete,
      onError: (Object error, StackTrace stack) =>
          completion.completeError(error, stack),
    );
    return completion.future;
  }

  Future<void> _dispose(AudioCaptureState previous) async {
    Object? failure;
    StackTrace? failureStack;
    Future<void> cleanup(Future<void> Function() action) async {
      try {
        await action();
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }

    if (previous == AudioCaptureState.recording ||
        previous == AudioCaptureState.saving) {
      await cleanup(_runtime.cancelRecording);
    }
    if (previous == AudioCaptureState.playing) {
      await cleanup(_runtime.stopPlayback);
    }
    if (previous == AudioCaptureState.preparing ||
        previous == AudioCaptureState.transcribing) {
      await cleanup(_transcription.cancel);
    }
    await Future.wait(List<Future<void>>.of(_settling));
    if (ownsProviders) {
      await cleanup(_runtime.dispose);
      if (!identical(_runtime, _transcription)) {
        await cleanup(_transcription.dispose);
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
  }
}

String _reportId() {
  final random = Random.secure();
  return 'audio_${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
}

/// Opens the default native adapter and owns its shared provider exactly once.
Future<AudioCaptureService> openDefaultAudioCaptureService({
  LocalCaptureStore? store,
}) async {
  final provider = AndroidAudioProvider();
  return AudioCaptureService(
    runtime: provider,
    transcription: provider,
    store: store ?? await openDefaultCaptureStore(),
    ownsProviders: true,
  );
}
