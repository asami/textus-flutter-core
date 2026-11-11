@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  late String namespace;
  final handles = <Future<void> Function()>[];
  final now = DateTime.utc(2026, 11, 7);
  setUp(() {
    namespace = 'phase7-browser-test-${DateTime.now().microsecondsSinceEpoch}';
  });
  tearDown(() async {
    for (final close in handles.reversed) {
      await close();
    }
    handles.clear();
    final done = Completer<void>();
    final request = web.window.indexedDB.deleteDatabase(
      'textus-capture/$namespace',
    );
    request.onsuccess = ((web.Event _) => done.complete()).toJS;
    request.onerror = ((web.Event _) => done.completeError(
      StateError('Test cleanup failed'),
    )).toJS;
    await done.future;
  });
  Future<BrowserCaptureStore> capture() async {
    final store = await BrowserCaptureStore.open(namespace: namespace);
    handles.add(store.close);
    return store;
  }

  Future<SubmissionQueueStore> queue() async {
    final store = await openBrowserSubmissionQueueStore(namespace: namespace);
    handles.add(store.close);
    return store;
  }

  SubmissionRequest intent(String id, {String? subject}) => SubmissionRequest(
    id: id,
    kind: 'syntheticImage',
    subjectId: subject ?? id,
    createdAt: now,
    document: {
      'opaque': [
        null,
        {'title': '窯変源氏物語'},
      ],
    },
    payload: {'title': '原画像の確認'},
    materials: [],
    transportConnectionId: 'studio',
  );

  test('original Blob and opaque documents survive independent handle reopening with bounded range reads', () async {
    // Given real isolated IndexedDB storage and caller-owned original bytes.
    var store = await capture();
    final bytes = Uint8List.fromList(List.generate(140000, (i) => i % 251));
    final expected = Uint8List.fromList(bytes);
    // When originals and opaque documents are retained, then the caller changes its buffer and closes this handle.
    final ref = await store.saveMaterial(
      bytes: bytes,
      mediaType: 'image/png',
      capturedAt: now,
      originalName: '表紙.png',
    );
    await store.saveDocument('books', 'book1', {
      'source': ref.toJson(),
      'opaque': [
        null,
        {'日本語': '第7巻'},
      ],
    });
    bytes.fillRange(0, bytes.length, 0);
    await store.close();
    store = await capture();
    // Then reopening returns exact originals/documents; ranges never yield more than64KiB per chunk.
    expect(await store.readMaterial(ref), expected);
    final chunks = await store
        .openMaterial(ref, start: 100, end: 130000)
        .toList();
    expect(chunks.every((c) => c.length <= 65536), isTrue);
    expect(chunks.expand((c) => c).toList(), expected.sublist(100, 130000));
    expect(await store.listDocumentIds('books'), ['book1']);
    expect((await store.readDocument('books', 'book1'))!['opaque'], [
      null,
      {'日本語': '第7巻'},
    ]);
    final detached = await store.readMaterial(ref);
    detached[0] = 255;
    expect((await store.readMaterial(ref))[0], expected[0]);
    final altered = CaptureMaterialReference(
      id: ref.id,
      mediaType: ref.mediaType,
      byteLength: ref.byteLength + 1,
      capturedAt: ref.capturedAt,
      originalName: ref.originalName,
    );
    await expectLater(store.readMaterial(altered), throwsFormatException);
  });

  test('independent browser queue handles atomically claim one immutable intent and retain unknown dispatch across reopening', () async {
    // Given two actual IndexedDB handles over the shared accepted queue engine.
    final a = await queue();
    final b = await queue();
    final request = intent('request1');
    await a.enqueue(request);
    expect((await b.enqueue(request)).request, request);
    // When both handles compete for the same ready job.
    final claims = await Future.wait([
      a.claimNext(
        now: now,
        leaseToken: 'ownerA',
        leaseDuration: const Duration(minutes: 1),
      ),
      b.claimNext(
        now: now,
        leaseToken: 'ownerB',
        leaseDuration: const Duration(minutes: 1),
      ),
    ]);
    // Then one owner wins; its uncertain dispatch survives failure/retry/reopen.
    expect(claims.whereType<SubmissionRecord>(), hasLength(1));
    final claimed = claims.whereType<SubmissionRecord>().single;
    await a.markTransportDispatch(
      id: request.id,
      leaseToken: claimed.leaseToken!,
      now: now,
    );
    await a.fail(
      id: request.id,
      leaseToken: claimed.leaseToken!,
      now: now,
      failure: SubmissionFailure(
        stage: SubmissionFailureStage.transport,
        code: 'unconfirmed',
        message: 'Synthetic lost reply',
        retryable: false,
        occurredAt: now,
        claimCount: claimed.claimCount,
      ),
    );
    await a.close();
    await b.close();
    final reopened = await queue();
    final retained = (await reopened.find(request.id))!;
    expect(retained.request, request);
    expect(retained.transportCheckpoint, isNotNull);
    final ready = await reopened.retry(
      id: request.id,
      now: now.add(const Duration(seconds: 1)),
    );
    expect(ready.transportCheckpoint, retained.transportCheckpoint);
    expect(
      await reopened.findForSubject(request.kind, request.subjectId),
      ready,
    );
  });

  test('cross-handle conflicting subjects roll back without replacing the winning intent', () async {
    // Given two independent handles attempting a different Commit for one subject.
    final a = await queue();
    final b = await queue();
    final first = intent('first', subject: 'shared');
    final second = intent('second', subject: 'shared');
    Future<bool> commit(
      SubmissionQueueStore store,
      SubmissionRequest request,
    ) async {
      try {
        await store.enqueue(request);
        return true;
      } on StateError {
        return false;
      }
    }

    // When both transactions enter the browser storage owner.
    final results = await Future.wait([commit(a, first), commit(b, second)]);
    // Then exactly one immutable intent remains and the losing transaction did not partially write.
    expect(results.where((v) => v), hasLength(1));
    final rows = await a.list();
    expect(rows, hasLength(1));
    expect(rows.single.request, results.first ? first : second);
    expect(await b.list(), rows);
  });
}
