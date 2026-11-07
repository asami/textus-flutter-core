import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../capture/capture_material.dart';
import '../submission/submission_queue_engine.dart';
import '../submission/submission_queue_store.dart';
import '../submission/submission_json.dart' as j;
import 'local_capture_store.dart';

const _stores = ['originals', 'documents', 'jobs', 'handoffs'];

Future<web.IDBDatabase> _openDatabase(String namespace) {
  if (namespace.trim().isEmpty ||
      namespace.length > 4096 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(namespace)) {
    throw ArgumentError('Invalid browser storage namespace');
  }
  final done = Completer<web.IDBDatabase>();
  final request = web.window.indexedDB.open('textus-capture/$namespace', 1);
  final timer = Timer(const Duration(seconds: 15), () {
    if (!done.isCompleted) {
      done.completeError(StateError('Browser storage could not be opened'));
    }
  });
  request.onupgradeneeded = ((web.Event _) {
    final db = request.result as web.IDBDatabase;
    for (final name in _stores) {
      if (!db.objectStoreNames.contains(name)) db.createObjectStore(name);
    }
  }).toJS;
  request.onerror = ((web.Event _) {
    timer.cancel();
    if (!done.isCompleted) {
      done.completeError(StateError('Browser storage could not be opened'));
    }
  }).toJS;
  request.onsuccess = ((web.Event _) {
    timer.cancel();
    final db = request.result as web.IDBDatabase;
    if (done.isCompleted) {
      db.close();
      return;
    }
    db.onversionchange = ((web.Event _) => db.close()).toJS;
    done.complete(db);
  }).toJS;
  return done.future;
}

Future<JSAny?> _request(web.IDBRequest request) {
  final done = Completer<JSAny?>();
  request.onsuccess = ((web.Event _) {
    done.complete(request.result);
  }).toJS;
  request.onerror = ((web.Event _) {
    done.completeError(StateError('Browser storage request failed'));
  }).toJS;
  return done.future;
}

Future<T> _atomic<T>(
  web.IDBDatabase db,
  List<String> stores,
  Future<T> Function(web.IDBTransaction) action,
) {
  final done = Completer<T>();
  final tx = db.transaction(
    stores.map((s) => s.toJS).toList().toJS,
    'readwrite',
  );
  T? value;
  Object? failure;
  StackTrace? failureStack;
  var actionDone = false;
  final timer = Timer(const Duration(seconds: 30), () {
    failure = StateError('Browser storage transaction timed out');
    try {
      tx.abort();
    } catch (_) {}
    if (!done.isCompleted) done.completeError(failure!);
  });
  void fail() {
    timer.cancel();
    if (!done.isCompleted) {
      done.completeError(
        failure ?? StateError('Browser storage transaction failed'),
        failureStack,
      );
    }
  }

  tx.onabort = ((web.Event _) => fail()).toJS;
  tx.onerror = ((web.Event _) => fail()).toJS;
  tx.oncomplete = ((web.Event _) {
    timer.cancel();
    if (!done.isCompleted) {
      if (!actionDone || failure != null) {
        fail();
      } else {
        done.complete(value as T);
      }
    }
  }).toJS;
  // IndexedDB auto-commits between event turns. Keep this bounded transaction
  // alive while the existing async semantic engine chains its own DB requests.
  void keepAlive() {
    if (actionDone || done.isCompleted) return;
    final pulse = tx
        .objectStore(stores.first)
        .get('__transaction_lifetime__'.toJS);
    pulse.onsuccess = ((web.Event _) => keepAlive()).toJS;
  }

  keepAlive();
  unawaited(() async {
    try {
      value = await action(tx);
      actionDone = true;
    } catch (error, stack) {
      failure = error;
      failureStack = stack;
      actionDone = true;
      try {
        tx.abort();
      } catch (_) {
        fail();
      }
    }
  }());
  return done.future;
}

