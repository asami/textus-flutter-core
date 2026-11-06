import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';
import 'package:textus_flutter_core/src/submission/tkl_material_delivery_codec.dart';

import '../support/submission_fixture.dart';
import 'registered_material_submission_test.dart'
    show registeredTestRequest, registeredTestTarget;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SubmissionFixture fixture;
  final handoffServices = <RegisteredMaterialHandoffService>[];

  setUp(() async {
    fixture = await SubmissionFixture.create();
    fixture.now = DateTime.utc(2026, 10, 26, 3);
  });
  tearDown(() async {
    for (final service in handoffServices) {
      await service.close();
    }
    handoffServices.clear();
    await fixture.dispose();
  });

  SubmissionService ordinaryService(
    SubmissionQueueStore queue, {
    bool requiresAuthentication = false,
    SubmissionAuthenticationContext? context,
    LocalCaptureStore? originals,
    TklMaterialDeliveryClient? tkl,
  }) {
    final service = SubmissionService(
      queue: queue,
      materials: originals ?? fixture.materials,
      storageAdapters: {'drive': fixture.storage},
      transports: {'server': fixture.transport},
      scheduler: fixture.scheduler,
      referenceAccessPolicy: fixture.referenceAccess,
      tklClients: {'lake': ?tkl},
      requiresAuthentication: requiresAuthentication,
      authenticationContext: context,
      now: () => fixture.now,
    );
    fixture.services.add(service);
    return service;
  }

  RegisteredMaterialHandoffService handoffService(
    SubmissionQueueStore queue,
    RegisteredMaterialHandoffStore store,
    _RegisteredTransport transport, {
    bool requiresAuthentication = false,
    SubmissionAuthenticationContext? context,
  }) {
    final service = RegisteredMaterialHandoffService(
      queue: queue,
      store: store,
      transports: {'studio': transport},
      scheduler: fixture.scheduler,
      requiresAuthentication: requiresAuthentication,
      authenticationContext: context,
      now: () => fixture.now,
    );
    handoffServices.add(service);
    return service;
  }

  final denials = <({String name, bool required, bool bound, String? context})>[
    (
      name: 'required bound without context',
      required: true,
      bound: true,
      context: null,
    ),
    (
      name: 'required legacy without context',
      required: true,
      bound: false,
      context: null,
    ),
    (
      name: 'default bound without context',
      required: false,
      bound: true,
      context: null,
    ),
    (
      name: 'default legacy with context',
      required: false,
      bound: false,
      context: 'current',
    ),
    (
      name: 'required legacy with context',
      required: true,
      bound: false,
      context: 'current',
    ),
    for (final required in [false, true])
      for (final context in ['account', 'profile', 'base', 'false', 'throw'])
        (
          name: '$context context required=$required',
          required: required,
          bound: true,
          context: context,
        ),
  ];

  group('ordinary dispatch admission', () {
    for (final denial in denials) {
      test('${denial.name} persists safe denial before all ports', () async {
        // Given a real queue row and observable original, provider and policy ports.
        var queue = await fixture.openQueue();
        final request = _withBinding(
          await fixture.request(),
          denial.bound ? _binding() : null,
        );
        await queue.enqueue(request);
        final originals = ControlledMaterials(fixture.materials);
        var callbacks = 0;
        final context = _denialContext(denial.context, () => callbacks++);
        final service = ordinaryService(
          queue,
          requiresAuthentication: denial.required,
          context: context,
          originals: originals,
        );
        // When online processing claims the actual immutable request.
        final result = await service.processNext(networkAllowed: true);
        await service.close();
        await queue.close();
        queue = await fixture.openQueue();
        // Then denial survives reopen without reading bytes or consulting any remote port.
        final saved = (await queue.find(request.id))!;
        expect(result.outcome, SubmissionRunOutcome.failed);
        expect(result.record, saved);
        expect(saved.request, request);
        expect(saved.state, SubmissionState.submissionFailed);
        expect(saved.lastFailure!.stage, SubmissionFailureStage.configuration);
        expect(saved.lastFailure!.code, 'authenticationRequired');
        expect(saved.lastFailure!.message, _authenticationMessage);
        expect(saved.lastFailure!.retryable, isFalse);
        expect(saved.nextAttemptAt, isNull);
        expect(saved.leaseToken, isNull);
        expect(saved.reservations, isEmpty);
        expect(saved.receipts, isEmpty);
        expect(saved.transportCheckpoint, isNull);
        expect(saved.acknowledgement, isNull);
        expect(
          callbacks,
          denial.context == 'false' || denial.context == 'throw' ? 1 : 0,
        );
        expect(originals.reads, 0);
        expect(fixture.storage.prepares, 0);
        expect(fixture.storage.uploads, 0);
        expect(fixture.referenceAccess.calls, 0);
        expect(fixture.transport.submits, 0);
        expect(fixture.scheduler.calls, 0);
      });
    }

    for (final bound in [false, true]) {
      test(
        'required TKL ${bound ? 'bound' : 'legacy'} denies before client or original access',
        () async {
          // Given real TKL intent whose processing composition has no accepted context.
          final queue = await fixture.openQueue();
          final request = _withBinding(
            await fixture.request(),
            bound ? _binding() : null,
            tkl: true,
          );
          await queue.enqueue(request);
          final originals = ControlledMaterials(fixture.materials);
          final tkl = _NoTklCalls();
          final service = ordinaryService(
            queue,
            requiresAuthentication: true,
            originals: originals,
            tkl: tkl,
          );
          // When processing reaches claim admission rather than hashing or provider resolution.
          final result = await service.processNext(networkAllowed: true);
          // Then fail-closed composition prevents all downstream work and retains TKL intent.
          expect(result.outcome, SubmissionRunOutcome.failed);
          expect(result.record!.lastFailure!.code, 'authenticationRequired');
          expect(result.record!.request, request);
          expect(result.record!.tklContentDigests, isEmpty);
          expect(result.record!.tklProgress, isNull);
          expect(originals.reads, 0);
          expect(tkl.calls, 0);
          expect(fixture.referenceAccess.calls, 0);
          expect(fixture.transport.submits, 0);
          expect(fixture.storage.prepares, 0);
        },
      );
    }

    for (final bound in [false, true]) {
      test(
        '${bound ? 'required exact current' : 'default legacy'} keeps the complete ordinary path',
        () async {
          // Given retained real originals and either exact participant intent or an old unbound row.
          final queue = await fixture.openQueue();
          final request = _withBinding(
            await fixture.request(),
            bound ? _binding() : null,
          );
          await queue.enqueue(request);
          final originals = ControlledMaterials(fixture.materials);
          final service = ordinaryService(
            queue,
            requiresAuthentication: bound,
            context: bound ? _context() : null,
            originals: originals,
          );
          // When the existing five bounded stages prepare, upload and accept the request.
          final outcomes = <SubmissionRunOutcome>[];
          for (var i = 0; i < 5; i++) {
            outcomes.add(
              (await service.processNext(networkAllowed: true)).outcome,
            );
          }
          final saved = (await queue.find(request.id))!;
          // Then IDs, intent and uploaded bytes survive without binding becoming a wire owner.
          expect(service.requiresAuthentication, bound);
          expect(outcomes, [
            SubmissionRunOutcome.progress,
            SubmissionRunOutcome.progress,
            SubmissionRunOutcome.progress,
            SubmissionRunOutcome.progress,
            SubmissionRunOutcome.submitted,
          ]);
          expect(saved.request, request);
          expect(
            saved.request.authenticationBinding,
            bound ? _binding() : null,
          );
          expect(saved.reservations.keys, ['photo', 'audio']);
          expect(saved.receipts.keys, ['photo', 'audio']);
          expect(saved.transportCheckpoint, isNull);
          expect(
            saved.acknowledgement,
            fixture.transport.acknowledgement(request),
          );
          expect(originals.reads, 2);
          expect(fixture.storage.prepares, 2);
          expect(fixture.storage.uploadedBytes, [
            SubmissionFixture.photoBytes,
            SubmissionFixture.audioBytes,
          ]);
          expect(fixture.transport.submits, 1);
          expect(fixture.transport.packets.single.request, request);
          final wire = SubmissionCodec.packetToJson(
            fixture.transport.packets.single,
          );
          expect(wire.containsKey('authenticationBinding'), isFalse);
          expect(wire.containsKey('userAccountId'), isFalse);
          expect(wire['requestId'], request.id);
        },
      );
    }

    for (final offline in [false, true]) {
      test(
        '${offline ? 'offline' : 'caller false'} returns before claims and auth callbacks',
        () async {
          // Given bound pending intent and independently observable borrowed ports.
          final queue = await fixture.openQueue();
          final request = _withBinding(await fixture.request(), _binding());
          final before = await queue.enqueue(request);
          final observed = ControlledQueue(queue);
          final originals = ControlledMaterials(fixture.materials);
          var callbacks = 0;
          final service = ordinaryService(
            observed,
            requiresAuthentication: true,
            originals: originals,
            context: _context(
              isCurrent: () {
                callbacks++;
                throw StateError('private context');
              },
            ),
          );
          // When processing receives an offline or withdrawn caller gate.
          final result = await service.processNext(
            networkAllowed: !offline,
            isRunCurrent: () => false,
          );
          // Then no selection, credential observation, original access or send occurs.
          expect(
            result.outcome,
            offline
                ? SubmissionRunOutcome.offline
                : SubmissionRunOutcome.cancelled,
          );
          expect(observed.calls, 0);
          expect(callbacks, 0);
          expect(originals.reads, 0);
          expect(fixture.storage.prepares, 0);
          expect(fixture.transport.submits, 0);
          expect(fixture.referenceAccess.calls, 0);
          expect(await queue.find(request.id), before);
        },
      );
    }

    for (final retireCaller in [false, true]) {
      test(
        'held claim ${retireCaller ? 'caller' : 'context'} retirement does not send',
        () async {
          // Given a real claim held before admission, with independent caller and context lifetimes.
          final queue = await fixture.openQueue();
          final request = _withBinding(await fixture.request(), _binding());
          await queue.enqueue(request);
          final entered = Completer<void>();
          final release = Completer<void>();
          final observed = ControlledQueue(queue)
            ..after = (name) async {
              if (name == 'claimNext') {
                entered.complete();
                await release.future;
              }
            };
          var current = true;
          var caller = true;
          final service = ordinaryService(
            observed,
            requiresAuthentication: true,
            context: _context(isCurrent: () => current),
          );
          final pending = service.processNext(
            networkAllowed: true,
            isRunCurrent: () => caller,
          );
          await entered.future;
          // When a selected lifetime retires before the claimed row is returned.
          if (retireCaller) {
            caller = false;
          } else {
            current = false;
          }
          release.complete();
          final result = await pending;
          // Then caller cancellation releases, while initial context denial persists a safe failure.
          expect(
            result.outcome,
            retireCaller
                ? SubmissionRunOutcome.cancelled
                : SubmissionRunOutcome.failed,
          );
          expect(result.record!.request, request);
          expect(result.record!.acknowledgement, isNull);
          expect(result.record!.leaseToken, isNull);
          expect(
            result.record!.lastFailure?.code,
            retireCaller ? null : 'authenticationRequired',
          );
          expect(fixture.storage.prepares, 0);
          expect(fixture.transport.submits, 0);
        },
      );
    }

    for (final retireCaller in [false, true]) {
      test(
        'held original ${retireCaller ? 'caller' : 'context'} retirement preserves reservations',
        () async {
          // Given admitted A with saved reservations and an original reader held before upload.
          final queue = await fixture.openQueue();
          final request = _withBinding(await fixture.request(), _binding());
          await queue.enqueue(request);
          final originals = ControlledMaterials(fixture.materials);
          var current = true;
          var caller = true;
          final service = ordinaryService(
            queue,
            requiresAuthentication: true,
            originals: originals,
            context: _context(isCurrent: () => current),
          );
          await service.processNext(networkAllowed: true);
          await service.processNext(networkAllowed: true);
          final before = (await queue.find(request.id))!;
          final entered = Completer<void>();
          final release = Completer<void>();
          originals.beforeRead = () async {
            entered.complete();
            await release.future;
          };
          final pending = service.processNext(
            networkAllowed: true,
            isRunCurrent: () => caller,
          );
          await entered.future;
          // When the caller or bound context retires during the actual original await.
          if (retireCaller) {
            caller = false;
          } else {
            current = false;
          }
          release.complete();
          final result = await pending;
          // Then returned bytes cannot start upload or alter accepted intent/checkpoints.
          expect(result.outcome, SubmissionRunOutcome.cancelled);
          expect(result.record!.request, request);
          expect(result.record!.reservations, before.reservations);
          expect(result.record!.receipts, isEmpty);
          expect(result.record!.acknowledgement, isNull);
          expect(fixture.storage.uploads, 0);
          expect(fixture.transport.submits, 0);
        },
      );
    }

    for (final retirement in [
      'caller',
      'false',
      'throw',
      'account',
      'profile',
      'base',
    ]) {
      test(
        'held ordinary transport $retirement discards ACK and reconciles only A',
        () async {
          // Given an admitted A and a held transport after the durable dispatch checkpoint.
          final queue = await fixture.openQueue();
          final request = _withBinding(
            await fixture.request(withMaterials: false),
            _binding(),
          );
          await queue.enqueue(request);
          var current = true;
          var caller = true;
          var activeBinding = _binding();
          final entered = Completer<void>();
          final held = Completer<SubmissionAcknowledgement>();
          fixture.transport.onSubmit = (_) {
            entered.complete();
            return held.future;
          };
          final a = ordinaryService(
            queue,
            requiresAuthentication: true,
            context: _context(
              isCurrent: () {
                if (!current && retirement == 'throw') {
                  throw StateError('private retirement');
                }
                return current && activeBinding == _binding();
              },
            ),
          );
          final pending = a.processNext(
            networkAllowed: true,
            isRunCurrent: () => caller,
          );
          await entered.future;
          final dispatched = (await queue.find(request.id))!
              .transportCheckpoint;
          // When the caller or authentication lifetime retires before a matching late ACK.
          switch (retirement) {
            case 'caller':
              caller = false;
            case 'account':
              activeBinding = _binding(account: 'B');
            case 'profile':
              activeBinding = _binding(profile: 'other');
            case 'base':
              activeBinding = _binding(base: 'https://other.example/account/');
            default:
              current = false;
          }
          held.complete(fixture.transport.acknowledgement(request));
          final cancelled = await pending;
          // Then the old dispatch remains uncertain and no ACK or new actor is published.
          expect(cancelled.outcome, SubmissionRunOutcome.cancelled);
          expect(cancelled.record!.transportCheckpoint, dispatched);
          expect(dispatched, isNotNull);
          expect(cancelled.record!.acknowledgement, isNull);
          expect(cancelled.record!.request, request);
          await a.close();
          final b = ordinaryService(
            queue,
            requiresAuthentication: true,
            context: _context(binding: _binding(account: 'B')),
          );
          // When B tries the released row, then fresh A explicitly retries the same intent.
          final denied = await b.processNext(networkAllowed: true);
          await b.close();
          fixture.transport.onSubmit = null;
          final freshA = ordinaryService(
            queue,
            requiresAuthentication: true,
            context: _context(),
          );
          await freshA.retry(request.id);
          final accepted = await freshA.processNext(networkAllowed: true);
          // Then B's denial keeps uncertainty and only A resends the same packet/key.
          expect(denied.record!.lastFailure!.code, 'authenticationRequired');
          expect(denied.record!.transportCheckpoint, dispatched);
          expect(accepted.outcome, SubmissionRunOutcome.submitted);
          expect(accepted.record!.request, request);
          expect(accepted.record!.transportCheckpoint, isNull);
          expect(fixture.transport.submits, 2);
          expect(
            SubmissionCodec.packetToJson(fixture.transport.packets[0]),
            SubmissionCodec.packetToJson(fixture.transport.packets[1]),
          );
        },
      );
    }

    test(
      'ordinary retired transport cannot publish after lease expiry',
      () async {
        // Given an admitted A held beyond the real SQLite lease ownership boundary.
        final queue = await fixture.openQueue();
        final request = _withBinding(
          await fixture.request(withMaterials: false),
          _binding(),
        );
        await queue.enqueue(request);
        var current = true;
        final entered = Completer<void>();
        final held = Completer<SubmissionAcknowledgement>();
        fixture.transport.onSubmit = (_) {
          entered.complete();
          return held.future;
        };
        final service = ordinaryService(
          queue,
          context: _context(isCurrent: () => current),
        );
        final pending = service.processNext(networkAllowed: true);
        await entered.future;
        // When the lease expires and A retires before the late ACK arrives.
        fixture.now = fixture.now.add(const Duration(minutes: 6));
        current = false;
        held.complete(fixture.transport.acknowledgement(request));
        final result = await pending;
        // Then cancellation cannot release another owner's lease or accept the ACK.
        expect(result.outcome, SubmissionRunOutcome.leaseLost);
        expect(result.record!.request, request);
        expect(result.record!.acknowledgement, isNull);
        expect(result.record!.transportCheckpoint, isNotNull);
        expect(fixture.transport.submits, 1);
      },
    );

    test('ordinary local intent and inspection ignore a failing context', () async {
      // Given an explicit required composition with a context that must remain unobserved locally.
      final queue = await fixture.openQueue();
      final originals = ControlledMaterials(fixture.materials);
      final request = _withBinding(
        await fixture.request(withMaterials: false),
        _binding(),
      );
      var callbacks = 0;
      final service = ordinaryService(
        queue,
        requiresAuthentication: true,
        originals: originals,
        context: _context(
          isCurrent: () {
            callbacks++;
            throw StateError('local only');
          },
        ),
      );
      // When Commit, read/list, retry and wake operate on durable local intent.
      final committed = await service.commit(request);
      final found = await service.find(request.id);
      final subject = await service.findForSubject(
        request.kind,
        request.subjectId,
      );
      final listed = await service.list();
      final retried = await service.retry(request.id);
      final woken = await service.requestRun(request.id);
      await service.close();
      // Then local identity remains and closing leaves independently owned persistence usable.
      expect(service.requiresAuthentication, isTrue);
      expect(found, committed.record);
      expect(subject, committed.record);
      expect(listed, [committed.record]);
      expect(retried.record, committed.record);
      expect(woken.record, committed.record);
      expect(await queue.find(request.id), committed.record);
      expect(callbacks, 0);
      expect(originals.reads, 0);
      expect(fixture.scheduler.calls, 3);
      expect(fixture.transport.submits, 0);
      expect(fixture.storage.prepares, 0);
      expect(fixture.referenceAccess.calls, 0);
      await expectLater(service.list(), throwsStateError);
    });

    test('ordinary close drains accepted reads and leaves the borrowed queue usable', () async {
      // Given durable A intent and an accepted strict find held in a real borrowed queue.
      final queue = await fixture.openQueue();
      final request = _withBinding(
        await fixture.request(withMaterials: false),
        _binding(),
      );
      final before = await queue.enqueue(request);
      final entered = Completer<void>();
      final release = Completer<void>();
      final observed = ControlledQueue(queue)
        ..after = (name) async {
          if (name == 'find') {
            entered.complete();
            await release.future;
          }
        };
      var callbacks = 0;
      final service = ordinaryService(
        observed,
        requiresAuthentication: true,
        context: _context(
          isCurrent: () {
            callbacks++;
            return false;
          },
        ),
      );
      final reading = service.find(request.id);
      await entered.future;
      // When close immediately rejects new work and waits for the accepted borrowed read.
      var drained = false;
      final closing = service.close().then((_) {
        drained = true;
      });
      expect(drained, isFalse);
      release.complete();
      final found = await reading;
      await closing;
      // Then the existing strict read completes, A remains durable and no auth/adapter work runs.
      expect(found, before);
      expect(drained, isTrue);
      expect(await queue.find(request.id), before);
      expect(callbacks, 0);
      expect(fixture.transport.submits, 0);
      await expectLater(service.find(request.id), throwsStateError);
    });
  });

  group('Registered-source dispatch admission', () {
    for (final denial in denials) {
      test(
        '${denial.name} fails before target lookup and retains source',
        () async {
          // Given a real saved Registered source and one frozen independent handoff.
          var queue = await fixture.openQueue();
          final request = _withBinding(
            registeredTestRequest(),
            denial.bound ? _binding() : null,
          );
          final source = await _saveRegistered(queue, request, fixture.now);
          final transport = _RegisteredTransport();
          var callbacks = 0;
          final service = handoffService(
            queue,
            queue,
            transport,
            requiresAuthentication: denial.required,
            context: _denialContext(denial.context, () => callbacks++),
          );
          final before = (await service.enqueueRegistered(
            request.id,
            registeredTestTarget(),
          )).record;
          // When the driver claims the durable handoff and applies the local actor matrix.
          final result = await service.processNext(networkAllowed: true);
          await service.close();
          await queue.close();
          queue = await fixture.openQueue();
          // Then the exact safe failed row survives reopen with no provider or source mutation.
          final saved = (await queue.findHandoffForSource(request.id))!;
          expect(result.outcome, RegisteredMaterialHandoffRunOutcome.failed);
          expect(result.record, saved);
          expect(saved.state, RegisteredMaterialHandoffState.failed);
          expect(
            saved.failure!.kind,
            RegisteredMaterialHandoffFailureKind.configuration,
          );
          expect(saved.failure!.code, 'authenticationRequired');
          expect(saved.failure!.message, _authenticationMessage);
          expect(saved.acknowledgement, isNull);
          expect(saved.leaseToken, isNull);
          _expectFrozenHandoff(saved, before);
          expect(await queue.find(request.id), source);
          expect(
            callbacks,
            denial.context == 'false' || denial.context == 'throw' ? 1 : 0,
          );
          expect(transport.connectionReads, 0);
          expect(transport.packets, isEmpty);
          expect(fixture.storage.prepares, 0);
          expect(fixture.storage.uploads, 0);
          expect(fixture.transport.submits, 0);
          expect(fixture.referenceAccess.calls, 0);
          expect(fixture.scheduler.calls, 1);
        },
      );
    }

    for (final bound in [false, true]) {
      test(
        '${bound ? 'required exact current' : 'default legacy'} accepts unchanged Registered packet',
        () async {
          // Given an authentic saved registration and exact current context, or legacy defaults.
          final queue = await fixture.openQueue();
          final request = _withBinding(
            registeredTestRequest(),
            bound ? _binding() : null,
          );
          final source = await _saveRegistered(queue, request, fixture.now);
          final transport = _RegisteredTransport();
          final service = handoffService(
            queue,
            queue,
            transport,
            requiresAuthentication: bound,
            context: bound ? _context() : null,
          );
          final before = (await service.enqueueRegistered(
            request.id,
            registeredTestTarget(),
          )).record;
          // When the registered transport returns a matching controlled acknowledgement.
          final result = await service.processNext(networkAllowed: true);
          // Then only the handoff accepts, preserving the original source, target and association.
          expect(service.requiresAuthentication, bound);
          expect(result.outcome, RegisteredMaterialHandoffRunOutcome.accepted);
          expect(result.record!.acknowledgement, _ack(request));
          _expectFrozenHandoff(result.record!, before);
          expect(await queue.find(request.id), source);
          expect(source.acknowledgement, isNull);
          expect(transport.packets, [before.packet]);
          final wire = RegisteredMaterialSubmissionCodec.packetToJson(
            transport.packets.single,
          );
          expect(wire.containsKey('authenticationBinding'), isFalse);
          expect(wire.containsKey('userAccountId'), isFalse);
          expect(wire['requestId'], request.id);
          expect(
            result.record!.sourceRequest.authenticationBinding,
            bound ? _binding() : null,
          );
          expect(fixture.storage.prepares, 0);
          expect(fixture.storage.uploads, 0);
          expect(fixture.transport.submits, 0);
          expect(fixture.scheduler.calls, 1);
        },
      );
    }

    for (final offline in [false, true]) {
      test(
        '${offline ? 'offline' : 'caller false'} skips handoff claims and context',
        () async {
          // Given a pending handoff and a context whose observation would fail.
          final queue = await fixture.openQueue();
          final request = _withBinding(registeredTestRequest(), _binding());
          await _saveRegistered(queue, request, fixture.now);
          final store = _ControlledHandoffStore(queue);
          final transport = _RegisteredTransport();
          var callbacks = 0;
          final service = handoffService(
            queue,
            store,
            transport,
            requiresAuthentication: true,
            context: _context(
              isCurrent: () {
                callbacks++;
                throw StateError('private context');
              },
            ),
          );
          final before = (await service.enqueueRegistered(
            request.id,
            registeredTestTarget(),
          )).record;
          final storeCalls = store.calls;
          // When an early caller or network gate forbids processing before claim.
          final result = await service.processNext(
            networkAllowed: !offline,
            isRunCurrent: offline ? null : () => false,
          );
          // Then pending local intent and all adapters remain untouched.
          expect(
            result.outcome,
            offline
                ? RegisteredMaterialHandoffRunOutcome.offline
                : RegisteredMaterialHandoffRunOutcome.cancelled,
          );
          expect(store.calls, storeCalls);
          expect(callbacks, 0);
          expect(transport.connectionReads, 0);
          expect(transport.packets, isEmpty);
          expect(await queue.findHandoffForSource(request.id), before);
          expect(fixture.storage.prepares, 0);
          expect(fixture.transport.submits, 0);
          expect(fixture.scheduler.calls, 1);
        },
      );
    }

    for (final retireCaller in [false, true]) {
      test(
        'held handoff claim ${retireCaller ? 'caller' : 'context'} retirement sends nothing',
        () async {
          // Given a real sending lease held before the service receives its claim.
          final queue = await fixture.openQueue();
          final request = _withBinding(registeredTestRequest(), _binding());
          final source = await _saveRegistered(queue, request, fixture.now);
          final entered = Completer<void>();
          final release = Completer<void>();
          final store = _ControlledHandoffStore(queue)
            ..afterClaim = () async {
              entered.complete();
              await release.future;
            };
          var current = true;
          var caller = true;
          final transport = _RegisteredTransport();
          final service = handoffService(
            queue,
            store,
            transport,
            requiresAuthentication: true,
            context: _context(isCurrent: () => current),
          );
          final before = (await service.enqueueRegistered(
            request.id,
            registeredTestTarget(),
          )).record;
          final pending = service.processNext(
            networkAllowed: true,
            isRunCurrent: () => caller,
          );
          await entered.future;
          // When the caller or context retires before claim admission completes.
          if (retireCaller) {
            caller = false;
          } else {
            current = false;
          }
          release.complete();
          final result = await pending;
          // Then caller retirement stays unknown, while initial context denial is configuration failure.
          expect(
            result.outcome,
            retireCaller
                ? RegisteredMaterialHandoffRunOutcome.outcomeUnknown
                : RegisteredMaterialHandoffRunOutcome.failed,
          );
          expect(
            result.record!.failure!.code,
            retireCaller ? 'runRetired' : 'authenticationRequired',
          );
          _expectFrozenHandoff(result.record!, before);
          expect(await queue.find(request.id), source);
          expect(result.record!.acknowledgement, isNull);
          expect(transport.connectionReads, 0);
          expect(transport.packets, isEmpty);
        },
      );
    }

    test('admitted context retired before transport preserves conservative unknown', () async {
      // Given an exact context that retires at the observable target lookup boundary.
      final queue = await fixture.openQueue();
      final request = _withBinding(registeredTestRequest(), _binding());
      await _saveRegistered(queue, request, fixture.now);
      var current = true;
      final transport = _RegisteredTransport()
        ..onConnection = () {
          current = false;
        };
      final service = handoffService(
        queue,
        queue,
        transport,
        requiresAuthentication: true,
        context: _context(isCurrent: () => current),
      );
      await service.enqueueRegistered(request.id, registeredTestTarget());
      // When admission succeeds but the bound context retires before transport dispatch.
      final result = await service.processNext(networkAllowed: true);
      // Then existing sending uncertainty remains without inventing a server refusal.
      expect(
        result.outcome,
        RegisteredMaterialHandoffRunOutcome.outcomeUnknown,
      );
      expect(
        result.record!.failure!.kind,
        RegisteredMaterialHandoffFailureKind.outcomeUnknown,
      );
      expect(result.record!.failure!.code, 'runRetired');
      expect(result.record!.acknowledgement, isNull);
      expect(transport.connectionReads, 1);
      expect(transport.packets, isEmpty);
    });

    for (final retirement in [
      'caller',
      'false',
      'throw',
      'account',
      'profile',
      'base',
    ]) {
      for (final lateFailure in [false, true]) {
        test(
          'held handoff $retirement discards late ${lateFailure ? 'rejection' : 'ACK'} and only A reconciles',
          () async {
            // Given admitted A with frozen packet/key/target and held actual transport work.
            final queue = await fixture.openQueue();
            final request = _withBinding(registeredTestRequest(), _binding());
            final source = await _saveRegistered(queue, request, fixture.now);
            var current = true;
            var caller = true;
            var activeBinding = _binding();
            final entered = Completer<void>();
            final held = Completer<SubmissionAcknowledgement>();
            final transport = _RegisteredTransport()
              ..onSubmit = (_) {
                entered.complete();
                return held.future;
              };
            final service = handoffService(
              queue,
              queue,
              transport,
              requiresAuthentication: true,
              context: _context(
                isCurrent: () {
                  if (!current && retirement == 'throw') {
                    throw StateError('private retirement');
                  }
                  return current && activeBinding == _binding();
                },
              ),
            );
            final before = (await service.enqueueRegistered(
              request.id,
              registeredTestTarget(),
            )).record;
            final pending = service.processNext(
              networkAllowed: true,
              isRunCurrent: () => caller,
            );
            await entered.future;
            // When the caller retires or its account/profile/base/lifetime changes before completion.
            switch (retirement) {
              case 'caller':
                caller = false;
              case 'account':
                activeBinding = _binding(account: 'B');
              case 'profile':
                activeBinding = _binding(profile: 'other');
              case 'base':
                activeBinding = _binding(
                  base: 'https://other.example/account/',
                );
              default:
                current = false;
            }
            if (lateFailure) {
              held.completeError(
                SubmissionAdapterException(
                  stage: SubmissionFailureStage.transport,
                  code: 'privateRejected',
                  message: 'Controlled rejection.',
                  retryable: false,
                  transportFailureOutcome:
                      SubmissionTransportFailureOutcome.rejected,
                ),
              );
            } else {
              held.complete(_ack(request));
            }
            final retired = await pending;
            // Then both ACK and classified catch paths retain unknown acceptance and A's source.
            expect(
              retired.outcome,
              RegisteredMaterialHandoffRunOutcome.outcomeUnknown,
            );
            expect(retired.record!.acknowledgement, isNull);
            expect(
              retired.record!.failure!.kind,
              RegisteredMaterialHandoffFailureKind.outcomeUnknown,
            );
            _expectFrozenHandoff(retired.record!, before);
            expect(await queue.find(request.id), source);
            expect(transport.packets.length, 1);
            await service.close();
            // When B explicitly reconciles local intent but attempts dispatch with its own context.
            final b = handoffService(
              queue,
              queue,
              transport,
              requiresAuthentication: true,
              context: _context(binding: _binding(account: 'B')),
            );
            final bIntent = await b.reconcile(request.id);
            final denied = await b.processNext(networkAllowed: true);
            // Then local reconciliation grants no account adoption or second send.
            _expectFrozenHandoff(bIntent.record, before);
            expect(denied.record!.failure!.code, 'authenticationRequired');
            expect(
              denied.record!.sourceRequest.authenticationBinding,
              _binding(),
            );
            expect(transport.packets.length, 1);
            await b.close();
            transport.onSubmit = null;
            final freshA = handoffService(
              queue,
              queue,
              transport,
              requiresAuthentication: true,
              context: _context(),
            );
            // When fresh exact A explicitly reconciles and dispatches the same durable intent.
            await freshA.reconcile(request.id);
            final accepted = await freshA.processNext(networkAllowed: true);
            // Then the exact same packet/key can accept without replacing source or history.
            expect(
              accepted.outcome,
              RegisteredMaterialHandoffRunOutcome.accepted,
            );
            expect(accepted.record!.acknowledgement, _ack(request));
            _expectFrozenHandoff(accepted.record!, before);
            expect(transport.packets, [before.packet, before.packet]);
            expect(await queue.find(request.id), source);
            expect(fixture.scheduler.calls, 3);
          },
        );
      }
    }

    test(
      'denial persistence losing its handoff lease retains leaseLost semantics',
      () async {
        // Given required mode without a context and a claim whose lease expires before failure save.
        final queue = await fixture.openQueue();
        final request = _withBinding(registeredTestRequest(), _binding());
        final source = await _saveRegistered(queue, request, fixture.now);
        final store = _ControlledHandoffStore(queue)
          ..afterClaim = () async {
            fixture.now = fixture.now.add(const Duration(minutes: 6));
          };
        final transport = _RegisteredTransport();
        final service = handoffService(
          queue,
          store,
          transport,
          requiresAuthentication: true,
        );
        await service.enqueueRegistered(request.id, registeredTestTarget());
        // When initial authentication denial cannot persist under the expired lease.
        final result = await service.processNext(networkAllowed: true);
        // Then no forged failed row or remote result replaces the actual sending checkpoint.
        expect(result.outcome, RegisteredMaterialHandoffRunOutcome.leaseLost);
        expect(
          (await queue.findHandoffForSource(request.id))!.state,
          RegisteredMaterialHandoffState.sending,
        );
        expect(result.record!.acknowledgement, isNull);
        expect(await queue.find(request.id), source);
        expect(transport.connectionReads, 0);
        expect(transport.packets, isEmpty);
      },
    );

    test('retired handoff transport after lease expiry cannot overwrite the saved row', () async {
      // Given admitted A held after sending under a real SQLite handoff lease.
      final queue = await fixture.openQueue();
      final request = _withBinding(registeredTestRequest(), _binding());
      final source = await _saveRegistered(queue, request, fixture.now);
      var current = true;
      final entered = Completer<void>();
      final held = Completer<SubmissionAcknowledgement>();
      final transport = _RegisteredTransport()
        ..onSubmit = (_) {
          entered.complete();
          return held.future;
        };
      final service = handoffService(
        queue,
        queue,
        transport,
        context: _context(isCurrent: () => current),
      );
      await service.enqueueRegistered(request.id, registeredTestTarget());
      final pending = service.processNext(networkAllowed: true);
      await entered.future;
      // When lease expiry and context retirement precede a matching ACK.
      fixture.now = fixture.now.add(const Duration(minutes: 6));
      current = false;
      held.complete(_ack(request));
      final result = await pending;
      // Then lost ownership cannot save unknown or ACK, and a later scan only records expiry.
      expect(result.outcome, RegisteredMaterialHandoffRunOutcome.leaseLost);
      final fresh = handoffService(
        queue,
        queue,
        transport,
        context: _context(),
      );
      expect(
        (await fresh.processNext(networkAllowed: true)).outcome,
        RegisteredMaterialHandoffRunOutcome.noWork,
      );
      final saved = (await queue.findHandoffForSource(request.id))!;
      expect(saved.state, RegisteredMaterialHandoffState.outcomeUnknown);
      expect(saved.failure!.code, 'leaseExpired');
      expect(saved.acknowledgement, isNull);
      expect(await queue.find(request.id), source);
      expect(transport.packets.length, 1);
    });

    test('a valid ACK save already issued remains its durable transaction after retirement', () async {
      // Given admitted A, a matching ACK and a barrier after the real acceptance save is issued.
      final queue = await fixture.openQueue();
      final request = _withBinding(registeredTestRequest(), _binding());
      final source = await _saveRegistered(queue, request, fixture.now);
      var current = true;
      final entered = Completer<void>();
      final release = Completer<void>();
      final store = _ControlledHandoffStore(queue)
        ..afterFinish = (state) async {
          if (state == RegisteredMaterialHandoffState.accepted) {
            entered.complete();
            await release.future;
          }
        };
      final transport = _RegisteredTransport();
      final service = handoffService(
        queue,
        store,
        transport,
        context: _context(isCurrent: () => current),
      );
      await service.enqueueRegistered(request.id, registeredTestTarget());
      final pending = service.processNext(networkAllowed: true);
      await entered.future;
      // When the context retires while the already-issued durable transaction's result is held.
      current = false;
      release.complete();
      final result = await pending;
      // Then publication is cancelled without rolling back or overwriting the valid durable ACK.
      expect(result.outcome, RegisteredMaterialHandoffRunOutcome.cancelled);
      expect(result.record!.state, RegisteredMaterialHandoffState.accepted);
      expect(result.record!.acknowledgement, _ack(request));
      expect(await queue.findHandoffForSource(request.id), result.record);
      expect(await queue.find(request.id), source);
      expect(store.acceptanceWrites, 1);
      expect(transport.packets.length, 1);
    });

    test(
      'ACK save errors propagate once and leave sending uncertainty',
      () async {
        // Given a matching controlled ACK and one selected local acceptance-write failure.
        final queue = await fixture.openQueue();
        final request = _withBinding(registeredTestRequest(), _binding());
        await _saveRegistered(queue, request, fixture.now);
        final error = StateError('controlled ACK save failure');
        final store = _ControlledHandoffStore(queue)..acceptanceError = error;
        final transport = _RegisteredTransport();
        final service = handoffService(
          queue,
          store,
          transport,
          context: _context(),
        );
        await service.enqueueRegistered(request.id, registeredTestTarget());
        // When the actual driver tries to persist the acknowledgement exactly once.
        await expectLater(
          service.processNext(networkAllowed: true),
          throwsA(same(error)),
        );
        // Then the write error is strict and no fallback accepts, retries or rewrites sending.
        final saved = (await queue.findHandoffForSource(request.id))!;
        expect(saved.state, RegisteredMaterialHandoffState.sending);
        expect(saved.acknowledgement, isNull);
        expect(store.acceptanceWrites, 1);
        expect(transport.packets.length, 1);
        expect(
          (await service.processNext(networkAllowed: true)).outcome,
          RegisteredMaterialHandoffRunOutcome.noWork,
        );
        expect(store.acceptanceWrites, 1);
        expect(transport.packets.length, 1);
      },
    );

    for (final bound in [false, true]) {
      test(
        'local ${bound ? 'bound' : 'legacy'} handoff intent and inspection never observe context',
        () async {
          // Given saved registration and an unusable context in an explicit required composition.
          final queue = await fixture.openQueue();
          final request = _withBinding(
            registeredTestRequest(),
            bound ? _binding() : null,
          );
          final source = await _saveRegistered(queue, request, fixture.now);
          var callbacks = 0;
          final transport = _RegisteredTransport();
          final service = handoffService(
            queue,
            queue,
            transport,
            requiresAuthentication: true,
            context: _context(
              isCurrent: () {
                callbacks++;
                throw StateError('local context');
              },
            ),
          );
          // When enqueue, duplicate enqueue, find/list and explicit reconcile manipulate local intent.
          final created = await service.enqueueRegistered(
            request.id,
            registeredTestTarget(),
          );
          final duplicate = await service.enqueueRegistered(
            request.id,
            registeredTestTarget(),
          );
          final found = await service.findForSource(request.id);
          final listed = await service.list();
          final reconciled = await service.reconcile(request.id);
          await service.close();
          // Then no credential/provider/original operation occurs and logout never backfills or erases history.
          expect(duplicate.record, created.record);
          expect(found, created.record);
          expect(listed, [created.record]);
          expect(reconciled.record, created.record);
          expect(await queue.findHandoffForSource(request.id), created.record);
          expect(await queue.find(request.id), source);
          expect(
            created.record.sourceRequest.authenticationBinding,
            bound ? _binding() : null,
          );
          expect(callbacks, 0);
          expect(transport.connectionReads, 0);
          expect(transport.packets, isEmpty);
          expect(fixture.storage.prepares, 0);
          expect(fixture.storage.uploads, 0);
          expect(fixture.transport.submits, 0);
          expect(fixture.scheduler.calls, 3);
          await expectLater(service.list(), throwsStateError);
        },
      );
    }

    test(
      'close drains borrowed handoff reads without closing queue or erasing A',
      () async {
        // Given A's durable handoff and an accepted list command held in its borrowed store.
        final queue = await fixture.openQueue();
        final request = _withBinding(registeredTestRequest(), _binding());
        final source = await _saveRegistered(queue, request, fixture.now);
        final entered = Completer<void>();
        final release = Completer<void>();
        final store = _ControlledHandoffStore(queue)
          ..afterList = () async {
            entered.complete();
            await release.future;
          };
        final transport = _RegisteredTransport();
        final service = handoffService(
          queue,
          store,
          transport,
          context: _context(),
        );
        final before = (await service.enqueueRegistered(
          request.id,
          registeredTestTarget(),
        )).record;
        final reading = service.list();
        final rejection = expectLater(reading, throwsStateError);
        await entered.future;
        // When close fences publication and waits for the accepted borrowed command.
        var drained = false;
        final closing = service.close().then((_) {
          drained = true;
        });
        expect(drained, isFalse);
        release.complete();
        await rejection;
        await closing;
        // Then borrowed handles and historical A intent remain usable after the drain.
        expect(drained, isTrue);
        expect(await queue.find(request.id), source);
        expect(await queue.findHandoffForSource(request.id), before);
        expect(transport.packets, isEmpty);
        expect(transport.connectionReads, 0);
      },
    );

    test(
      'close retires a held bound transport and discards the late ACK',
      () async {
        // Given A's bound handoff held in a noncooperative borrowed transport.
        final queue = await fixture.openQueue();
        final request = _withBinding(registeredTestRequest(), _binding());
        final source = await _saveRegistered(queue, request, fixture.now);
        final entered = Completer<void>();
        final held = Completer<SubmissionAcknowledgement>();
        final transport = _RegisteredTransport()
          ..onSubmit = (_) {
            entered.complete();
            return held.future;
          };
        final service = handoffService(
          queue,
          queue,
          transport,
          context: _context(),
        );
        await service.enqueueRegistered(request.id, registeredTestTarget());
        final pending = service.processNext(networkAllowed: true);
        await entered.future;
        // When close immediately fences the run before the transport returns.
        final closing = service.close();
        final result = await pending;
        await closing;
        held.complete(_ack(request));
        // Then durable unknown survives, with source and borrowed queue independently retained.
        expect(
          result.outcome,
          RegisteredMaterialHandoffRunOutcome.outcomeUnknown,
        );
        expect(result.record!.acknowledgement, isNull);
        expect(await queue.findHandoffForSource(request.id), result.record);
        expect(await queue.find(request.id), source);
        expect(transport.packets.length, 1);
        await expectLater(service.list(), throwsStateError);
      },
    );
  });
}

