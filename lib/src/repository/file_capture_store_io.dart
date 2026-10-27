import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../capture/capture_material.dart';
import 'local_capture_store.dart';

/// Filesystem-backed durable original materials and opaque JSON documents.
///
/// Writes use a flushed temporary file and atomic rename within the same
/// directory. One instance serializes writes; separate instances use ordinary
/// atomic replacement without an interprocess lock or transaction engine.
final class FileCaptureStore
    implements LocalCaptureStore, StreamingLocalCaptureStore {
  /// Configures this store's root; directories are created when saving.
  ///
  /// [directoryPath] belongs to the caller. Permission/path/IO errors propagate
  /// from operations. No material garbage collection or broad cleanup occurs.
  FileCaptureStore(String directoryPath) : _root = Directory(directoryPath);

  final Directory _root;
  final Random _random = Random.secure();
  Future<void> _pendingWrite = Future<void>.value();

  /// Snapshots bytes immediately and returns a new reference after flushed IO.
  ///
  /// Throws [ArgumentError] for empty bytes or invalid media type; filesystem
  /// failures propagate. Original names are descriptive, never path components.
  @override
  Future<CaptureMaterialReference> saveMaterial({
    required Uint8List bytes,
    required String mediaType,
    required DateTime capturedAt,
    String? originalName,
  }) {
    try {
      final snapshot = Uint8List.fromList(bytes);
      // Validate descriptive data before any queued filesystem work.
      final description = CaptureMaterialReference(
        id: 'pending',
        mediaType: mediaType,
        byteLength: snapshot.length,
        capturedAt: capturedAt,
        originalName: originalName,
      );
      return _enqueue(() async {
        final directory = Directory(_child(_root.path, 'materials'));
        await directory.create(recursive: true);
        String id;
        File destination;
        do {
          id = _newToken();
          destination = File(_child(directory.path, '$id.bin'));
        } while (await FileSystemEntity.type(destination.path) !=
            FileSystemEntityType.notFound);
        await _replace(destination, snapshot);
        return CaptureMaterialReference(
          id: id,
          mediaType: description.mediaType,
          byteLength: description.byteLength,
          capturedAt: description.capturedAt,
          originalName: description.originalName,
        );
      });
    } catch (error, stackTrace) {
      return Future<CaptureMaterialReference>.error(error, stackTrace);
    }
  }

  /// Returns original caller-owned bytes; missing files and IO errors propagate.
  /// A length mismatch throws [FormatException] without changing the file.
  @override
  Future<Uint8List> readMaterial(CaptureMaterialReference reference) async {
    final id = _requireToken(reference.id, 'id');
    final bytes = await File(_child(_child(_root.path, 'materials'), '$id.bin'))
        .readAsBytes();
    if (bytes.length != reference.byteLength) {
      throw FormatException('Original material length mismatch for $id');
    }
    return bytes;
  }

  @override
  Stream<List<int>> openMaterial(
    CaptureMaterialReference reference, {
    int start = 0,
    int? end,
  }) async* {
    final id = _requireToken(reference.id, 'id');
    final limit = end ?? reference.byteLength;
    if (start < 0 || limit < start || limit > reference.byteLength) {
      throw ArgumentError('Invalid original material range.');
    }
    final file = File(_child(_child(_root.path, 'materials'), '$id.bin'));
    try {
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FormatException('Original material is not a regular file.');
    }
    final reader = await file.open(mode: FileMode.read);
    try {
      if (await reader.length() != reference.byteLength) {
        throw const FormatException('Original material length mismatch.');
      }
      await reader.setPosition(start);
      var remaining = limit - start;
      while (remaining > 0) {
        final bytes = await reader.read(min(65536, remaining));
        if (bytes.isEmpty) {
          throw const FormatException('Original material range is truncated.');
        }
        remaining -= bytes.length;
        yield bytes;
      }
      if (await reader.position() != limit ||
          await reader.length() != reference.byteLength ||
          await file.length() != reference.byteLength) {
        throw const FormatException('Original material length changed.');
      }
    } finally {
      await reader.close();
    }
    } on FileSystemException {
      throw const FormatException('Retained original could not be read.');
    }
  }

  /// Encodes a strict JSON snapshot before enqueueing atomic replacement.
  /// Invalid tokens/JSON throw [ArgumentError]; IO errors propagate without
  /// deleting accepted documents or any original material.
  @override
  Future<void> saveDocument(
    String collection,
    String id,
    Map<String, Object?> document,
  ) {
    try {
      final destination = _documentFile(collection, id);
      final snapshot = _snapshotJson(document, HashSet<Object>.identity());
      final bytes = utf8.encode(jsonEncode(snapshot));
      return _enqueue(() => _replace(destination, bytes));
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  /// Returns a fresh JSON object, null only for an absent file.
  /// Absence is observed by this read; a later call may see a concurrent creation.
  /// Invalid tokens throw [ArgumentError]; corruption/nonobject JSON throws
  /// [FormatException]. Other IO errors propagate and the source stays intact.
  @override
  Future<Map<String, Object?>?> readDocument(
    String collection,
    String id,
  ) async {
    final file = _documentFile(collection, id);
    String contents;
    try {
      contents = await file.readAsString();
    } on FileSystemException catch (error) {
      if (_isMissingPath(error)) {
        return null;
      }
      rethrow;
    }
    final value = jsonDecode(contents);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Capture document must be a JSON object');
    }
    return Map<String, Object?>.from(value);
  }

  /// Lists sorted safe tokens from final regular JSON files without parsing.
  /// An absent collection is empty; invalid tokens and IO failures throw.
  /// Absence is observed by this listing; a later call may see new documents.
  @override
  Future<List<String>> listDocumentIds(String collection) async {
    final directory = _collectionDirectory(collection);
    final ids = <String>[];
    try {
      await for (final entry in directory.list(followLinks: false)) {
        if (entry is! File) continue;
        final name = entry.uri.pathSegments.last;
        if (!name.endsWith('.json')) continue;
        final id = name.substring(0, name.length - '.json'.length);
        if (_isToken(id)) ids.add(id);
      }
    } on FileSystemException catch (error) {
      if (_isMissingPath(error)) {
        return <String>[];
      }
      rethrow;
    }
    return ids..sort();
  }

  Directory _collectionDirectory(String collection) => Directory(
    _child(
      _child(_root.path, 'documents'),
      _requireToken(collection, 'collection'),
    ),
  );

  File _documentFile(String collection, String id) => File(
    _child(
      _collectionDirectory(collection).path,
      '${_requireToken(id, 'id')}.json',
    ),
  );

  String _newToken() => List<String>.generate(
    32,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  Future<T> _enqueue<T>(Future<T> Function() write) {
    final operation = _pendingWrite.then((_) => write());
    _pendingWrite = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return operation;
  }

  Future<void> _replace(File destination, List<int> bytes) async {
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.${_newToken()}.tmp');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(destination.path);
    } catch (_) {
      // Only this operation's temporary file may be cleaned, preserving the
      // primary error even if cleanup itself fails.
      try {
        if (await temporary.exists()) await temporary.delete();
      } on FileSystemException {
        // The original operation's exception remains observable.
      }
      rethrow;
    }
  }
}

