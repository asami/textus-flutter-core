import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'media_input.dart';
import 'photo_capture.dart';

MediaInputProvider createPlatformMediaInputProvider() =>
    ImagePickerMediaInputProvider();

final class ImagePickerMediaInputProvider implements MediaInputProvider {
  ImagePickerMediaInputProvider({
    ImagePicker? picker,
    DateTime Function()? clock,
  }) : _picker = picker ?? ImagePicker(),
       _clock = clock ?? DateTime.now;
  final ImagePicker _picker;
  final DateTime Function() _clock;
  bool _closed = false;
  final _denied = <MediaInputAction>{};
  final _previouslyDenied = <MediaInputAction>{};
  bool get _supported => const {
    TargetPlatform.android,
    TargetPlatform.iOS,
  }.contains(defaultTargetPlatform);
  @override
  Map<MediaInputAction, MediaInputCapability> get capabilities => {
    for (final action in MediaInputAction.values)
      action: MediaInputCapability.unsupported,
    if (_supported)
      MediaInputAction.imageImport: MediaInputCapability(
        support: MediaAdapterSupport.supported,
        device: MediaDeviceAvailability.available,
        permission: _denied.contains(MediaInputAction.imageImport)
            ? MediaPermissionState.denied
            : _previouslyDenied.contains(MediaInputAction.imageImport)
            ? MediaPermissionState.requestable
            : MediaPermissionState.allowed,
      ),
    if (_supported)
      MediaInputAction.cameraCapture: MediaInputCapability(
        support: MediaAdapterSupport.supported,
        device: MediaDeviceAvailability.unknown,
        permission: _denied.contains(MediaInputAction.cameraCapture)
            ? MediaPermissionState.denied
            : MediaPermissionState.requestable,
      ),
  };
  @override
  Future<Map<MediaInputAction, MediaInputCapability>> inspect() async {
    if (_closed) throw const MediaInputException(MediaInputFailure.retired);
    // No passive native permission API is supplied by image_picker. Explicit
    // retry reopens requestable state, without claiming the OS granted access.
    _denied.clear();
    return capabilities;
  }

  Future<CapturedPhoto?> _pick(ImageSource source) async {
    if (_closed) throw const MediaInputException(MediaInputFailure.retired);
    if (!_supported) {
      throw const MediaInputException(MediaInputFailure.unsupported);
    }
    try {
      final file = await _picker.pickImage(
        source: source,
        requestFullMetadata: false,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (_closed) throw const MediaInputException(MediaInputFailure.retired);
      if (file == null) return null;
      _previouslyDenied.remove(
        source == ImageSource.camera
            ? MediaInputAction.cameraCapture
            : MediaInputAction.imageImport,
      );
      if (await file.length() > 16777216) {
        throw const MediaInputException(MediaInputFailure.tooLarge);
      }
      final bytes = await file.readAsBytes();
      if (_closed) throw const MediaInputException(MediaInputFailure.retired);
      return validateImportedImage(
        bytes: bytes,
        acquiredAt: _clock(),
        originalName: file.name,
      );
    } on PlatformException catch (error) {
      if (const {
        'camera_access_denied',
        'photo_access_denied',
        'camera_access_denied_without_prompt',
        'photo_access_denied_without_prompt',
      }.contains(error.code)) {
        _denied.add(
          source == ImageSource.camera
              ? MediaInputAction.cameraCapture
              : MediaInputAction.imageImport,
        );
        _previouslyDenied.add(
          source == ImageSource.camera
              ? MediaInputAction.cameraCapture
              : MediaInputAction.imageImport,
        );
        throw const MediaInputException(MediaInputFailure.permissionDenied);
      }
      throw const MediaInputException(MediaInputFailure.unavailable);
    }
  }

  @override
  Future<CapturedPhoto?> importImage() => _pick(ImageSource.gallery);
  @override
  Future<CapturedPhoto?> captureImage() => _pick(ImageSource.camera);
  @override
  Future<void> close() async {
    _closed = true;
  }
}