const _authenticationMessage =
    'Sign in to the account bound to this submission.';

SubmissionAuthenticationBinding _binding({
  String account = 'A',
  String profile = 'authority.main',
  String base = 'https://authority.example/account/',
}) => SubmissionAuthenticationBinding(
  authority: UserAccountHttpProfile.fromString(
    profileId: profile,
    serviceBaseUri: base,
  ),
  userAccountId: account,
);

SubmissionAuthenticationContext _context({
  SubmissionAuthenticationBinding? binding,
  bool Function()? isCurrent,
}) => SubmissionAuthenticationContext(
  binding: binding ?? _binding(),
  isCurrent: isCurrent ?? () => true,
);

SubmissionAuthenticationContext? _denialContext(
  String? selection,
  void Function() observe,
) {
  if (selection == null) return null;
  final binding = switch (selection) {
    'account' => _binding(account: 'B'),
    'profile' => _binding(profile: 'other'),
    'base' => _binding(base: 'https://other.example/account/'),
    _ => _binding(),
  };
  return _context(
    binding: binding,
    isCurrent: () {
      observe();
      if (selection == 'throw') throw StateError('private context exception');
      return selection != 'false';
    },
  );
}

SubmissionRequest _withBinding(
  SubmissionRequest original,
  SubmissionAuthenticationBinding? binding, {
  bool tkl = false,
}) => SubmissionRequest(
  id: original.id,
  kind: original.kind,
  subjectId: original.subjectId,
  createdAt: original.createdAt,
  document: original.document,
  payload: original.payload,
  materials: original.materials,
  transportConnectionId: tkl ? 'lake' : original.transportConnectionId,
  storageConnectionId: tkl ? null : original.storageConnectionId,
  authenticationBinding: binding,
  extensions: original.extensions,
  tklDelivery: tkl
      ? TklMaterialDeliveryRequest(
          requestId: original.id,
          contribution: {
            'originals': [
              for (final material in original.materials)
                {
                  'resourceId': material.key,
                  'mediaType': material.original.mediaType,
                  'byteLength': material.original.byteLength,
                  'sourceReference': {'kind': 'mobileOriginal'},
                },
            ],
          },
        )
      : original.tklDelivery,
);