/// Opens durable IO storage under application support / textus_capture.
/// Directory-provider and filesystem errors propagate; no memory fallback is
/// returned. Each call returns a new store over the same application root.
Future<LocalCaptureStore> openDefaultCaptureStore() async {
  final support = await getApplicationSupportDirectory();
  return FileCaptureStore(_child(support.path, 'textus_capture'));
}

String _child(String parent, String name) =>
    '$parent${Platform.pathSeparator}$name';

bool _isMissingPath(FileSystemException error) =>
    error.osError?.errorCode == 2 ||
    (Platform.isWindows && error.osError?.errorCode == 3);

bool _isToken(String value) =>
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(value);

String _requireToken(String value, String name) {
  if (!_isToken(value)) {
    throw ArgumentError.value(value, name, 'must be a safe identity token');
  }
  return value;
}

Object? _snapshotJson(Object? value, Set<Object> ancestors) {
  if (value == null || value is String || value is bool) return value;
  if (value is num && value.isFinite) return value;
  if (value is! Map && value is! List) {
    throw ArgumentError.value(value, 'document', 'must contain only JSON');
  }
  if (!ancestors.add(value)) throw ArgumentError('JSON must not be cyclic');
  try {
    if (value is Map) {
      final copy = <String, Object?>{};
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw ArgumentError('JSON document keys must be strings');
        }
        copy[entry.key as String] = _snapshotJson(entry.value, ancestors);
      }
      return copy;
    }
    return (value as List)
        .map((item) => _snapshotJson(item, ancestors))
        .toList();
  } finally {
    ancestors.remove(value);
  }
}
