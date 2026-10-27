import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

import '../support/submission_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SubmissionFixture fixture;
  setUp(() async => fixture = await SubmissionFixture.create());
  tearDown(() => fixture.dispose());

  group('retained-byte preparation and independent verification', () {
    test('TKL Commit checks presence and length with empty ranges and no payload or digest scan', () async {
      // Given actual retained originals and a stream-only public capture store.
      final request = _request(await fixture.request());
      final originals = _StreamingOnlyOriginals(fixture.materials);
      var payloadChunks = 0;
      originals.onChunk = () { payloadChunks++; };
      final queue = await fixture.openQueue();
      final service = fixture.service(queue, originals: originals);
      // When explicit Commit admits local intent without any leased hashing or server operation.
      final committed = await service.commit(request);
      // Then only empty ranges validate actual full-file presence/length; no payload or hash is consumed.
      expect(originals.ranges, [(0, 0), (0, 0)]);
      expect(payloadChunks, 0);
      expect(originals.wholeReads, 0);
      expect(committed.record.tklContentDigests, isEmpty);
      expect(committed.record.request, request);
      expect(committed.record.claimCount, 0);
    });
    for (final storageState in ['missing', 'truncated', 'extended']) {
      test('TKL Commit rejects $storageState retained original before enqueue', () async {
        // Given a committed reference whose native retained file is absent or has changed length.
        final request = _request(await fixture.request());
        final reference = request.materials.first.original;
        final file = File('${fixture.directory.path}/originals/materials/${reference.id}.bin');
        if (storageState == 'missing') {
          await file.delete();
        } else {
          await file.writeAsBytes(Uint8List(reference.byteLength + (storageState == 'extended' ? 1 : -1)), flush: true);
        }
        final queue = await fixture.openQueue();
        final service = fixture.service(queue);
        // When Commit uses the native empty-range full-length validation.
        await expectLater(service.commit(request), throwsA(isA<SubmissionAdapterException>()
          .having((e) => e.code, 'code', 'originalUnavailable')));
        // Then no intent or scheduler wake is fabricated from missing/invalid originals.
        expect(await queue.find(request.id), isNull);
        expect(fixture.scheduler.calls, 0);
      });
    }
    test('TKL Commit requires optional stream capability before enqueue without whole-read fallback', () async {
      // Given a source-compatible capture implementer without the optional stream capability.
      final request = _request(await fixture.request());
      final originals = _LegacyOnlyOriginals(fixture.materials);
      final queue = await fixture.openQueue();
      final service = fixture.service(queue, originals: originals);
      // When new TKL intent is committed through that local adapter.
      await expectLater(service.commit(request), throwsA(isA<SubmissionAdapterException>()
        .having((e) => e.code, 'code', 'originalStreamingRequired')));
      // Then no full read, queued intent or provider effect occurs.
      expect(originals.wholeReads, 0);
      expect(await queue.find(request.id), isNull);
      expect(fixture.scheduler.calls, 0);
    });

    test('one digest per claim precedes prepare and survives lost prepare reply and reopening', () async {
      // Given actual retained originals, opaque null contexts and a streaming-only reader.
      final request = _request(await fixture.request(document: {
        'literal_context': [null, {'snake_case': ' 原文 ', 'contentDigest': null}],
      }));
      final accepted = jsonEncode(SubmissionCodec.requestToJson(request));
      final server = _LakePeer()..direct = true..losePrepareResponse = true;
      final client = server.client();
      addTearDown(client.close);
      final originals = _StreamingOnlyOriginals(fixture.materials);
      var queue = await fixture.openQueue();
      final barrier = ControlledQueue(queue);
      SubmissionTransferStatus? active;
      barrier.after = (name) async {
        if (name == 'saveTklContentDigest') {
          active = SubmissionTransferStatus.fromRecord((await queue.find(request.id))!,
            observedAt: fixture.now);
        }
      };
      var service = fixture.service(barrier, originals: originals, tklClients: {'lake': _remote(client)});
      await service.commit(request);
      // When the first eligible claim reads and durably checkpoints one actual original.
      final first = await service.processNext(networkAllowed: true);
      // Then preparation counts actual saved digests while its lease was active, without provider effects.
      expect(first.record!.tklContentDigests.keys, ['photo']);
      expect(server.prepares, 0);
      expect(server.providerUploads, isEmpty);
      expect(active!.preparation!.state, SubmissionTransferOperationState.running);
      expect(active!.preparation!.completedCount, 1);
      expect(active!.preparation!.totalCount, 2);
      expect(active!.verification, isNull);
      expect(active!.acknowledgement, isNull);
      // When the next claim hashes only the remaining original and both SQLite/service handles reopen.
      final second = await service.processNext(networkAllowed: true);
      await service.close(); await queue.close();
      queue = await fixture.openQueue();
      service = fixture.service(queue, originals: originals, tklClients: {'lake': _remote(client)});
      // Then both expectations remain before the first prepare and accepted opaque intent is exact.
      expect((await queue.find(request.id))!.tklContentDigests, second.record!.tklContentDigests);
      expect(server.prepares, 0);
      expect(jsonEncode(SubmissionCodec.requestToJson((await queue.find(request.id))!.request)), accepted);
      // When prepare commits remotely but its reply is lost, then another service reconciles the correlation.
      final unknown = await service.processNext(networkAllowed: true);
      // Then uncertainty is retained without inventing preparation or placement acceptance.
    expect(unknown.record!.lastFailure!.code, 'lakeOutcomeUnknown');
      await service.close(); await queue.close();
      fixture.now = fixture.now.add(const Duration(minutes: 1));
      queue = await fixture.openQueue();
      service = fixture.service(queue, originals: originals, tklClients: {'lake': _remote(client)});
      SubmissionRunResult? done;
      for (var i = 0; i < 5; i++) { done = await service.processNext(networkAllowed: true); }
      // Then the same prepared delivery finishes without replacing request JSON or reading a whole original.
      expect(done!.outcome, SubmissionRunOutcome.materialRegistered);
      expect(server.prepares, 1);
      expect(originals.wholeReads, 0);
      expect(server.uploads, isEmpty);
      expect(jsonEncode(SubmissionCodec.requestToJson(done.record!.request)), accepted);
      final expectedContribution = jsonDecode(jsonEncode(request.tklDelivery!.contribution)) as Map;
      for (var i = 0; i < request.materials.length; i++) {
        final material = request.materials[i];
        (expectedContribution['originals'] as List)[i]['contentDigest'] =
            done.record!.tklContentDigests[material.key]!.toJson();
      }
      expect(server.committed!['contribution'], expectedContribution);
      expect(done.record!.tklContentDigests['photo']!.value,
        sha256.convert(SubmissionFixture.photoBytes).toString());
      final status = SubmissionTransferStatus.fromRecord(done.record!, observedAt: fixture.now);
      expect(status.preparation!.completedCount, 2);
      expect(status.upload.state, SubmissionTransferOperationState.succeeded);
      expect(status.verification!.completedCount, 2);
      expect(status.verification!.state, SubmissionTransferOperationState.succeeded);
      expect(status.registration!.state, SubmissionTransferOperationState.succeeded);
      expect(status.submission.state, SubmissionTransferOperationState.notRequired);
      expect(status.acknowledgement, isNull);
    });

    test('lost prepare without a committed server row rebuilds the exact enriched transport request', () async {
      // Given saved local expectations and a peer losing the first preparation before commit.
      final request = _request(await fixture.request());
      final server = _LakePeer()..direct = true..losePrepareWithoutCommit = true;
      final client = server.client(); addTearDown(client.close);
      var queue = await fixture.openQueue();
      var service = fixture.service(queue, tklClients: {'lake': _remote(client)});
      await service.commit(request);
      await service.processNext(networkAllowed: true);
      await service.processNext(networkAllowed: true);
      final expected = (await queue.find(request.id))!.tklContentDigests;
      // When the first prepare outcome is unknown, both native handles reopen and authorized absence is confirmed.
      final unknown = await service.processNext(networkAllowed: true);
      // Then uncertainty is retained without inventing preparation or placement acceptance.
    expect(unknown.record!.lastFailure!.code, 'lakeOutcomeUnknown');
      await service.close(); await queue.close();
      fixture.now = fixture.now.add(const Duration(minutes: 1));
      queue = await fixture.openQueue();
      service = fixture.service(queue, tklClients: {'lake': _remote(client)});
      final prepared = await service.processNext(networkAllowed: true);
      // Then retry uses the same persisted bytes expectations and exact detached JSON, without rewriting intent.
      expect(server.prepareBodies.length, 2);
      expect(server.prepareBodies[1], server.prepareBodies[0]);
      expect(prepared.record!.tklContentDigests, expected);
      expect(prepared.record!.request, request);
      expect(prepared.record!.directReceipts, isEmpty);
      expect(server.providerUploads, isEmpty);
    });

    test('an existing server expectation is independently hashed before any upload', () async {
      // Given a server delivery found by correlation but no local digest checkpoint yet.
      final request = _request(await fixture.request());
      final server = _LakePeer()..direct = true;
      server.snapshot = {
        'delivery_ref': 'existing', 'request_id': request.id, 'revision': 1,
        'destination_id': 'selected', 'destination_label': 'Selected',
        'transfer_method': 'googleDriveResumable', 'state': 'prepared',
        'resources': [for (final material in request.materials) {
          'resource_id': material.key, 'media_type': material.original.mediaType,
          'byte_length': material.original.byteLength, 'state': 'pending',
          'content_digest': {'algorithm': 'sha256', 'value': sha256.convert(
            material.key == 'photo' ? SubmissionFixture.photoBytes : SubmissionFixture.audioBytes).toString()},
          'verification_state': 'pending', 'verification_attempts': 0,
        }],
      };
      final client = server.client(); addTearDown(client.close);
      final queue = await fixture.openQueue(); await queue.enqueue(request);
      final originals = _StreamingOnlyOriginals(fixture.materials);
      final service = fixture.service(queue, originals: originals, tklClients: {'lake': _remote(client)});
      // When two eligible claims observe server expectations and read the two actual retained originals.
      final first = await service.processNext(networkAllowed: true);
      final second = await service.processNext(networkAllowed: true);
      // Then local expectations come from full actual streams before any provider mutation, not server trust.
      expect(first.record!.tklContentDigests.length, 1);
      expect(second.record!.tklContentDigests.length, 2);
      expect(originals.ranges, [(0, null), (0, null)]);
      expect(originals.wholeReads, 0);
      expect(server.prepares, 0);
      expect(server.providerUploads, isEmpty);
      expect(second.record!.tklProgress, isNull);
    });

    test('verification of a placed original precedes upload of a still-pending sibling', () async {
      // Given first-original placement whose SHA is not yet visible while the other original remains pending.
      final request = _request(await fixture.request());
      final server = _LakePeer()..direct = true..missingShaChecks = 1;
      final client = server.client(); addTearDown(client.close);
      final queue = await fixture.openQueue();
      final service = fixture.service(queue, tklClients: {'lake': _remote(client)});
      await service.commit(request);
      for (var i = 0; i < 5; i++) { await service.processNext(networkAllowed: true); }
      final verifying = (await queue.find(request.id))!;
      expect(verifying.tklProgress!.state, TklMaterialDeliveryState.verifying);
      expect(verifying.tklProgress!.resources.last.state, TklOriginalTransferState.pending);
      // When one eligible claim requests the existing metadata-only finalization check.
      final checked = await service.processNext(networkAllowed: true);
      // Then only the first original's SHA advances; pending bytes wait until verification returns transferring.
      expect(server.finalizations, 1);
      expect(server.providerUploads, ['photo']);
      expect(checked.record!.tklProgress!.resources.first.verificationState, TklOriginalVerificationState.verified);
      expect(checked.record!.tklProgress!.resources.last.state, TklOriginalTransferState.pending);
      expect(checked.record!.tklProgress!.state, TklMaterialDeliveryState.transferring);
      expect(checked.record!.acknowledgement, isNull);
    });

    test('a lease replacement while hashing cannot checkpoint or mutate the new owner', () async {
      // Given a normal hash reader and a competing native queue handle.
      final request = _request(await fixture.request());
      final server = _LakePeer()..direct = true;
      final client = server.client(); addTearDown(client.close);
      final queue = await fixture.openQueue();
      final competitor = await fixture.openQueue(); await queue.enqueue(request);
      SubmissionRecord? replacement;
      final originals = _StreamingOnlyOriginals(fixture.materials);
      originals.beforeChunk = () async {
        originals.beforeChunk = null;
        fixture.now = fixture.now.add(const Duration(minutes: 6));
        replacement = await competitor.claimNext(now: fixture.now, leaseToken: 'replacement',
          leaseDuration: const Duration(minutes: 5));
      };
      final service = fixture.service(queue, originals: originals, tklClients: {'lake': _remote(client)});
      // When the original source yields only after another owner has acquired the expired lease.
      final result = await service.processNext(networkAllowed: true);
      // Then the old hash result is discarded without changing the replacement claim or checkpoint.
      expect(result.outcome, SubmissionRunOutcome.leaseLost);
      expect(await queue.find(request.id), replacement);
      expect(replacement!.tklContentDigests, isEmpty);
      expect(server.prepares, 0);
      expect(server.providerUploads, isEmpty);
    });

    for (final malformed in ['resource', 'mime', 'length', 'source', 'provenance']) {
      test('accepted declaration $malformed mismatch is refused before hashing or sending', () async {
        // Given an immutable request with an original declaration inconsistent with its retained reference.
        final base = _request(await fixture.request());
        final contribution = jsonDecode(jsonEncode(base.tklDelivery!.contribution)) as Map<String, dynamic>;
        final original = (contribution['originals'] as List).first as Map;
        switch (malformed) {
          case 'resource': original['resourceId'] = 'wrong';
          case 'mime': original['mediaType'] = 'text/plain';
          case 'length': original['byteLength'] = 900;
          case 'source': original['sourceReference'] = {'kind': 'mobileOriginal', 'resourceId': 'wrong'};
          case 'provenance': original['sourceReference'] = {'kind': 'mobileOriginal', 'provenance': {'different': true}};
        }
        final request = _contributionRequest(base, contribution);
        final server = _LakePeer()..direct = true;
        final client = server.client(); addTearDown(client.close);
        final queue = await fixture.openQueue(); await queue.enqueue(request);
        final originals = _StreamingOnlyOriginals(fixture.materials);
        final service = fixture.service(queue, originals: originals, tklClients: {'lake': _remote(client)});
        // When a normal driver claim validates the declared resource/source binding.
        final result = await service.processNext(networkAllowed: true);
        // Then failure retains accepted intent and reads/sends no original payload or provider preparation.
        expect(result.record!.lastFailure!.code, 'originalBindingMismatch');
        expect(result.record!.request, request);
        expect(originals.ranges, isEmpty);
        expect(server.operations, isEmpty);
      });
    }

    test('caller-supplied digest is checked against actual retained bytes before prepare', () async {
      // Given immutable caller intent containing an incorrect expected digest.
      final base = _request(await fixture.request());
      final contribution = jsonDecode(jsonEncode(base.tklDelivery!.contribution)) as Map<String, dynamic>;
      (contribution['originals'] as List).first['contentDigest'] = {
        'algorithm': 'sha256', 'value': List.filled(64, 'a').join(),
      };
      final request = _contributionRequest(base, contribution);
      final server = _LakePeer()..direct = true;
      final client = server.client(); addTearDown(client.close);
      final queue = await fixture.openQueue();
      final service = fixture.service(queue, tklClients: {'lake': _remote(client)});
      await service.commit(request);
      // When the normal driver hashes the actual original before any preparation mutation.
      final failed = await service.processNext(networkAllowed: true);
      // Then mismatch is terminal and the caller's expectation and retained bytes remain untouched.
      expect(failed.record!.lastFailure!.code, 'integrityMismatch');
      expect(failed.record!.lastFailure!.retryable, isFalse);
      expect(failed.record!.tklContentDigests, isEmpty);
      expect(failed.record!.request, request);
      expect(server.prepares, 0);
      expect(await fixture.materials.readMaterial(request.materials.first.original), SubmissionFixture.photoBytes);
      expect(SubmissionTransferStatus.fromRecord(failed.record!, observedAt: fixture.now).actions, isEmpty);
    });

    test('same-length changed source fails independent server SHA and preserves verified sibling and receipts', () async {
      // Given immutable expectations, a prepared direct delivery and one verified original.
      final request = _request(await fixture.request());
      final server = _LakePeer()..direct = true;
      final client = server.client(); addTearDown(client.close);
      final queue = await fixture.openQueue();
      final service = fixture.service(queue, tklClients: {'lake': _remote(client)});
      await service.commit(request);
      for (var i = 0; i < 5; i++) { await service.processNext(networkAllowed: true); }
      final before = (await queue.find(request.id))!;
      expect(before.tklProgress!.resources.first.verificationState, TklOriginalVerificationState.verified);
      final material = request.materials.last.original;
      final changed = Uint8List.fromList(SubmissionFixture.audioBytes)..[0] = 0;
      final file = File('${fixture.directory.path}/originals/materials/${material.id}.bin');
      // When the same-length retained file changes after preparation and its new bytes are uploaded.
      await file.writeAsBytes(changed, flush: true);
      SubmissionRunResult? result;
      for (var i = 0; i < 3; i++) { result = await service.processNext(networkAllowed: true); }
      // Then only independent server comparison fails; placement never becomes registration/Studio acceptance.
      expect(result!.record!.lastFailure!.code, 'integrityMismatch');
      expect(result.record!.lastFailure!.retryable, isFalse);
      expect(result.record!.tklContentDigests, before.tklContentDigests);
      expect(result.record!.directReceipts.length, 2);
      expect(result.record!.tklProgress!.resources.first.verificationState, TklOriginalVerificationState.verified);
      expect(result.record!.tklProgress!.resources.last.verificationReason, 'integrityMismatch');
      expect(result.record!.acknowledgement, isNull);
      expect(result.record!.tklProgress!.materialRef, isNull);
      expect(await file.readAsBytes(), changed);
      final status = SubmissionTransferStatus.fromRecord(result.record!, observedAt: fixture.now);
      expect(status.upload.state, SubmissionTransferOperationState.succeeded);
      expect(status.verification!.state, SubmissionTransferOperationState.failed);
      expect(status.verification!.completedCount, 1);
      expect(status.registration!.state, SubmissionTransferOperationState.failed);
      expect(status.actions, isEmpty);
      expect(server.prepares, 1);
    });

    for (final unavailable in [false, true]) {
      test('verifying ${unavailable ? 'exhausts three checks safely' : 'performs one bytes-free finalize then registers'}', () async {
        // Given placed originals whose independent provider SHA is initially unavailable.
        final request = _request(await fixture.request());
        final server = _LakePeer()..direct = true;
        final client = server.client(); addTearDown(client.close);
        final queue = await fixture.openQueue();
        final service = fixture.service(queue, tklClients: {'lake': _remote(client)});
        await service.commit(request);
        for (var i = 0; i < 6; i++) { await service.processNext(networkAllowed: true); }
        server.missingShaChecks = unavailable ? 3 : 1;
        await service.processNext(networkAllowed: true); // confirm audio, first SHA check
        final placed = (await queue.find(request.id))!;
        expect(placed.tklProgress!.state, TklMaterialDeliveryState.verifying);
        final operations = server.providerUploads.toList();
        // When one eligible claim requests an existing finalize metadata check.
        var result = await service.processNext(networkAllowed: true);
        // Then it never uploads again or replays prepare; successful proof is independent of placed bytes.
        expect(server.providerUploads, operations);
        expect(server.prepares, 1);
        expect(server.finalizations, 1);
        if (!unavailable) {
          expect(result.outcome, SubmissionRunOutcome.materialRegistered);
          expect(server.verificationChecks['audio'], 2);
          expect(result.record!.acknowledgement, isNull);
        } else {
          // Given the same retained delivery still lacks provider SHA after its second check.
          expect(result.record!.tklProgress!.resources.last.verificationAttempts, 2);
          // When one more eligible finalize exhausts the server's total bound and a read classifies failure.
          await service.processNext(networkAllowed: true);
          result = await service.processNext(networkAllowed: true);
          // Then the third missing observation is terminal with no fourth check or automatic retry action.
          expect(result.record!.lastFailure!.code, 'verificationUnavailable');
          expect(server.verificationChecks['audio'], 3);
          expect(server.finalizations, 2);
          expect(server.providerUploads, operations);
          final status = SubmissionTransferStatus.fromRecord(result.record!, observedAt: fixture.now);
          expect(status.actions, isEmpty);
          expect(status.verification!.completedCount, 1);
          expect(status.upload.state, SubmissionTransferOperationState.succeeded);
          expect(result.record!.acknowledgement, isNull);
        }
      });
    }

    test('missing streaming capability refuses a queued request before preparation and whole reads', () async {
      // Given existing immutable queued TKL intent and a source-compatible legacy capture implementer.
      final request = _request(await fixture.request());
      final server = _LakePeer()..direct = true;
      final client = server.client(); addTearDown(client.close);
      final queue = await fixture.openQueue(); await queue.enqueue(request);
      final originals = _LegacyOnlyOriginals(fixture.materials);
      final service = fixture.service(queue, originals: originals, tklClients: {'lake': _remote(client)});
      // When preparation needs final-byte hashing but no optional stream capability exists.
      final result = await service.processNext(networkAllowed: true);
      // Then explicit safe failure preserves accepted intent without whole-read fallback or provider mutation.
      expect(result.record!.lastFailure!.code, 'originalStreamingRequired');
      expect(result.record!.request, request);
      expect(result.record!.tklContentDigests, isEmpty);
      expect(originals.wholeReads, 0);
      expect(server.prepares, 0);
    });

    test('new direct without SHA capability and unfinished legacy direct require explicit disposition', () async {
      // Given a new destination that cannot promise independent SHA verification.
      final request = _request(await fixture.request());
      final server = _LakePeer()..direct = true..advertiseIntegrity = false;
      final client = server.client(); addTearDown(client.close);
      final queue = await fixture.openQueue();
      final service = fixture.service(queue, tklClients: {'lake': _remote(client)});
      await service.commit(request);
      // When the driver discovers that direct destination before preparation.
      final refused = await service.processNext(networkAllowed: true);
      // Then no provider state is created under an unverifiable new expectation.
      expect(refused.record!.lastFailure!.code, 'integrityCapabilityRequired');
      expect(server.prepares, 0);
      // Given a retained old direct server delivery without any digest expectation.
      server.snapshot = {
        'delivery_ref': 'old-direct', 'request_id': request.id, 'revision': 1,
        'destination_id': 'selected', 'destination_label': 'Selected',
        'transfer_method': 'googleDriveResumable', 'state': 'prepared',
        'resources': [for (final m in request.materials) {
          'resource_id': m.key, 'media_type': m.original.mediaType,
          'byte_length': m.original.byteLength, 'state': 'pending',
        }],
      };
      // When an explicit retry reconciles that existing legacy delivery.
      await service.retry(request.id);
      final old = await service.processNext(networkAllowed: true);
      // Then it remains action-required without hashing, uploading or silently upgrading the old reservation.
      expect(old.record!.lastFailure!.code, 'integrityUpgradeRequired');
      expect(old.record!.tklContentDigests, isEmpty);
      expect(old.record!.tklProgress!.deliveryRef, 'old-direct');
      expect(server.providerUploads, isEmpty);
      expect(server.prepares, 0);
      expect(SubmissionTransferStatus.fromRecord(old.record!, observedAt: fixture.now).actions, isEmpty);
    });

    test('hash cancellation cannot checkpoint a retired owner or prepare remotely', () async {
      // Given native queued intent and a stream that retires the run during its first chunk.
      final request = _request(await fixture.request());
      final server = _LakePeer()..direct = true;
      final client = server.client(); addTearDown(client.close);
      final queue = await fixture.openQueue(); await queue.enqueue(request);
      var current = true;
      final originals = _StreamingOnlyOriginals(fixture.materials)..onChunk = () { current = false; };
      final service = fixture.service(queue, originals: originals, tklClients: {'lake': _remote(client)});
      // When hashing observes cancellation before accepting the current source chunk.
      final result = await service.processNext(networkAllowed: true, isRunCurrent: () => current);
      // Then the valid claim is released with no expectation or remote preparation, and originals remain.
      expect(result.outcome, SubmissionRunOutcome.cancelled);
      expect((await queue.find(request.id))!.tklContentDigests, isEmpty);
      expect(server.prepares, 0);
      expect(originals.wholeReads, 0);
      expect(originals.closedStreams, 1);
    });

    test('preparation and verification projections participate in pure status equality', () async {
      // Given a native TKL queue observed at the same time before and after actual digest persistence.
      final request = _request(await fixture.request());
      final queue = await fixture.openQueue();
      await queue.enqueue(request);
      final claimed = (await queue.claimNext(now: fixture.now, leaseToken: 'owner',
        leaseDuration: const Duration(minutes: 5)))!;
      final before = SubmissionTransferStatus.fromRecord(claimed, observedAt: fixture.now);
      // When one real queue checkpoint changes preparation alone under that existing lease.
      final saved = await queue.saveTklContentDigest(id: request.id, leaseToken: 'owner',
        key: 'photo', digest: TklContentDigest(algorithm: 'sha256',
          value: sha256.convert(SubmissionFixture.photoBytes).toString()), now: fixture.now);
      final after = SubmissionTransferStatus.fromRecord(saved, observedAt: fixture.now);
      // Then pure equality observes actual preparation count while verification remains absent.
      expect(before, isNot(after));
      expect(before.upload, after.upload);
      expect(before.registration, after.registration);
      expect(before.preparation!.completedCount, 0);
      expect(after.preparation!.completedCount, 1);
      expect(after.verification, isNull);
      expect(after, SubmissionTransferStatus.fromRecord(saved, observedAt: fixture.now));
      expect(after.hashCode, SubmissionTransferStatus.fromRecord(saved, observedAt: fixture.now).hashCode);
    });

    test('hash deadline discards late source bytes without checkpoint or provider preparation', () async {
      // Given existing queued intent and a retained range reader held before its first byte.
      final request = _request(await fixture.request());
      final queue = await fixture.openQueue(); await queue.enqueue(request);
      final server = _LakePeer()..direct = true;
      final client = server.client(); addTearDown(client.close);
      final entered = Completer<void>();
      final release = Completer<void>();
      final originals = _StreamingOnlyOriginals(fixture.materials);
      originals.beforeChunk = () async { entered.complete(); await release.future; };
      final service = fixture.service(queue, originals: originals,
        operationTimeout: const Duration(milliseconds: 15), tklClients: {'lake': _remote(client)});
      // When hashing exceeds its deadline while the actual native source is held.
      final pending = service.processNext(networkAllowed: true);
      await entered.future;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      release.complete();
      // Then this scenario releases the held reader after the deadline and rejects any late digest.
      // The source itself enforces the elapsed-time fence independently of its byte count.
      final result = await pending;
      expect(result.record!.tklContentDigests, isEmpty);
      expect(result.record!.lastFailure!.code, 'operationTimeout');
      expect(server.prepares, 0);
      expect(originals.wholeReads, 0);
    });

    test('empty originals prepare without fabricating any digest', () async {
      // Given a new empty contribution on a SHA-capable direct destination.
      final request = _request(await fixture.request(withMaterials: false));
      final server = _LakePeer()..direct = true;
      final client = server.client(); addTearDown(client.close);
      final queue = await fixture.openQueue();
      final service = fixture.service(queue, tklClients: {'lake': _remote(client)});
      await service.commit(request);
      // When preparation and registration are pumped without binary originals.
      await service.processNext(networkAllowed: true);
      final result = await service.processNext(networkAllowed: true);
      // Then no hash or byte transfer is fabricated and verification remains unreported.
      expect(result.outcome, SubmissionRunOutcome.materialRegistered);
      expect(result.record!.tklContentDigests, isEmpty);
      expect(server.providerUploads, isEmpty);
      final status = SubmissionTransferStatus.fromRecord(result.record!, observedAt: fixture.now);
      expect(status.preparation!.state, SubmissionTransferOperationState.notRequired);
      expect(status.verification, isNull);
      expect(status.acknowledgement, isNull);
    });
  });

  test('direct provider upload is checkpointed before TKL notification and survives queue reopening', () async {
    // Given the ordinary durable queue and TKL-selected direct provider route.
    final request = _request(await fixture.request());
    final server = _LakePeer()..direct = true;
    final client = server.client();
    addTearDown(client.close);
    var queue = await fixture.openQueue();
    var service = fixture.service(queue, tklClients: {'lake': _remote(client)});
    await service.commit(request);
    // When two bounded preparation claims persist the actual originals before provider preparation.
    await service.processNext(networkAllowed: true); // photo digest
    await service.processNext(networkAllowed: true); // audio digest
    await service.processNext(networkAllowed: true); // prepare delivery
    await service.processNext(networkAllowed: true); // direct photo upload
    final partial = (await queue.find(request.id))!;
    // Then placement alone creates a safe receipt before server verification or registration.
    expect(partial.directReceipts.keys, ['photo']);
    expect(
      partial.tklProgress!.resources.first.state,
      TklOriginalTransferState.pending,
    );
    expect(partial.acknowledgement, isNull);
    final saved = SubmissionCodec.recordToJson(partial);
    // Then both expectations and the independent direct receipt survive in V5.
    expect(saved['version'], 5);
    expect(partial.tklContentDigests.length, 2);
    expect(jsonEncode(saved), isNot(contains('upload_id=')));
    expect(jsonEncode(saved), isNot(contains('fixture-application-token')));
    // When the shared pure projection observes that independent placement checkpoint.
    final status = (await service.findTransferStatus(
      request.id,
      observedAt: fixture.now,
    ))!;
    // Then upload status advances while registration remains incomplete.
    expect(
      status.files.first.state,
      SubmissionTransferOperationState.succeeded,
    );
    expect(
      status.registration!.state,
      isNot(SubmissionTransferOperationState.succeeded),
    );
    await service.close();
    await queue.close();
    // When a new service resumes only notification, the remaining original and registration.
    queue = await fixture.openQueue();
    service = fixture.service(queue, tklClients: {'lake': _remote(client)});
    SubmissionRunResult? result;
    for (var i = 0; i < 4; i++) {
      result = await service.processNext(networkAllowed: true);
    }
    // Then no original bytes passed through TKL and no Studio acceptance was invented.
    expect(result!.outcome, SubmissionRunOutcome.materialRegistered);
    expect(server.providerUploads, ['photo', 'audio']);
    expect(server.uploads, isEmpty);
    expect(server.confirmations, ['photo', 'audio']);
    expect(server.uploadedBytes['photo'], SubmissionFixture.photoBytes);
    expect(server.uploadedBytes['audio'], SubmissionFixture.audioBytes);
    expect(server.prepares, 1);
    expect(result.record!.acknowledgement, isNull);
  });

  test('lost provider upload reply probes the same session without replay or alternate-route bytes', () async {
    // Given persisted actual-byte expectations and the existing direct provider session.
    final request = _request(await fixture.request());
    final server = _LakePeer()
      ..direct = true
      ..loseUploadResponse = true;
    final client = server.client();
    addTearDown(client.close);
    final queue = await fixture.openQueue();
    var service = fixture.service(queue, tklClients: {'lake': _remote(client)});
    await service.commit(request);
    // When bounded hashing and preparation finish before the first provider upload.
    await service.processNext(networkAllowed: true);
    await service.processNext(networkAllowed: true);
    await service.processNext(networkAllowed: true);
    // When the provider commits the first upload but its response is lost.
    final unknown = await service.processNext(networkAllowed: true);
    // Then uncertainty is retained without inventing preparation or placement acceptance.
    expect(unknown.record!.lastFailure!.code, 'lakeOutcomeUnknown');
    expect(unknown.record!.directReceipts, isEmpty);
    await service.close();
    fixture.now = fixture.now.add(const Duration(minutes: 1));
    service = fixture.service(queue, tklClients: {'lake': _remote(client)});
    SubmissionRunResult? done;
    for (var i = 0; i < 4; i++) {
      done = await service.processNext(networkAllowed: true);
    }
    // Then retained provider completion is independently reconciled before continuing.
    expect(done!.outcome, SubmissionRunOutcome.materialRegistered);
    expect(server.providerUploads, ['photo', 'audio']);
    expect(server.confirmations, ['audio']);
    expect(server.uploads, isEmpty);
    expect(server.prepares, 1);
  });

  test('one existing durable queue resumes confirmed uploads and finishes TKL without Studio acknowledgement', () async {
    // Given real captured originals and one explicitly configured TKL service.
    final legacy = await fixture.request();
    final request = _request(legacy);
    final server = _LakePeer();
    final client = server.client();
    addTearDown(client.close);
    final remote = _remote(client);
    var queue = await fixture.openQueue();
    var service = fixture.service(queue, tklClients: {'lake': remote});
    await service.commit(request);
    expect(server.operations, isEmpty);
    // When offline work is requested, no remote call or claim is made.
    expect(
      (await service.processNext(networkAllowed: false)).outcome,
      SubmissionRunOutcome.offline,
    );
    expect(server.operations, isEmpty);
    await service.processNext(networkAllowed: true); // prepare
    await service.processNext(networkAllowed: true); // first original
    final partial = (await queue.find(request.id))!;
    expect(
      partial.tklProgress!.resources.first.state,
      TklOriginalTransferState.uploaded,
    );
    expect(partial.receipts, isEmpty);
    expect(SubmissionCodec.requestToJson(request)['version'], 2);
    expect(SubmissionCodec.recordToJson(partial)['version'], 3);
    // Given a fresh service and SQLite handle over the same persisted queue.
    await service.close();
    await queue.close();
    queue = await fixture.openQueue();
    service = fixture.service(queue, tklClients: {'lake': remote});
    expect(
      (await queue.find(request.id))!.tklProgress!.deliveryRef,
      'delivery-commit1',
    );
    // When only remaining work is pumped after restart.
    await service.processNext(networkAllowed: true);
    final done = await service.processNext(networkAllowed: true);
    // Then each original is uploaded once and registration has its own terminal state.
    expect(done.outcome, SubmissionRunOutcome.materialRegistered);
    expect(done.record!.state, SubmissionState.materialRegistered);
    expect(
      done.record!.tklProgress!.materialRef,
      'urn:textus:klake:test:material:commit1',
    );
    expect(done.record!.acknowledgement, isNull);
    expect(server.uploads, ['photo', 'audio']);
    expect(server.prepares, 1);
    expect(server.finalizations, 1);
    expect(server.uploadedBytes['photo'], SubmissionFixture.photoBytes);
    expect(server.uploadedBytes['audio'], SubmissionFixture.audioBytes);
    expect(
      server.committed!['contribution'],
      request.tklDelivery!.contribution,
    );
    expect(fixture.referenceAccess.calls, 0);
    expect(fixture.storage.prepares, 0);
    expect(fixture.storage.uploads, 0);
    expect(fixture.transport.submits, 0);
    final status = (await service.findTransferStatus(
      request.id,
      observedAt: fixture.now,
    ))!;
    // Then historical metadata-only registration reports no invented SHA success.
    expect(status.verification, isNull);
    expect(status.preparation!.completedCount, 0);
    expect(status.preparation!.totalCount, 2);
    expect(status.usesLakeDelivery, isTrue);
    expect(status.upload.state, SubmissionTransferOperationState.succeeded);
    expect(
      status.registration!.state,
      SubmissionTransferOperationState.succeeded,
    );
    expect(
      status.submission.state,
      SubmissionTransferOperationState.notRequired,
    );
    expect(status.acknowledgement, isNull);
    expect(
      status.files.every(
        (file) => file.state == SubmissionTransferOperationState.succeeded,
      ),
      isTrue,
    );
    expect(
      (await service.processNext(networkAllowed: true)).outcome,
      SubmissionRunOutcome.noWork,
    );
    final wakeCount = fixture.scheduler.calls;
    await service.requestRun(request.id);
    expect(fixture.scheduler.calls, wakeCount);
  });

  test('lost finalization acknowledgement reconciles the same delivery without another finalize', () async {
    // Given a controlled server that commits Registered before losing its response.
    final request = _request(await fixture.request());
    final server = _LakePeer()..loseFinalizeResponse = true;
    final client = server.client();
    addTearDown(client.close);
    final queue = await fixture.openQueue();
    var service = fixture.service(queue, tklClients: {'lake': _remote(client)});
    await service.commit(request);
    for (var i = 0; i < 3; i++) {
      await service.processNext(networkAllowed: true);
    }
    // When the mutation reply is unavailable after remote registration.
    final unknown = await service.processNext(networkAllowed: true);
    expect(unknown.outcome, SubmissionRunOutcome.failed);
    // Then uncertainty is retained without inventing preparation or placement acceptance.
    expect(unknown.record!.lastFailure!.code, 'lakeOutcomeUnknown');
    expect(unknown.record!.acknowledgement, isNull);
    expect(unknown.record!.tklProgress!.materialRef, isNull);
    await service.close();
    fixture.now = fixture.now.add(const Duration(minutes: 1));
    service = fixture.service(queue, tklClients: {'lake': _remote(client)});
    // Then recovery queries the retained identity and does not replay finalization.
    final done = await service.processNext(networkAllowed: true);
    expect(done.record!.state, SubmissionState.materialRegistered);
    expect(server.finalizations, 1);
    expect(server.prepares, 1);
    expect(server.uploads, ['photo', 'audio']);
    expect(server.operations.last, 'get');
    expect(done.record!.acknowledgement, isNull);
  });

  test('TKL reconciliationRequired keeps originals and blocks automatic provider retry', () async {
    // Given a prepared delivery whose next status reports an uncertain provider write.
    final request = _request(await fixture.request());
    final server = _LakePeer();
    final client = server.client();
    addTearDown(client.close);
    final queue = await fixture.openQueue();
    final service = fixture.service(
      queue,
      tklClients: {'lake': _remote(client)},
    );
    await service.commit(request);
    await service.processNext(networkAllowed: true);
    server.snapshot!['state'] = 'reconciliationRequired';
    server.snapshot!['action_required'] = 'operatorReconciliationRequired';
    // When the next claim reconciles actual server state.
    final failed = await service.processNext(networkAllowed: true);
    // Then it retains state/data and waits for explicit resolution without upload.
    expect(failed.record!.lastFailure!.code, 'lakeReconciliationRequired');
    expect(failed.record!.lastFailure!.retryable, isFalse);
    expect(server.uploads, isEmpty);
    for (final material in request.materials) {
      expect(
        await fixture.materials.readMaterial(material.original),
        isNotEmpty,
      );
    }
    final count = server.operations.length;
    fixture.now = fixture.now.add(const Duration(hours: 1));
    expect(
      (await service.processNext(networkAllowed: true)).outcome,
      SubmissionRunOutcome.noWork,
    );
    expect(server.operations.length, count);
  });

  test('legacy request/record JSON remains unchanged and TKL is not a Drive configuration fallback', () async {
    // Given an ordinary existing direct-Drive request.
    final legacy = await fixture.request();
    final queue = await fixture.openQueue();
    final legacyRecord = await queue.enqueue(legacy);
    // When old and new formats are read through the same queue codec.
    expect(SubmissionCodec.requestToJson(legacy)['version'], 1);
    expect(SubmissionCodec.recordToJson(legacyRecord)['version'], 2);
    expect(
      SubmissionCodec.recordFromJson(
        SubmissionCodec.recordToJson(legacyRecord),
      ),
      legacyRecord,
    );
    final request = _request(
      await fixture.request(id: 'commit2', subjectId: 'subject2'),
    );
    final service = fixture.service(queue, storageAdapters: {}, transports: {});
    // First claim the old row explicitly so the TKL row is selected independently.
    await queue.claimNext(
      now: fixture.now,
      leaseToken: 'held-legacy',
      leaseDuration: const Duration(hours: 1),
    );
    await service.commit(request);
    final failed = await service.processNext(networkAllowed: true);
    // Then missing TKL bootstrap is explicit; no direct-Drive adapter is selected.
    expect(failed.record!.lastFailure!.code, 'lakeConnectionRequired');
    expect(failed.record!.request.storageConnectionId, isNull);
    expect(fixture.storage.prepares, 0);
    expect(fixture.storage.uploads, 0);
    expect((await queue.find(legacy.id))!.request, legacy);
  });
}