Future<SubmissionRecord> _saveRegistered(
  SqliteSubmissionQueueStore queue,
  SubmissionRequest request,
  DateTime now,
) async {
  await queue.enqueue(request);
  final claim = (await queue.claimNext(
    now: now,
    leaseToken: 'registration${request.id}',
    leaseDuration: const Duration(minutes: 5),
  ))!;
  await queue.saveTklProgress(
    id: request.id,
    leaseToken: claim.leaseToken!,
    now: now,
    progress: TklMaterialDeliverySnapshot(
      deliveryRef: 'saved/${request.id}',
      requestId: request.id,
      revision: 7,
      destinationId: 'server-selected',
      destinationLabel: 'Saved destination',
      state: TklMaterialDeliveryState.registered,
      materialRef: '  urn:tkl:Material:${request.id}  ',
      resources: [
        for (final material in request.materials)
          TklOriginalTransferProgress(
            resourceId: material.key,
            mediaType: material.original.mediaType,
            byteLength: material.original.byteLength,
            state: TklOriginalTransferState.uploaded,
          ),
      ],
    ),
  );
  return queue.completeMaterialRegistration(
    id: request.id,
    leaseToken: claim.leaseToken!,
    now: now,
  );
}

void _expectFrozenHandoff(
  RegisteredMaterialHandoffRecord actual,
  RegisteredMaterialHandoffRecord original,
) {
  expect(actual.id, original.id);
  expect(actual.sourceRequest, original.sourceRequest);
  expect(actual.packet, original.packet);
  expect(sameRegisteredMaterialTarget(actual.target, original.target), isTrue);
  expect(actual.sourceCheckpointUpdatedAt, original.sourceCheckpointUpdatedAt);
  expect(actual.createdAt, original.createdAt);
  expect(
    TklMaterialDeliveryCodec.snapshotToJson(actual.registeredSnapshot),
    TklMaterialDeliveryCodec.snapshotToJson(original.registeredSnapshot),
  );
}

