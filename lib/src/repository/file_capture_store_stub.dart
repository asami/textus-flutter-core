import 'dart:typed_data';

import '../capture/capture_material.dart';
import 'local_capture_store.dart';

/// API-compatible storage boundary for platforms without dart:io.
final class FileCaptureStore
    implements LocalCaptureStore, StreamingLocalCaptureStore {
  /// Creates an unsupported-platform boundary; no durable storage is opened.
  FileCaptureStore(String directoryPath);

  @override
  Stream<List<int>> openMaterial(
    CaptureMaterialReference reference, {
    int start = 0,
    int? end,
  }) => throw _unsupported();

  /// Fails observably because original material cannot be persisted here.
  @override
  Future<CaptureMaterialReference> saveMaterial({
    required Uint8List bytes,
    required String mediaType,
    required DateTime capturedAt,
    String? originalName,
  }) async => throw _unsupported();

  /// Fails observably because local original material is unsupported.
  @override
  Future<Uint8List> readMaterial(CaptureMaterialReference reference) async =>
      throw _unsupported();

  /// Fails observably because durable document storage is unsupported.
  @override
  Future<void> saveDocument(
    String collection,
    String id,
    Map<String, Object?> document,
  ) async => throw _unsupported();

  /// Fails observably; unsupported storage never reports an absent document.
  @override
  Future<Map<String, Object?>?> readDocument(
    String collection,
    String id,
  ) async => throw _unsupported();

  /// Fails observably; unsupported storage never reports an empty collection.
  @override
  Future<List<String>> listDocumentIds(String collection) async =>
      throw _unsupported();
}

/// Throws [UnsupportedError] because this platform has no IO capture storage.
Future<LocalCaptureStore> openDefaultCaptureStore() async => throw _unsupported();

UnsupportedError _unsupported() => UnsupportedError(
  'Durable local capture storage requires a dart:io platform; web storage '
  'is not supported.',
);
