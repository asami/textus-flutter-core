import 'dart:typed_data';

import '../capture/capture_material.dart';

/// Local durable storage for original materials and opaque JSON documents.
///
/// Core supplies persistence without defining application schema, capture
/// lifecycle, remote identity, synchronization, or submission policy.
abstract interface class LocalCaptureStore {
  /// Snapshots [bytes] before IO, preserving the complete original material.
  ///
  /// Returns a new logical reference only after durable storage succeeds.
  /// Throws for empty bytes/invalid media type or IO failure. The caller keeps
  /// ownership of its input. Unsupported platforms throw [UnsupportedError].
  Future<CaptureMaterialReference> saveMaterial({
    required Uint8List bytes,
    required String mediaType,
    required DateTime capturedAt,
    String? originalName,
  });

  /// Reads original bytes using [reference]'s logical id within this store.
  ///
  /// Returns caller-owned bytes. Missing or length-inconsistent data fails
  /// observably; unsupported platforms throw [UnsupportedError].
  Future<Uint8List> readMaterial(CaptureMaterialReference reference);

  /// Validates and snapshots an opaque JSON object before durable replacement.
  ///
  /// [collection] and [id] must be safe identity tokens. Invalid JSON or IO
  /// failure throws, preserving previously accepted data and original material.
  /// Writes on one instance run in invocation order and recover after failure.
  /// Unsupported platforms throw [UnsupportedError].
  Future<void> saveDocument(
    String collection,
    String id,
    Map<String, Object?> document,
  );

  /// Returns detached JSON, or null only when the document is absent.
  ///
  /// Invalid tokens throw [ArgumentError]; corrupted/nonobject JSON throws
  /// [FormatException]; IO and unsupported-platform errors remain observable.
  Future<Map<String, Object?>?> readDocument(String collection, String id);

  /// Lists sorted valid ids from final JSON files without parsing documents.
  ///
  /// An absent collection is empty. Invalid tokens, IO failures and unsupported
  /// platforms throw; temporary files and nonfile entries are ignored.
  Future<List<String>> listDocumentIds(String collection);
}
