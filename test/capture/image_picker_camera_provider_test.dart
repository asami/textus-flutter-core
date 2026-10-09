import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('real image_picker API acquisition and recovery', () {
    late Directory directory;
    late TargetPlatform? previousPlatform;
    late _Picker picker;
    setUp(() async {
      previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      directory = await Directory.systemTemp.createTemp('image-picker-spec-');
      picker = _Picker();
    });
    tearDown(() async {
      debugDefaultTargetPlatformOverride = previousPlatform;
      await directory.delete(recursive: true);
    });

    test('I1 rear camera returns unchanged bytes metadata and retains plugin cache', () async {
      // Given an actual temp XFile and an injected public ImagePicker implementation.
      final file = await _image(directory, 'original.jpg', [9, 8, 7], mime: 'image/jpeg');
      picker.file = file;
      var clocks = 0;
      DateTime clock() { clocks++; return _time.toLocal(); }
      final provider = ImagePickerCameraProvider(picker: picker, clock: clock);
      // When the real adapter calls the public plugin acquisition API.
      final photo = (await provider.capturePhoto())!;
      // Then rear acquisition requests no resize/compression/metadata and keeps its cache file.
      expect(provider.isSupported, isTrue);
      expect(picker.source, ImageSource.camera); expect(picker.camera, CameraDevice.rear);
      expect(picker.maxWidth, isNull); expect(picker.maxHeight, isNull); expect(picker.quality, isNull);
      expect(picker.metadata, isFalse); expect(picker.captures, 1);
      expect(photo.bytes, [9, 8, 7]); expect(photo.originalName, 'original.jpg');
      expect(photo.mediaType, 'image/jpeg'); expect(photo.capturedAt, _time);
      expect(photo.capturedAt.isUtc, isTrue); expect(clocks, 1);
      expect(await File(file.path).exists(), isTrue);
      expect(await File(file.path).readAsBytes(), [9, 8, 7]);
      photo.bytes[0] = 0;
      expect(photo.bytes, [9, 8, 7]);
    });

    test('I2 cancel permission errors and invalid files stay observable and retries succeed', () async {
      // Given cancellation, a native permission exception and malformed image files.
      final provider = ImagePickerCameraProvider(picker: picker, clock: () => _time);
      final permission = PlatformException(code: 'camera_access_denied', message: 'Camera permission denied');
      final invalid = [
        await _image(directory, 'empty.jpg', []),
        await _image(directory, 'unknown.bin', [1]),
        await _image(directory, 'bad-mime.bin', [1], mime: 'image/ invalid'),
        await _image(directory, 'non-image.bin', [1], mime: 'text/plain'),
      ];
      // When cancellation and permission failure precede each invalid file.
      final cancelled = await provider.capturePhoto();
      picker.captureError = permission;
      await expectLater(provider.capturePhoto(), throwsA(same(permission)));
      picker.captureError = null;
      for (final file in invalid) {
        picker.file = file;
        await expectLater(provider.capturePhoto(), throwsFormatException);
      }
      picker.file = await _image(directory, 'retry.PNG', [1, 2], mime: 'broken');
      final retried = (await provider.capturePhoto())!;
      // Then no successful empty image is fabricated and known filename fallback supports a retry.
      expect(cancelled, isNull); expect(retried.bytes, [1, 2]); expect(retried.mediaType, 'image/png');
      for (final file in invalid) { expect(await File(file.path).exists(), isTrue); }
    });

    test('I2 valid supplied image MIME and known filename suffixes preserve media types', () async {
      // Given every documented fallback suffix plus a valid case-insensitive supplied MIME.
      final suffixes = <String, String>{
        'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'heic': 'image/heic',
        'heif': 'image/heif', 'webp': 'image/webp', 'gif': 'image/gif',
      };
      final provider = ImagePickerCameraProvider(picker: picker);
      // When files with no MIME and a file with an explicit valid image MIME are acquired.
      final photos = <CapturedPhoto>[];
      for (final suffix in suffixes.keys) {
        picker.file = await _image(directory, 'image.$suffix', [1]);
        photos.add((await provider.capturePhoto())!);
      }
      picker.file = await _image(directory, 'custom.bin', [2], mime: 'IMAGE/PNG');
      final supplied = (await provider.capturePhoto())!;
      // Then filename inference is finite and supplied valid MIME is preserved verbatim.
      expect(photos.map((photo) => photo.mediaType), suffixes.values);
      expect(supplied.mediaType, 'IMAGE/PNG'); expect(supplied.originalName, 'custom.bin');
    });

    test('I3 Android lost image recovery rejects ambiguous native responses and retains files', () async {
      // Given a recovered image, empty lost data, native errors and ambiguous responses.
      final file = await _image(directory, 'lost.jpeg', [3, 2, 1]);
      final other = await _image(directory, 'other.jpeg', [4]);
      final provider = ImagePickerCameraProvider(picker: picker, clock: () => _time);
      picker.lost = LostDataResponse(files: [file], type: RetrieveType.image);
      // When valid recovery is followed by every empty or invalid response.
      final recovered = (await provider.recoverLostPhoto())!;
      picker.lost = LostDataResponse.empty();
      final empty = await provider.recoverLostPhoto();
      final native = PlatformException(code: 'lost_data_error', message: 'native recovery failed');
      picker.lost = LostDataResponse(exception: native);
      await expectLater(provider.recoverLostPhoto(), throwsA(same(native)));
      picker.recoveryError = native;
      await expectLater(provider.recoverLostPhoto(), throwsA(same(native)));
      picker.recoveryError = null;
      for (final response in [
        LostDataResponse(files: [file, other], type: RetrieveType.image),
        LostDataResponse(), LostDataResponse(files: [file], type: RetrieveType.video),
      ]) {
        picker.lost = response;
        await expectLater(provider.recoverLostPhoto(), throwsFormatException);
      }
      picker.lost = LostDataResponse(files: [file], type: RetrieveType.image);
      final next = await provider.recoverLostPhoto();
      // Then recovery metadata and errors are truthful and plugin cache survives every response.
      expect(recovered.bytes, [3, 2, 1]); expect(recovered.mediaType, 'image/jpeg');
      expect(recovered.originalName, 'lost.jpeg'); expect(recovered.capturedAt, _time);
      expect(empty, isNull); expect(next, recovered); expect(picker.captures, 0);
      expect(await File(file.path).exists(), isTrue); expect(await File(other.path).exists(), isTrue);
    });

    test('I3 iOS skips Android recovery and unsupported targets never call native acquisition', () async {
      // Given a picker that would throw if its lost-data API were called.
      picker.recoveryError = PlatformException(code: 'must-not-call');
      final provider = ImagePickerCameraProvider(picker: picker);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      // When iOS recovers and unsupported desktop targets request acquisition and recovery.
      final ios = await provider.recoverLostPhoto();
      for (final target in [TargetPlatform.linux, TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.fuchsia]) {
        debugDefaultTargetPlatformOverride = target;
        await expectLater(provider.capturePhoto(), throwsUnsupportedError);
        await expectLater(provider.recoverLostPhoto(), throwsUnsupportedError);
        // Then unsupported targets expose support accurately and perform no plugin calls.
        expect(provider.isSupported, isFalse);
      }
      expect(ios, isNull); expect(picker.recoveries, 0); expect(picker.captures, 0);
    });
  });
}

final _time = DateTime.utc(2026, 10, 6, 1, 2, 3);
Future<XFile> _image(Directory directory, String name, List<int> bytes, {String? mime}) async {
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(Uint8List.fromList(bytes), flush: true);
  return XFile(file.path, mimeType: mime);
}
final class _Picker extends ImagePicker {
  XFile? file;
  Object? captureError; Object? recoveryError;
  LostDataResponse lost = LostDataResponse.empty();
  int captures = 0; int recoveries = 0;
  ImageSource? source; CameraDevice? camera;
  double? maxWidth; double? maxHeight; int? quality; bool? metadata;
  @override
  Future<XFile?> pickImage({required ImageSource source, double? maxWidth, double? maxHeight,
    int? imageQuality, CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true}) async {
    captures++; this.source = source; camera = preferredCameraDevice;
    this.maxWidth = maxWidth; this.maxHeight = maxHeight;
    quality = imageQuality; metadata = requestFullMetadata;
    if (captureError != null) throw captureError!;
    return file;
  }
  @override
  Future<LostDataResponse> retrieveLostData() async {
    recoveries++;
    if (recoveryError != null) throw recoveryError!;
    return lost;
  }
}
