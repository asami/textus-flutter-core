import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

import '../support/submission_fixture.dart';
import '../support/submission_http_fixture.dart';
import 'registered_material_submission_test.dart' show registeredTestRequest,
    registeredTestPacket, registeredTestTarget, registeredJsonCopy;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SubmissionFixture f;
  final services = <RegisteredMaterialHandoffService>[];
  setUp(() async {
    f = await SubmissionFixture.create();
    f.now = DateTime.utc(2026, 10, 26, 2);
  });
  tearDown(() async {
    for (final service in services) { await service.close(); }
    services.clear();
    await f.dispose();
  });

  RegisteredMaterialHandoffService service(SqliteSubmissionQueueStore queue,
      RegisteredMaterialSubmissionTransport transport, {
      RegisteredMaterialHandoffStore? store,
      Duration operationTimeout = const Duration(minutes: 1),
    }) {
    final result = RegisteredMaterialHandoffService(queue: queue, store: store ?? queue,
      transports: {transport.connection.id: transport}, scheduler: f.scheduler,
      now: () => f.now, operationTimeout: operationTimeout);
    services.add(result);
    return result;
  }

  test('should create once from the saved Registered source and reject changed targets without IO', () async {
    // Given an actual persisted Registered TKL source and borrowed legacy storage/transport ports.
    final queue = await f.openQueue();
    final source = await _saveRegistered(queue, registeredTestRequest(), f.now);
    final transport = _RegisteredTransport(registeredTestTarget());
    final handoffs = service(queue, transport);
    // When explicit creation is repeated and a changed endpoint is proposed under the same ID.
    final first = await handoffs.enqueueRegistered(source.request.id, transport.connection);
    f.now = f.now.add(const Duration(seconds: 1));
    final duplicate = await handoffs.enqueueRegistered(source.request.id, transport.connection);
    await expectLater(handoffs.enqueueRegistered(source.request.id,
      registeredTestTarget(path: '/another')), throwsStateError);
    // Then one stable packet/ID/time exists and the original source has no Studio ACK or changes.
    expect(duplicate.record, first.record);
    expect(await handoffs.list(), [first.record]);
    expect(await handoffs.findForSource(source.request.id), first.record);
    expect(await queue.find(source.request.id), source);
    expect((await queue.list()).length, 1);
    expect(source.acknowledgement, isNull);
    expect(first.record.sourceCheckpointUpdatedAt, source.updatedAt);
    expect(first.record.registeredSnapshot.deliveryRef, source.tklProgress!.deliveryRef);
    expect(first.record.registeredSnapshot.revision, source.tklProgress!.revision);
    expect(transport.packets, isEmpty);
    expect(f.storage.prepares, 0);
    expect(f.storage.uploads, 0);
    expect(f.transport.submits, 0);
    expect(f.scheduler.calls, 2);
  });

  test('should require a real saved Registered source instead of trusting packet or snapshot DTOs', () async {
    // Given a valid-looking Registered DTO that was never saved in this real database.
    final queue = await f.openQueue();
    final request = registeredTestRequest();
    final source = _registeredRecord(request, f.now);
    final packet = registeredTestPacket(source: request);
    final transport = _RegisteredTransport(packet.target);
    final handoffs = service(queue, transport);
    // When a forged source is supplied to the typed store, or enqueue selects an absent/pending source.
    await expectLater(queue.createHandoff(id: 'forged', source: source,
      target: packet.target, packet: packet, now: f.now), throwsStateError);
    await expectLater(handoffs.enqueueRegistered(request.id, packet.target), throwsStateError);
    await queue.enqueue(request);
    await expectLater(handoffs.enqueueRegistered(request.id, packet.target), throwsStateError);
    // Then no handoff, scheduler wake or remote dispatch is authorized by DTO construction.
    expect(await queue.listHandoffs(), isEmpty);
    expect(f.scheduler.calls, 0);
    expect(transport.packets, isEmpty);
  });

  test('should add database version 2 while retaining every version 1 source body byte', () async {
    // Given an actual old database containing both an ordinary body and a complete Registered body.
    final request = registeredTestRequest();
    final registered = _registeredRecord(request, f.now);
    final ordinary = SubmissionRecord(request: await f.request(id: 'old', subjectId: 'old'),
      state: SubmissionState.readyToSubmit, claimCount: 0, updatedAt: f.now);
    final bodies = {
      registered.request.id: '  ${jsonEncode(SubmissionCodec.recordToJson(registered))}\n',
      ordinary.request.id: jsonEncode(SubmissionCodec.recordToJson(ordinary)),
    };
    final old = await databaseFactoryFfi.openDatabase(f.databasePath,
      options: OpenDatabaseOptions(version: 1, singleInstance: false, onCreate: (db, _) async {
        await db.execute('CREATE TABLE submission_jobs (request_id TEXT PRIMARY KEY, '
          'kind TEXT NOT NULL, subject_id TEXT NOT NULL, body TEXT NOT NULL, UNIQUE(kind, subject_id))');
      }));
    for (final record in [registered, ordinary]) {
      await old.insert('submission_jobs', {'request_id': record.request.id,
        'kind': record.request.kind, 'subject_id': record.request.subjectId,
        'body': bodies[record.request.id]});
    }
    await old.close();
    // When the production store performs its additive 1-to-2 migration and creates a handoff.
    final queue = await f.openQueue();
    final handoffs = service(queue, _RegisteredTransport(registeredTestTarget()));
    await handoffs.enqueueRegistered(request.id, registeredTestTarget());
    final native = await databaseFactoryFfi.openDatabase(f.databasePath,
      options: OpenDatabaseOptions(singleInstance: false));
    final rows = await native.query('submission_jobs');
    final version = await native.getVersion();
    await native.close();
    // Then old jobs and serialized bodies are identical and only the independent new table was added.
    expect(version, 2);
    expect({for (final row in rows) row['request_id']: row['body']}, bodies);
    expect(await queue.find(request.id), registered);
    expect(await queue.find('old'), ordinary);
    expect((await queue.listHandoffs()).length, 1);
  });

  test('should persist the sending lease before HTTP and restore the actual accepted ACK after reopen', () async {
    // Given a real file database, saved Registered source and concrete HTTP transport with controlled IO.
    var queue = await f.openQueue();
    final source = await _saveRegistered(queue, registeredTestRequest(), f.now);
    final network = SubmissionHttpFixture();
    addTearDown(network.dispose);
    final expected = _ack(source.request);
    network.client.handler = (_) async {
      final marker = await queue.findHandoffForSource(source.request.id);
      expect(marker!.state, RegisteredMaterialHandoffState.sending);
      expect(marker.leaseToken, isNotNull);
      expect(marker.acknowledgement, isNull);
      return submissionJsonResponse(SubmissionCodec.acknowledgementToJson(expected));
    };
    final handoffs = service(queue, network.transport());
    final created = await handoffs.enqueueRegistered(source.request.id, network.httpConnection);
    // When the actual adapter response is saved and the native database is closed/reopened.
    final result = await handoffs.processNext(networkAllowed: true);
    await handoffs.close();
    await queue.close();
    queue = await f.openQueue();
    final restored = await queue.findHandoffForSource(source.request.id);
    // Then only the separate handoff accepts, retaining exact packet, registration and server time.
    expect(result.outcome, RegisteredMaterialHandoffRunOutcome.accepted);
    expect(restored!.acknowledgement, expected);
    expect(restored.state, RegisteredMaterialHandoffState.accepted);
    expect(restored.packet, created.record.packet);
    expect(restored.leaseToken, isNull);
    expect(await queue.find(source.request.id), source);
    expect(network.client.requests.length, 1);
    final status = SubmissionTransferStatus.fromRecord(source, observedAt: f.now,
      handoff: restored);
    expect(status.registration!.state, SubmissionTransferOperationState.succeeded);
    expect(status.submission.state, SubmissionTransferOperationState.succeeded);
    expect(status.submission.completedAt, expected.receivedAt);
    expect(status.acknowledgement, expected);
    expect(status.studioHandoff, restored);
    expect(status.transportConnectionId, 'lake');
  });

  test('should freeze the same packet across unknown outcome and explicit reconciliation only', () async {
    // Given an actual Registered source and a transport whose first potential send loses its response.
    final queue = await f.openQueue();
    final source = await _saveRegistered(queue, registeredTestRequest(), f.now);
    final transport = _RegisteredTransport(registeredTestTarget());
    transport.onSubmit = (_) => throw StateError('untrusted private response data');
    final handoffs = service(queue, transport);
    final original = (await handoffs.enqueueRegistered(source.request.id, transport.connection)).record;
    // When the uncertain result is observed twice, then the user explicitly reconciles the frozen packet.
    final first = await handoffs.processNext(networkAllowed: true);
    final wakeCount = f.scheduler.calls;
    expect((await handoffs.processNext(networkAllowed: true)).outcome,
      RegisteredMaterialHandoffRunOutcome.noWork);
    final requeued = await handoffs.reconcile(source.request.id);
    transport.onSubmit = (packet) async => _ack(packet.sourceRequest);
    final accepted = await handoffs.processNext(networkAllowed: true);
    // Then unknown never auto-retries/wakes; explicit replay retains identity, mapping and target.
    expect(first.outcome, RegisteredMaterialHandoffRunOutcome.outcomeUnknown);
    expect(first.record!.failure!.message, isNot(contains('untrusted')));
    expect(requeued.record.id, original.id);
    expect(requeued.record.packet, original.packet);
    expect(requeued.record.target.toJson(), original.target.toJson());
    expect(requeued.record.createdAt, original.createdAt);
    expect(f.scheduler.calls, wakeCount + 1);
    expect(transport.packets, [original.packet, original.packet]);
    expect(accepted.record!.acknowledgement, _ack(source.request));
    await expectLater(handoffs.reconcile(source.request.id), throwsStateError);
    expect(await queue.find(source.request.id), source);
  });

  test('should reject a mismatched ACK and never accept an unrelated manual ACK in persisted state', () async {
    // Given a matching packet but a transport returning another request's acknowledgement.
    final queue = await f.openQueue();
    final source = await _saveRegistered(queue, registeredTestRequest(), f.now);
    final transport = _RegisteredTransport(registeredTestTarget());
    transport.onSubmit = (_) async => _ack(registeredTestRequest(id: 'other'));
    final handoffs = service(queue, transport);
    await handoffs.enqueueRegistered(source.request.id, transport.connection);
    // When that real typed transport response is processed and handoff JSON is tampered with.
    final result = await handoffs.processNext(networkAllowed: true);
    final json = RegisteredMaterialSubmissionCodec.handoffToJson(result.record!);
    json['acknowledgement'] = SubmissionCodec.acknowledgementToJson(_ack(source.request));
    // Then the outcome remains unknown and an ACK cannot be attached to a nonaccepted state.
    expect(result.outcome, RegisteredMaterialHandoffRunOutcome.outcomeUnknown);
    expect(result.record!.acknowledgement, isNull);
    expect(() => RegisteredMaterialSubmissionCodec.handoffFromJson(json), throwsFormatException);
    expect((await queue.find(source.request.id))!.acknowledgement, isNull);
  });

  test('should observe expired sending as unknown without dispatching or accepting the lost lease', () async {
    // Given a durable sending marker created before a worker vanished.
    final queue = await f.openQueue();
    final source = await _saveRegistered(queue, registeredTestRequest(), f.now);
    final transport = _RegisteredTransport(registeredTestTarget());
    final handoffs = service(queue, transport);
    final original = (await handoffs.enqueueRegistered(source.request.id, transport.connection)).record;
    final claim = await queue.claimNextHandoff(now: f.now, leaseToken: 'vanished',
      leaseDuration: const Duration(minutes: 5));
    await expectLater(handoffs.reconcile(source.request.id), throwsStateError);
    f.now = f.now.add(const Duration(minutes: 6));
    // When another driver scans and the old worker tries to save a late ACK.
    final result = await handoffs.processNext(networkAllowed: true);
    await expectLater(queue.finishHandoff(id: claim!.id, leaseToken: 'vanished', now: f.now,
      state: RegisteredMaterialHandoffState.accepted, acknowledgement: _ack(source.request)),
      throwsA(isA<RegisteredMaterialHandoffLeaseLostException>()));
    // Then no transport is called, no automatic requeue occurs and the packet is unchanged.
    final saved = await handoffs.findForSource(source.request.id);
    expect(result.outcome, RegisteredMaterialHandoffRunOutcome.noWork);
    expect(saved!.state, RegisteredMaterialHandoffState.outcomeUnknown);
    expect(saved.packet, original.packet);
    expect(saved.acknowledgement, isNull);
    expect(transport.packets, isEmpty);
    expect(f.scheduler.calls, 1);
  });

  test('should discard a matching transport ACK after the lease expires during send', () async {
    // Given a held transport response after a real sending lease has been persisted.
    final queue = await f.openQueue();
    final source = await _saveRegistered(queue, registeredTestRequest(), f.now);
    final transport = _RegisteredTransport(registeredTestTarget());
    final entered = Completer<void>();
    final held = Completer<SubmissionAcknowledgement>();
    transport.onSubmit = (_) { entered.complete(); return held.future; };
    final handoffs = service(queue, transport);
    await handoffs.enqueueRegistered(source.request.id, transport.connection);
    final pending = handoffs.processNext(networkAllowed: true);
    await submissionEntered(entered);
    // When wall time exceeds that lease before the real matching response returns.
    f.now = f.now.add(const Duration(minutes: 6));
    held.complete(_ack(source.request));
    final result = await pending;
    // Then the stale worker cannot acknowledge success and a later scan only observes unknown.
    expect(result.outcome, RegisteredMaterialHandoffRunOutcome.leaseLost);
    expect((await queue.findHandoffForSource(source.request.id))!.state, RegisteredMaterialHandoffState.sending);
    await handoffs.processNext(networkAllowed: true);
    expect((await queue.findHandoffForSource(source.request.id))!.state, RegisteredMaterialHandoffState.outcomeUnknown);
    expect(transport.packets.length, 1);
  });

  for (final outcome in [SubmissionTransportFailureOutcome.notSent, SubmissionTransportFailureOutcome.rejected]) {
    test('should keep $outcome failure explicit with no automatic replay', () async {
      // Given a trusted typed transport that conclusively classifies this one failed attempt.
      final queue = await f.openQueue();
      final source = await _saveRegistered(queue, registeredTestRequest(), f.now);
      final transport = _RegisteredTransport(registeredTestTarget());
      transport.onSubmit = (_) => throw SubmissionAdapterException(
        stage: SubmissionFailureStage.transport, code: 'controlledFailure', message: 'Safe test failure.',
        retryable: true, transportFailureOutcome: outcome);
      final handoffs = service(queue, transport);
      final original = (await handoffs.enqueueRegistered(source.request.id, transport.connection)).record;
      // When the failure is processed and another automatic run scans the queue.
      final failed = await handoffs.processNext(networkAllowed: true);
      final again = await handoffs.processNext(networkAllowed: true);
      // Then failed remains terminal for automatic work despite the legacy retryable flag.
      expect(failed.outcome, RegisteredMaterialHandoffRunOutcome.failed);
      expect(failed.record!.state, RegisteredMaterialHandoffState.failed);
      expect(SubmissionTransferStatus.fromRecord(source, observedAt: f.now,
        handoff: failed.record).submission.state, SubmissionTransferOperationState.failed);
      expect(again.outcome, RegisteredMaterialHandoffRunOutcome.noWork);
      expect(transport.packets.length, 1);
      expect(f.scheduler.calls, 1);
      expect((await handoffs.reconcile(source.request.id)).record.packet, original.packet);
    });
  }

  test('should perform no queue IO offline or retired and keep passive reads free of dispatch', () async {
    // Given an existing pending handoff and an observable forwarding store.
    final queue = await f.openQueue();
    final source = await _saveRegistered(queue, registeredTestRequest(), f.now);
    final transport = _RegisteredTransport(registeredTestTarget());
    final port = _HandoffStore(queue);
    final handoffs = service(queue, transport, store: port);
    await handoffs.enqueueRegistered(source.request.id, transport.connection);
    final calls = port.calls;
    final wakes = f.scheduler.calls;
    // When offline/retired runs are attempted, followed by ordinary status reads.
    expect((await handoffs.processNext(networkAllowed: false)).outcome, RegisteredMaterialHandoffRunOutcome.offline);
    expect((await handoffs.processNext(networkAllowed: true, isRunCurrent: () => false)).outcome,
      RegisteredMaterialHandoffRunOutcome.cancelled);
    expect(port.calls, calls);
    await handoffs.findForSource(source.request.id);
    await handoffs.list();
    // Then reads never claim/send/wake and the original source remains unchanged.
    expect(transport.packets, isEmpty);
    expect(f.scheduler.calls, wakes);
    expect(await queue.find(source.request.id), source);
    expect(f.storage.prepares, 0);
    expect(f.storage.uploads, 0);
  });

  test('should recheck retirement after the persisted claim before any transport call', () async {
    // Given a store barrier that retires the run while the sending claim is awaited.
    final queue = await f.openQueue();
    final source = await _saveRegistered(queue, registeredTestRequest(), f.now);
    final transport = _RegisteredTransport(registeredTestTarget());
    var current = true;
    final store = _HandoffStore(queue)..afterClaim = () async { current = false; };
    final handoffs = service(queue, transport, store: store);
    await handoffs.enqueueRegistered(source.request.id, transport.connection);
    // When the claim finishes after run retirement.
    final result = await handoffs.processNext(networkAllowed: true, isRunCurrent: () => current);
    // Then the persisted uncertainty boundary stays unknown without starting remote work.
    expect(result.outcome, RegisteredMaterialHandoffRunOutcome.outcomeUnknown);
    expect(result.record!.acknowledgement, isNull);
    expect(transport.packets, isEmpty);
  });

  test('should verify the actual typed transport destination before dispatch', () async {
    // Given a service map whose connection ID matches but whose actual endpoint differs.
    final queue = await f.openQueue();
    final source = await _saveRegistered(queue, registeredTestRequest(), f.now);
    final transport = _RegisteredTransport(registeredTestTarget(path: '/different'));
    final handoffs = service(queue, transport);
    final created = await handoffs.enqueueRegistered(source.request.id, registeredTestTarget());
    // When the driver claims the frozen packet and inspects the typed port definition.
    final result = await handoffs.processNext(networkAllowed: true);
    // Then no remote call occurs and the pinned target stays unchanged for explicit reconciliation.
    expect(result.outcome, RegisteredMaterialHandoffRunOutcome.failed);
    expect(result.record!.failure!.kind, RegisteredMaterialHandoffFailureKind.configuration);
    expect(result.record!.packet, created.record.packet);
    expect(transport.packets, isEmpty);
  });

  test('should claim only the oldest pending handoff and keep one active owner per row', () async {
    // Given two Registered sources with handoffs durably created at distinct local times.
    final queue = await f.openQueue();
    final first = await _saveRegistered(queue, registeredTestRequest(id: 'first'), f.now);
    final second = await _saveRegistered(queue, registeredTestRequest(id: 'second'), f.now);
    final transport = _RegisteredTransport(registeredTestTarget());
    final handoffs = service(queue, transport);
    final older = await handoffs.enqueueRegistered(first.request.id, transport.connection);
    f.now = f.now.add(const Duration(seconds: 1));
    final newer = await handoffs.enqueueRegistered(second.request.id, transport.connection);
    // When independent typed claims select pending rows under different tokens.
    final firstClaim = await queue.claimNextHandoff(now: f.now,
      leaseToken: 'firstOwner', leaseDuration: const Duration(minutes: 5));
    await expectLater(queue.claimNextHandoff(now: f.now, leaseToken: 'firstOwner',
      leaseDuration: const Duration(minutes: 5)), throwsArgumentError);
    final secondClaim = await queue.claimNextHandoff(now: f.now,
      leaseToken: 'secondOwner', leaseDuration: const Duration(minutes: 5));
    final none = await queue.claimNextHandoff(now: f.now,
      leaseToken: 'thirdOwner', leaseDuration: const Duration(minutes: 5));
    // Then the oldest pending row wins exactly once and active sending is never reselected.
    expect(firstClaim!.id, older.record.id);
    expect(secondClaim!.id, newer.record.id);
    expect(none, isNull);
    expect(transport.packets, isEmpty);
  });

  test('should fence and drain close while discarding a late matching ACK without closing borrowed ports', () async {
    // Given a transport held after dispatch and borrowed queue/scheduler/connection ports.
    final queue = await f.openQueue();
    final source = await _saveRegistered(queue, registeredTestRequest(), f.now);
    final transport = _RegisteredTransport(registeredTestTarget());
    final entered = Completer<void>();
    final held = Completer<SubmissionAcknowledgement>();
    transport.onSubmit = (_) { entered.complete(); return held.future; };
    final handoffs = service(queue, transport);
    await handoffs.enqueueRegistered(source.request.id, transport.connection);
    final pending = handoffs.processNext(networkAllowed: true);
    await submissionEntered(entered);
    // When close retires accepted work before the held remote response settles.
    final closing = handoffs.close();
    final result = await pending;
    await closing;
    held.complete(_ack(source.request));
    // Then unknown remains durable, later calls fail, and the independently owned queue stays usable.
    expect(result.outcome, RegisteredMaterialHandoffRunOutcome.outcomeUnknown);
    expect((await queue.findHandoffForSource(source.request.id))!.acknowledgement, isNull);
    expect(await queue.find(source.request.id), source);
    await expectLater(handoffs.list(), throwsStateError);
    await handoffs.close();
  });

  test('should leave durable sending intact and propagate local ACK-save failure', () async {
    // Given an actual matching response but a controlled local failure at the ACK write boundary.
    final queue = await f.openQueue();
    final source = await _saveRegistered(queue, registeredTestRequest(), f.now);
    final transport = _RegisteredTransport(registeredTestTarget());
    final store = _HandoffStore(queue)..failAcceptance = true;
    final handoffs = service(queue, transport, store: store);
    await handoffs.enqueueRegistered(source.request.id, transport.connection);
    // When the ACK persistence operation fails after the actual transport succeeds.
    await expectLater(handoffs.processNext(networkAllowed: true), throwsStateError);
    final saved = await queue.findHandoffForSource(source.request.id);
    // Then no fallback accepts or resends, and the existing sending marker retains uncertainty.
    expect(saved!.state, RegisteredMaterialHandoffState.sending);
    expect(saved.acknowledgement, isNull);
    expect((await handoffs.processNext(networkAllowed: true)).outcome, RegisteredMaterialHandoffRunOutcome.noWork);
    expect(transport.packets.length, 1);
    expect(await queue.find(source.request.id), source);
  });

  test('should discard a late ACK after an operation timeout without replay or rescheduling', () async {
    // Given a noncooperative transport whose pending response exceeds the bounded operation deadline.
    final queue = await f.openQueue();
    final source = await _saveRegistered(queue, registeredTestRequest(), f.now);
    final transport = _RegisteredTransport(registeredTestTarget());
    final held = Completer<SubmissionAcknowledgement>();
    transport.onSubmit = (_) => held.future;
    final handoffs = service(queue, transport, operationTimeout: const Duration(milliseconds: 20));
    await handoffs.enqueueRegistered(source.request.id, transport.connection);
    // When the deadline expires and a matching ACK subsequently arrives.
    final result = await handoffs.processNext(networkAllowed: true);
    held.complete(_ack(source.request));
    // Then only explicit reconciliation can authorize another identical POST.
    expect(result.outcome, RegisteredMaterialHandoffRunOutcome.outcomeUnknown);
    expect((await queue.findHandoffForSource(source.request.id))!.acknowledgement, isNull);
    expect((await handoffs.processNext(networkAllowed: true)).outcome, RegisteredMaterialHandoffRunOutcome.noWork);
    expect(transport.packets.length, 1);
    expect(f.scheduler.calls, 1);
  });

  test('should preserve durable creation when scheduler wake fails safely', () async {
    // Given a saved source and an unavailable borrowed scheduler.
    final queue = await f.openQueue();
    final source = await _saveRegistered(queue, registeredTestRequest(), f.now);
    final transport = _RegisteredTransport(registeredTestTarget());
    final handoffs = service(queue, transport);
    f.scheduler.fail = true;
    // When explicit handoff creation commits before requesting the wake.
    final result = await handoffs.enqueueRegistered(source.request.id, transport.connection);
    // Then scheduling failure is separate from the durable pending packet and invokes no transport.
    expect(result.schedulingFailed, isTrue);
    expect(await queue.findHandoffForSource(source.request.id), result.record);
    expect(transport.packets, isEmpty);
  });

  test('should join handoff state into one source status without changing original registration or legacy actions', () async {
    // Given one Registered source and an explicitly composed optional handoff capability.
    final queue = await f.openQueue();
    final source = await _saveRegistered(queue, registeredTestRequest(), f.now);
    final transport = _RegisteredTransport(registeredTestTarget());
    final handoffs = service(queue, transport);
    final primary = SubmissionService(queue: queue, materials: f.materials,
      storageAdapters: {'drive': f.storage}, transports: {'server': f.transport},
      scheduler: f.scheduler, registeredMaterialHandoffs: handoffs, now: () => f.now);
    f.services.add(primary);
    final absent = await primary.findTransferStatus(source.request.id, observedAt: f.now);
    await handoffs.enqueueRegistered(source.request.id, transport.connection);
    // When status is queried before dispatch, during its lease, after expiry and after explicit replay/ACK.
    final pending = await primary.findTransferStatus(source.request.id, observedAt: f.now);
    final claim = await queue.claimNextHandoff(now: f.now, leaseToken: 'owner', leaseDuration: const Duration(minutes: 5));
    final running = await primary.findTransferStatus(source.request.id, observedAt: f.now);
    f.now = f.now.add(const Duration(minutes: 6));
    final expired = await primary.findTransferStatus(source.request.id, observedAt: f.now);
    await handoffs.processNext(networkAllowed: true);
    final unknown = await primary.findTransferStatus(source.request.id, observedAt: f.now);
    await handoffs.reconcile(source.request.id);
    await handoffs.processNext(networkAllowed: true);
    final accepted = await primary.listTransferStatuses(observedAt: f.now);
    // Then registration/upload remain source facts while only the genuine handoff ACK completes submission.
    expect(absent!.submission.state, SubmissionTransferOperationState.notRequired);
    expect(absent.acknowledgement, isNull);
    expect(pending!.submission.state, SubmissionTransferOperationState.queued);
    expect(running!.submission.state, SubmissionTransferOperationState.running);
    expect(running.submission.leaseExpiresAt, claim!.leaseExpiresAt);
    expect(expired!.submission.state, SubmissionTransferOperationState.outcomeUnknown);
    expect(unknown!.submission.state, SubmissionTransferOperationState.outcomeUnknown);
    expect(accepted.length, 1);
    expect(accepted.single.registration!.state, SubmissionTransferOperationState.succeeded);
    expect(accepted.single.upload.state, SubmissionTransferOperationState.succeeded);
    expect(accepted.single.submission.state, SubmissionTransferOperationState.succeeded);
    expect(accepted.single.acknowledgement, _ack(source.request));
    expect(accepted.single.actions, isEmpty);
    expect((await queue.find(source.request.id))!.acknowledgement, isNull);
    expect(() => SubmissionTransferStatus.fromRecord(
      _registeredRecord(registeredTestRequest(id: 'other'), f.now), observedAt: f.now,
      handoff: pending.studioHandoff), throwsArgumentError);
  });

  test('should keep legacy custom compositions capability-null and registered source submission notRequired', () async {
    // Given an existing custom service composition with no optional handoff port.
    final queue = await f.openQueue();
    final source = await _saveRegistered(queue, registeredTestRequest(mediaTypes: const []), f.now);
    final primary = f.service(queue);
    // When that unchanged composition queries its original source.
    final status = await primary.findTransferStatus(source.request.id, observedAt: f.now);
    // Then no automatic capability, submission requirement or ACK is manufactured.
    expect(primary.registeredMaterialHandoffs, isNull);
    expect(status!.studioHandoff, isNull);
    expect(status.submission.state, SubmissionTransferOperationState.notRequired);
    expect(status.acknowledgement, isNull);
  });

  test('should process original queue before handoffs under the same runner operation budget', () async {
    // Given an ordinary queue job, a Registered source and a separate pending Studio handoff.
    final queue = await f.openQueue();
    final source = await _saveRegistered(queue, registeredTestRequest(), f.now);
    final ordinary = await f.request(id: 'ordinary', subjectId: 'ordinary', withMaterials: false);
    await queue.enqueue(ordinary);
    final transport = _RegisteredTransport(registeredTestTarget());
    final lake = _NoTklCalls();
    final handoffs = service(queue, transport);
    await handoffs.enqueueRegistered(source.request.id, transport.connection);
    final primary = SubmissionService(queue: queue, materials: f.materials,
      storageAdapters: const {}, transports: {'server': f.transport}, scheduler: f.scheduler,
      tklClients: {'lake': lake},
      registeredMaterialHandoffs: handoffs, now: () => f.now);
    f.services.add(primary);
    final resources = SubmissionBackgroundResources(service: primary, queue: queue, close: () async {});
    final lifetime = SubmissionRunLifetime(id: 'runner');
    // When the bounded runner gets one operation, then a separate bounded continuation.
    final first = await SubmissionBackgroundRunner(resources: resources, lifetime: lifetime,
      now: () => f.now, maxOperations: 1).run(networkAllowed: true);
    expect(transport.packets, isEmpty);
    final second = await SubmissionBackgroundRunner(resources: resources, lifetime: lifetime,
      now: () => f.now, maxOperations: 4).run(networkAllowed: true);
    // Then original acceptance precedes handoff work and the same budget accounts for both queue scans.
    expect(first.operations, 1);
    expect(first.outcome, SubmissionBackgroundOutcome.pending);
    expect(first.nextDelay, Duration.zero);
    expect((await queue.find(ordinary.id))!.state, SubmissionState.submitted);
    expect(second.operations, 4);
    expect(second.outcome, SubmissionBackgroundOutcome.drained);
    expect(transport.packets.length, 1);
    expect(f.storage.prepares, 0);
    expect(f.storage.uploads, 0);
    expect(lake.calls, 0);
  });

  test('should schedule sending expiry observation but never schedule unknown handoff replay', () async {
    // Given a sending handoff and a primary runner sharing its real queue/capability.
    final queue = await f.openQueue();
    final source = await _saveRegistered(queue, registeredTestRequest(), f.now);
    final transport = _RegisteredTransport(registeredTestTarget());
    final handoffs = service(queue, transport);
    await handoffs.enqueueRegistered(source.request.id, transport.connection);
    await queue.claimNextHandoff(now: f.now, leaseToken: 'lost', leaseDuration: const Duration(minutes: 5));
    final primary = SubmissionService(queue: queue, materials: f.materials,
      storageAdapters: const {}, transports: const {}, scheduler: f.scheduler,
      registeredMaterialHandoffs: handoffs, now: () => f.now);
    f.services.add(primary);
    final lifetime = SubmissionRunLifetime(id: 'observation');
    final resources = SubmissionBackgroundResources(service: primary, queue: queue, close: () async {});
    final runner = SubmissionBackgroundRunner(resources: resources, lifetime: lifetime, now: () => f.now);
    // When the same runner observes a live lease, then its expiry on a later invocation.
    final live = await runner.run(networkAllowed: true);
    f.now = f.now.add(const Duration(minutes: 6));
    final expired = await runner.run(networkAllowed: true);
    // Then the only due time observes uncertainty; unknown itself generates no wake or send.
    expect(live.outcome, SubmissionBackgroundOutcome.pending);
    expect(live.nextDelay, const Duration(minutes: 5));
    expect(expired.outcome, SubmissionBackgroundOutcome.drained);
    expect(expired.nextDelay, isNull);
    expect(transport.packets, isEmpty);
    expect(f.scheduler.calls, 1);
  });

  test('should strictly decode the versioned handoff and reject state identity lease or unknown fields', () async {
    // Given a durable valid pending handoff with full original source and Registered snapshot.
    final queue = await f.openQueue();
    final source = await _saveRegistered(queue, registeredTestRequest(), f.now);
    final transport = _RegisteredTransport(registeredTestTarget());
    final handoffs = service(queue, transport);
    final created = (await handoffs.enqueueRegistered(source.request.id, transport.connection)).record;
    final json = RegisteredMaterialSubmissionCodec.handoffToJson(created);
    final mutations = <void Function(Map<String, Object?>)>[
      (v) => v['version'] = 2,
      (v) => v['observedAt'] = null,
      (v) => v.remove('sourceCheckpointUpdatedAt'),
      (v) => v['leaseToken'] = 'fake',
      (v) => v['state'] = 'sending',
      (v) => v['state'] = 'accepted',
      (v) => (v['registeredSnapshot'] as Map)['material_ref'] = 'changed',
      (v) => (v['packet'] as Map)['requestId'] = 'changed',
      (v) => v['acknowledgement'] = SubmissionCodec.acknowledgementToJson(_ack(source.request)),
    ];
    // When closed/versioned persistence decoding observes each independent invalid relationship.
    for (final mutate in mutations) {
      final bad = registeredJsonCopy(json);
      mutate(bad);
      // Then no decoder repairs or invents a lease, timestamp, identity or ACK.
      expect(() => RegisteredMaterialSubmissionCodec.handoffFromJson(bad), throwsFormatException);
    }
    expect(RegisteredMaterialSubmissionCodec.handoffFromJson(json), created);
  });
}

