import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  group('checked binary content digest', () {
    for (var i = 0; i < 16; i++) {
      test('ASCII hex digit $i normalizes and round trips without disclosure', () {
        // Given 64 ASCII hex digits, including uppercase input where applicable.
        final hex = List.filled(64, i.toRadixString(16).toUpperCase()).join();
        // When the checked value is constructed and decoded from its exact JSON.
        final digest = TklContentDigest(algorithm: 'sha256', value: hex);
        final decoded = TklContentDigest.fromJson(digest.toJson());
        // Then equality is content equality and ordinary display excludes the value.
        expect(digest.value, hex.toLowerCase());
        expect(decoded, digest);
        expect(decoded.hashCode, digest.hashCode);
        expect(digest.toJson(), {'algorithm': 'sha256', 'value': hex.toLowerCase()});
        expect(digest.toString(), isNot(contains(hex.toLowerCase())));
      });
    }
    final valid = List.filled(64, 'a').join();
    final invalid = <Object?>[
      null, [], 'sha256', 1, true, {}, {'algorithm': 'sha256'}, {'value': valid},
      {'algorithm': null, 'value': valid}, {'algorithm': 'sha256', 'value': null},
      {'algorithm': 'SHA256', 'value': valid}, {'algorithm': 'sha1', 'value': valid},
      {'algorithm': 'sha256', 'value': ''}, {'algorithm': 'sha256', 'value': valid.substring(1)},
      {'algorithm': 'sha256', 'value': '${valid}a'}, {'algorithm': 'sha256', 'value': ' $valid'},
      {'algorithm': 'sha256', 'value': '${valid.substring(1)}g'},
      {'algorithm': 'sha256', 'value': List.filled(64, 'Ａ').join()},
      {'algorithm': 'sha256', 'value': '$valid\n'},
      {'algorithm': 'sha256', 'value': valid, 'extra': null},
      {'algorithm': 'sha256', 'Value': valid},
      {'algorithm': 'sha256', 'value': 123},
    ];
    for (var i = 0; i < invalid.length; i++) {
      test('malformed digest JSON case $i is rejected', () {
        // Given malformed presence, type, shape, algorithm or non-ASCII hex.
        final value = invalid[i];
        // When the public checked decoder receives it.
        Object? observedError;
        try {
          TklContentDigest.fromJson(value);
        } catch (error) {
          observedError = error;
        }
        // Then no invalid expectation is accepted or reflected in diagnostics.
        expect(observedError, isA<FormatException>());
      });
    }
    test('published abc SHA vector is independent of source chunk boundaries', () async {
      // Given the published SHA-256 abc vector, split at every possible boundary.
      const expected = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
      for (final chunks in <List<List<int>>>[[[97, 98, 99]], [[97], [98, 99]], [[97, 98], [99]], [[97], [], [98], [99]]]) {
        var checks = 0;
        // When the normal bounded hash reads exactly those binary source chunks.
        final digest = await hashTklOriginalContent(store: _StreamStore(chunks),
          reference: _reference(3), checkCurrent: () { checks++; },
          timeout: const Duration(seconds: 1));
        // Then actual bytes produce the published vector with current-run checks during consumption.
        expect(digest.value, expected);
        expect(checks, greaterThan(chunks.length));
      }
    });
    test('count mismatch rejects short long and oversized source chunks', () async {
      // Given streams that disagree with the retained reference or chunk contract.
      for (final chunks in [<List<int>>[[97, 98]], [[97, 98, 99, 100]], [Uint8List(65537)]]) {
        // When hashing consumes the declared three-byte original.
        final pending = hashTklOriginalContent(store: _StreamStore(chunks),
          reference: _reference(3), checkCurrent: () {}, timeout: const Duration(seconds: 1));
        // Then no digest is returned for truncated/excess or unbounded source bytes.
        await expectLater(pending, throwsFormatException);
      }
    });
    test('cancellation fences the result and cancels the source', () async {
      // Given a source that retires the current run between its first and second chunks.
      var current = true;
      var closed = false;
      Stream<List<int>> source() async* {
        try { yield utf8.encode('a'); current = false; yield utf8.encode('bc'); }
        finally { closed = true; }
      }
      // When the explicit current-run check rejects the retired run.
      await expectLater(hashTklOriginalContent(store: _StreamStore.source(source),
        reference: _reference(3), checkCurrent: () {
          if (!current) throw StateError('retired');
        }, timeout: const Duration(seconds: 1)), throwsStateError);
      // Then no late digest is returned and the current stream is closed.
      expect(closed, isTrue);
    });
    test('stalled original respects its deadline and closes the current subscription', () async {
      // Given a retained source that never yields and records subscription cancellation.
      var closed = false;
      final controller = StreamController<List<int>>(onCancel: () { closed = true; });
      // When the hash deadline expires before the next chunk.
      await expectLater(hashTklOriginalContent(store: _StreamStore.source(() => controller.stream),
        reference: _reference(3), checkCurrent: () {}, timeout: const Duration(milliseconds: 15)),
        throwsA(isA<TimeoutException>()));
      // Then timed-out bytes cannot produce a digest and the reader is released.
      expect(closed, isTrue);
      await controller.close();
    });
  });
}

CaptureMaterialReference _reference(int length) => CaptureMaterialReference(
  id: 'original', mediaType: 'application/octet-stream', byteLength: length,
  capturedAt: DateTime.utc(2026));
final class _StreamStore implements StreamingLocalCaptureStore {
  _StreamStore(List<List<int>> chunks) : source = (() => Stream.fromIterable(chunks));
  _StreamStore.source(this.source);
  final Stream<List<int>> Function() source;
  @override
  Stream<List<int>> openMaterial(CaptureMaterialReference reference, {int start = 0, int? end}) => source();
}