SubmissionRequest _request(SubmissionRequest original) => SubmissionRequest(
  id: original.id,
  kind: original.kind,
  subjectId: original.subjectId,
  createdAt: original.createdAt,
  document: original.document,
  payload: original.payload,
  materials: original.materials,
  transportConnectionId: 'lake',
  extensions: original.extensions,
  tklDelivery: TklMaterialDeliveryRequest(
    requestId: original.id,
    contribution: {
      'schema': 'textus.material-contribution/1',
      'title': 'Book',
      'createdAt': original.createdAt.toIso8601String(),
      'classifications': ['book'],
      'provenance': original.extensions,
      'originals': [
        for (final material in original.materials)
          {
            'resourceId': material.key,
            'role': 'original',
            'mediaType': material.original.mediaType,
            'byteLength': material.original.byteLength,
            'sourceReference': {'kind': 'mobileOriginal'},
          },
      ],
      'documents': [
        {
          'resourceId': 'metadata',
          'role': 'book',
          'body': original.payload,
          'derivedFrom': [
            for (final material in original.materials) material.key,
          ],
        },
      ],
    },
  ),
);

TklMaterialDeliveryHttpClient _remote(http.Client client) =>
    TklMaterialDeliveryHttpClient(
      connection: HttpSubmissionConnection(
        id: 'lake',
        endpoint: Uri.parse(
          'https://lake.example/rest/v1/lake/material-delivery/',
        ),
      ),
      client: client,
      credentials: _Credentials(),
    );

