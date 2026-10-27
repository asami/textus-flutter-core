import '../repository/local_capture_store.dart';
import 'recognition_report.dart';
import 'recognition_report_codec.dart';

/// Durable comparison history belonging to originals in this same store.
final class LocalRecognitionRepository {
  LocalRecognitionRepository({required this._store});
  static const collection = 'recognition_comparisons_v1';
  final LocalCaptureStore _store;
  Future<void> _pending = Future<void>.value();

  /// Ordered writes recover after errors, preserving original and old report.
  Future<void> save(RecognitionComparison comparison) {
    final document = RecognitionReportCodec.encode(comparison);
    final operation = _pending.then((_) async {
      await _store.readMaterial(comparison.material);
      final existing = await findById(comparison.id);
      if (existing != null && (existing.material != comparison.material ||
          existing.createdAt != comparison.createdAt)) {
        throw ArgumentError('Existing comparison original or creation time cannot change');
      }
      await _store.saveDocument(collection, comparison.id, document);
    });
    _pending = operation.then<void>((_) {}, onError: (Object error, StackTrace stackTrace) {});
    return operation;
  }

  Future<RecognitionComparison?> findById(String id) async {
    _token(id);
    final document = await _store.readDocument(collection, id);
    if (document == null) return null;
    final report = RecognitionReportCodec.decode(document);
    if (report.id != id) throw FormatException('Stored comparison identity mismatch for $id');
    return report;
  }

  Future<List<RecognitionComparison>> listForMaterial(String materialId) async {
    _token(materialId);
    final result = <RecognitionComparison>[];
    for (final id in await _store.listDocumentIds(collection)) {
      final report = await findById(id);
      if (report == null) throw FormatException('Listed comparison disappeared: $id');
      if (report.material.id == materialId) result.add(report);
    }
    result.sort((first, second) {
      final time = second.createdAt.compareTo(first.createdAt);
      return time == 0 ? first.id.compareTo(second.id) : time;
    });
    return List.unmodifiable(result);
  }
}

void _token(String value) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(value)) {
    throw ArgumentError.value(value, 'id', 'unsafe logical token');
  }
}
