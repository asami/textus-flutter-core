import 'image_recognition_service.dart';
import 'photo_capture.dart';
import 'recognition_configuration.dart';

/// Unsupported non-IO implementation; never supplies successful empty output.
final class MlKitImageRecognitionProvider implements ImageRecognitionProvider {
  MlKitImageRecognitionProvider();
  @override
  final RecognitionProviderDescriptor descriptor = RecognitionProviderDescriptor(
    id: RecognitionConfigurations.standardProviderId, label: 'ML Kit OCR and barcodes',
    capabilities: {RecognitionCapability.ocr, RecognitionCapability.barcodes},
  );
  @override
  Future<RecognitionProviderAvailability> availability() async => RecognitionProviderAvailability(
    providerId: descriptor.id, state: RecognitionProviderState.unavailable,
    capabilities: descriptor.capabilities, reason: 'unsupportedPlatform',
  );
  @override
  Future<void> prepare() async => throw UnsupportedError('ML Kit recognition unsupported on this platform');
  @override
  Future<ImageRecognitionResult> recognize(ImageRecognitionInput input) async =>
      throw UnsupportedError('ML Kit recognition unsupported on this platform');
}