final class _Credentials implements SubmissionCredentialProvider {
  @override
  Future<String?> bearerToken(String connectionId) async =>
      'fixture-application-token';
}

/// A controlled remote process surviving local service/SQLite reopening.
final class _LakePeer {
  final operations = <String>[];
  final uploads = <String>[];
  final uploadedBytes = <String, List<int>>{};
  Map<String, dynamic>? committed;
  Map<String, dynamic>? snapshot;
  int prepares = 0;
  int finalizations = 0;
  bool loseFinalizeResponse = false;
  bool losePrepareResponse = false;
  bool losePrepareWithoutCommit = false;
  final prepareBodies = <Map<String, dynamic>>[];
  bool direct = false;
  bool advertiseIntegrity = true;
  int missingShaChecks = 0;
  final verificationChecks = <String, int>{};
  bool loseUploadResponse = false;
  final providerUploads = <String>[];
  final confirmations = <String>[];
  final providerCompleted = <String>{};
  void checkIntegrity(Map resource) {
    if (resource['state'] != 'uploaded' || !resource.containsKey('content_digest') ||
        resource['verification_state'] == 'verified' ||
        resource['verification_state'] == 'failed') {
      return;
    }
    final key = resource['resource_id'] as String;
    final attempts = (resource['verification_attempts'] as int) + 1;
    verificationChecks[key] = (verificationChecks[key] ?? 0) + 1;
    resource['verification_attempts'] = attempts;
    if (missingShaChecks > 0) {
      missingShaChecks--;
      resource['verification_state'] = attempts == 3 ? 'failed' : 'verifying';
      if (attempts == 3) resource['verification_reason'] = 'verificationUnavailable';
    } else if (sha256.convert(uploadedBytes[key]!).toString() ==
        (resource['content_digest'] as Map)['value']) {
      resource['verification_state'] = 'verified';
    } else {
      resource['verification_state'] = 'failed';
      resource['verification_reason'] = 'integrityMismatch';
    }
  }
  void updateState() {
    final resources = snapshot!['resources'] as List;
    final failed = resources.where((r) => r['verification_state'] == 'failed');
    snapshot!['state'] = failed.isNotEmpty ? 'verificationFailed'
        : resources.any((r) => r['state'] == 'uploaded' && r.containsKey('content_digest') &&
            r['verification_state'] != 'verified') ? 'verifying'
        : resources.every((r) => r['state'] == 'uploaded') ? 'readyToRegister'
        : 'transferring';
    if (failed.isNotEmpty) snapshot!['action_required'] = failed.first['verification_reason'];
  }
  void markUploaded(String key) {
    for (final resource in snapshot!['resources'] as List) {
      if (resource['resource_id'] == key) {
        resource['state'] = 'uploaded';
        checkIntegrity(resource as Map);
      }
    }
    snapshot!['revision'] = (snapshot!['revision'] as int) + 1;
    updateState();
  }

