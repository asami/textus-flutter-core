import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'audio_capture.dart';
import 'pcm_wave_audio.dart';

/// Session-isolated Android microphone, replay and saved-PCM Basic ASR adapter.
///
/// An injectable channel supports protocol specifications; channel mocks do not
/// establish Android microphone, model or hardware availability.
final class AndroidAudioProvider
    implements AudioRuntimeProvider, AudioTranscriptionProvider {
  /// Creates an inert adapter with a unique logical native session.
  AndroidAudioProvider({MethodChannel? channel, bool? isAndroid})
    : _channel =
          channel ?? const MethodChannel('org.textus.flutter.core/audio'),
      _android =
          isAndroid ??
          (!kIsWeb && defaultTargetPlatform == TargetPlatform.android),
      _sessionId = _newSessionId();

  final MethodChannel _channel;
  final bool _android;
  final String _sessionId;
  final Set<Future<void>> _settling = {};
  AudioCaptureState _state = AudioCaptureState.idle;
  bool _busy = false;
  int _generation = 0;
  Future<void>? _disposal;
  Future<void>? _recordingCancel;
  Future<void>? _playbackStop;
  bool _stoppingRecording = false;

  @override
  String get id => 'android-basic-speech';

  @override
  bool get isSupported => _android;

  @override
  Future<AudioProviderAvailability> availability(String locale) => _normal(
    AudioCaptureState.preparing,
    () => _availability('availability', locale),
  );

  @override
  Future<AudioProviderAvailability> prepare(String locale) => _normal(
    AudioCaptureState.preparing,
    () => _availability('prepare', locale),
  );

  Future<AudioProviderAvailability> _availability(
    String method,
    String locale,
  ) async {
    AudioProviderAvailability(
      providerId: id,
      locale: locale,
      state: AudioProviderState.unavailable,
    );
    if (!_android) {
      return AudioProviderAvailability(
        providerId: id,
        locale: locale,
        state: AudioProviderState.unavailable,
        reason: 'Android audio is unsupported',
      );
    }
    Object? value;
    try {
      value = await _call(method, {'locale': locale});
    } on AudioProviderException catch (error) {
      if (error.code != 'missingPlugin') rethrow;
      return AudioProviderAvailability(
        providerId: id,
        locale: locale,
        state: AudioProviderState.unavailable,
        reason: error.message,
      );
    }
    final map = _map(value, {'providerId', 'locale', 'state', 'reason'});
    if (map['providerId'] != id ||
        map['locale'] != locale ||
        map['state'] is! String ||
        (map['reason'] != null && map['reason'] is! String)) {
      throw const FormatException(
        'Invalid audio capability provenance or types',
      );
    }
    final states = AudioProviderState.values.where(
      (item) => item.name == map['state'],
    );
    if (states.isEmpty) {
      throw const FormatException('Unknown audio capability state');
    }
    return AudioProviderAvailability(
      providerId: id,
      locale: locale,
      state: states.single,
      reason: map['reason'] as String?,
    );
  }

  @override
  Future<void> startRecording(AudioRecordingConfiguration configuration) =>
      _normal(AudioCaptureState.recording, () async {
        _requireAndroid();
        _void(
          await _call('startRecording', {
            'maxDurationSeconds': configuration.maxDurationSeconds,
          }),
        );
      }, hold: true);

  @override
  Future<CapturedAudio> stopRecording() {
    final task = _interrupt(AudioCaptureState.recording, () async {
      final map = _map(await _call('stopRecording', {}), {
        'bytes',
        'capturedAt',
        'originalName',
      });
      final bytes = map['bytes'];
      final time = map['capturedAt'];
      final name = map['originalName'];
      if (bytes is! Uint8List ||
          time is! String ||
          (name != null && name is! String)) {
        throw const FormatException('Invalid native captured audio types');
      }
      final capturedAt = DateTime.tryParse(time);
      if (capturedAt == null ||
          !capturedAt.isUtc ||
          capturedAt.toIso8601String() != time) {
        throw const FormatException('Invalid native UTC capture time');
      }
      PcmWaveAudio.parse(bytes);
      return CapturedAudio(
        bytes: bytes,
        capturedAt: capturedAt,
        originalName: name as String?,
      );
    }, invalidate: false);
    _stoppingRecording = true;
    return task.whenComplete(() => _stoppingRecording = false);
  }

  @override
  Future<void> cancelRecording() {
    _alive();
    if (_recordingCancel != null) return _recordingCancel!;
    if (_state == AudioCaptureState.idle) return Future<void>.value();
    final expected = _stoppingRecording
        ? AudioCaptureState.saving
        : AudioCaptureState.recording;
    final task = _interrupt(expected, () async {
      _void(await _call('cancelRecording', {}));
    }, cleanup: true);
    _recordingCancel = task.whenComplete(() => _recordingCancel = null);
    return _recordingCancel!;
  }

  @override
  Future<void> play(Uint8List bytes) {
    final snapshot = PcmWaveAudio.parse(bytes).bytes;
    return _normal(AudioCaptureState.playing, () async {
      _requireAndroid();
      _void(await _call('play', {'bytes': snapshot}));
    });
  }

  @override
  Future<void> stopPlayback() {
    _alive();
    if (_playbackStop != null) return _playbackStop!;
    if (_state == AudioCaptureState.idle) return Future<void>.value();
    final task = _interrupt(AudioCaptureState.playing, () async {
      _void(await _call('stopPlayback', {}));
    }, cleanup: true);
    _playbackStop = task.whenComplete(() => _playbackStop = null);
    return _playbackStop!;
  }

  @override
  Future<AudioProviderTranscript> transcribe(AudioTranscriptionInput input) {
    final bytes = PcmWaveAudio.parse(input.bytes).bytes;
    return _normal(AudioCaptureState.transcribing, () async {
      _requireAndroid();
      final map = _map(
        await _call('transcribe', {'bytes': bytes, 'locale': input.locale}),
        {'text', 'extensions'},
      );
      if (map['text'] is! String ||
          map['extensions'] is! Map ||
          (map['extensions'] as Map).keys.any((key) => key is! String)) {
        throw const FormatException('Invalid native transcript types');
      }
      try {
        return AudioProviderTranscript(
          text: map['text'] as String,
          extensions: Map<String, Object?>.from(map['extensions'] as Map),
        );
      } on ArgumentError catch (error) {
        throw FormatException('Invalid native transcript: $error');
      }
    });
  }

  @override
  Future<void> cancel() {
    if (_state == AudioCaptureState.idle) {
      _alive();
      return Future<void>.value();
    }
    if (_state != AudioCaptureState.preparing &&
        _state != AudioCaptureState.transcribing) {
      throw StateError('No active transcription or preparation');
    }
    return _interrupt(_state, () async {
      _void(await _call('cancelTranscription', {}));
    });
  }

  Future<T> _normal<T>(
    AudioCaptureState state,
    Future<T> Function() action, {
    bool hold = false,
  }) {
    _alive();
    if (_busy || _state != AudioCaptureState.idle) {
      throw StateError('Audio bridge is busy');
    }
    _state = state;
    _busy = true;
    final token = ++_generation;
    return _track(_run(token, action, hold: hold));
  }

  Future<T> _run<T>(
    int token,
    Future<T> Function() action, {
    bool hold = false,
    bool cleanup = false,
  }) async {
    var successful = false;
    try {
      final value = await action();
      if (!cleanup || _state != AudioCaptureState.disposed) _check(token);
      successful = true;
      return value;
    } finally {
      if (token == _generation && _state != AudioCaptureState.disposed) {
        _busy = false;
        if (!hold || !successful) _state = AudioCaptureState.idle;
      }
    }
  }

  Future<T> _interrupt<T>(
    AudioCaptureState expected,
    Future<T> Function() action, {
    bool invalidate = true,
    bool cleanup = false,
  }) {
    _alive();
    if (_state != expected) throw StateError('No active ${expected.name}');
    if (!invalidate && _busy) {
      throw StateError('Recording start must finish before stop');
    }
    final previous = List<Future<void>>.of(_settling);
    final token = ++_generation;
    _state = AudioCaptureState.saving;
    _busy = true;
    return _track(
      _run(token, () async {
        final value = await action();
        await Future.wait(previous);
        return value;
      }, cleanup: cleanup),
    );
  }

  Future<T> _track<T>(Future<T> task) {
    late final Future<void> settled;
    settled = task
        .then<void>((_) {}, onError: (Object _, StackTrace _) {})
        .whenComplete(() => _settling.remove(settled));
    _settling.add(settled);
    return task;
  }

  void _alive() {
    if (_state == AudioCaptureState.disposed) {
      throw StateError('Audio provider is disposed');
    }
  }

  void _check(int token) {
    _alive();
    if (token != _generation) {
      throw AudioProviderException('cancelled', 'Audio operation cancelled');
    }
  }

  void _requireAndroid() {
    if (!_android) {
      throw AudioProviderException(
        'unsupported',
        'Android audio is unsupported',
      );
    }
  }

  Future<Object?> _call(String method, Map<String, Object?> arguments) async {
    try {
      return await _channel.invokeMethod<Object?>(method, {
        'sessionId': _sessionId,
        ...arguments,
      });
    } on MissingPluginException catch (error) {
      throw AudioProviderException('missingPlugin', error.message);
    } on PlatformException catch (error) {
      throw AudioProviderException(error.code, error.message);
    }
  }

  @override
  Future<void> dispose() {
    if (_disposal != null) return _disposal!;
    final completion = Completer<void>();
    _disposal = completion.future;
    _state = AudioCaptureState.disposed;
    ++_generation;
    _dispose().then(
      completion.complete,
      onError: (Object error, StackTrace stack) =>
          completion.completeError(error, stack),
    );
    return completion.future;
  }

  Future<void> _dispose() async {
    Object? failure;
    StackTrace? failureStack;
    Future<void> attempt(Future<void> Function() action) async {
      try {
        await action();
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }

    // Equivalent cleanup settles before native disposal, retaining its first failure.
    await attempt(() async {
      await Future.wait([?_recordingCancel, ?_playbackStop]);
    });
    if (_android) {
      await attempt(() async {
        try {
          _void(await _call('dispose', {}));
        } on AudioProviderException catch (error) {
          if (error.code != 'missingPlugin') rethrow;
        }
      });
    }
    await attempt(() async {
      await Future.wait(List<Future<void>>.of(_settling));
    });
    if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
  }
}

String _newSessionId() {
  final random = Random.secure();
  return 'session_${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
}

Map<Object?, Object?> _map(Object? value, Set<String> keys) {
  if (value is! Map ||
      value.length != keys.length ||
      !value.keys.every(keys.contains)) {
    throw const FormatException('Invalid native audio response keys');
  }
  return Map<Object?, Object?>.from(value);
}

void _void(Object? value) {
  if (value != null) {
    throw const FormatException('Expected an empty native response');
  }
}
