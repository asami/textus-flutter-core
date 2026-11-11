import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  test('capability inventory is inert and independent of unknown hardware and permissions', () async {
    // Given a supported camera with unknown hardware and requestable permission.
    final provider = _Provider();
    final service = MediaInputService(provider: provider);
    addTearDown(service.dispose);
    // When the UI observes capabilities and performs passive inspection.
    expect(
      service.capability(MediaInputAction.cameraCapture).needsConfirmation,
      isTrue,
    );
    await service.inspect();
    // Then no acquisition or permission operation ran; unsupported audio is not absent hardware.
    expect(provider.calls, 0);
    expect(
      service.capability(MediaInputAction.audioRecording).support,
      MediaAdapterSupport.unsupported,
    );
    expect(
      service.capability(MediaInputAction.audioRecording).device,
      MediaDeviceAvailability.unknown,
    );
    await service.close();
    expect(provider.closed, isFalse);
  });
  test(
    'cancel, duplicate clicks and owner retirement never produce an attachment',
    () async {
      // Given an owned provider with a pending user selection.
      final provider = _Provider();
      final service = MediaInputService(provider: provider, ownsProvider: true);
      addTearDown(service.dispose);
      final first = service.importImage();
      // When a duplicate acquisition is attempted and the original selection is cancelled.
      await expectLater(
        service.captureImage(),
        throwsA(
          isA<MediaInputException>().having(
            (e) => e.failure,
            'failure',
            MediaInputFailure.busy,
          ),
        ),
      );
      provider.pending.complete(null);
      expect(await first, isNull);
      expect(provider.calls, 1);
      // When another selection resolves after retirement.
      provider.pending = Completer<CapturedPhoto?>();
      final late = service.importImage();
      final observed = expectLater(
        late,
        throwsA(
          isA<MediaInputException>().having(
            (e) => e.failure,
            'failure',
            MediaInputFailure.retired,
          ),
        ),
      );
      await service.close();
      provider.pending.complete(_photo());
      await observed;
      // Then ownership is closed and no image escapes the retired operation.
      expect(provider.closed, isTrue);
      expect(service.isClosed, isTrue);
    },
  );
  test('supported image content determines MIME and retained bytes independent of the filename', () {
    // Given PNG content with a misleading extension.
    final bytes = Uint8List.fromList(
      image.encodePng(image.Image(width: 3, height: 2)),
    );
    final original = Uint8List.fromList(bytes);
    // When import validation snapshots it.
    final photo = validateImportedImage(
      bytes: bytes,
      acquiredAt: DateTime.utc(2026),
      originalName: 'cover.txt',
    );
    bytes.fillRange(0, bytes.length, 0);
    // Then actual content is retained and malformed/oversized input is rejected.
    expect(photo.mediaType, 'image/png');
    expect(photo.bytes, original);
    expect(
      () => validateImportedImage(
        bytes: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
        acquiredAt: DateTime.utc(2026),
      ),
      throwsA(isA<MediaInputException>()),
    );
    expect(
      () => validateImportedImage(
        bytes: original,
        acquiredAt: DateTime.utc(2026),
        maximumBytes: 1,
      ),
      throwsA(
        isA<MediaInputException>().having(
          (e) => e.failure,
          'failure',
          MediaInputFailure.tooLarge,
        ),
      ),
    );
  });
}

CapturedPhoto _photo() => CapturedPhoto(
  bytes: Uint8List.fromList([1]),
  mediaType: 'image/png',
  capturedAt: DateTime.utc(2026),
);

class _Provider implements MediaInputProvider {
  int calls = 0;
  bool closed = false;
  Completer<CapturedPhoto?> pending = Completer();
  @override
  Map<MediaInputAction, MediaInputCapability> get capabilities => {
    MediaInputAction.imageImport: const MediaInputCapability(
      support: MediaAdapterSupport.supported,
      device: MediaDeviceAvailability.available,
      permission: MediaPermissionState.allowed,
    ),
    MediaInputAction.cameraCapture: const MediaInputCapability(
      support: MediaAdapterSupport.supported,
      device: MediaDeviceAvailability.unknown,
      permission: MediaPermissionState.requestable,
    ),
  };
  @override
  Future<Map<MediaInputAction, MediaInputCapability>> inspect() async =>
      capabilities;
  @override
  Future<CapturedPhoto?> importImage() {
    calls++;
    return pending.future;
  }

  @override
  Future<CapturedPhoto?> captureImage() => importImage();
  @override
  Future<void> close() async {
    closed = true;
  }
}
