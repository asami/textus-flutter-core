
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;

import 'photo_capture.dart';

enum MediaInputAction {
  imageImport,
  cameraCapture,
  audioRecording,
  audioPlayback,
}

enum MediaAdapterSupport { supported, unsupported }

enum MediaDeviceAvailability { available, absent, unknown }

enum MediaPermissionState {
  allowed,
  requestable,
  denied,
  policyBlocked,
  unknown,
}

enum MediaInputFailure {
  unsupported,
  unavailable,
  permissionDenied,
  policyBlocked,
  invalidImage,
  tooLarge,
  busy,
  retired,
}

/// Support, hardware and permission are independent observations, not rights.
@immutable
final class MediaInputCapability {
  const MediaInputCapability({
    required this.support,
    required this.device,
    required this.permission,
    this.busy = false,
  });
  final MediaAdapterSupport support;
  final MediaDeviceAvailability device;
  final MediaPermissionState permission;
  final bool busy;
  bool get canAttempt =>
      support == MediaAdapterSupport.supported &&
      device != MediaDeviceAvailability.absent &&
      !const {
        MediaPermissionState.denied,
        MediaPermissionState.policyBlocked,
      }.contains(permission) &&
      !busy;
  bool get needsConfirmation =>
      canAttempt &&
      (device == MediaDeviceAvailability.unknown ||
          const {
            MediaPermissionState.unknown,
            MediaPermissionState.requestable,
          }.contains(permission));
  static const unsupported = MediaInputCapability(
    support: MediaAdapterSupport.unsupported,
    device: MediaDeviceAvailability.unknown,
    permission: MediaPermissionState.unknown,
  );
}

final class MediaInputException implements Exception {
  const MediaInputException(this.failure);
  final MediaInputFailure failure;
  @override
  String toString() => 'MediaInputException(${failure.name})';
}

/// Platform observations must never start capture or permission requests.
abstract interface class MediaInputProvider {
  Map<MediaInputAction, MediaInputCapability> get capabilities;
  Future<Map<MediaInputAction, MediaInputCapability>> inspect();
  Future<CapturedPhoto?> importImage();
  Future<CapturedPhoto?> captureImage();
  Future<void> close();
}

/// Explicit acquisition, separate from attachment, local retention and delivery.
/// A borrowed provider is closed only when ownsProvider was explicitly selected.
final class MediaInputService extends ChangeNotifier {
  MediaInputService({
    required MediaInputProvider provider,
    this.ownsProvider = false,
  }) : _provider = provider,
       _capabilities = Map.unmodifiable(provider.capabilities);
  final MediaInputProvider _provider;
  final bool ownsProvider;
  Map<MediaInputAction, MediaInputCapability> _capabilities;
  bool _busy = false;
  bool _closed = false;
  Future<void>? _closeFuture;
  bool get busy => _busy;
  bool get isClosed => _closed;
  Map<MediaInputAction, MediaInputCapability> get capabilities => _capabilities;
  MediaInputCapability capability(MediaInputAction action) =>
      _capabilities[action] ?? MediaInputCapability.unsupported;
  Future<void> inspect() async {
    if (_closed) throw const MediaInputException(MediaInputFailure.retired);
    final observed = await _provider.inspect();
    if (_closed) throw const MediaInputException(MediaInputFailure.retired);
    _capabilities = Map.unmodifiable(observed);
    notifyListeners();
  }

  Future<CapturedPhoto?> importImage() =>
      _acquire(MediaInputAction.imageImport, _provider.importImage);
  Future<CapturedPhoto?> captureImage() =>
      _acquire(MediaInputAction.cameraCapture, _provider.captureImage);
  Future<CapturedPhoto?> _acquire(
    MediaInputAction action,
    Future<CapturedPhoto?> Function() acquire,
  ) async {
    if (_closed) throw const MediaInputException(MediaInputFailure.retired);
    if (_busy) throw const MediaInputException(MediaInputFailure.busy);
    final cap = capability(action);
    if (!cap.canAttempt) {
      throw MediaInputException(switch (cap.permission) {
        MediaPermissionState.denied => MediaInputFailure.permissionDenied,
        MediaPermissionState.policyBlocked => MediaInputFailure.policyBlocked,
        _ =>
          cap.support == MediaAdapterSupport.unsupported
              ? MediaInputFailure.unsupported
              : MediaInputFailure.unavailable,
      });
    }
    _busy = true;
    notifyListeners();
    try {
      final value = await acquire();
      if (_closed) throw const MediaInputException(MediaInputFailure.retired);
      return value;
    } on MediaInputException {
      rethrow;
    } catch (_) {
      throw const MediaInputException(MediaInputFailure.unavailable);
    } finally {
      _busy = false;
      if (!_closed) {
        _capabilities = Map.unmodifiable(_provider.capabilities);
        notifyListeners();
      }
    }
  }

  Future<void> close() {
    if (_closeFuture case final future?) return future;
    _closed = true;
    notifyListeners();
    return _closeFuture = ownsProvider ? _provider.close() : Future.value();
  }
}

/// Validate actual supported image content, not a suffix or untrusted MIME hint.
CapturedPhoto validateImportedImage({
  required Uint8List bytes,
  required DateTime acquiredAt,
  String? originalName,
  int maximumBytes = 16777216,
}) {
  if (maximumBytes < 1 || maximumBytes > 67108864) {
    throw ArgumentError('Invalid image bound');
  }
  if (bytes.length > maximumBytes) {
    throw const MediaInputException(MediaInputFailure.tooLarge);
  }
  final String type;
  if (bytes.length >= 8 &&
      bytes[0] == 137 &&
      bytes[1] == 80 &&
      bytes[2] == 78 &&
      bytes[3] == 71 &&
      bytes[4] == 13 &&
      bytes[5] == 10 &&
      bytes[6] == 26 &&
      bytes[7] == 10) {
    type = 'image/png';
  } else if (bytes.length >= 3 &&
      bytes[0] == 255 &&
      bytes[1] == 216 &&
      bytes[2] == 255) {
    type = 'image/jpeg';
  } else if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    type = 'image/webp';
  } else {
    throw const MediaInputException(MediaInputFailure.invalidImage);
  }
  try {
    final decoder = image.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (info == null ||
        info.width < 1 ||
        info.height < 1 ||
        info.width * info.height > 40000000) {
      throw const MediaInputException(MediaInputFailure.invalidImage);
    }
  } on MediaInputException {
    rethrow;
  } catch (_) {
    throw const MediaInputException(MediaInputFailure.invalidImage);
  }
  return CapturedPhoto(
    bytes: bytes,
    mediaType: type,
    capturedAt: acquiredAt,
    originalName: originalName,
  );
}
