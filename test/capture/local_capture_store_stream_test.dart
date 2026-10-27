import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  group('retained original streaming', () {
    late Directory directory;
    late FileCaptureStore store;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('original-stream-');
      store = FileCaptureStore(directory.path);
    });
    tearDown(() => directory.delete(recursive: true));

    test('fresh store reads exact half-open ranges and compatible original bytes', () async {
      // Given an actual retained original spanning several native read chunks.
      final bytes = Uint8List.fromList(List.generate(196619, (i) => i % 251));
      final reference = await store.saveMaterial(bytes: bytes,
        mediaType: 'image/jpeg', capturedAt: DateTime.utc(2026));
      final fresh = FileCaptureStore(directory.path);
      // When a reopened store reads full, crossing and empty ranges.
      final full = await fresh.openMaterial(reference).toList();
      final range = await fresh.openMaterial(reference, start: 65530, end: 131079).toList();
      final empty = await fresh.openMaterial(reference, start: 100, end: 100).toList();
      // Then actual bytes and range endpoints agree, with at most 64KiB per chunk.
      expect(full.expand((c) => c), bytes);
      expect(full.every((c) => c.length <= 65536), isTrue);
      expect(range.expand((c) => c), bytes.sublist(65530, 131079));
      expect(empty, isEmpty);
      expect(await fresh.readMaterial(reference), bytes);
    });

    test('incremental original larger than 32MiB hashes final bytes with bounded chunks', () async {
      // Given a native retained file created incrementally, without a full fixture allocation.
      const length = 33 * 1024 * 1024 + 19;
      final file = File('${directory.path}/materials/large.bin');
      await file.parent.create(recursive: true);
      final writer = await file.open(mode: FileMode.write);
      final block = Uint8List.fromList(List.generate(65536, (i) => (i * 17) % 251));
      try {
        var count = 0;
        while (count < length) {
          final size = length - count < block.length ? length - count : block.length;
          await writer.writeFrom(block, 0, size);
          count += size;
        }
        await writer.flush();
      } finally { await writer.close(); }
      final reference = _reference('large', length);
      // When a fresh store hashes the final retained original and an independent native reader hashes it.
      final digest = await hashTklOriginalContent(store: FileCaptureStore(directory.path),
        reference: reference, checkCurrent: () {}, timeout: const Duration(minutes: 2));
      final independent = await sha256.bind(file.openRead()).single;
      var count = 0;
      var maximum = 0;
      await for (final chunk in store.openMaterial(reference, start: 13, end: length - 7)) {
        count += chunk.length;
        if (chunk.length > maximum) maximum = chunk.length;
      }
      // Then independently observed content, exact range count and bounded allocation agree.
      expect(digest.value, independent.toString());
      expect(count, length - 20);
      expect(maximum, lessThanOrEqualTo(65536));
      expect(await file.length(), length);
    });

    test('missing truncated extended and nonregular originals fail without rewriting', () async {
      // Given a declared four-byte retained original and independently changed native storage.
      final reference = _reference('changed', 4);
      final file = File('${directory.path}/materials/changed.bin');
      await file.parent.create(recursive: true);
      // When absence, short length, excessive length and a directory occupy that logical original.
      await expectLater(store.openMaterial(reference).drain<void>(), throwsFormatException);
      for (final bytes in [[1, 2, 3], [1, 2, 3, 4, 5]]) {
        await file.writeAsBytes(bytes, flush: true);
        await expectLater(store.openMaterial(reference).drain<void>(), throwsFormatException);
        // Then failed streaming leaves the actual retained bytes intact.
        expect(await file.readAsBytes(), bytes);
      }
      await file.delete();
      await Directory(file.path).create();
      await expectLater(store.openMaterial(reference).drain<void>(), throwsFormatException);
      expect(await Directory(file.path).exists(), isTrue);
    });

    test('hostile ranges fail before filesystem access and hostile tokens are rejected', () async {
      // Given a reference with no file, so invalid ranges must fail before opening IO.
      final reference = _reference('absent', 5);
      // When negative, backwards and beyond-total half-open ranges are requested.
      for (final range in [(-1, 1), (4, 3), (0, 6), (6, 6)]) {
        await expectLater(store.openMaterial(reference, start: range.$1, end: range.$2).drain<void>(),
          throwsArgumentError);
      }
      // Then token traversal is refused by the checked reference before any reader exists.
      for (final token in ['../outside', '/absolute', 'a/b', 'a\\b', '', 'a\n']) {
        expect(() => _reference(token, 5), throwsArgumentError);
      }
      expect(await directory.list().toList(), isEmpty);
    });

    test('paused consumption applies backpressure and cancellation releases its reader', () async {
      // Given a native original longer than a single chunk and an explicit paused subscriber.
      final reference = await store.saveMaterial(bytes: Uint8List(262145),
        mediaType: 'audio/wav', capturedAt: DateTime.utc(2026));
      var chunks = 0;
      final first = Completer<void>();
      late StreamSubscription<List<int>> subscription;
      subscription = store.openMaterial(reference).listen((bytes) {
        chunks++;
        if (chunks == 1) { subscription.pause(); first.complete(); }
      });
      // When the subscriber yields multiple event turns while paused, then cancels.
      await first.future;
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(chunks, 1);
      await subscription.cancel();
      // Then no subsequent chunk arrives and a fresh reader can read the exact retained end.
      await Future<void>.delayed(Duration.zero);
      expect(chunks, 1);
      expect(await FileCaptureStore(directory.path).openMaterial(reference,
        start: reference.byteLength - 1).expand((c) => c).toList(), [0]);
    });

    test('length changes during consumption cannot complete successfully', () async {
      // Given a correctly sized file at open and a reader paused after its first native chunk.
      final reference = await store.saveMaterial(bytes: Uint8List(131073),
        mediaType: 'image/jpeg', capturedAt: DateTime.utc(2026));
      final iterator = StreamIterator(store.openMaterial(reference));
      expect(await iterator.moveNext(), isTrue);
      final file = File('${directory.path}/materials/${reference.id}.bin');
      // When another writer appends after streaming has begun.
      final writer = await file.open(mode: FileMode.append);
      await writer.writeByte(9);
      await writer.close();
      // Then final length rechecking rejects completion while retaining the external bytes.
      await expectLater(() async { while (await iterator.moveNext()) {} }, throwsFormatException);
      await iterator.cancel();
      expect(await file.length(), reference.byteLength + 1);
    });
  });
}

CaptureMaterialReference _reference(String id, int length) => CaptureMaterialReference(
  id: id, mediaType: 'application/octet-stream', byteLength: length,
  capturedAt: DateTime.utc(2026),
);
