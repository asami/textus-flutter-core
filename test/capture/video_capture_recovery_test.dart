import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

final _time = DateTime.utc(2026, 11, 8);
final _target = VideoRecoveryTarget(ownerId: 'book-1', elementId: 'note-1');
final _other = VideoRecoveryTarget(ownerId: 'book-2', elementId: 'note-2');
// Container-only fixture; these tests make no decoder/playback claim.
Uint8List _bytes() => Uint8List.fromList([
  0,
  0,
  0,
  20,
  ...'ftypmp42'.codeUnits,
  0,
  0,
  0,
  0,
  ...'mp42'.codeUnits,
]);
CapturedVideo _video() => CapturedVideo(
  bytes: _bytes(),
  capturedAt: _time,
  originalName: 'original.mp4',
);

void main() {
  late Directory directory;
  late _Store store;
  late _Video provider;
  late VideoCaptureRecovery service;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('video-recovery-');
    store = _Store(FileCaptureStore(directory.path));
    provider = _Video();
    service = VideoCaptureRecovery(
      store: store,
      provider: provider,
      now: () => _time,
    );
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
    'a fresh save owner acknowledges only the exact ready target and original',
    () async {
      // Given an original retained by an input lifetime that has since ended.
      final original = (await service.acquire(target: _target, label: '注釈1'))!;
      final pending = (await service.pending())!;
      service.retire();
      final fresh = FileCaptureStore(directory.path);
      final different = await fresh.saveMaterial(
        bytes: _bytes(),
        mediaType: 'video/mp4',
        capturedAt: _time,
      );
      // When a stale owner or another reference claims that the association was saved.
      for (final mismatch in [(_other, original), (_target, different)]) {
        await expectLater(
          VideoCaptureRecovery.acknowledgeStored(
            fresh,
            id: pending.id,
            target: mismatch.$1,
            original: mismatch.$2,
          ),
          throwsStateError,
        );
        expect((await VideoCaptureRecovery.pendingIn(fresh))!.id, pending.id);
      }
      // Then only the exact saved association retires the intent, keeping its bytes.
      await VideoCaptureRecovery.acknowledgeStored(
        fresh,
        id: pending.id,
        target: _target,
        original: original,
      );
      expect(
        await VideoCaptureRecovery.pendingIn(FileCaptureStore(directory.path)),
        isNull,
      );
      expect(await fresh.readMaterial(original), _bytes());
      expect(await fresh.readMaterial(different), _bytes());
    },
  );

  test('persisted target precedes the OS picker and a fresh owner recovers the same video', () async {
    // Given a picker interrupted after its target was durably recorded.
    provider.captureAction = () async {
      final intent = await VideoCaptureRecovery.pendingIn(
        FileCaptureStore(directory.path),
      );
      expect(intent!.target, _target);
      expect(intent.state, VideoRecoveryState.acquiring);
      throw StateError('simulated process interruption');
    };
    await expectLater(
      service.acquire(target: _target, label: '第7巻・注釈1'),
      throwsStateError,
    );
    // When a new store/service explicitly recovers for that exact target.
    final freshProvider = _Video();
    final freshStore = FileCaptureStore(directory.path);
    final fresh = VideoCaptureRecovery(
      store: freshStore,
      provider: freshProvider,
    );
    final pending = (await fresh.pending())!;
    final original = (await fresh.recover(id: pending.id, target: _target))!;
    // Then the complete original is durable, without a Book document or new capture.
    expect(freshProvider.captures, 0);
    expect(freshProvider.recoveries, 1);
    expect(await freshStore.readMaterial(original), _bytes());
    expect(
      await freshStore.listDocumentIds('annotation_candidates_v1'),
      isEmpty,
    );
    final repeatedProvider = _Video();
    final repeated = VideoCaptureRecovery(
      store: freshStore,
      provider: repeatedProvider,
    );
    expect(await repeated.recover(id: pending.id, target: _target), original);
    expect(repeatedProvider.recoveries, 0);
    await repeated.acknowledge(
      id: pending.id,
      target: _target,
      original: original,
    );
    expect(await repeated.pending(), isNull);
  });

  test('another target or stale acquisition id cannot consume global picker data', () async {
    // Given a retained pending acquisition owned by one exact target.
    provider.captureAction = () async => throw StateError('interrupted');
    await expectLater(
      service.acquire(target: _target, label: '元の注釈'),
      throwsStateError,
    );
    final pending = (await service.pending())!;
    final before = await store.readDocument(
      VideoCaptureRecovery.collection,
      VideoCaptureRecovery.documentId,
    );
    // When another Book, stale action or new capture attempts to take it over.
    await expectLater(
      service.recover(id: pending.id, target: _other),
      throwsStateError,
    );
    await expectLater(
      service.recover(id: 'stale-id', target: _target),
      throwsStateError,
    );
    await expectLater(
      service.acquire(target: _other, label: '別の注釈'),
      throwsStateError,
    );
    // Then neither the SDK response nor persisted target is consumed/replaced.
    expect(provider.recoveries, 0);
    expect(provider.captures, 1);
    expect(
      await store.readDocument(
        VideoCaptureRecovery.collection,
        VideoCaptureRecovery.documentId,
      ),
      before,
    );
  });

  test('intent write failure prevents camera launch; ready write failure retries the saved original once', () async {
    // Given an unavailable persistence boundary before any OS operation.
    store.failIntent = true;
    await expectLater(
      service.acquire(target: _target, label: '注釈'),
      throwsStateError,
    );
    expect(provider.captures, 0);
    // When metadata fails after the original was already saved.
    store.failIntent = false;
    store.failReadyOnce = true;
    await expectLater(
      service.acquire(target: _target, label: '注釈'),
      throwsStateError,
    );
    expect(store.materialSaves, 1);
    final pending = (await service.pending())!;
    final recovered = (await service.recover(id: pending.id, target: _target))!;
    // Then retry acknowledges those exact saved bytes, not a second SDK read/import.
    expect(store.materialSaves, 1);
    expect(provider.recoveries, 0);
    expect(await store.readMaterial(recovered), _bytes());
  });

  test('absence preserves unresolved intent; explicit discard never deletes an original', () async {
    // Given a process-interrupted request with no currently returned SDK video.
    provider.captureAction = () async => throw StateError('interrupted');
    await expectLater(
      service.acquire(target: _target, label: '注釈'),
      throwsStateError,
    );
    final pending = (await service.pending())!;
    provider.lost = null;
    expect(await service.recover(id: pending.id, target: _target), isNull);
    expect((await service.pending())!.id, pending.id);
    await expectLater(
      VideoCaptureRecovery.requireNoPending(store),
      throwsStateError,
    );
    // When the user explicitly discards, then later retains a different capture.
    await service.discard(id: pending.id, target: _target);
    provider.captureAction = () async => _video();
    final original = (await service.acquire(target: _other, label: '別の注釈'))!;
    final next = (await service.pending())!;
    await service.discard(id: next.id, target: _other);
    // Then retirement releases the picker slot while keeping original bytes.
    expect(await service.pending(), isNull);
    expect(await store.readMaterial(original), _bytes());
    await VideoCaptureRecovery.requireNoPending(store);
  });

  test('retiring an owner fences its late OS result without claiming successful recovery', () async {
    // Given a currently open OS picker.
    final gate = Completer<CapturedVideo?>();
    provider.captureAction = () => gate.future;
    final started = Completer<void>();
    provider.onCapture = started.complete;
    final pending = service.acquire(target: _target, label: '注釈');
    final rejected = expectLater(pending, throwsStateError);
    await started.future;
    // When the caller retires before native completion.
    service.retire();
    gate.complete(_video());
    await rejected;
    // Then no original is imported or marked ready by the obsolete owner.
    expect(store.materialSaves, 0);
    expect(
      (await VideoCaptureRecovery.pendingIn(store))!.state,
      VideoRecoveryState.acquiring,
    );
  });

  test(
    'malformed pending documents are errors, never successful absence',
    () async {
      // Given an actual persisted ready record and an unknown explicit-null field.
      await service.acquire(target: _target, label: '注釈');
      final valid = (await service.pending())!.toJson();
      final invalid = {...valid, 'unexpected': null};
      await store.saveDocument(
        VideoCaptureRecovery.collection,
        VideoCaptureRecovery.documentId,
        invalid,
      );
      // When a fresh observer reads it, then corruption is not a free picker slot.
      await expectLater(
        VideoCaptureRecovery.pendingIn(store),
        throwsFormatException,
      );
      await expectLater(
        VideoCaptureRecovery.requireNoPending(store),
        throwsFormatException,
      );
      expect(provider.recoveries, 0);
    },
  );
}