TklMaterialDeliverySnapshot _snapshot(SubmissionRequest request) => TklMaterialDeliverySnapshot(
  deliveryRef: 'actual-saved-delivery/${request.id}', requestId: request.id, revision: 7,
  destinationId: 'server-selected', destinationLabel: 'Registered destination',
  state: TklMaterialDeliveryState.registered, materialRef: '  urn:tkl:Material:${request.id}  ',
  resources: [for (final m in request.materials) TklOriginalTransferProgress(
    resourceId: m.key, mediaType: m.original.mediaType, byteLength: m.original.byteLength,
    state: TklOriginalTransferState.uploaded)],
);

SubmissionRecord _registeredRecord(SubmissionRequest request, DateTime now) => SubmissionRecord(
  request: request, state: SubmissionState.materialRegistered, claimCount: 1,
  updatedAt: now, tklProgress: _snapshot(request),
);

Future<SubmissionRecord> _saveRegistered(SqliteSubmissionQueueStore queue,
  SubmissionRequest request, DateTime now,
) async {
  await queue.enqueue(request);
  await queue.claimNext(now: now, leaseToken: 'registration${request.id}',
    leaseDuration: const Duration(minutes: 5));
  await queue.saveTklProgress(id: request.id, leaseToken: 'registration${request.id}',
    progress: _snapshot(request), now: now);
  return queue.completeMaterialRegistration(id: request.id,
    leaseToken: 'registration${request.id}', now: now);
}