SubmissionAcknowledgement _ack(SubmissionRequest request) =>
    SubmissionAcknowledgement(
      requestId: request.id,
      subjectId: request.subjectId,
      serverId: 'controlled/${request.id}',
      receivedAt: DateTime.utc(2026, 10, 26, 3),
      extensions: const {'accepted': true},
    );

final class _RegisteredTransport
    implements RegisteredMaterialSubmissionTransport {
  final List<RegisteredMaterialSubmissionPacket> packets = [];
  int connectionReads = 0;
  void Function()? onConnection;
  Future<SubmissionAcknowledgement> Function(
    RegisteredMaterialSubmissionPacket,
  )?
  onSubmit;
  @override
  HttpSubmissionConnection get connection {
    connectionReads++;
    onConnection?.call();
    return registeredTestTarget();
  }

  @override
  Future<SubmissionAcknowledgement> submitRegisteredMaterial(
    RegisteredMaterialSubmissionPacket packet,
  ) {
    packets.add(packet);
    return Future.sync(
      () => onSubmit?.call(packet) ?? _ack(packet.sourceRequest),
    );
  }
}

/// Only exposes deterministic await boundaries around a real SQLite store.
final class _ControlledHandoffStore implements RegisteredMaterialHandoffStore {
  _ControlledHandoffStore(this.inner);
  final RegisteredMaterialHandoffStore inner;
  int calls = 0;
  int acceptanceWrites = 0;
  Object? acceptanceError;
  Future<void> Function()? afterClaim;
  Future<void> Function()? afterList;
  Future<void> Function(RegisteredMaterialHandoffState)? beforeFinish;
  Future<void> Function(RegisteredMaterialHandoffState)? afterFinish;

