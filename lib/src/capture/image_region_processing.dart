import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../repository/file_capture_store.dart';
import '../repository/local_capture_store.dart';
import '../settings/recognition_settings.dart';
import 'capture_material.dart';
import 'gemini_nano_image_recognition_provider.dart';
import 'image_recognition_service.dart';
import 'image_region.dart';
import 'mlkit_image_recognition_provider.dart';
import 'photo_capture.dart';
import 'recognition_configuration.dart';
import 'recognition_operation_context.dart';
import 'recognition_repository.dart';

/// Trusted canonical display raster created only by [ImageRegionService].
final class ImageRegionFrame {
  ImageRegionFrame._(this.source, this.pixelWidth, this.pixelHeight, Uint8List bytes)
    : _pngBytes = Uint8List.fromList(bytes);
  /// Exact original reference; its bytes are never rewritten.
  final CaptureMaterialReference source;
  /// Upright raster width.
  final int pixelWidth;
  /// Upright raster height.
  final int pixelHeight;
  final Uint8List _pngBytes;
  /// Versioned display and selection coordinate convention.
  String get frameVersion => 'exifUprightV1';
  /// Defensive canonical PNG snapshot without orientation metadata.
  Uint8List get pngBytes => Uint8List.fromList(_pngBytes);
}

/// Serial local region decoding, derivation and explicit durable recognition.
final class ImageRegionService {
  /// Construction performs no IO or native/provider work.
  ImageRegionService({required LocalCaptureStore store,
    required this._recognition, DateTime Function()? clock,
    this.maxEncodedBytes = 33554432, this.maxPixels = 32000000})
    : _store = store, _clock = clock ?? DateTime.now,
      reports = LocalRecognitionRepository(store: store) {
    if (maxEncodedBytes <= 0 || maxPixels <= 0) throw ArgumentError('Resource limits must be positive');
  }
  final LocalCaptureStore _store;
  final ImageRecognitionService _recognition;
  final DateTime Function() _clock;
  /// Durable exact provenance records keyed by the derived material id.
  static const derivationsCollection = 'image_region_derivations_v1';
  /// Maximum original encoded byte count before decoding.
  final int maxEncodedBytes;
  /// Maximum source raster area, checked from decoder headers.
  final int maxPixels;
  /// Durable unmodified raw comparisons in the same material store.
  final LocalRecognitionRepository reports;
  bool _busy = false;

  /// Reads and normalizes a supported static JPEG or PNG on Flutter compute.
  Future<ImageRegionFrame> loadFrame(CaptureMaterialReference source) => _operate(() async {
    final result = await _process(source);
    return ImageRegionFrame._(source, result['width'] as int, result['height'] as int,
      result['bytes'] as Uint8List);
  });

  /// Re-reads the original and saves a fresh PNG and its exact provenance.
  /// A provenance write failure propagates without deleting retained bytes.
  Future<ImageRegionDerivation> derive(ImageRegionSnapshot region) => _operate(() async {
    final result = await _process(region.source, region: region);
    final bytes = result['bytes'] as Uint8List;
    final now = _clock().toUtc();
    final capturedAt = now.isBefore(region.recordedAt) ? region.recordedAt : now;
    final input = await _store.saveMaterial(bytes: Uint8List.fromList(bytes),
      mediaType: 'image/png', capturedAt: capturedAt);
    if (input.mediaType != 'image/png' || input.byteLength != bytes.length ||
        input.capturedAt != capturedAt || input.id == region.source.id) {
      throw StateError('Store returned inconsistent derived material provenance');
    }
    final derivation = ImageRegionDerivation(region: region, input: input,
      bounds: region.geometry.boundsFor(pixelWidth: region.pixelWidth, pixelHeight: region.pixelHeight));
    await _store.saveDocument(derivationsCollection, input.id, derivation.toJson());
    return derivation;
  });

  /// Resolves durable provenance without reading bytes or consulting selection.
  /// Returns null only for an absent record; invalid data and store errors fail.
  Future<ImageRegionDerivation?> findDerivation(String inputId) => _operate(() async {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(inputId)) {
      throw ArgumentError.value(inputId, 'inputId', 'unsafe logical token');
    }
    final document = await _store.readDocument(derivationsCollection, inputId);
    if (document == null) return null;
    final derivation = ImageRegionDerivation.fromJson(document);
    if (derivation.input.id != inputId) {
      throw FormatException('Stored derivation input identity mismatch for $inputId');
    }
    return derivation;
  });

  /// Reads the exact retained derived PNG, with observable length failures.
  Future<Uint8List> readDerived(ImageRegionDerivation derivation) =>
      _operate(() => _read(derivation.input));

  /// Standard OCR is always first; local AI is a separate explicit supplement.
  Future<ImageRegionExtraction> recognize(ImageRegionDerivation derivation, {
    bool supplementWithLocalAi = false, RecognitionOperationContext? operationContext,
  }) => _operate(() async {
    final bytes = await _read(derivation.input);
    final comparison = await _recognition.recognize(input: ImageRecognitionInput(
      material: derivation.input, bytes: bytes,
      operationContext: operationContext ?? RecognitionOperationContext(
        sourceRole: 'region', targetKinds: const ['quotation'],
        instructions: 'Extract verbatim visible text; never paraphrase.',
      )), configurationIds: [RecognitionSettings.androidStandard,
        if (supplementWithLocalAi) RecognitionSettings.pixelEnhanced]);
    final extraction = ImageRegionExtraction(derivation: derivation, comparison: comparison);
    await reports.save(comparison);
    return extraction;
  });

  /// Forwards actual provider readiness without preparing providers.
  Future<List<RecognitionProviderAvailability>> availability() => _operate(_recognition.availability);
  /// Explicit caller action forwarding existing provider preparation.
  Future<RecognitionProviderAvailability> prepareProvider(String providerId) =>
      _operate(() => _recognition.prepareProvider(providerId));

  Future<Uint8List> _read(CaptureMaterialReference source) async {
    final bytes = await _store.readMaterial(source);
    if (bytes.length != source.byteLength) throw StateError('Stored material byte length mismatch');
    return Uint8List.fromList(bytes);
  }
  Future<Map<String, Object?>> _process(CaptureMaterialReference source, {ImageRegionSnapshot? region}) async {
    if (source.mediaType != 'image/png' && source.mediaType != 'image/jpeg') {
      throw UnsupportedError('Manual selection required: only static JPEG and PNG are supported');
    }
    if (source.byteLength > maxEncodedBytes) throw UnsupportedError('Manual selection required: encoded image limit exceeded');
    return compute(_processRegionRaster, <String, Object?>{
      'bytes': await _read(source), 'mediaType': source.mediaType,
      'maxEncodedBytes': maxEncodedBytes, 'maxPixels': maxPixels,
      'region': region?.toJson(),
    });
  }
  Future<T> _operate<T>(Future<T> Function() operation) async {
    if (_busy) throw StateError('An image region operation is already active');
    _busy = true;
    try { return await operation(); } finally { _busy = false; }
  }
}

