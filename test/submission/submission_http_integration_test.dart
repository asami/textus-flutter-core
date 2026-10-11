import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

import '../support/submission_fixture.dart';
import '../support/submission_http_fixture.dart';

void main() {
  test('HB1', () async {
    // Given actual FileCaptureStore photo/audio originals and a real file SQLite queue.
    final disk = await SubmissionFixture.create();
    final network = SubmissionHttpFixture();
    addTearDown(() async {
      // Given the test owns all service/queue handles and the controlled HTTP client.
      final owned = network.client;
      // When teardown drains and closes those owners before removing test disk data.
      await disk.dispose();
      network.dispose();
      // Then no adapter has inherited ownership of the client or original root.
      expect(owned.closed, isTrue);
    });
    final request = await disk.request(
      document: {
        'localDocumentMarker': '/private/editor/local-document',
        'editor': {'draft': true},
      },
      payload: {
        'title': '  手入力の書名\n  ',
        'transcript': '  手入力\n原文  ',
        'namespace/book': {
          'opaque': [null, false, 0.25],
        },
      },
    );
    final originals = <String, Uint8List>{
      for (final material in request.materials)
        material.key: await disk.materials.readMaterial(material.original),
    };
    var queue = await disk.openQueue();
    var service = disk.service(
      queue,
      storageAdapters: {'drive': network.drive()},
      transports: {'server': network.transport()},
    );
    final remote = <String, Map<String, Object?>>{};
    final uploaded = <String, Uint8List>{};
    var generated = 0;
    String? pendingFile;
    SubmissionMaterial? pendingMaterial;
    var verificationReads = 0;
    Map<String, Object?>? serverPacket;

    network.client.handler = (captured) async {
      // Given actual concrete adapters dispatch to this controlled HTTP port.
      expect(captured.followsRedirects, isFalse);
      expect(
        captured.headers['authorization'],
        'Bearer ${ControlledSubmissionCredentials.secret}',
      );
      // When the server endpoint receives the real encoded complete packet.
      if (captured.uri.host == network.httpConnection.endpoint.host) {
        expect(captured.method, 'POST');
        expect(captured.uri, network.httpConnection.endpoint);
        expect(captured.headers['idempotency-key'], request.id);
        serverPacket = captured.json;
        expect(serverPacket!.containsKey('document'), isFalse);
        expect(
          utf8.decode(captured.bytes),
          allOf(
            isNot(contains('localDocumentMarker')),
            isNot(contains('/private/editor/local-document')),
            isNot(contains(ControlledSubmissionCredentials.secret)),
          ),
        );
        // Then only this controlled explicit server acknowledgement can submit.
        return submissionJsonResponse(
          network.acknowledgement(request),
          status: 201,
        );
      }
      // Given every storage operation targets the fixed Google host.
      expect(captured.uri.host, 'www.googleapis.com');
      // When generateIds allocates the next controlled immutable remote identity.
      if (captured.uri.path.endsWith('/generateIds')) {
        expect(captured.method, 'GET');
        final material = request.materials[generated++];
        // Then no bytes have been uploaded during preparation.
        expect(uploaded, isEmpty);
        return submissionJsonResponse({
          'ids': ['File_${material.key}'],
          'space': 'drive',
          'kind': 'drive#generatedIds',
        });
      }
      // Given initiation must use a reservation already stored on real disk.
      if (captured.method == 'POST') {
        final metadata = captured.json;
        final fileId = metadata['id']! as String;
        final material = request.materials.singleWhere(
          (material) => fileId == 'File_${material.key}',
        );
        // When a separate real SQLite read observes the durable reservation.
        final durable = (await queue.find(request.id))!;
        expect(durable.reservations[material.key]!.data['fileId'], fileId);
        expect(
          durable.reservations[material.key]!.data['originalId'],
          material.original.id,
        );
        expect(metadata['mimeType'], material.original.mediaType);
        expect(metadata['parents'], [network.driveConnection.folderId]);
        pendingFile = fileId;
        pendingMaterial = material;
        // Then a prior remote effect conflicts at the same id, otherwise one session starts.
        if (remote.containsKey(fileId)) return submissionEmptyResponse(409);
        return submissionEmptyResponse(
          200,
          headers: {'location': SubmissionHttpFixture.uploadLocation},
        );
      }
      // Given a binary PUT is the first remote effect for its reserved identity.
      if (captured.method == 'PUT') {
        final fileId = pendingFile!;
        final material = pendingMaterial!;
        // When unchanged bytes reach this controlled remote stream boundary.
        expect(captured.bytes, orderedEquals(originals[material.key]!));
        expect(captured.headers['content-type'], material.original.mediaType);
        expect(
          captured.headers['content-length'],
          material.original.byteLength.toString(),
        );
        uploaded[material.key] = Uint8List.fromList(captured.bytes);
        remote[fileId] = network.file(request, material, fileId);
        // Then the remote effect survives simulated loss of the local SQLite receipt.
        return submissionJsonResponse(remote[fileId], status: 201);
      }
      // Given the first upload completed remotely but its local checkpoint was lost.
      expect(captured.method, 'GET');
      final fileId = captured.uri.pathSegments.last;
      // When retry verifies that same remote identity after a creation 409.
      verificationReads++;
      expect(remote.containsKey(fileId), isTrue);
      // Then matching controlled metadata, not 409 alone, supplies the receipt.
      return submissionJsonResponse(remote[fileId]);
    };

    Future<SubmissionRecord> restart() async {
      // Given the latest real service and queue are distinct owned lifetimes.
      final oldService = service;
      final oldQueue = queue;
      // When both close and new handles reopen the same actual SQLite/original roots.
      await oldService.close();
      await oldQueue.close();
      queue = await disk.openQueue();
      service = disk.service(
        queue,
        storageAdapters: {'drive': network.drive()},
        transports: {'server': network.transport()},
      );
      final record = (await queue.find(request.id))!;
      // Then new objects preserve exact immutable intent without credential/config RAM.
      expect(identical(queue, oldQueue), isFalse);
      expect(identical(service, oldService), isFalse);
      expect(record.request, request);
      expect(network.client.closed, isFalse);
      return record;
    }

    // When explicit Commit persists intent while the driver remains offline.
    final committed = await service.commit(request);
    final offline = await service.processNext(networkAllowed: false);
    // Then Commit/offline perform no HTTP or credential retrieval and preserve originals.
    expect(committed.record.state, SubmissionState.readyToSubmit);
    expect(offline.outcome, SubmissionRunOutcome.offline);
    expect(network.client.requests, isEmpty);
    expect(network.credentials.calls, isEmpty);
    expect(disk.scheduler.calls, 1);

    // Given ready intent reopens on a distinct real SQLite handle.
    final ready = await restart();
    expect(ready.reservations, isEmpty);
    // When one concrete Drive preparation is checkpointed, then the service closes.
    final preparedPhoto = await service.processNext(networkAllowed: true);
    final afterPhotoPreparation = await restart();
    // Then only the immutable photo reservation persisted and no upload occurred.
    expect(preparedPhoto.outcome, SubmissionRunOutcome.progress);
    expect(afterPhotoPreparation.reservations.keys, ['photo']);
    expect(
      afterPhotoPreparation.reservations['photo']!.data['fileId'],
      'File_photo',
    );
    expect(afterPhotoPreparation.receipts, isEmpty);
    expect(uploaded, isEmpty);

    // Given the photo reservation survived service/queue closure.
    final photoReservation = afterPhotoPreparation.reservations['photo'];
    // When a second preparation checkpoints audio and then reopens.
    final preparedAudio = await service.processNext(networkAllowed: true);
    final prepared = await restart();
    // Then both complete reservations persist before any unchanged original is uploaded.
    expect(preparedAudio.outcome, SubmissionRunOutcome.progress);
    expect(prepared.reservations.keys.toSet(), {'photo', 'audio'});
    expect(prepared.reservations['photo'], photoReservation);
    expect(prepared.reservations['audio']!.data['fileId'], 'File_audio');
    expect(prepared.receipts, isEmpty);
    expect(uploaded, isEmpty);
    expect(network.client.requests.map((value) => value.method), [
      'GET',
      'GET',
    ]);

    // Given a real SQLite forwarding fault on saveReceipt after remote completion.
    await service.close();
    final controlled = ControlledQueue(queue)..failAt = 'saveReceipt';
    service = disk.service(
      controlled,
      storageAdapters: {'drive': network.drive()},
      transports: {'server': network.transport()},
    );
    // When the original photo PUT succeeds remotely but the local write is lost.
    await expectLater(
      service.processNext(networkAllowed: true),
      throwsStateError,
    );
    final lost = await restart();
    // Then remote data survives while the durable queue retains its original reservation.
    expect(uploaded.keys, ['photo']);
    expect(lost.reservations, prepared.reservations);
    expect(lost.receipts, isEmpty);
    expect(lost.state, SubmissionState.readyToSubmit);
    expect(lost.acknowledgement, isNull);

    // Given a new service retries the same persisted photo file id after write loss.
    final photoFileId = lost.reservations['photo']!.data['fileId'];
    // When creation returns 409 and actual DriveAdapter verifies matching metadata.
    final replay = await service.processNext(networkAllowed: true);
    final photoStored = await restart();
    // Then retry keeps one remote identity and sends no second photo PUT.
    expect(replay.outcome, SubmissionRunOutcome.progress);
    expect(photoStored.receipts['photo']!.remoteId, photoFileId);
    expect(
      photoStored.receipts['photo']!.metadata['createdTime'],
      SubmissionHttpFixture.createdTime,
    );
    expect(verificationReads, 1);
    expect(
      network.client.requests.where((value) => value.method == 'PUT').length,
      1,
    );
    expect(photoStored.acknowledgement, isNull);

    // Given the photo receipt persists but original audio has not yet uploaded.
    final photoReceipt = photoStored.receipts['photo'];
    // When the concrete DriveAdapter uploads audio and the queue closes/reopens.
    final audioRun = await service.processNext(networkAllowed: true);
    final allStored = await restart();
    // Then unchanged audio/photo bodies and both receipts persist without server acceptance.
    expect(audioRun.outcome, SubmissionRunOutcome.progress);
    expect(allStored.receipts.keys.toSet(), {'photo', 'audio'});
    expect(allStored.receipts['photo'], photoReceipt);
    expect(allStored.receipts['audio']!.remoteId, 'File_audio');
    expect(allStored.state, SubmissionState.readyToSubmit);
    expect(allStored.acknowledgement, isNull);
    expect(serverPacket, isNull);
    expect(uploaded['photo'], orderedEquals(originals['photo']!));
    expect(uploaded['audio'], orderedEquals(originals['audio']!));

    // Given complete persisted storage receipts and the immutable server payload.
    final expectedPacket = SubmissionCodec.packetToJson(
      SubmissionPacket(request: request, receipts: allStored.receipts),
    );
    // When actual HttpSubmissionTransport receives the controlled matching acknowledgement.
    final submittedRun = await service.processNext(networkAllowed: true);
    final submitted = await restart();
    // Then a distinct real SQLite handle reopens Submitted with full provenance/context.
    expect(submittedRun.outcome, SubmissionRunOutcome.submitted);
    expect(submitted.state, SubmissionState.submitted);
    expect(submitted.acknowledgement!.serverId, 'fake-server/${request.id}');
    expect(submitted.acknowledgement!.requestId, request.id);
    expect(submitted.acknowledgement!.subjectId, request.subjectId);
    expect(submitted.reservations, prepared.reservations);
    expect(submitted.receipts, allStored.receipts);
    expect(serverPacket, expectedPacket);
    expect(serverPacket!['payload'], request.payload);
    expect(serverPacket!['extensions'], request.extensions);
    expect(submitted.request.payload['transcript'], '  手入力\n原文  ');
    expect(
      jsonEncode(SubmissionCodec.recordToJson(submitted)),
      isNot(contains(ControlledSubmissionCredentials.secret)),
    );

    // Given Submitted is terminal and the originals remain owned by FileCaptureStore.
    final calls = network.client.requests.length;
    // When another driver invocation and original reads run after reopen.
    final noWork = await service.processNext(networkAllowed: true);
    final photo = await disk.materials.readMaterial(
      request.materials[0].original,
    );
    final audio = await disk.materials.readMaterial(
      request.materials[1].original,
    );
    // Then the terminal queue sends nothing and both original files remain unchanged.
    expect(noWork.outcome, SubmissionRunOutcome.noWork);
    expect(network.client.requests.length, calls);
    expect(photo, orderedEquals(originals['photo']!));
    expect(audio, orderedEquals(originals['audio']!));
  });
}
