import 'dart:typed_data';

import '../repository/file_capture_store.dart';
import '../repository/local_capture_store.dart';
import '../settings/recognition_settings.dart';
import 'camera_service.dart';
import 'capture_material.dart';
import 'gemini_nano_image_recognition_provider.dart';
import 'image_picker_camera_provider.dart';
import 'image_recognition_service.dart';
import 'mlkit_image_recognition_provider.dart';
import 'photo_capture.dart';
import 'recognition_configuration.dart';
import 'recognition_operation_context.dart';
import 'recognition_report.dart';
import 'recognition_repository.dart';

/// Saves originals durably, with explicit recognition returning durable reports.
final class PhotoCaptureService {
  PhotoCaptureService({
    required this._camera, required this._recognition,
    required LocalCaptureStore store,
  }) : _store = store,
       reports = LocalRecognitionRepository(store: store);
  final CameraService _camera;
  final ImageRecognitionService _recognition;
  final LocalCaptureStore _store;
  final LocalRecognitionRepository reports;
  bool _busy = false;
  bool get isSupported => _camera.isSupported;
  List<RecognitionConfiguration> get configurations => _recognition.configurations;

  Future<List<RecognitionProviderAvailability>> availability() =>
      _operate(_recognition.availability);

  Future<RecognitionProviderAvailability> prepareProvider(String providerId) =>
      _operate(() => _recognition.prepareProvider(providerId));

  /// Saves the exact camera original without settings, providers or a report.
  /// Returns null on cancellation; camera/import errors propagate unchanged.
  Future<CaptureMaterialReference?> captureOriginal() =>
      _operate(() => _importOriginal(_camera.capture));

  /// Durably imports one recovered original without recognition or a report.
  /// Returns null for empty recovery; shares the guard with all photo operations.
  Future<CaptureMaterialReference?> recoverOriginal() =>
      _operate(() => _importOriginal(_camera.recover));

  /// Reads the exact saved original while holding the shared photo guard.
  /// Requires no camera support or model readiness; store errors remain unchanged.
  Future<Uint8List> readOriginal(CaptureMaterialReference material) =>
      _operate(() => _store.readMaterial(material));

  /// Captures and durably recognizes with optional caller intent for this call.
  Future<RecognitionComparison?> capture({
    required String desiredConfigurationId,
    RecognitionOperationContext? operationContext,
  }) => _acquire(desiredConfigurationId, _camera.capture, operationContext);

  /// Recovers and durably recognizes with optional caller intent for this call.
  Future<RecognitionComparison?> recover({
    required String desiredConfigurationId,
    RecognitionOperationContext? operationContext,
  }) => _acquire(desiredConfigurationId, _camera.recover, operationContext);

  /// Recognizes one saved original without importing it again.
  Future<RecognitionComparison> recognize(CaptureMaterialReference material, {
    required String desiredConfigurationId,
    RecognitionOperationContext? operationContext,
  }) => compare(material, configurationIds: [desiredConfigurationId],
    operationContext: operationContext);

  /// Compares selected routes using the same optional intent and saved original.
  Future<RecognitionComparison> compare(CaptureMaterialReference material, {
    Iterable<String>? configurationIds,
    RecognitionOperationContext? operationContext,
  }) => _operate(() async {
    final selection = _selection(configurationIds ?? const [
      RecognitionSettings.androidStandard, RecognitionSettings.pixelEnhanced,
    ]);
    return _recognize(material, selection, operationContext);
  });

  Future<RecognitionComparison?> _acquire(
    String desired, Future<CapturedPhoto?> Function() acquire,
    RecognitionOperationContext? operationContext,
  ) => _operate(() async {
    final selection = _selection([desired]);
    final material = await _importOriginal(acquire);
    if (material == null) {
      return null;
    }
    return _recognize(material, selection, operationContext);
  });

  Future<CaptureMaterialReference?> _importOriginal(
    Future<CapturedPhoto?> Function() acquire,
  ) async {
    final photo = await acquire();
    if (photo == null) {
      return null;
    }
    return _store.saveMaterial(
      bytes: photo.bytes, mediaType: photo.mediaType, capturedAt: photo.capturedAt,
      originalName: photo.originalName,
    );
  }

  Future<RecognitionComparison> _recognize(
    CaptureMaterialReference material, List<String> selection,
    RecognitionOperationContext? operationContext,
  ) async {
    final bytes = await _store.readMaterial(material);
    final comparison = await _recognition.recognize(
      input: ImageRecognitionInput(material: material, bytes: bytes,
        operationContext: operationContext), configurationIds: selection,
    );
    await reports.save(comparison);
    return comparison;
  }

  List<String> _selection(Iterable<String> ids) {
    final selection = List<String>.of(ids);
    final known = _recognition.configurations.map((item) => item.id).toSet();
    if (selection.isEmpty || selection.toSet().length != selection.length ||
        selection.any((id) => !known.contains(id))) {
      throw ArgumentError('Select distinct known configurations');
    }
    return selection;
  }
  Future<T> _operate<T>(Future<T> Function() operation) async {
    if (_busy) {
      throw StateError('A photo operation is already active');
    }
    _busy = true;
    try {
      return await operation();
    } finally {
      _busy = false;
    }
  }
}

/// Caller owns services/providers; optional native registration remains truthful.
Future<PhotoCaptureService> openDefaultPhotoCaptureService({
  LocalCaptureStore? store,
  Iterable<ImageRecognitionProvider> additionalProviders = const [],
}) async {
  final additional = List<ImageRecognitionProvider>.of(additionalProviders);
  final hasNano = additional.any(
    (provider) => provider.descriptor.id == RecognitionConfigurations.enhancedProviderId,
  );
  final registry = RecognitionProviderRegistry(providers: [
    MlKitImageRecognitionProvider(),
    if (!hasNano) GeminiNanoImageRecognitionProvider(),
    ...additional,
  ]);
  return PhotoCaptureService(
    camera: CameraService(provider: ImagePickerCameraProvider()),
    recognition: ImageRecognitionService(registry: registry),
    store: store ?? await openDefaultCaptureStore(),
  );
}
