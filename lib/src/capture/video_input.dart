import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Bounded, unchanged MP4/QuickTime bytes. Paths never become durable identities.
final class CapturedVideo {
  CapturedVideo({
    required Uint8List bytes,
    required DateTime capturedAt,
    this.originalName,
    int maximumBytes = 67108864,
  }) : _bytes = Uint8List.fromList(bytes),
       capturedAt = capturedAt.toUtc(),
       mediaType = inspectVideoContainer(bytes, maximumBytes: maximumBytes);
  final Uint8List _bytes;
  Uint8List get bytes => Uint8List.fromList(_bytes);
  final String mediaType;
  final DateTime capturedAt;
  final String? originalName;
}

/// Container recognition only: actual decoder/playback readiness is separate.
String inspectVideoContainer(Uint8List bytes, {int maximumBytes = 67108864}) {
  if (maximumBytes < 1 || maximumBytes > 268435456) {
    throw ArgumentError('Invalid video byte bound');
  }
  if (bytes.isEmpty || bytes.length > maximumBytes) {
    throw const FormatException('Video is empty or exceeds the byte limit');
  }
  if (bytes.length < 16 ||
      String.fromCharCodes(bytes.sublist(4, 8)) != 'ftyp') {
    throw const FormatException('Expected MP4 or QuickTime video container');
  }
  final size = ByteData.sublistView(bytes).getUint32(0);
  if (size < 16 || size > bytes.length) {
    throw const FormatException('Invalid video file type box');
  }
  final brand = String.fromCharCodes(bytes.sublist(8, 12));
  if (brand == 'qt  ') return 'video/quicktime';
  if (!const {
    'isom',
    'iso2',
    'iso4',
    'iso5',
    'iso6',
    'mp41',
    'mp42',
    'avc1',
    'M4V ',
  }.contains(brand)) {
    throw const FormatException('Unsupported video container brand');
  }
  return 'video/mp4';
}

abstract interface class VideoInputProvider {
  bool get canCapture;
  bool get canImport;
  bool get canRecoverLostVideo;
  Future<CapturedVideo?> capture();
  Future<CapturedVideo?> importVideo();
  Future<CapturedVideo?> recoverLostVideo();
  Future<void> close();
}

/// Explicit native picker use. Closing fences results but cannot dismiss the OS picker.
final class ImagePickerVideoProvider implements VideoInputProvider {
  ImagePickerVideoProvider({ImagePicker? picker, DateTime Function()? now})
    : _picker = picker ?? ImagePicker(),
      _now = now ?? DateTime.now;
  final ImagePicker _picker;
  final DateTime Function() _now;
  bool _closed = false, _busy = false;
  @override
  bool get canCapture =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  @override
  bool get canImport => canCapture || kIsWeb;
  @override
  bool get canRecoverLostVideo =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  @override
  Future<CapturedVideo?> capture() => _pick(ImageSource.camera);
  @override
  Future<CapturedVideo?> importVideo() => _pick(ImageSource.gallery);
  Future<CapturedVideo?> _pick(ImageSource source) => _operate(() async {
    if (source == ImageSource.camera ? !canCapture : !canImport) {
      throw UnsupportedError('Video input unsupported');
    }
    final file = await _picker.pickVideo(
      source: source,
      maxDuration: const Duration(seconds: 30),
    );
    return file == null ? null : _read(file);
  });
  @override
  Future<CapturedVideo?> recoverLostVideo() => _operate(() async {
    if (!canRecoverLostVideo) {
      throw UnsupportedError(
        'Lost video recovery unsupported on this platform',
      );
    }
    final response = await _picker.retrieveLostData();
    if (response.exception != null) throw response.exception!;
    if (response.isEmpty) return null;
    final files = response.files ?? <XFile>[];
    if (response.type != RetrieveType.video || files.length != 1) {
      throw const FormatException('Expected one recovered video');
    }
    return _read(files.single);
  });
  Future<CapturedVideo> _read(XFile file) async {
    // Enforce the complete-file bound before allocating original bytes.
    if (await file.length() > 67108864) {
      throw const FormatException(
        'Video exceeds 64 MiB; original is not truncated',
      );
    }
    if (_closed) throw StateError('Video input closed');
    return CapturedVideo(
      bytes: await file.readAsBytes(),
      capturedAt: _now(),
      originalName: file.name,
    );
  }

  Future<T> _operate<T>(Future<T> Function() operation) async {
    if (_closed) throw StateError('Video input closed');
    if (_busy) throw StateError('Video input busy');
    _busy = true;
    try {
      final value = await operation();
      if (_closed) throw StateError('Video input closed');
      return value;
    } finally {
      _busy = false;
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
  }
}