SubmissionAcknowledgement _ack(SubmissionRequest request) => SubmissionAcknowledgement(
  requestId: request.id, subjectId: request.subjectId,
  serverId: 'controlled-server/${request.id}', receivedAt: DateTime.utc(2026, 10, 26, 3),
  extensions: const {'response': [null, '実際の制御応答']},
);

final class _RegisteredTransport implements RegisteredMaterialSubmissionTransport {
  _RegisteredTransport(this.connection);
  @override
  final HttpSubmissionConnection connection;
  final List<RegisteredMaterialSubmissionPacket> packets = [];
  Future<SubmissionAcknowledgement> Function(RegisteredMaterialSubmissionPacket)? onSubmit;
  @override
  Future<SubmissionAcknowledgement> submitRegisteredMaterial(RegisteredMaterialSubmissionPacket packet) {
    packets.add(packet);
    return Future.sync(() => onSubmit?.call(packet) ?? _ack(packet.sourceRequest));
  }
}

/// Fault injection only around typed handoff writes; persistence remains native.
final class _HandoffStore implements RegisteredMaterialHandoffStore {
  _HandoffStore(this.inner);
  final RegisteredMaterialHandoffStore inner;
  int calls = 0;
  bool failAcceptance = false;
  Future<void> Function()? afterClaim;
  @override
  Future<RegisteredMaterialHandoffRecord?> findHandoffForSource(String sourceRequestId) {
    calls++;
    return inner.findHandoffForSource(sourceRequestId);
  }
  @override
  Future<List<RegisteredMaterialHandoffRecord>> listHandoffs() {
    calls++;
    return inner.listHandoffs();
  }
  @override
  Future<RegisteredMaterialHandoffRecord> createHandoff({required String id,
    required SubmissionRecord source, required HttpSubmissionConnection target,
    required RegisteredMaterialSubmissionPacket packet, required DateTime now}) {
    calls++;
    return inner.createHandoff(id: id, source: source, target: target, packet: packet, now: now);
  }
  @override
  Future<RegisteredMaterialHandoffRecord?> claimNextHandoff({required DateTime now,
    required String leaseToken, required Duration leaseDuration}) async {
    calls++;
    final result = await inner.claimNextHandoff(now: now, leaseToken: leaseToken, leaseDuration: leaseDuration);
    await afterClaim?.call();
    return result;
  }
  @override
  Future<RegisteredMaterialHandoffRecord> finishHandoff({required String id,
    required String leaseToken, required DateTime now, required RegisteredMaterialHandoffState state,
    SubmissionAcknowledgement? acknowledgement, RegisteredMaterialHandoffFailure? failure}) async {
    calls++;
    if (failAcceptance && state == RegisteredMaterialHandoffState.accepted) {
      throw StateError('Controlled local ACK save failure');
    }
    return inner.finishHandoff(id: id, leaseToken: leaseToken, now: now,
      state: state, acknowledgement: acknowledgement, failure: failure);
  }
  @override
  Future<RegisteredMaterialHandoffRecord> reconcileHandoff({required String sourceRequestId, required DateTime now}) {
    calls++;
    return inner.reconcileHandoff(sourceRequestId: sourceRequestId, now: now);
  }
}

/// An explicit forbidden-call witness for the independently retained TKL route.
final class _NoTklCalls implements TklMaterialDeliveryClient {
  int calls = 0;
  Future<T> _unexpected<T>() {
    calls++;
    return Future<T>.error(StateError('A Registered Studio handoff must not call TKL'));
  }
  @override
  Future<TklMaterialDeliveryDestination> getDestination() => _unexpected();
  @override
  Future<TklMaterialDeliverySnapshot> prepare(TklMaterialDeliveryRequest request) => _unexpected();
  @override
  Future<TklMaterialDeliverySnapshot?> findForRequest(String requestId) => _unexpected();
  @override
  Future<TklMaterialDeliverySnapshot> get(String deliveryRef) => _unexpected();
  @override
  Future<TklMaterialDeliverySnapshot> uploadOriginal({required String deliveryRef,
    required String resourceId, required String mediaType, required Uint8List content}) => _unexpected();
  @override
  Future<TklMaterialDeliverySnapshot> finalize(String deliveryRef) => _unexpected();
}