/// Independent owned IndexedDB handle, preserving existing original/document DTOs.
final class BrowserCaptureStore
    implements LocalCaptureStore, StreamingLocalCaptureStore {
  BrowserCaptureStore._(this._db);
  final web.IDBDatabase _db;
  Future<void> _tail = Future.value();
  Future<void>? _closing;
  static Future<BrowserCaptureStore> open({required String namespace}) async =>
      BrowserCaptureStore._(await _openDatabase(namespace));
  Future<T> _operate<T>(Future<T> Function() action) {
    if (_closing != null) {
      return Future.error(StateError('Capture store is closed'));
    }
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<CaptureMaterialReference> saveMaterial({
    required Uint8List bytes,
    required String mediaType,
    required DateTime capturedAt,
    String? originalName,
  }) {
    final snapshot = Uint8List.fromList(bytes);
    final random = Random.secure();
    final id =
        'material-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    final reference = CaptureMaterialReference(
      id: id,
      mediaType: mediaType,
      byteLength: snapshot.length,
      capturedAt: capturedAt,
      originalName: originalName,
    );
    final blob = web.Blob(
      [snapshot.toJS].toJS,
      web.BlobPropertyBag(type: mediaType),
    );
    return _operate(
      () => _atomic(_db, ['originals'], (tx) async {
        final value = JSObject();
        value.setProperty('reference'.toJS, reference.toJson().jsify());
        value.setProperty('binary'.toJS, blob);
        await _request(tx.objectStore('originals').add(value, id.toJS));
        return reference;
      }),
    );
  }

  Future<web.Blob> _blob(CaptureMaterialReference reference) => _atomic(
    _db,
    ['originals'],
    (tx) async {
      final value = await _request(
        tx.objectStore('originals').get(reference.id.toJS),
      );
      if (value == null) throw StateError('Retained original is missing');
      final object = value as JSObject;
      final raw = object.getProperty<JSAny?>('reference'.toJS).dartify();
      if (raw is! Map) throw const FormatException('Invalid original metadata');
      final stored = CaptureMaterialReference.fromJson(
        Map<String, Object?>.from(raw),
      );
      final blob = object.getProperty<web.Blob>('binary'.toJS);
      if (stored != reference ||
          blob.size != reference.byteLength ||
          blob.type != reference.mediaType) {
        throw const FormatException('Retained original mismatch');
      }
      return blob;
    },
  );
  @override
  Future<Uint8List> readMaterial(CaptureMaterialReference reference) =>
      _operate(() async {
        final blob = await _blob(reference);
        final bytes = (await blob.arrayBuffer().toDart).toDart.asUint8List();
        if (bytes.length != reference.byteLength) {
          throw const FormatException('Retained original mismatch');
        }
        return Uint8List.fromList(bytes);
      });
  @override
  Stream<List<int>> openMaterial(
    CaptureMaterialReference reference, {
    int start = 0,
    int? end,
  }) async* {
    final stop = end ?? reference.byteLength;
    if (start < 0 || stop < start || stop > reference.byteLength) {
      throw RangeError('Invalid original range');
    }
    final blob = await _operate(() => _blob(reference));
    for (var offset = start; offset < stop; offset += 65536) {
      if (_closing != null) throw StateError('Capture store is closed');
      final bytes =
          (await blob
                  .slice(offset, min(offset + 65536, stop))
                  .arrayBuffer()
                  .toDart)
              .toDart
              .asUint8List();
      yield Uint8List.fromList(bytes);
    }
  }

  @override
  Future<void> saveDocument(
    String collection,
    String id,
    Map<String, Object?> document,
  ) {
    j.token(collection);
    j.token(id);
    final body = jsonEncode(j.frozenJson(document));
    return _operate(
      () => _atomic(_db, ['documents'], (tx) async {
        await _request(
          tx
              .objectStore('documents')
              .put(
                {'collection': collection, 'id': id, 'body': body}.jsify()!,
                [collection, id].jsify(),
              ),
        );
      }),
    );
  }

  @override
  Future<Map<String, Object?>?> readDocument(String collection, String id) {
    j.token(collection);
    j.token(id);
    return _operate(
      () => _atomic(_db, ['documents'], (tx) async {
        final value = (await _request(
          tx.objectStore('documents').get([collection, id].jsify()!),
        )).dartify();
        if (value == null) return null;
        if (value is! Map ||
            value['collection'] != collection ||
            value['id'] != id ||
            value['body'] is! String) {
          throw const FormatException('Invalid retained document');
        }
        return j.object(jsonDecode(value['body'] as String));
      }),
    );
  }

  @override
  Future<List<String>> listDocumentIds(String collection) {
    j.token(collection);
    return _operate(
      () => _atomic(_db, ['documents'], (tx) async {
        final values = (await _request(tx.objectStore('documents').getAll()))
            .dartify();
        if (values is! List) {
          throw const FormatException('Invalid document index');
        }
        final result = <String>[];
        for (final value in values) {
          if (value is! Map ||
              value['collection'] is! String ||
              value['id'] is! String) {
            throw const FormatException('Invalid document index');
          }
          if (value['collection'] == collection) {
            result.add(j.token(value['id'] as String));
          }
        }
        return result..sort();
      }),
    );
  }

  Future<void> close() => _closing ??= _tail.then((_) {
    _db.close();
  });
}

Future<SubmissionQueueStore> openBrowserSubmissionQueueStore({
  required String namespace,
}) async => SubmissionQueueEngine(
  _BrowserQueuePersistence(await _openDatabase(namespace)),
);

final class _BrowserQueuePersistence implements SubmissionQueuePersistence {
  _BrowserQueuePersistence(this.db);
  final web.IDBDatabase db;
  @override
  Future<T> transaction<T>(
    Future<T> Function(SubmissionQueueTransaction) action,
  ) => _atomic(db, [
    'jobs',
    'handoffs',
  ], (tx) => action(_BrowserQueueTransaction(tx)));
  @override
  Future<void> close() async {
    db.close();
  }
}

final class _BrowserQueueTransaction implements SubmissionQueueTransaction {
  _BrowserQueueTransaction(this.tx);
  final web.IDBTransaction tx;
  web.IDBObjectStore _store(SubmissionStoreTable table) =>
      tx.objectStore(table.name);
  String _key(SubmissionStoreTable table, Map<String, Object?> row) => j.token(
    row[table == SubmissionStoreTable.jobs ? 'request_id' : 'handoff_id']
        as String,
  );
  @override
  Future<List<Map<String, Object?>>> rows(
    SubmissionStoreTable table, {
    Map<String, Object?> equals = const {},
  }) async {
    final value = (await _request(_store(table).getAll())).dartify();
    if (value is! List) throw const FormatException('Invalid queue index');
    final result = <Map<String, Object?>>[];
    for (final raw in value) {
      if (raw is! Map) throw const FormatException('Invalid queue record');
      final row = Map<String, Object?>.from(raw);
      if (equals.entries.every((e) => row[e.key] == e.value)) result.add(row);
    }
    return result;
  }

  @override
  Future<void> insert(
    SubmissionStoreTable table,
    Map<String, Object?> values,
  ) async {
    await _request(
      _store(table).add(values.jsify()!, _key(table, values).toJS),
    );
  }

  @override
  Future<int> update(
    SubmissionStoreTable table,
    Map<String, Object?> values, {
    required Map<String, Object?> equals,
  }) async {
    final found = await rows(table, equals: equals);
    for (final row in found) {
      final next = {...row, ...values};
      await _request(_store(table).put(next.jsify()!, _key(table, row).toJS));
    }
    return found.length;
  }
}