  @override
  Future<RegisteredMaterialHandoffRecord?> findHandoffForSource(
    String sourceRequestId,
  ) {
    calls++;
    return inner.findHandoffForSource(sourceRequestId);
  }

  @override
  Future<List<RegisteredMaterialHandoffRecord>> listHandoffs() async {
    calls++;
    final result = await inner.listHandoffs();
    await afterList?.call();
    return result;
  }

  @override
  Future<RegisteredMaterialHandoffRecord> createHandoff({
    required String id,
    required SubmissionRecord source,
    required HttpSubmissionConnection target,
    required RegisteredMaterialSubmissionPacket packet,
    required DateTime now,
  }) {
    calls++;
    return inner.createHandoff(
      id: id,
      source: source,
      target: target,
      packet: packet,
      now: now,
    );
  }

  @override
  Future<RegisteredMaterialHandoffRecord?> claimNextHandoff({
    required DateTime now,
    required String leaseToken,
    required Duration leaseDuration,
  }) async {
    calls++;
    final result = await inner.claimNextHandoff(
      now: now,
      leaseToken: leaseToken,
      leaseDuration: leaseDuration,
    );
    await afterClaim?.call();
    return result;
  }

  @override
  Future<RegisteredMaterialHandoffRecord> finishHandoff({
    required String id,
    required String leaseToken,
    required DateTime now,
    required RegisteredMaterialHandoffState state,
    SubmissionAcknowledgement? acknowledgement,
    RegisteredMaterialHandoffFailure? failure,
  }) async {
    calls++;
    if (state == RegisteredMaterialHandoffState.accepted) {
      acceptanceWrites++;
      final error = acceptanceError;
      if (error != null) throw error;
    }
    await beforeFinish?.call(state);
    final result = await inner.finishHandoff(
      id: id,
      leaseToken: leaseToken,
      now: now,
      state: state,
      acknowledgement: acknowledgement,
      failure: failure,
    );
    await afterFinish?.call(state);
    return result;
  }

