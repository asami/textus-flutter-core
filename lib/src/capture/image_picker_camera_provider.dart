import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'camera_service.dart';
import 'photo_capture.dart';

/// Real image_picker acquisition. Plugin-owned cache files are never deleted.
final class ImagePickerCameraProvider implements CameraProvider {
  ImagePickerCameraProvider({ImagePicker? picker, DateTime Function()? clock})
    : _picker = picker ?? ImagePicker(), _clock = clock ?? DateTime.now;
  final ImagePicker _picker;
  final DateTime Function() _clock;

  @override
  bool get isSupported => !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<CapturedPhoto?> capturePhoto() async {
    _requireSupported();
    final file = await _picker.pickImage(
      source: ImageSource.camera, preferredCameraDevice: CameraDevice.rear,
      requestFullMetadata: false,
    );
    return file == null ? null : _read(file);
  }

  @override
  Future<CapturedPhoto?> recoverLostPhoto() async {
    _requireSupported();
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    final response = await _picker.retrieveLostData();
    if (response.exception != null) throw response.exception!;
    if (response.isEmpty) return null;
    final files = response.files ?? <XFile>[];
    if (files.length != 1 || response.type != RetrieveType.image) {
      throw const FormatException('Lost image response must contain exactly one image');
    }
    return _read(files.single);
  }

  Future<CapturedPhoto> _read(XFile file) async {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw const FormatException('Captured image is empty');
    final provided = file.mimeType;
    final valid = provided != null && provided.toLowerCase().startsWith('image/') &&
        RegExp(r"^[A-Za-z0-9!#$%&'*+.^_`|~-]+/[A-Za-z0-9!#$%&'*+.^_`|~-]+$")
            .hasMatch(provided);
    final mediaType = valid ? provided : _filenameType(file.name);
    if (mediaType == null) throw const FormatException('Captured image MIME type is unknown');
    return CapturedPhoto(
      bytes: bytes, mediaType: mediaType, capturedAt: _clock(), originalName: file.name,
    );
  }

  void _requireSupported() {
    if (!isSupported) throw UnsupportedError('Camera acquisition unsupported on this platform');
  }
}

String? _filenameType(String name) => switch (name.split('.').last.toLowerCase()) {
  'jpg' || 'jpeg' => 'image/jpeg', 'png' => 'image/png',
  'heic' => 'image/heic', 'heif' => 'image/heif', 'webp' => 'image/webp',
  'gif' => 'image/gif', _ => null,
};
