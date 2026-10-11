import 'dart:io';
import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

/// Test-owned real originals/database and independently controlled borrowed ports.
final class SubmissionFixture {
  SubmissionFixture._(this.directory, this.materials);
  final Directory directory;
  final LocalCaptureStore materials;
  DateTime now = DateTime.utc(2026, 10, 10, 1);
  final storage = ControlledStorage();
  final transport = ControlledTransport();
  final scheduler = ControlledScheduler();
  final referenceAccess = ControlledReferenceAccessPolicy();
  final List<SubmissionQueueStore> queues = [];
  final List<SubmissionService> services = [];
  static final photoBytes = Uint8List.fromList([255, 216, 10, 20, 255, 217]);
  static final audioBytes = Uint8List.fromList([82, 73, 70, 70, 0, 1, 2, 3]);
  String get databasePath => '${directory.path}/submission.sqlite';

  static Future<SubmissionFixture> create() async {
    // Given an isolated test directory and an explicit host SQLite factory.
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp('submission-spec-');
    // When file-backed originals are configured inside the test-owned directory.
    final fixture = SubmissionFixture._(
      directory,
      FileCaptureStore('${directory.path}/originals'),
    );
    // Then every scenario owns its disk artifacts without a global factory swap.
    return fixture;
  }

  Future<SqliteSubmissionQueueStore> openQueue() async {
    // Given the same real database path for independent handles/restarts.
    final queue = await SqliteSubmissionQueueStore.open(
      databasePath,
      factory: databaseFactoryFfi,
    );
    // When the caller borrows the queue in a service, fixture still owns cleanup.
    queues.add(queue);
    // Then subsequent handles can observe the durable rows.
    return queue;
  }

  SubmissionService service(
    SubmissionQueueStore queue, {
    LocalCaptureStore? originals,
    Map<String, SubmissionStorageAdapter>? storageAdapters,
    Map<String, SubmissionTransport>? transports,
    SubmissionReferenceAccessPolicy? referenceAccessPolicy,
    Duration leaseDuration = const Duration(minutes: 5),
    Duration operationTimeout = const Duration(minutes: 1),
  }) {
    // Given independently controlled ports and an explicit mutable test clock.
    final service = SubmissionService(
      queue: queue,
      materials: originals ?? materials,
      storageAdapters: storageAdapters ?? {'drive': storage},
      transports: transports ?? {'server': transport},
      scheduler: scheduler,
      referenceAccessPolicy: referenceAccessPolicy ?? referenceAccess,
      now: () => now,
      leaseDuration: leaseDuration,
      operationTimeout: operationTimeout,
    );
    // When fixture retains only the service's own lifetime for cleanup.
    services.add(service);
    // Then closing a service cannot close its separately owned ports/queue.
    return service;
  }

  Future<SubmissionRequest> request({
    String id = 'commit1',
    String subjectId = 'subject1',
    bool withMaterials = true,
    Map<String, Object?>? document,
    Map<String, Object?>? payload,
  }) async {
    // Given complete original photo/audio bytes, with no recapture on queue work.
    final originals = <SubmissionMaterial>[];
    if (withMaterials) {
      for (final entry in [
        ('photo', photoBytes, 'image/jpeg'),
        ('audio', audioBytes, 'audio/wav'),
      ]) {
        final original = await materials.saveMaterial(
          bytes: entry.$2,
          mediaType: entry.$3,
          capturedAt: now,
          originalName: '${entry.$1}.original',
        );
        final extended = CaptureMaterialReference(
          id: original.id,
          mediaType: original.mediaType,
          byteLength: original.byteLength,
          capturedAt: original.capturedAt,
          originalName: original.originalName,
          extensions: {
            'source': [
              entry.$1,
              {'unchanged': true},
            ],
          },
        );
        originals.add(
          SubmissionMaterial(
            key: entry.$1,
            original: extended,
            provenance: {
              'capture': {'source': entry.$1, 'manual': false},
            },
          ),
        );
      }
    }
    // When consumer document/payload/context are snapshotted at explicit intent.
    final request = SubmissionRequest(
      id: id,
      kind: 'bookMaterial',
      subjectId: subjectId,
      createdAt: now,
      document:
          document ??
          {
            'local': {'draft': true},
          },
      payload: payload ?? {'transcript': '  手入力\n原文  ', 'title': 'opaque'},
      materials: originals,
      transportConnectionId: 'server',
      storageConnectionId: withMaterials ? 'drive' : null,
      extensions: {
        'presentation': {'armId': 'uninterpreted/arm'},
        'execution': [
          null,
          {'locale': 'ja'},
        ],
      },
    );
    // Then the request retains references to the exact bytes plus opaque context.
    return request;
  }