  http.Client client() => MockClient((request) async {
    if (request.url.host == 'www.googleapis.com') {
      expect(request.method, 'PUT');
      expect(
        request.headers.keys.any((key) => key.toLowerCase() == 'authorization'),
        isFalse,
      );
      final key = request.url.queryParameters['upload_id']!;
      providerUploads.add(key);
      uploadedBytes[key] = request.bodyBytes;
      providerCompleted.add(key);
      if (loseUploadResponse) {
        loseUploadResponse = false;
        return _response({}, status: 503);
      }
      return _response({'id': 'provider-$key'});
    }
    final operation = request.url.pathSegments.last;
    operations.add(operation);
    switch (operation) {
      case 'getDestination':
        return _response({
          'availability': 'available',
          if (direct && advertiseIntegrity) 'contentIntegrity': 'sha256',
          'destination_id': 'selected',
          'label': 'TKL selected destination',
          'transfer_method': direct ? 'googleDriveResumable' : 'tklMultipart',
        });
      case 'findForRequest':
        return _response({
          'found': snapshot != null,
          if (snapshot != null) 'delivery': snapshot,
        });
      case 'prepare':
        prepares++;
        committed = jsonDecode(request.body) as Map<String, dynamic>;
        prepareBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        snapshot = {
          'delivery_ref': 'delivery-${committed!['requestId']}',
          'request_id': committed!['requestId'],
          'revision': 1,
          'destination_id': 'selected',
          'destination_label': 'TKL selected destination',
          'transfer_method': direct ? 'googleDriveResumable' : 'tklMultipart',
          'state': 'prepared',
          'resources': [
            for (final value in committed!['contribution']['originals'] as List)
              {
                'resource_id': value['resourceId'],
                'media_type': value['mediaType'],
                'byte_length': value['byteLength'],
                'state': 'pending',
                if (value.containsKey('contentDigest')) ...{
                  'content_digest': value['contentDigest'],
                  'verification_state': 'pending', 'verification_attempts': 0,
                },
              },
          ],
        };
        if (losePrepareWithoutCommit) {
          losePrepareWithoutCommit = false;
          snapshot = null;
          return _response({}, status: 503);
        }
        if (losePrepareResponse) {
          losePrepareResponse = false;
          return _response({}, status: 503);
        }
        return _response(snapshot, status: 201);
      case 'get':
        return _response(snapshot);
      case 'prepareOriginalTransfer':
        final body = jsonDecode(request.body) as Map;
        final key = body['resourceId'] as String;
        if (providerCompleted.contains(key)) {
          markUploaded(key);
          return _response({'delivery': snapshot});
        }
        final resource = (snapshot!['resources'] as List).singleWhere(
          (item) => item['resource_id'] == key,
        ) as Map;
        return _response({
          'delivery': snapshot,
          'instruction': {
            'transfer_ref': 'transfer-$key',
            'resource_id': key,
            'method': 'googleDriveResumable',
            'upload_session_uri':
                'https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=$key',
            'media_type': resource['media_type'],
            'byte_length': resource['byte_length'],
            'next_offset': 0,
          },
        });
      case 'confirmOriginalTransfer':
        final body = jsonDecode(request.body) as Map;
        final key = body['resourceId'] as String;
        expect(body['transferRef'], 'transfer-$key');
        expect((body['result'] as Map)['outcome'], 'uploaded');
        expect(providerCompleted, contains(key));
        confirmations.add(key);
        markUploaded(key);
        return _response(snapshot);
      case 'uploadOriginal':
        final wire = latin1.decode(request.bodyBytes);
        final key = RegExp('name="resourceId"\\r\\n\\r\\n([^\\r\\n]+)')
            .firstMatch(wire)!
            .group(1)!;
        uploads.add(key);
        final file = wire.indexOf('filename="original"');
        final start = wire.indexOf('\r\n\r\n', file) + 4;
        final end = wire.indexOf('\r\n--', start);
        uploadedBytes[key] = latin1.encode(wire.substring(start, end));
        for (final resource in snapshot!['resources'] as List) {
          if (resource['resource_id'] == key) resource['state'] = 'uploaded';
        }
        snapshot!['revision'] = (snapshot!['revision'] as int) + 1;
        snapshot!['state'] =
            (snapshot!['resources'] as List).every(
              (value) => value['state'] == 'uploaded',
            )
            ? 'readyToRegister'
            : 'transferring';
        return _response(snapshot);
      case 'finalize':
        finalizations++;
        if (snapshot!['state'] == 'verifying') {
          for (final resource in snapshot!['resources'] as List) {
            checkIntegrity(resource as Map);
          }
          snapshot!['revision'] = (snapshot!['revision'] as int) + 1;
          updateState();
          if (snapshot!['state'] != 'readyToRegister') return _response(snapshot);
        }
        snapshot!['state'] = 'registered';
        snapshot!['revision'] = (snapshot!['revision'] as int) + 1;
        snapshot!['material_ref'] =
            'urn:textus:klake:test:material:${snapshot!['request_id']}';
        return loseFinalizeResponse
            ? _response({}, status: 503)
            : _response(snapshot);
      default:
        throw StateError('Unexpected fixture operation');
    }
  });
  http.Response _response(Object? body, {int status = 200}) =>
      http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json'},
      );
}

