import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  group('bounded native direct HTTP', () {
    test('on-demand original larger than 1MiB dispatches exact 256KiB ranges without credentials', () async {
      // Given a synthetic retained original generated only for the current requested range.
      const total = 1024 * 1024 + 73;
      final opened = <(int, int)>[];
      var offset = 0;
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        final end = offset + 262144 < total ? offset + 262144 : total;
        expect(request.method, 'PUT');
        expect(request.url.host, 'www.googleapis.com');
        expect(request.headers['Content-Range'], 'bytes $offset-${end - 1}/$total');
        expect(request.bodyBytes.length, end - offset);
        expect(request.bodyBytes.length, lessThanOrEqualTo(262144));
        expect(request.bodyBytes, List.generate(end - offset, (i) => _byte(offset + i)));
        expect(request.headers.keys.any((k) => k.toLowerCase() == 'authorization'), isFalse);
        expect(request.followRedirects, isFalse);
        offset = end;
        return end == total ? http.Response('{}', 201)
            : http.Response('', 308, headers: {'range': 'bytes=0-${end - 1}'});
      });
      addTearDown(client.close);
      // When the production client requests and sends each bounded next range.
      final receipt = await _client(client).uploadDirectStream(
        instruction: _streamInstruction(total), totalLength: total,
        openRange: (start, end) {
          opened.add((start, end));
          return _range(start, end);
        });
      // Then all actual source bytes are placed with only five ranges and a final completion receipt.
      expect(receipt.byteLength, total);
      expect(requests, 5);
      expect(opened, [(0, 262144), (262144, 524288), (524288, 786432),
        (786432, 1048576), (1048576, total)]);
    });
    test('partial 308 prefix reopens only acknowledged offset and full prefix needs an empty status PUT', () async {
      // Given a provider-confirmed resume offset and a partial first prefix.
      const total = 600000;
      var call = 0;
      final ranges = <(int, int)>[];
      final expected = [(17, 262161), (100017, 362161), (362161, total)];
      final client = MockClient((request) async {
        final index = call++;
        if (index == 3) {
          expect(request.bodyBytes, isEmpty);
          expect(request.headers['Content-Range'], 'bytes */$total');
          return http.Response('{}', 200);
        }
        final range = expected[index];
        expect(request.headers['Content-Range'], 'bytes ${range.$1}-${range.$2 - 1}/$total');
        expect(request.bodyBytes, List.generate(range.$2 - range.$1, (i) => _byte(range.$1 + i)));
        final acknowledged = index == 0 ? 100017 : range.$2;
        return http.Response('', 308, headers: {'Range': 'bytes=0-${acknowledged - 1}'});
      });
      addTearDown(client.close);
      // When the client proceeds strictly from confirmed contiguous prefixes.
      final receipt = await _client(client).uploadDirectStream(
        instruction: _streamInstruction(total, offset: 17), totalLength: total,
        openRange: (start, end) { ranges.add((start, end)); return _range(start, end); });
      // Then unacknowledged bytes are reread without inferring completion from bytes sent.
      expect(ranges, expected);
      expect(call, 4);
      expect(receipt.byteLength, total);
    });
    test('already acknowledged total sends only an empty status PUT', () async {
      // Given a resumed instruction whose total prefix is already confirmed.
      final client = MockClient((request) async {
        expect(request.bodyBytes, isEmpty);
        expect(request.headers['Content-Range'], 'bytes */9');
        return http.Response('{}', 200);
      });
      addTearDown(client.close);
      // When production direct streaming reconciles that total offset.
      final receipt = await _client(client).uploadDirectStream(
        instruction: _streamInstruction(9, offset: 9), totalLength: 9,
        openRange: (_, _) => throw StateError('No source range should open'));
      // Then provider completion is required but no original is reread.
      expect(receipt.byteLength, 9);
    });
    final invalidRanges = <String?>[null, '', 'bytes=1-10', 'bytes=0-0',
      'bytes=0-16', 'bytes=0-262161', 'bytes=0-999999', 'bytes=0-12,bytes=0-13',
      'bytes=0--1', 'bytes=0-abc', 'bytes=0-17 ', 'bytes=0-9999999999999999999999999999999'];
    for (var i = 0; i < invalidRanges.length; i++) {
      test('missing malformed regressing or excess 308 prefix case $i returns to reconciliation', () async {
        // Given a dispatched bounded range and an unusable provider prefix observation.
        var calls = 0;
        final client = MockClient((_) async {
          calls++;
          return http.Response('', 308, headers: {
            if (invalidRanges[i] != null) 'range': invalidRanges[i]!,
          });
        });
        addTearDown(client.close);
        // When the native direct client receives that ambiguous/incomplete result.
        await expectLater(_client(client).uploadDirectStream(
          instruction: _streamInstruction(600000, offset: 17), totalLength: 600000,
          openRange: _range), throwsA(isA<TklMaterialDeliveryHttpException>()
            .having((e) => e.code, 'code', 'uploadIncomplete')
            .having((e) => e.outcomeUnknown, 'unknown placement', isTrue)));
        // Then no completion receipt or blind retry is manufactured.
        expect(calls, 1);
      });
    }
    for (final status in [200, 201, 403, 503]) {
      test('nonfinal provider response $status cannot manufacture completion or switch routes', () async {
        // Given a multi-chunk original and an early success, refusal or unavailable reply.
        var calls = 0;
        final client = MockClient((_) async { calls++; return http.Response('', status); });
        addTearDown(client.close);
        // When the first nonfinal bounded PUT receives that reply.
        await expectLater(_client(client).uploadDirectStream(
          instruction: _streamInstruction(600000), totalLength: 600000, openRange: _range),
          throwsA(isA<TklMaterialDeliveryHttpException>()
            .having((e) => e.outcomeUnknown, 'unknown', status != 403)));
        // Then the caller must reconcile the same route; this client sends no further request.
        expect(calls, 1);
      });
    }
    test('lost provider response retains unknown outcome without replaying the bounded PUT', () async {
      // Given a peer that receives the final range and then loses its response connection.
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        expect(request.headers['Content-Range'], 'bytes 0-8/9');
        throw http.ClientException('private-session-response-loss', request.url);
      });
      addTearDown(client.close);
      // When the normal bounded HTTP operation observes a connection loss after dispatch.
      await expectLater(_client(client).uploadDirectStream(
        instruction: _streamInstruction(9), totalLength: 9, openRange: _range),
        throwsA(isA<TklMaterialDeliveryHttpException>()
          .having((e) => e.code, 'code', 'connectionFailed')
          .having((e) => e.outcomeUnknown, 'unknown', isTrue)
          .having((e) => e.toString(), 'safe display', isNot(contains('session-marker')))));
      // Then no duplicate PUT, session recovery guess or alternate route is attempted here.
      expect(calls, 1);
    });

    test('short or excessive range bytes fail before provider dispatch', () async {
      // Given range readers that disagree with a retained nine-byte declaration.
      var calls = 0;
      final client = MockClient((_) async { calls++; return http.Response('{}', 200); });
      addTearDown(client.close);
      for (final bytes in [Uint8List(8), Uint8List(10), Uint8List(65537)]) {
        // When the current range cannot be checked as exactly declared.
        await expectLater(_client(client).uploadDirectStream(
          instruction: _streamInstruction(9), totalLength: 9,
          openRange: (_, _) => Stream.value(bytes)),
          throwsA(isA<TklMaterialDeliveryHttpException>().having(
            (e) => e.outcomeUnknown, 'unknown', isFalse)));
        // Then no partial or invalid bytes are dispatched.
        expect(calls, 0);
      }
    });
    test('deadline cancels a stalled range and keeps the borrowed client usable', () async {
      // Given a source awaiting bytes with observable cancellation and a borrowed HTTP client.
      var canceled = false;
      var requests = 0;
      final source = StreamController<List<int>>(onCancel: () { canceled = true; });
      final client = MockClient((_) async { requests++; return http.Response('{}', 200); });
      addTearDown(client.close);
      // When the operation deadline expires while reading its first range.
      await expectLater(_client(client, timeout: const Duration(milliseconds: 15)).uploadDirectStream(
        instruction: _streamInstruction(9), totalLength: 9, openRange: (_, _) => source.stream),
        throwsA(isA<TklMaterialDeliveryHttpException>().having((e) => e.code, 'code', 'operationTimeout')));
      // Then its source is canceled before dispatch and the borrowed client remains reusable.
      expect(canceled, isTrue);
      expect(requests, 0);
      await source.close();
      final receipt = await _client(client).uploadDirectStream(
        instruction: _streamInstruction(9), totalLength: 9, openRange: _range);
      expect(receipt.byteLength, 9);
      expect(requests, 1);
    });
    test('cancellation after dispatch retains unknown outcome and releases the active source', () async {
      // Given a provider that holds its response after receiving the final bytes.
      final sent = Completer<void>();
      final reply = Completer<http.Response>();
      final cancellation = Completer<void>();
      var closed = false;
      final client = MockClient((_) { sent.complete(); return reply.future; });
      addTearDown(client.close);
      Stream<List<int>> source(int start, int end) async* {
        try { yield Uint8List(end - start); } finally { closed = true; }
      }
      final pending = _client(client, cancellation: cancellation.future).uploadDirectStream(
        instruction: _streamInstruction(9), totalLength: 9, openRange: source);
      // When the current operation is canceled after dispatch but before provider observation.
      await sent.future;
      cancellation.complete();
      await expectLater(pending, throwsA(isA<TklMaterialDeliveryHttpException>()
        .having((e) => e.code, 'code', 'operationCancelled')
        .having((e) => e.outcomeUnknown, 'unknown', isTrue)));
      // Then the source is released and a late provider success cannot return a receipt.
      expect(closed, isTrue);
      reply.complete(http.Response('{}', 200));
    });
  });

  test('a provider-confirmed full prefix uses an empty status PUT instead of sending bytes again', () async {
    // Given a provider-confirmed full prefix in the compatible byte-array API.
    final client = MockClient((request) async {
      expect(request.bodyBytes, isEmpty);
      expect(request.headers['Content-Range'], 'bytes */4');
      return http.Response('{"id":"provider-file"}', 200);
    });
    addTearDown(client.close);
    // When that existing API sends its empty status request.
    final receipt = await _client(
      client,
    ).uploadDirect(instruction: _instruction(offset: 4), content: Uint8List(4));
    // Then it returns only the actually observed completion.
    expect(receipt.byteLength, 4);
  });
  test('direct upload sends only the provider-confirmed remaining bytes without an application bearer', () async {
    // Given a provider that accepts the remaining range without application authorization.
    final client = MockClient((request) async {
      // Then the dispatched PUT has only the remaining bytes and no bearer or redirect.
      expect(request.method, 'PUT');
      expect(request.url.host, 'www.googleapis.com');
      expect(
        request.headers.keys.any(
          (name) => name.toLowerCase() == 'authorization',
        ),
        isFalse,
      );
      expect(request.headers['Content-Range'], 'bytes 2-3/4');
      expect(request.bodyBytes, [128, 255]);
      expect(request.followRedirects, isFalse);
      return http.Response('{"id":"provider-file"}', 201);
    });
    addTearDown(client.close);
    final remote = _client(client);
    final instruction = _instruction(offset: 2);
    // When the original bytes are uploaded from the provider-confirmed offset.
    final receipt = await remote.uploadDirect(
      instruction: instruction,
      content: Uint8List.fromList([0, 1, 128, 255]),
    );
    // Then the completion retains resource identity and hides the session in diagnostics.
    expect(receipt.resourceId, 'cover');
    expect(receipt.transferRef, 'server-transfer-1');
    expect(receipt.byteLength, 4);
    expect(instruction.toString(), isNot(contains('session-marker')));
  });

  test('direct instructions reject foreign origins, malformed authority and duplicate sessions before dispatch', () {
    // Given foreign, malformed or duplicate-session upload URIs.
    for (final uri in [
      'http://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=x',
      'https://attacker.test/upload/drive/v3/files?uploadType=resumable&upload_id=x',
      'https://user@www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=x',
      'https://www.googleapis.com/drive/v3/files?uploadType=resumable&upload_id=x',
      'https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=x&upload_id=y',
      'https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=x#fragment',
    ]) {
      // When an instruction is constructed with that URI,
      expect(() => _instruction(uri: uri),
          // Then construction rejects it before dispatch.
          throwsArgumentError);
    }
    // Given a four-byte original, When its confirmed offset exceeds its length,
    expect(() => _instruction(offset: 5),
        // Then construction rejects the invalid offset before dispatch.
        throwsArgumentError);
  });

  test('provider refusal remains an explicit failure without changing the transfer route', () async {
    // Given a provider that refuses the direct PUT with HTTP 403.
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('', 403);
    });
    addTearDown(client.close);
    // When the original is submitted through the direct upload route.
    await expectLater(
      _client(client)
          .uploadDirect(instruction: _instruction(), content: Uint8List(4)),
      // Then refusal is permissionDenied, known and non-retryable.
      throwsA(
        isA<TklMaterialDeliveryHttpException>()
            .having((error) => error.code, 'code', 'permissionDenied')
            .having((error) => error.outcomeUnknown, 'outcomeUnknown', isFalse)
            .having((error) => error.retryable, 'retryable', isFalse),
      ),
    );
    // Then exactly one provider call occurs.
    expect(calls, 1);
  });
}