  Future<void> dispose() async {
    // Given fixture-owned services, queue handles and temporary disk artifacts.
    for (final service in services) {
      await service.close();
    }
    // When all borrowed work has drained, close only fixture-owned handles.
    for (final queue in queues) {
      await queue.close();
    }
    // Then temporary artifacts can be removed without touching production data.
    await directory.delete(recursive: true);
  }
}

/// Explicit test-only local fact, never a production default or remote proof.
final class ControlledReferenceAccessPolicy
    implements SubmissionReferenceAccessPolicy {
  int calls = 0;
  final List<SubmissionPacket> packets = [];
  Future<SubmissionReferenceAccessState> Function(SubmissionPacket)? onEvaluate;

  @override
  Future<SubmissionReferenceAccessState> evaluate(
    SubmissionPacket packet,
  ) async {
    // Given a controlled local declaration independent of credentials/network.
    calls++;
    packets.add(packet);
    // When a scenario supplies a held or failing observation, expose that await.
    final selected = onEvaluate;
    if (selected != null) return selected(packet);
    // Then only this explicit test fact defaults to available; production denies.
    return SubmissionReferenceAccessState.available;
  }
}

final class ControlledStorage implements SubmissionStorageAdapter {
  @override
  String get providerId => 'controlledDrive';
  int prepares = 0;
  int uploads = 0;
  final List<SubmissionStorageReservation> uploadedReservations = [];
  final List<Uint8List> uploadedBytes = [];
  final Map<String, SubmissionMaterialReceipt> remote = {};
  Future<SubmissionStorageReservation> Function(
    SubmissionRequest,
    SubmissionMaterial,
  )?
  onPrepare;
  Future<SubmissionMaterialReceipt> Function(
    SubmissionRequest,
    SubmissionMaterial,
    SubmissionStorageReservation,
    Uint8List,
  )?
  onUpload;

  @override
  Future<SubmissionStorageReservation> prepare({
    required SubmissionRequest request,
    required SubmissionMaterial material,
  }) async {
    // Given an independent preparation port, observable separately from upload.
    prepares++;
    // When a barrier/failure callback is configured, expose that actual await.
    if (onPrepare != null) return onPrepare!(request, material);
    // Then the default controlled provider reserves a stable future file id.
    return reservation(material.key, request.id);
  }

  SubmissionStorageReservation reservation(String key, String id) {
    // Given a request/material pair whose fake remote identity is deterministic.
    final data = <String, Object?>{
      'remoteId': '$id/$key',
      'context': [
        null,
        {'prepared': true},
      ],
    };
    // When the controlled provider constructs a full reservation value.
    final reservation = SubmissionStorageReservation(
      key: key,
      providerId: providerId,
      data: data,
    );
    // Then scenarios can compare its exact persisted/replayed value.
    return reservation;
  }

  @override
  Future<SubmissionMaterialReceipt> upload({
    required SubmissionRequest request,
    required SubmissionMaterial material,
    required SubmissionStorageReservation reservation,
    required Uint8List bytes,
  }) async {
    // Given the exact persisted reservation and original bytes supplied by Core.
    uploads++;
    uploadedReservations.add(reservation);
    uploadedBytes.add(Uint8List.fromList(bytes));
    // When upload is controlled, callbacks can separate remote effect/local write.
    if (onUpload != null) {
      return onUpload!(request, material, reservation, bytes);
    }
    // Then replay of the same reservation acknowledges one stable remote object.
    return remote.putIfAbsent('${request.id}/${material.key}', () {
      // Given a first upload for this fake request/material identity.
      final remoteId = reservation.data['remoteId']! as String;
      // When the controlled remote records its stable receipt for replay.
      final receipt = SubmissionMaterialReceipt(
        key: material.key,
        providerId: providerId,
        remoteId: remoteId,
        accessConnectionId: 'drive',
        storedAt: request.createdAt,
        metadata: {
          'originalLength': bytes.length,
          'opaque': [null, true],
        },
      );
      // Then subsequent calls return this identical remote acknowledgement value.
      return receipt;
    });
  }
}

