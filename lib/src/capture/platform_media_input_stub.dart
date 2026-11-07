import 'media_input.dart';
import 'photo_capture.dart';

MediaInputProvider createPlatformMediaInputProvider() =>
    _UnsupportedMediaInput();

final class _UnsupportedMediaInput implements MediaInputProvider {
  @override
  Map<MediaInputAction, MediaInputCapability> get capabilities => {
    for (final action in MediaInputAction.values)
      action: MediaInputCapability.unsupported,
  };
  @override
  Future<Map<MediaInputAction, MediaInputCapability>> inspect() async =>
      capabilities;
  @override
  Future<CapturedPhoto?> importImage() async =>
      throw const MediaInputException(MediaInputFailure.unsupported);
  @override
  Future<CapturedPhoto?> captureImage() async =>
      throw const MediaInputException(MediaInputFailure.unsupported);
  @override
  Future<void> close() async {}
}