TklDirectTransferInstruction _instruction({int offset = 0, String? uri}) =>
    TklDirectTransferInstruction(
      transferRef: 'server-transfer-1',
      resourceId: 'cover',
      mediaType: 'image/png',
      byteLength: 4,
      nextOffset: offset,
      uploadUri: Uri.parse(
        uri ?? 'https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=session-marker',
      ),
    );
TklMaterialDeliveryHttpClient _client(http.Client client, {
  Duration timeout = const Duration(seconds: 45), Future<void>? cancellation,
}) =>
    TklMaterialDeliveryHttpClient(
      connection: HttpSubmissionConnection(
        id: 'lake',
        endpoint: Uri.parse('https://lake.example/delivery/'),
      ),
      client: client,
      credentials: _NoCredentials(),
      operationTimeout: timeout, cancellation: cancellation,
    );

final class _NoCredentials implements SubmissionCredentialProvider {
  @override
  Future<String?> bearerToken(String connectionId) => throw StateError(
    'Direct provider transfer must not acquire application credentials',
  );
}

int _byte(int index) => (index * 17 + 3) % 251;
Stream<List<int>> _range(int start, int end) async* {
  for (var offset = start; offset < end;) {
    final limit = offset + 65536 < end ? offset + 65536 : end;
    yield List.generate(limit - offset, (i) => _byte(offset + i));
    offset = limit;
  }
}
TklDirectTransferInstruction _streamInstruction(int total, {int offset = 0}) =>
  TklDirectTransferInstruction(transferRef: 'retained-transfer', resourceId: 'original',
    uploadUri: Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=session-marker'),
    mediaType: 'application/octet-stream', byteLength: total, nextOffset: offset);