/// Caller-owned service with existing ML Kit and Nano defaults, without camera.
Future<ImageRegionService> openDefaultImageRegionService({LocalCaptureStore? store,
  Iterable<ImageRecognitionProvider> additionalProviders = const []}) async {
  final additional = List<ImageRecognitionProvider>.of(additionalProviders);
  final hasNano = additional.any((p) => p.descriptor.id == RecognitionConfigurations.enhancedProviderId);
  return ImageRegionService(store: store ?? await openDefaultCaptureStore(),
    recognition: ImageRecognitionService(registry: RecognitionProviderRegistry(providers: [
      MlKitImageRecognitionProvider(), if (!hasNano) GeminiNanoImageRecognitionProvider(), ...additional,
    ])));
}

// Top-level compute callback accepts and returns only transferable plain values.
Map<String, Object?> _processRegionRaster(Map<String, Object?> request) {
  final bytes = request['bytes'] as Uint8List;
  if (bytes.length > (request['maxEncodedBytes'] as int)) {
    throw UnsupportedError('Manual selection required: encoded image limit exceeded');
  }
  final img.Decoder decoder = request['mediaType'] == 'image/jpeg' ? img.JpegDecoder() : img.PngDecoder();
  img.Image raster;
  try {
    final info = decoder.startDecode(bytes);
    if (info == null || info.width <= 0 || info.height <= 0) throw const FormatException('Corrupt or unsupported image header');
    if (info.numFrames != 1) throw UnsupportedError('Manual selection required: animated images are unsupported');
    if (info.width * info.height > (request['maxPixels'] as int)) {
      throw UnsupportedError('Manual selection required: raster pixel limit exceeded');
    }
    final decoded = decoder.decodeFrame(0);
    if (decoded == null) throw const FormatException('Corrupt image raster');
    // image 4.3 JPEG decoding already applies and clears EXIF orientation.
    // PNG or other remaining EXIF is honored exactly once by this operation.
    raster = img.bakeOrientation(decoded).convert(format: img.Format.uint8, numChannels: 4);
  } on UnsupportedError { rethrow; } on FormatException { rethrow; } catch (error) {
    throw FormatException('Corrupt or unsupported image: $error');
  }
  final width = raster.width;
  final height = raster.height;
  final regionJson = request['region'];
  if (regionJson != null) {
    final region = ImageRegionSnapshot.fromJson(Map<String, Object?>.from(regionJson as Map));
    if (width != region.pixelWidth || height != region.pixelHeight) throw StateError('Source raster dimensions changed');
    final b = region.geometry.boundsFor(pixelWidth: width, pixelHeight: height);
    final crop = img.Image(width: b.right - b.left, height: b.bottom - b.top, numChannels: 4);
    final g = region.geometry;
    final rx = g.width * width / 2;
    final ry = g.height * height / 2;
    final cx = g.x * width + rx;
    final cy = g.y * height + ry;
    for (var y = b.top; y < b.bottom; y++) {
      for (var x = b.left; x < b.right; x++) {
        final dx = (x + 0.5 - cx) / rx;
        final dy = (y + 0.5 - cy) / ry;
        if (g.shape == ImageRegionShape.ellipse && dx * dx + dy * dy > 1) {
          crop.setPixelRgba(x - b.left, y - b.top, 255, 255, 255, 255);
        } else {
          crop.setPixel(x - b.left, y - b.top, raster.getPixel(x, y));
        }
      }
    }
    raster = crop;
  }
  // A fresh raster drops all original metadata, including orientation.
  final canonical = img.Image(width: raster.width, height: raster.height, numChannels: 4);
  for (var y = 0; y < raster.height; y++) {
    for (var x = 0; x < raster.width; x++) { canonical.setPixel(x, y, raster.getPixel(x, y)); }
  }
  return {'width': width, 'height': height, 'bytes': Uint8List.fromList(img.encodePng(canonical))};
}
