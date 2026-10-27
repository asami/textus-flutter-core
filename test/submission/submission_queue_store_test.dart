import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

import '../support/submission_fixture.dart';

void main() {
  late SubmissionFixture f;
  setUp(() async {
    // Given a scenario needing real originals and independent host SQLite handles.
    // When a fresh isolated test-owned fixture is created and installed.
    f = await SubmissionFixture.create();
    // Then f holds the new fixture for this scenario to use and dispose.
  });
  tearDown(() async {
    // Given all scenario-owned handles, including already closed handles.
    // When fixture drains and closes them before deleting its temporary directory.
    await f.dispose();
    // Then persisted production data and borrowed resources are untouched.
  });

  group('TKL immutable retained-content checkpoint', () {
    test('one local digest is durable idempotent and fenced across native SQLite reopening', () async {
      // Given an accepted TKL request and a current lease on the native queue.
      var queue = await f.openQueue();
      final request = _integrityRequest(await f.request(document: {
        'opaque': [null, {'literal_key': '窯変', 'context': null}],
      }));
      await queue.enqueue(request);
      await queue.claimNext(now: f.now, leaseToken: 'ownerA',
        leaseDuration: const Duration(minutes: 5));
      final digest = _digest('a');
      // When the first actual original expectation is saved before any remote progress.
      final saved = await queue.saveTklContentDigest(id: request.id,
        leaseToken: 'ownerA', key: 'photo', digest: digest, now: f.now);
      // Then V5 contains empty progress/receipt checkpoints and exact immutable accepted JSON.
      final json = SubmissionCodec.recordToJson(saved);
      expect(json['version'], 5);
      expect(json['tklProgress'], isNull);
      expect(json['directReceipts'], isEmpty);
      expect(saved.request, request);
      expect(SubmissionCodec.recordFromJson(json), saved);
      expect(() => saved.tklContentDigests.clear(), throwsUnsupportedError);
      // When equal, changed and unknown-key duplicates are attempted under that lease.
      expect(await queue.saveTklContentDigest(id: request.id, leaseToken: 'ownerA',
        key: 'photo', digest: digest, now: f.now.add(const Duration(seconds: 1))), saved);
      await expectLater(queue.saveTklContentDigest(id: request.id, leaseToken: 'ownerA',
        key: 'photo', digest: _digest('b'), now: f.now), throwsStateError);
      await expectLater(queue.saveTklContentDigest(id: request.id, leaseToken: 'ownerA',
        key: 'unknown', digest: digest, now: f.now), throwsStateError);
      // Then failures do not replace the retained expectation or original request.
      expect(await queue.find(request.id), saved);
      await queue.close();
      // When the queue reopens and the expired owner loses to a new lease.
      queue = await f.openQueue();
      expect(await queue.find(request.id), saved);
      f.now = f.now.add(const Duration(minutes: 6));
      final claimed = await queue.claimNext(now: f.now, leaseToken: 'ownerB',
        leaseDuration: const Duration(minutes: 5));
      await expectLater(queue.saveTklContentDigest(id: request.id, leaseToken: 'ownerA',
        key: 'audio', digest: digest, now: f.now), throwsA(isA<SubmissionLeaseLostException>()));
      // Then a stale owner cannot alter the new claim or its durable expectations.
      expect(await queue.find(request.id), claimed);
      expect(claimed!.tklContentDigests, {'photo': digest});
      expect(claimed.request.document, request.document);
    });

    test('non-TKL originals cannot acquire a TKL digest checkpoint', () async {
      // Given an ordinary legacy request under a valid native queue lease.
      final queue = await f.openQueue();
      final request = await f.request();
      await queue.enqueue(request);
      final claimed = await queue.claimNext(now: f.now, leaseToken: 'owner',
        leaseDuration: const Duration(minutes: 5));
      // When a TKL expectation is offered to the unrelated original route.
      await expectLater(queue.saveTklContentDigest(id: request.id, leaseToken: 'owner',
        key: 'photo', digest: _digest('a'), now: f.now), throwsStateError);
      // Then the ordinary queued original and claim remain unchanged.
      expect(await queue.find(request.id), claimed);
    });

    test('server expectations verification and attempt counts cannot change or regress', () async {
      // Given both actual local expectations and a server-verified first original.
      final queue = await f.openQueue();
      final request = _integrityRequest(await f.request());
      await queue.enqueue(request);
      await queue.claimNext(now: f.now, leaseToken: 'owner',
        leaseDuration: const Duration(minutes: 5));
      for (final material in request.materials) {
        await queue.saveTklContentDigest(id: request.id, leaseToken: 'owner',
          key: material.key, digest: _digest('a'), now: f.now);
      }
      TklMaterialDeliverySnapshot snapshot({
        TklContentDigest? firstDigest, int attempts = 2,
        TklOriginalVerificationState firstState = TklOriginalVerificationState.verified,
        bool complete = false, bool omitProof = false,
      }) => TklMaterialDeliverySnapshot(
        deliveryRef: 'delivery', requestId: request.id, revision: 2,
        destinationId: 'selected', destinationLabel: 'Selected',
        state: complete ? TklMaterialDeliveryState.readyToRegister : TklMaterialDeliveryState.transferring,
        resources: [for (var i = 0; i < request.materials.length; i++)
          TklOriginalTransferProgress(resourceId: request.materials[i].key,
            mediaType: request.materials[i].original.mediaType,
            byteLength: request.materials[i].original.byteLength,
            state: i == 0 || complete ? TklOriginalTransferState.uploaded : TklOriginalTransferState.pending,
            contentDigest: omitProof ? null : i == 0 ? firstDigest ?? _digest('a') : _digest('a'),
            verificationState: omitProof ? null : i == 0 ? firstState
                : complete ? TklOriginalVerificationState.verified : TklOriginalVerificationState.pending,
            verificationAttempts: omitProof ? null : i == 0 ? attempts : complete ? 1 : 0,
          ),
        ],
      );
      final saved = await queue.saveTklProgress(id: request.id, leaseToken: 'owner',
        progress: snapshot(), now: f.now);
      // When a changed expectation, lost verified state, fewer checks or absent proof is returned.
      for (final invalid in [snapshot(firstDigest: _digest('b')),
        snapshot(firstState: TklOriginalVerificationState.verifying),
        snapshot(attempts: 1), snapshot(complete: true, omitProof: true)]) {
        await expectLater(queue.saveTklProgress(id: request.id, leaseToken: 'owner',
          progress: invalid, now: f.now), throwsA(anyOf(isA<StateError>(), isA<ArgumentError>())));
        // Then the verified sibling, attempts and accepted expectations remain durable.
        expect(await queue.find(request.id), saved);
      }
      // When complete bound proof arrives for both retained originals.
      final ready = await queue.saveTklProgress(id: request.id, leaseToken: 'owner',
        progress: snapshot(complete: true), now: f.now);
      // Then readiness is accepted without inventing a Studio acknowledgement.
      expect(ready.tklProgress!.state, TklMaterialDeliveryState.readyToRegister);
      expect(ready.acknowledgement, isNull);
    });

    test('record versions one through five retain nullable opaque accepted contexts', () async {
      // Given a legacy ready request and the same JSON carried into a TKL request.
      final legacy = await f.request(withMaterials: false, document: {
        'literal_context': [null, {'contentDigest': null, 'snake_case': ' 原文 '}],
      });
      final queue = await f.openQueue();
      final original = await queue.enqueue(legacy);
      final v2 = SubmissionCodec.recordToJson(original);
      final v1 = {...v2, 'version': 1}..remove('transportCheckpoint');
      // When exact legacy schemas are decoded.
      // Then both preserve the original accepted nulls and opaque keys.
      expect(SubmissionCodec.recordFromJson(v1), original);
      expect(SubmissionCodec.recordFromJson(v2), original);
      final request = _integrityRequest(await f.request(id: 'integrity', subjectId: 'other',
        document: legacy.document));
      await queue.enqueue(request);
      final ready = (await queue.find(request.id))!;
      final v3 = SubmissionCodec.recordToJson(ready);
      final v4 = {...v3, 'version': 4, 'directReceipts': <String, Object?>{}};
      expect(SubmissionCodec.recordFromJson(v3), ready);
      expect(SubmissionCodec.recordFromJson(v4), ready);
      // When one actual original expectation upgrades only its record checkpoint to V5.
      await queue.claimNext(now: f.now, leaseToken: 'holdLegacy', leaseDuration: const Duration(hours: 1));
      await queue.claimNext(now: f.now, leaseToken: 'owner', leaseDuration: const Duration(minutes: 5));
      final checkpoint = await queue.saveTklContentDigest(id: request.id,
        leaseToken: 'owner', key: 'photo', digest: _digest('a'), now: f.now);
      // Then exact V5 round trip retains contexts, intent and an independent empty server projection.
      expect(SubmissionCodec.recordFromJson(SubmissionCodec.recordToJson(checkpoint)), checkpoint);
      expect(checkpoint.request.document, legacy.document);
      expect(checkpoint.tklProgress, isNull);
      expect(checkpoint.directReceipts, isEmpty);
    });
  });

  test(
    'Q2 independent duplicate enqueue and immutable subject uniqueness',
    () async {
      // Given two independent handles and mutable caller JSON at request creation.
      final first = await f.openQueue();
      final second = await f.openQueue();
      final document = <String, Object?>{
        'draft': <Object?>['before'],
      };
      final request = await f.request(document: document);
      // When intent enqueue starts and caller state subsequently changes.
      final pending = first.enqueue(request);
      (document['draft']! as List).add('after');
      final accepted = await pending;
      final duplicate = await second.enqueue(request);
      await first.close();
      final reopened = await f.openQueue();
      // Then equal duplicate/reopen preserve the exact accepted snapshot.
      expect(duplicate, accepted);
      expect(await reopened.enqueue(request), accepted);
      expect(accepted.request.document, {
        'draft': ['before'],
      });
      final conflicting = SubmissionCodec.requestFromJson({
        ...SubmissionCodec.requestToJson(request),
        'payload': {'changed': true},
      });
      await expectLater(second.enqueue(conflicting), throwsStateError);
      final otherId = SubmissionCodec.requestFromJson({
        ...SubmissionCodec.requestToJson(request),
        'id': 'commit2',
      });
      await expectLater(second.enqueue(otherId), throwsStateError);
      expect(await second.find(request.id), accepted);
      expect(
        await second.findForSubject(request.kind, request.subjectId),
        accepted,
      );
      expect(await second.find('absent'), isNull);
      expect(await second.findForSubject('other', request.subjectId), isNull);
      expect(await second.list(), [accepted]);
      expect(() async => (await second.list()).clear(), throwsUnsupportedError);
    },
  );

  test('Q3 competing claims, expiry fencing, rollback and renewal', () async {
    // Given one ready intent visible to two independent real SQLite handles.
    final a = await f.openQueue();
    final b = await f.openQueue();
    final request = await f.request();
    await a.enqueue(request);
    // When both handles compete for the same currently eligible row.
    final claims = await Future.wait([
      a.claimNext(
        now: f.now,
        leaseToken: 'ownerA',
        leaseDuration: const Duration(minutes: 5),
      ),
      b.claimNext(
        now: f.now,
        leaseToken: 'ownerB',
        leaseDuration: const Duration(minutes: 5),
      ),
    ]);
    // Then exactly one wins and the other cannot create a second active owner.
    expect(claims.whereType<SubmissionRecord>().length, 1);
    expect(claims.where((claim) => claim == null).length, 1);
    final claim = claims.whereType<SubmissionRecord>().single;
    expect(claim.claimCount, 1);
    final reservation = f.storage.reservation('photo', request.id);
    await a.saveReservation(
      id: request.id,
      leaseToken: claim.leaseToken!,
      reservation: reservation,
      now: f.now,
    );
    expect(
      await b.claimNext(
        now: f.now.subtract(const Duration(hours: 1)),
        leaseToken: 'rollback',
        leaseDuration: const Duration(minutes: 5),
      ),
      isNull,
    );
    final renewed = await b.renewLease(
      id: request.id,
      leaseToken: claim.leaseToken!,
      now: f.now.add(const Duration(minutes: 4)),
      leaseDuration: const Duration(minutes: 5),
    );
    expect(renewed.claimCount, 1);
    expect(renewed.leaseExpiresAt, f.now.add(const Duration(minutes: 9)));
    expect(renewed.reservations['photo'], reservation);
    expect(
      await a.claimNext(
        now: f.now.add(const Duration(minutes: 5)),
        leaseToken: 'notExpired',
        leaseDuration: const Duration(minutes: 5),
      ),
      isNull,
    );
    // Given the renewed expiry has now been reached exactly.
    final expiredAt = f.now.add(const Duration(minutes: 9));
    // When old owner renewal is attempted and a new token claims the expired row.
    await expectLater(
      a.renewLease(
        id: request.id,
        leaseToken: claim.leaseToken!,
        now: expiredAt,
        leaseDuration: const Duration(minutes: 5),
      ),
      throwsA(isA<SubmissionLeaseLostException>()),
    );
    final recovered = await b.claimNext(
      now: expiredAt,
      leaseToken: 'recovered',
      leaseDuration: const Duration(minutes: 5),
    );
    // Then checkpoints survive and every stale-owner operation remains fenced.
    expect(recovered!.claimCount, 2);
    expect(recovered.request, request);
    expect(recovered.reservations, renewed.reservations);
    await expectLater(
      a.release(id: request.id, leaseToken: claim.leaseToken!, now: expiredAt),
      throwsA(isA<SubmissionLeaseLostException>()),
    );
    await expectLater(
      a.renewLease(
        id: request.id,
        leaseToken: claim.leaseToken!,
        now: expiredAt,
        leaseDuration: const Duration(minutes: 5),
      ),
      throwsA(isA<SubmissionLeaseLostException>()),
    );
    await expectLater(
      a.saveReservation(
        id: request.id,
        leaseToken: claim.leaseToken!,
        reservation: reservation,
        now: expiredAt,
      ),
      throwsA(isA<SubmissionLeaseLostException>()),
    );
    await expectLater(
      a.saveReceipt(
        id: request.id,
        leaseToken: claim.leaseToken!,
        receipt: SubmissionMaterialReceipt(
          key: 'photo',
          providerId: reservation.providerId,
          remoteId: 'oldOwnerRemote',
          accessConnectionId: 'drive',
          storedAt: expiredAt,
        ),
        now: expiredAt,
      ),
      throwsA(isA<SubmissionLeaseLostException>()),
    );
    await expectLater(
      a.complete(
        id: request.id,
        leaseToken: claim.leaseToken!,
        acknowledgement: f.transport.acknowledgement(request),
        now: expiredAt,
      ),
      throwsA(isA<SubmissionLeaseLostException>()),
    );
    await expectLater(
      a.fail(
        id: request.id,
        leaseToken: claim.leaseToken!,
        failure: SubmissionFailure(
          stage: SubmissionFailureStage.storage,
          code: 'oldOwnerFailure',
          message: 'Safe old owner failure',
          retryable: false,
          occurredAt: expiredAt,
          claimCount: 1,
        ),
        now: expiredAt,
      ),
      throwsA(isA<SubmissionLeaseLostException>()),
    );
    expect(await a.find(request.id), recovered);
  });

  test(
    'Q3 oldest creation and id tie order; valid release retains history',
    () async {
      // Given same-time ids inserted in reverse order plus an older request.
      final queue = await f.openQueue();
      final b = await f.request(
        id: 'b',
        subjectId: 'subjectB',
        withMaterials: false,
      );
      final a = await f.request(
        id: 'a',
        subjectId: 'subjectA',
        withMaterials: false,
      );
      final old = SubmissionCodec.requestFromJson({
        ...SubmissionCodec.requestToJson(a),
        'id': 'old',
        'subjectId': 'oldSubject',
        'createdAt': f.now.subtract(const Duration(days: 1)).toIso8601String(),
      });
      await queue.enqueue(b);
      await queue.enqueue(a);
      await queue.enqueue(old);
      // When successive distinct tokens claim eligible rows while others stay active.
      final ids = <String>[];
      for (var i = 0; i < 3; i++) {
        ids.add(
          (await queue.claimNext(
            now: f.now,
            leaseToken: 'order$i',
            leaseDuration: const Duration(minutes: 5),
          ))!.request.id,
        );
      }
      // Then selection uses createdAt/id and excludes every nonexpired claim.
      expect(ids, ['old', 'a', 'b']);
      expect(
        await queue.claimNext(
          now: f.now,
          leaseToken: 'none',
          leaseDuration: const Duration(minutes: 5),
        ),
        isNull,
      );
      expect(
        (await queue.release(
          id: 'old',
          leaseToken: 'order0',
          now: f.now,
        )).state,
        SubmissionState.readyToSubmit,
      );
      await expectLater(
        queue.claimNext(
          now: f.now,
          leaseToken: 'order1',
          leaseDuration: const Duration(minutes: 5),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'Q4 reopen checkpoints/history and reject replacements transactionally',
    () async {
      // Given a real queued request claimed for reservation and upload checkpoints.
      final queue = await f.openQueue();
      final request = await f.request();
      await queue.enqueue(request);
      await queue.claimNext(
        now: f.now,
        leaseToken: 'owner',
        leaseDuration: const Duration(minutes: 5),
      );
      final reservation = f.storage.reservation('photo', request.id);
      final saved = await queue.saveReservation(
        id: request.id,
        leaseToken: 'owner',
        reservation: reservation,
        now: f.now,
      );
      // When equal checkpoints repeat, unequal/unknown/provider/ack values are tried.
      expect(
        await queue.saveReservation(
          id: request.id,
          leaseToken: 'owner',
          reservation: reservation,
          now: f.now,
        ),
        saved,
      );
      await expectLater(
        queue.saveReservation(
          id: request.id,
          leaseToken: 'owner',
          reservation: SubmissionStorageReservation(
            key: 'photo',
            providerId: reservation.providerId,
            data: {'different': true},
          ),
          now: f.now,
        ),
        throwsStateError,
      );
      await expectLater(
        queue.saveReservation(
          id: request.id,
          leaseToken: 'owner',
          reservation: f.storage.reservation('unknown', request.id),
          now: f.now,
        ),
        throwsStateError,
      );
      final receipt = SubmissionMaterialReceipt(
        key: 'photo',
        providerId: reservation.providerId,
        remoteId: 'remote/photo',
        accessConnectionId: 'drive',
        storedAt: f.now,
      );
      await expectLater(
        queue.saveReceipt(
          id: request.id,
          leaseToken: 'owner',
          receipt: SubmissionCodec.receiptFromJson({
            ...SubmissionCodec.receiptToJson(receipt),
            'providerId': 'other',
          }),
          now: f.now,
        ),
        throwsStateError,
      );
      final uploaded = await queue.saveReceipt(
        id: request.id,
        leaseToken: 'owner',
        receipt: receipt,
        now: f.now,
      );
      expect(
        await queue.saveReceipt(
          id: request.id,
          leaseToken: 'owner',
          receipt: receipt,
          now: f.now,
        ),
        uploaded,
      );
      await expectLater(
        queue.saveReceipt(
          id: request.id,
          leaseToken: 'owner',
          receipt: SubmissionCodec.receiptFromJson({
            ...SubmissionCodec.receiptToJson(receipt),
            'remoteId': 'replacement',
          }),
          now: f.now,
        ),
        throwsStateError,
      );
      await expectLater(
        queue.complete(
          id: request.id,
          leaseToken: 'owner',
          acknowledgement: f.transport.acknowledgement(request),
          now: f.now,
        ),
        throwsStateError,
      );
      final failure = SubmissionFailure(
        stage: SubmissionFailureStage.transport,
        code: 'safeFailure',
        message: 'Safe failure',
        retryable: true,
        occurredAt: f.now,
        claimCount: 1,
      );
      await expectLater(
        queue.fail(
          id: request.id,
          leaseToken: 'owner',
          failure: failure,
          now: f.now,
        ),
        throwsArgumentError,
      );
      final failed = await queue.fail(
        id: request.id,
        leaseToken: 'owner',
        failure: failure,
        now: f.now,
        nextAttemptAt: f.now.add(const Duration(seconds: 30)),
      );
      await queue.close();
      final reopened = await f.openQueue();
      // Then exact persisted checkpoints/history survive failures and reopen.
      expect(await reopened.find(request.id), failed);
      final ready = await reopened.retry(id: request.id, now: f.now);
      expect(ready.reservations, failed.reservations);
      expect(ready.receipts, failed.receipts);
      expect(ready.failureHistory, [failure]);
      expect(ready.lastFailure, isNull);
      await reopened.claimNext(
        now: f.now,
        leaseToken: 'nextOwner',
        leaseDuration: const Duration(minutes: 5),
      );
      await expectLater(
        reopened.retry(id: request.id, now: f.now),
        throwsStateError,
      );
      await reopened.saveReservation(
        id: request.id,
        leaseToken: 'nextOwner',
        reservation: f.storage.reservation('audio', request.id),
        now: f.now,
      );
      final audio = SubmissionMaterialReceipt(
        key: 'audio',
        providerId: reservation.providerId,
        remoteId: 'remote/audio',
        accessConnectionId: 'drive',
        storedAt: f.now,
      );
      await reopened.saveReceipt(
        id: request.id,
        leaseToken: 'nextOwner',
        receipt: audio,
        now: f.now,
      );
      await expectLater(
        reopened.complete(
          id: request.id,
          leaseToken: 'nextOwner',
          acknowledgement: SubmissionAcknowledgement(
            requestId: 'wrong',
            subjectId: request.subjectId,
            serverId: 'fake',
            receivedAt: f.now,
          ),
          now: f.now,
        ),
        throwsStateError,
      );
      final submitted = await reopened.complete(
        id: request.id,
        leaseToken: 'nextOwner',
        acknowledgement: f.transport.acknowledgement(request),
        now: f.now,
      );
      expect(submitted.failureHistory, [failure]);
      expect(await reopened.retry(id: request.id, now: f.now), submitted);
      expect(
        await reopened.claimNext(
          now: f.now,
          leaseToken: 'submittedExcluded',
          leaseDuration: const Duration(minutes: 5),
        ),
        isNull,
      );
    },
  );

  test('Q4 opening an independent handle waits for an existing lock', () async {
    // Given a warmed production FFI worker and an exact durable fixture record.
    final seed = await f.openQueue();
    final request = await f.request();
    final accepted = await seed.enqueue(request);
    await seed.close();
    final raw = await databaseFactoryFfiNoIsolate.openDatabase(
      f.databasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    final enteredConfigure = Completer<void>();
    final factory = _ConfigureObservingFactory(
      databaseFactoryFfi,
      enteredConfigure,
    );
    var lockHeld = false;
    SqliteSubmissionQueueStore? opened;
    Object? openError;
    StackTrace? openStack;
    Future<void>? openObserved;
    Future<void>? release;
    try {
      await raw.execute('BEGIN EXCLUSIVE');
      lockHeld = true;
      // When an independent production open enters its unchanged configuration.
      final opening = SqliteSubmissionQueueStore.open(
        f.databasePath,
        factory: factory,
      );
      openObserved = opening.then<void>(
        (queue) {
          // Given the production open has succeeded with its own handle.
          // When its immediate observer receives that handle.
          opened = queue;
          // Then assertions and finally cleanup retain this owned resource.
        },
        onError: (Object error, StackTrace stack) {
          // Given configuration can fail while the raw lock is still held.
          // When its immediately attached observer receives that failure.
          openError = error;
          openStack = stack;
          // Then failure stays observable after the owned lock is released.
        },
      );
      await enteredConfigure.future.timeout(const Duration(seconds: 10));
      release = Future<void>.delayed(const Duration(milliseconds: 50), () async {
        // Given the raw main-event-loop handle owns the exclusive lock.
        // When the real timer fires while the FFI worker configures its handle.
        await raw.execute('COMMIT');
        lockHeld = false;
        // Then production configuration can continue within its native budget.
      });
      await openObserved.timeout(const Duration(seconds: 10));
      await release;
      if (openError != null) {
        Error.throwWithStackTrace(openError!, openStack!);
      }
      final queue = opened!;
      // Then FULL/5s configuration and exact original intent survive contention.
      expect(lockHeld, isFalse);
      expect(await queue.find(request.id), accepted);
      expect(await queue.list(), [accepted]);
      final configured = factory.configuredDatabase!;
      expect(
        (await configured.rawQuery('PRAGMA synchronous')).single.values.single,
        2,
      );
      expect(
        (await configured.rawQuery('PRAGMA busy_timeout')).single.values.single,
        5000,
      );
      // Given the independently opened queue is usable after lock release.
      final next = await f.request(id: 'commit2', subjectId: 'subject2');
      // When another exact intent is enqueued and the independent handle closes.
      final nextAccepted = await queue.enqueue(next);
      expect(await queue.find(next.id), nextAccepted);
      await queue.close();
      final reopened = await f.openQueue();
      // Then a fresh handle retains both records without replacement or loss.
      expect(await reopened.find(request.id), accepted);
      expect(await reopened.find(next.id), nextAccepted);
      expect(await reopened.list(), [accepted, nextAccepted]);
    } finally {
      // Given success, open failure or a bounded configure-observation timeout.
      // When any scheduled release joins and only this scenario's lock is freed.
      try {
        if (release != null) await release;
      } finally {
        try {
          if (lockHeld) {
            await raw.execute('ROLLBACK');
            lockHeld = false;
          }
        } finally {
          try {
            if (openObserved != null) await openObserved;
            if (opened != null) await opened!.close();
          } finally {
            await raw.close();
          }
        }
      }
      // Then no opening future or owned raw/queue handle escapes fixture teardown.
    }
  });

  test('Q4 actual SQLite write failure recovers and retained corruption is observable', () async {
    // Given an accepted row and an independent raw handle used only for faults.
    final queue = await f.openQueue();
    final request = await f.request(withMaterials: false);
    final ready = await queue.enqueue(request);
    final raw = await databaseFactoryFfi.openDatabase(
      f.databasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      await raw.execute(
        "CREATE TRIGGER reject_checkpoint BEFORE UPDATE ON submission_jobs "
        "BEGIN SELECT RAISE(ABORT, 'controlled write failure'); END",
      );
      // When a real transaction fails, the later write is allowed after fault removal.
      await expectLater(
        queue.claimNext(
          now: f.now,
          leaseToken: 'failOwner',
          leaseDuration: const Duration(minutes: 5),
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(await queue.find(request.id), ready);
      await raw.execute('DROP TRIGGER reject_checkpoint');
      final recovered = await queue.claimNext(
        now: f.now,
        leaseToken: 'goodOwner',
        leaseDuration: const Duration(minutes: 5),
      );
      // Then the serialized chain recovers and the actual row stays intact.
      expect(recovered!.claimCount, 1);
      final body = jsonEncode(SubmissionCodec.recordToJson(recovered));
      await raw.update(
        'submission_jobs',
        {'body': '{broken'},
        where: 'request_id = ?',
        whereArgs: [request.id],
      );
      await expectLater(queue.find(request.id), throwsFormatException);
      await expectLater(
        queue.claimNext(
          now: f.now,
          leaseToken: 'corruptClaim',
          leaseDuration: const Duration(minutes: 5),
        ),
        throwsFormatException,
      );
      expect((await raw.query('submission_jobs')).single['body'], '{broken');
      await raw.update(
        'submission_jobs',
        {'body': body, 'kind': 'mismatched'},
        where: 'request_id = ?',
        whereArgs: [request.id],
      );
      await expectLater(queue.list(), throwsFormatException);
      expect((await raw.query('submission_jobs')).single['kind'], 'mismatched');
    } finally {
      // Given the raw fault handle is independently owned by this scenario.
      // When the scenario completes, close it without deleting any source row.
      await raw.close();
      // Then fixture can later close its own real queue handle.
    }
    expect(await File(f.databasePath).exists(), isTrue);
  });

  test('Q4 unsupported database version and close preserve the owned file', () async {
    // Given a test-owned future schema 3 database and a separately opened queue.
    final path = '${f.directory.path}/unsupported.sqlite';
    final raw = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        singleInstance: false,
        onCreate: (db, version) async {
          // Given a future schema marker owned by this test.
          // When SQLite creates it, preserve a detectable source value.
          await db.execute('CREATE TABLE future_data (value TEXT)');
          await db.insert('future_data', {'value': 'retained'});
          // Then opening the current version 2 store must not reset/drop this source.
        },
      ),
    );
    await raw.close();
    // When the current version 2 store tries opening the future version 3 database.
    await expectLater(
      SqliteSubmissionQueueStore.open(path, factory: databaseFactoryFfi),
      throwsFormatException,
    );
    final retained = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    // Then source version/data persist, and normal closed handles reject calls.
    expect(await retained.getVersion(), 3);
    expect((await retained.query('future_data')).single['value'], 'retained');
    await retained.close();
    final queue = await f.openQueue();
    await queue.close();
    await queue.close();
    await expectLater(queue.list(), throwsStateError);
    expect(await File(f.databasePath).exists(), isTrue);
  });
}

/// Given a production FFI factory and a scenario-owned configure notification,
/// when only openDatabase is forwarded, then its original options stay intact.
final class _ConfigureObservingFactory implements DatabaseFactory {
  _ConfigureObservingFactory(this.inner, this.enteredConfigure);

  final DatabaseFactory inner;
  final Completer<void> enteredConfigure;
  Database? configuredDatabase;

  @override
  Future<Database> openDatabase(String path, {OpenDatabaseOptions? options}) {
    // Given the exact production open options and callbacks for this real file.
    final supplied = options!;
    // When the supplied onConfigure callback is wrapped only for entry observation.
    return inner.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: supplied.version,
        readOnly: supplied.readOnly,
        singleInstance: supplied.singleInstance,
        onCreate: supplied.onCreate,
        onUpgrade: supplied.onUpgrade,
        onDowngrade: supplied.onDowngrade,
        onOpen: supplied.onOpen,
        onConfigure: (database) async {
          // Given the real FFI handle has reached production configuration.
          // When the scenario observes entry without changing the callback.
          configuredDatabase = database;
          enteredConfigure.complete();
          await supplied.onConfigure?.call(database);
          // Then native SQLite still executes the production wait/FULL settings.
        },
      ),
    );
    // Then the caller receives the real factory result or its unchanged failure.
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    // Given this helper owns only the required openDatabase forwarding surface.
    // When any unsupported factory member is requested.
    throw UnsupportedError(
      'Unsupported factory member: ${invocation.memberName}',
    );
    // Then no fabricated database, path or filesystem result can be returned.
  }
}

TklContentDigest _digest(String digit) => TklContentDigest(
  algorithm: 'sha256', value: List.filled(64, digit).join());
SubmissionRequest _integrityRequest(SubmissionRequest original) =>
  SubmissionCodec.requestFromJson({
    ...SubmissionCodec.requestToJson(original), 'version': 2,
    'storageConnectionId': null,
    'tklDelivery': {'requestId': original.id, 'contribution': {
      'originals': [for (final material in original.materials) {
        'resourceId': material.key, 'mediaType': material.original.mediaType,
        'byteLength': material.original.byteLength,
        'sourceReference': {'kind': 'mobileOriginal'},
      }],
    }},
  });
