import 'dart:typed_data';

import '../capture/capture_material.dart';
import '../submission/submission_queue_store.dart';
import 'local_capture_store.dart';

final class BrowserCaptureStore
    implements LocalCaptureStore, StreamingLocalCaptureStore {
  BrowserCaptureStore._();
  static Future<BrowserCaptureStore> open({required String namespace}) async =>
      throw UnsupportedError('Browser durable storage is unavailable');
  @override
  Future<CaptureMaterialReference> saveMaterial({
    required Uint8List bytes,
    required String mediaType,
    required DateTime capturedAt,
    String? originalName,
  }) async => throw UnsupportedError('Browser durable storage is unavailable');
  @override
  Future<Uint8List> readMaterial(CaptureMaterialReference reference) async =>
      throw UnsupportedError('Browser durable storage is unavailable');
  @override
  Stream<List<int>> openMaterial(
    CaptureMaterialReference reference, {
    int start = 0,
    int? end,
  }) => throw UnsupportedError('Browser durable storage is unavailable');
  @override
  Future<void> saveDocument(
    String collection,
    String id,
    Map<String, Object?> document,
  ) async => throw UnsupportedError('Browser durable storage is unavailable');
  @override
  Future<Map<String, Object?>?> readDocument(
    String collection,
    String id,
  ) async => throw UnsupportedError('Browser durable storage is unavailable');
  @override
  Future<List<String>> listDocumentIds(String collection) async =>
      throw UnsupportedError('Browser durable storage is unavailable');
  Future<void> close() async {}
}

Future<SubmissionQueueStore> openBrowserSubmissionQueueStore({
  required String namespace,
}) async => throw UnsupportedError('Browser durable queue is unavailable');
