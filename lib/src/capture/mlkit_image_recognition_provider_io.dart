import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'image_recognition_service.dart';
import 'photo_capture.dart';
import 'recognition_configuration.dart';

/// Independent Japanese OCR and all-format barcode stages over one temp image.
final class MlKitImageRecognitionProvider implements ImageRecognitionProvider {
  MlKitImageRecognitionProvider();
  @override
  final RecognitionProviderDescriptor descriptor = RecognitionProviderDescriptor(
    id: RecognitionConfigurations.standardProviderId,
    label: 'ML Kit OCR and barcodes',
    capabilities: {RecognitionCapability.ocr, RecognitionCapability.barcodes},
  );
  bool get _supported => !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<RecognitionProviderAvailability> availability() async => RecognitionProviderAvailability(
    providerId: descriptor.id,
    state: _supported ? RecognitionProviderState.available : RecognitionProviderState.unavailable,
    capabilities: descriptor.capabilities, reason: _supported ? null : 'unsupportedPlatform',
  );
  @override
  Future<void> prepare() async { _requireSupported(); }

  @override
  Future<ImageRecognitionResult> recognize(ImageRecognitionInput input) async {
    _requireSupported();
    final original = ImageRecognitionInput(material: input.material, bytes: input.bytes);
    Directory? directory;
    TextRecognizer? recognizer;
    BarcodeScanner? scanner;
    String? text;
    var barcodeCompleted = false;
    final barcodes = <RecognizedImageBarcode>[];
    final failures = <ImageRecognitionFailure>[];
    try {
      directory = await Directory.systemTemp.createTemp('textus-recognition-');
      final file = File('${directory.path}${Platform.pathSeparator}original${_suffix(original.material.mediaType)}');
      await file.writeAsBytes(original.bytes, flush: true);
      final image = InputImage.fromFilePath(file.path);
      recognizer = TextRecognizer(script: TextRecognitionScript.japanese);
      scanner = BarcodeScanner(formats: [BarcodeFormat.all]);
      try {
        text = (await recognizer.processImage(image)).text;
      } catch (error) {
        failures.add(_failure(ImageRecognitionStage.text, 'textRecognitionFailed', error));
      }
      try {
        final results = await scanner.processImage(image);
        for (final result in results) {
          final value = result.rawValue;
          if (value != null && value.trim().isNotEmpty) {
            barcodes.add(RecognizedImageBarcode(value: value, format: result.format.name));
          }
        }
        barcodeCompleted = true;
      } catch (error) {
        failures.add(_failure(ImageRecognitionStage.barcode, 'barcodeRecognitionFailed', error));
      }
    } finally {
      if (recognizer != null) {
        try { await recognizer.close(); }
        catch (error) { failures.add(_failure(ImageRecognitionStage.cleanup, 'cleanupFailed', error)); }
      }
      if (scanner != null) {
        try { await scanner.close(); }
        catch (error) { failures.add(_failure(ImageRecognitionStage.cleanup, 'cleanupFailed', error)); }
      }
      if (directory != null) {
        try { await directory.delete(recursive: true); }
        catch (error) { failures.add(_failure(ImageRecognitionStage.cleanup, 'cleanupFailed', error)); }
      }
    }
    return ImageRecognitionResult(
      text: text, barcodes: barcodes, barcodeCompleted: barcodeCompleted, failures: failures,
    );
  }

  void _requireSupported() {
    if (!_supported) throw UnsupportedError('ML Kit recognition unsupported on this platform');
  }
}

String _suffix(String type) => switch (type.toLowerCase()) {
  'image/jpeg' => '.jpg', 'image/png' => '.png', 'image/heic' => '.heic',
  'image/heif' => '.heif', 'image/webp' => '.webp', 'image/gif' => '.gif', _ => '.img',
};
ImageRecognitionFailure _failure(ImageRecognitionStage stage, String code, Object error) =>
    ImageRecognitionFailure(stage: stage, code: code,
      message: error.toString().trim().isEmpty ? error.runtimeType.toString() : error.toString());