class _Video implements VideoInputProvider {
  @override
  bool get canRecoverLostVideo => true;
  int captures = 0, recoveries = 0;
  Future<CapturedVideo?> Function()? captureAction;
  void Function()? onCapture;
  CapturedVideo? lost = _video();
  @override
  bool get canCapture => true;
  @override
  bool get canImport => true;
  @override
  Future<CapturedVideo?> capture() async {
    captures++;
    onCapture?.call();
    return captureAction == null ? _video() : captureAction!();
  }

  @override
  Future<CapturedVideo?> importVideo() => capture();
  @override
  Future<CapturedVideo?> recoverLostVideo() async {
    recoveries++;
    return lost;
  }

  @override
  Future<void> close() async {}
}

class _Store implements LocalCaptureStore {
  _Store(this.delegate);
  final LocalCaptureStore delegate;
  bool failIntent = false, failReadyOnce = false;
  int materialSaves = 0;
  @override
  Future<void> saveDocument(
    String collection,
    String id,
    Map<String, Object?> value,
  ) async {
    if (collection == VideoCaptureRecovery.collection &&
        (failIntent || (failReadyOnce && value['state'] == 'ready'))) {
      failReadyOnce = false;
      throw StateError('controlled persistence failure');
    }
    await delegate.saveDocument(collection, id, value);
  }

  @override
  Future<Map<String, Object?>?> readDocument(String collection, String id) =>
      delegate.readDocument(collection, id);
  @override
  Future<List<String>> listDocumentIds(String collection) =>
      delegate.listDocumentIds(collection);
  @override
  Future<Uint8List> readMaterial(CaptureMaterialReference value) =>
      delegate.readMaterial(value);
  @override
  Future<CaptureMaterialReference> saveMaterial({
    required Uint8List bytes,
    required String mediaType,
    required DateTime capturedAt,
    String? originalName,
  }) {
    materialSaves++;
    return delegate.saveMaterial(
      bytes: bytes,
      mediaType: mediaType,
      capturedAt: capturedAt,
      originalName: originalName,
    );
  }
}
