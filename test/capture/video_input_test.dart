import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

Uint8List _container(String brand) => Uint8List.fromList([
  0,
  0,
  0,
  20,
  ...'ftyp'.codeUnits,
  ...brand.codeUnits,
  0,
  0,
  0,
  0,
  ...brand.codeUnits,
]);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'container bounds and defensive copies never imply decoder acceptance',
    () {
      // Given a file-type box only, deliberately not a playable video fixture.
      final source = _container('mp42');
      final video = CapturedVideo(
        bytes: source,
        capturedAt: DateTime.utc(2026),
      );
      // When caller-owned input/output bytes are modified.
      source[8] = 0;
      video.bytes[8] = 0;
      // Then validated container identity and retained bytes do not change.
      expect(video.mediaType, 'video/mp4');
      expect(video.bytes, _container('mp42'));
      expect(inspectVideoContainer(_container('qt  ')), 'video/quicktime');
      expect(
        () => inspectVideoContainer(_container('heic')),
        throwsFormatException,
      );
      expect(
        () => inspectVideoContainer(_container('mp42'), maximumBytes: 19),
        throwsFormatException,
      );
      expect(() => inspectVideoContainer(Uint8List(8)), throwsFormatException);
    },
  );

  test('explicit camera selection uses a bounded duration and retains the complete file', () async {
    // Given an inert native picker adapter and a controlled camera response.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final picker = _Picker();
    final provider = ImagePickerVideoProvider(picker: picker);
    expect(picker.calls, 0);
    // When capture is explicitly requested.
    final result = await provider.capture();
    // Then the camera receives its declared limit and returns unchanged bytes.
    expect(picker.source, ImageSource.camera);
    expect(picker.duration, const Duration(seconds: 30));
    expect(result!.bytes, _container('mp42'));
    await provider.close();
  });

  test(
    'closing while the OS picker is pending retires its late result',
    () async {
      // Given an unresolved OS video picker.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final picker = _Picker()..gate = Completer<XFile?>();
      final provider = ImagePickerVideoProvider(picker: picker);
      final pending = provider.importVideo();
      final rejected = expectLater(pending, throwsStateError);
      // When its caller closes before the file arrives.
      await provider.close();
      picker.gate!.complete(
        XFile.fromData(_container('mp42'), name: 'original.mp4'),
      );
      // Then no future attachment can receive the obsolete result.
      await rejected;
    },
  );
}

class _Picker extends ImagePicker {
  int calls = 0;
  ImageSource? source;
  Duration? duration;
  Completer<XFile?>? gate;
  @override
  Future<XFile?> pickVideo({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    Duration? maxDuration,
  }) async {
    calls++;
    this.source = source;
    duration = maxDuration;
    return gate != null
        ? gate!.future
        : XFile.fromData(_container('mp42'), name: 'original.mp4');
  }
}