SubmissionRequest _contributionRequest(SubmissionRequest request, Map<String, Object?> contribution) =>
  SubmissionCodec.requestFromJson({...SubmissionCodec.requestToJson(request),
    'tklDelivery': {'requestId': request.id, 'contribution': contribution}});

class _LegacyOnlyOriginals implements LocalCaptureStore {
  _LegacyOnlyOriginals(this.inner);
  final LocalCaptureStore inner;
  int wholeReads = 0;
  @override
  Future<Uint8List> readMaterial(CaptureMaterialReference reference) {
    wholeReads++;
    throw StateError('Whole original reads are prohibited for this TKL scenario');
  }
  @override
  Future<CaptureMaterialReference> saveMaterial({required Uint8List bytes,
    required String mediaType, required DateTime capturedAt, String? originalName}) =>
      inner.saveMaterial(bytes: bytes, mediaType: mediaType, capturedAt: capturedAt, originalName: originalName);
  @override
  Future<void> saveDocument(String collection, String id, Map<String, Object?> document) => inner.saveDocument(collection, id, document);
  @override
  Future<Map<String, Object?>?> readDocument(String collection, String id) => inner.readDocument(collection, id);
  @override
  Future<List<String>> listDocumentIds(String collection) => inner.listDocumentIds(collection);
}
final class _StreamingOnlyOriginals extends _LegacyOnlyOriginals implements StreamingLocalCaptureStore {
  _StreamingOnlyOriginals(super.inner);
  void Function()? onChunk;
  Future<void> Function()? beforeChunk;
  int closedStreams = 0;
  final ranges = <(int, int?)>[];
  @override
  Stream<List<int>> openMaterial(CaptureMaterialReference reference, {int start = 0, int? end}) async* {
    ranges.add((start, end));
    try {
      await for (final chunk in (inner as StreamingLocalCaptureStore).openMaterial(reference, start: start, end: end)) {
        await beforeChunk?.call();
        onChunk?.call();
        yield chunk;
      }
    } finally { closedStreams++; }
  }
}