final class ControlledTransport implements SubmissionTransport {
  @override
  String get providerId => 'controlledServer';
  int submits = 0;
  final List<SubmissionPacket> packets = [];
  final Map<String, SubmissionAcknowledgement> remote = {};
  Future<SubmissionAcknowledgement> Function(SubmissionPacket)? onSubmit;
  @override
  Future<SubmissionAcknowledgement> submit(SubmissionPacket packet) async {
    // Given transport acceptance independent of storage acceptance.
    submits++;
    packets.add(packet);
    // When a controlled callback is installed, expose its barrier/error.
    if (onSubmit != null) return onSubmit!(packet);
    // Then repeated request id returns the same fake server identity.
    return acknowledgement(packet.request);
  }

  SubmissionAcknowledgement acknowledgement(SubmissionRequest request) {
    // Given a controlled remote indexed by the immutable transport request id.
    final id = request.id;
    // When fake acceptance is first created or replayed.
    final result = remote.putIfAbsent(id, () {
      // Given no prior acknowledgement exists for this request id.
      final serverId = 'fake-server/$id';
      // When fake server acceptance is constructed independently of storage.
      final acknowledgement = SubmissionAcknowledgement(
        requestId: id,
        subjectId: request.subjectId,
        serverId: serverId,
        receivedAt: request.createdAt,
        extensions: {
          'accepted': [id, null],
        },
      );
      // Then a retry reuses this same safe server identity/value.
      return acknowledgement;
    });
    // Then all scenarios can observe/replay the exact controlled acceptance.
    return result;
  }
}

final class ControlledScheduler implements SubmissionWakeScheduler {
  int calls = 0;
  bool fail = false;
  Future<void> Function()? onRequest;
  @override
  Future<void> requestRun() async {
    // Given an independently controlled wake scheduler.
    calls++;
    // When failure/barrier is requested, let Commit observe only a safe notice.
    if (fail) throw StateError('private scheduler exception must not persist');
    await onRequest?.call();
    // Then successful wake has no storage or server side effect.
  }
}

/// Test-only fault/barrier forwarding port; all storage remains real SQLite.
final class ControlledQueue implements SubmissionQueueStore {
  ControlledQueue(this.inner);
  final SubmissionQueueStore inner;
  String? failAt;
  int calls = 0;
  Future<void> Function(String)? after;

  Future<T> _call<T>(String name, Future<T> Function() action) async {
    // Given a real borrowed queue and a selected local write failure/barrier.
    calls++;
    if (failAt == name) {
      failAt = null;
      throw StateError('controlled SQLite checkpoint write failure');
    }
    // When the actual queue operation finishes, expose an awaited owner barrier.
    final result = await action();
    await after?.call(name);
    // Then the real durable result is returned unless the selected fault fired.
    return result;
  }

