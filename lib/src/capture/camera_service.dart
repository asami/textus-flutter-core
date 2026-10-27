import 'photo_capture.dart';

/// Caller-owned acquisition boundary, including Android lost-data recovery.
abstract interface class CameraProvider {
  bool get isSupported;
  Future<CapturedPhoto?> capturePhoto();
  Future<CapturedPhoto?> recoverLostPhoto();
}

/// Rejects unsupported acquisition and overlapping camera operations.
final class CameraService {
  CameraService({required this._provider});

  final CameraProvider _provider;
  bool _busy = false;
  bool get isSupported => _provider.isSupported;

  Future<CapturedPhoto?> capture() => _operate(_provider.capturePhoto);
  Future<CapturedPhoto?> recover() => _operate(_provider.recoverLostPhoto);

  Future<CapturedPhoto?> _operate(Future<CapturedPhoto?> Function() action) async {
    if (!isSupported) throw UnsupportedError('Camera acquisition unsupported');
    if (_busy) throw StateError('A camera operation is already active');
    _busy = true;
    try {
      return await action();
    } finally {
      _busy = false;
    }
  }
}