  @override
  Future<RegisteredMaterialHandoffRecord> reconcileHandoff({
    required String sourceRequestId,
    required DateTime now,
  }) {
    calls++;
    return inner.reconcileHandoff(sourceRequestId: sourceRequestId, now: now);
  }
}

final class _NoTklCalls implements TklMaterialDeliveryClient {
  int calls = 0;
  Future<T> _unexpected<T>() {
    calls++;
    return Future<T>.error(
      StateError('Authentication denial must precede TKL work'),
    );
  }

  @override
  Future<TklMaterialDeliveryDestination> getDestination() => _unexpected();
  @override
  Future<TklMaterialDeliverySnapshot> prepare(
    TklMaterialDeliveryRequest request,
  ) => _unexpected();
  @override
  Future<TklMaterialDeliverySnapshot?> findForRequest(String requestId) =>
      _unexpected();
  @override
  Future<TklMaterialDeliverySnapshot> get(String deliveryRef) => _unexpected();
  @override
  Future<TklMaterialDeliverySnapshot> uploadOriginal({
    required String deliveryRef,
    required String resourceId,
    required String mediaType,
    required Uint8List content,
  }) => _unexpected();
  @override
  Future<TklMaterialDeliverySnapshot> finalize(String deliveryRef) =>
      _unexpected();
}