  @override
  Future<SubmissionRecord> enqueue(SubmissionRequest request) =>
      _call('enqueue', () => inner.enqueue(request));
  @override
  Future<SubmissionRecord?> find(String id) =>
      _call('find', () => inner.find(id));
  @override
  Future<SubmissionRecord?> findForSubject(String kind, String subjectId) =>
      _call('findForSubject', () => inner.findForSubject(kind, subjectId));
  @override
  Future<List<SubmissionRecord>> list() => _call('list', inner.list);
  @override
  Future<SubmissionRecord?> claimNext({
    required DateTime now,
    required String leaseToken,
    required Duration leaseDuration,
  }) => _call(
    'claimNext',
    () => inner.claimNext(
      now: now,
      leaseToken: leaseToken,
      leaseDuration: leaseDuration,
    ),
  );
  @override
  Future<SubmissionRecord> renewLease({
    required String id,
    required String leaseToken,
    required DateTime now,
    required Duration leaseDuration,
  }) => _call(
    'renewLease',
    () => inner.renewLease(
      id: id,
      leaseToken: leaseToken,
      now: now,
      leaseDuration: leaseDuration,
    ),
  );
  @override
  Future<SubmissionRecord> saveReservation({
    required String id,
    required String leaseToken,
    required SubmissionStorageReservation reservation,
    required DateTime now,
  }) => _call(
    'saveReservation',
    () => inner.saveReservation(
      id: id,
      leaseToken: leaseToken,
      reservation: reservation,
      now: now,
    ),
  );
  @override
  Future<SubmissionRecord> saveReceipt({
    required String id,
    required String leaseToken,
    required SubmissionMaterialReceipt receipt,
    required DateTime now,
  }) => _call(
    'saveReceipt',
    () => inner.saveReceipt(
      id: id,
      leaseToken: leaseToken,
      receipt: receipt,
      now: now,
    ),
  );
  @override
  Future<SubmissionRecord> markTransportDispatch({
    required String id,
    required String leaseToken,
    required DateTime now,
  }) => _call(
    'markTransportDispatch',
    () => inner.markTransportDispatch(id: id, leaseToken: leaseToken, now: now),
  );
  @override
  Future<SubmissionRecord> complete({
    required String id,
    required String leaseToken,
    required SubmissionAcknowledgement acknowledgement,
    required DateTime now,
  }) => _call(
    'complete',
    () => inner.complete(
      id: id,
      leaseToken: leaseToken,
      acknowledgement: acknowledgement,
      now: now,
    ),
  );
  @override
  Future<SubmissionRecord> fail({
    required String id,
    required String leaseToken,
    required SubmissionFailure failure,
    required DateTime now,
    DateTime? nextAttemptAt,
    SubmissionTransportFailureOutcome transportFailureOutcome =
        SubmissionTransportFailureOutcome.unknown,
  }) => _call(
    'fail',
    () => inner.fail(
      id: id,
      leaseToken: leaseToken,
      failure: failure,
      now: now,
      nextAttemptAt: nextAttemptAt,
      transportFailureOutcome: transportFailureOutcome,
    ),
  );
  @override
  Future<SubmissionRecord> release({
    required String id,
    required String leaseToken,
    required DateTime now,
  }) => _call(
    'release',
    () => inner.release(id: id, leaseToken: leaseToken, now: now),
  );
  @override
  Future<SubmissionRecord> retry({required String id, required DateTime now}) =>
      _call('retry', () => inner.retry(id: id, now: now));
  @override
  Future<void> close() => inner.close();
}

/// Test-only local read barrier; persistence and original reads delegate unchanged.
final class ControlledMaterials implements LocalCaptureStore {
  ControlledMaterials(this.inner);
  final LocalCaptureStore inner;
  int reads = 0;
  Future<void> Function()? beforeRead;
  @override
  Future<Uint8List> readMaterial(CaptureMaterialReference reference) async {
    // Given a borrowed real original store with an explicit local read barrier.
    reads++;
    // When a delayed read resumes, Core must recheck ownership and renew its lease.
    await beforeRead?.call();
    // Then only the real unchanged original bytes become visible to upload.
    return inner.readMaterial(reference);
  }

  @override
  Future<CaptureMaterialReference> saveMaterial({
    required Uint8List bytes,
    required String mediaType,
    required DateTime capturedAt,
    String? originalName,
  }) => inner.saveMaterial(
    bytes: bytes,
    mediaType: mediaType,
    capturedAt: capturedAt,
    originalName: originalName,
  );
  @override
  Future<void> saveDocument(
    String collection,
    String id,
    Map<String, Object?> document,
  ) => inner.saveDocument(collection, id, document);
  @override
  Future<Map<String, Object?>?> readDocument(String collection, String id) =>
      inner.readDocument(collection, id);
  @override
  Future<List<String>> listDocumentIds(String collection) =>
      inner.listDocumentIds(collection);
}
