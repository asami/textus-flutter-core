import 'dart:async';

import 'package:crypto/crypto.dart';

import '../capture/capture_material.dart';
import '../repository/local_capture_store.dart';

/// Checked binary-content equality only; never a workflow identity or seal.
final class TklContentDigest {
  TklContentDigest({required String algorithm, required String value})
    : algorithm = algorithm,
      value = value.toLowerCase() {
    if (algorithm != 'sha256' ||
        value.length != 64 ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value)) {
      throw ArgumentError('Invalid original content digest.');
    }
  }

  factory TklContentDigest.fromJson(Object? json) {
    if (json is! Map ||
        json.length != 2 ||
        json['algorithm'] is! String ||
        json['value'] is! String) {
      throw const FormatException('Invalid original content digest.');
    }
    try {
      return TklContentDigest(
        algorithm: json['algorithm'] as String,
        value: json['value'] as String,
      );
    } on ArgumentError {
      throw const FormatException('Invalid original content digest.');
    }
  }

  final String algorithm;
  final String value;
  Map<String, Object?> toJson() => {'algorithm': algorithm, 'value': value};
  @override
  String toString() => 'TklContentDigest(sha256, <redacted>)';
  @override
  bool operator ==(Object other) =>
      other is TklContentDigest &&
      algorithm == other.algorithm && value == other.value;
  @override
  int get hashCode => Object.hash(algorithm, value);
}

/// Hashes actual final retained bytes without allocating a full original.
/// [checkCurrent] fences every read, including completion; it may throw.
Future<TklContentDigest> hashTklOriginalContent({
  required StreamingLocalCaptureStore store,
  required CaptureMaterialReference reference,
  required void Function() checkCurrent,
  required Duration timeout,
}) async {
  final clock = Stopwatch()..start();
  void check() {
    checkCurrent();
    if (clock.elapsed >= timeout) throw TimeoutException('Original hash timed out.');
  }
  check();
  Digest? result;
  final sink = sha256.startChunkedConversion(
    _DigestSink((digest) => result = digest),
  );
  late final StreamIterator<List<int>> reader;
  try {
    reader = StreamIterator<List<int>>(store.openMaterial(reference));
  } catch (_) {
    throw const FormatException('Retained original stream is unavailable.');
  }
  var count = 0;
  try {
    while (true) {
      check();
      late final bool hasNext;
      try {
        hasNext = await reader.moveNext().timeout(timeout - clock.elapsed);
      } on TimeoutException { rethrow;
      } catch (_) {
        throw const FormatException('Retained original stream is unavailable.');
      }
      if (!hasNext) break;
      check();
      final bytes = reader.current;
      if (bytes.length > 65536 || count + bytes.length > reference.byteLength) {
        throw const FormatException('Original stream length mismatch.');
      }
      count += bytes.length;
      sink.add(bytes);
    }
    check();
    if (count != reference.byteLength) {
      throw const FormatException('Original stream length mismatch.');
    }
    sink.close();
    return TklContentDigest(algorithm: 'sha256', value: result!.toString());
  } finally {
    clock.stop();
    await reader.cancel();
  }
}

final class _DigestSink implements Sink<Digest> {
  _DigestSink(this.accept);
  final void Function(Digest) accept;
  @override
  void add(Digest data) => accept(data);
  @override
  void close() {}
}
