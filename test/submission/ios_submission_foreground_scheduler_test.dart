import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:textus_flutter_core/textus_flutter_core.dart';

import '../support/submission_fixture.dart';
import '../support/submission_http_fixture.dart';
import 'registered_material_submission_test.dart'
    show registeredTestPacket, registeredTestRequest, registeredTestTarget;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  TargetPlatform? previousPlatform;
  AppLifecycleState? previousLifecycle;

  setUp(() {
    previousPlatform = debugDefaultTargetPlatformOverride;
    previousLifecycle = binding.lifecycleState;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    binding.resetInternalState();
  });

  tearDown(() {
    binding.resetInternalState();
    if (previousLifecycle != null) _lifecycle(binding, previousLifecycle!);
    debugDefaultTargetPlatformOverride = previousPlatform;
  });

  test('construction and null or paused wakes are inert until resumed', () async {
    // Given real retained original files, a durable queue and no active lifecycle.
    final h = await _Harness.create();
    addTearDown(h.dispose);
    final request = await h.disk.request();
    await h.queue.enqueue(request);
    final scheduler = h.scheduler(binding);
    addTearDown(scheduler.close);
    expect(h.opens, 0);
    expect(h.network.credentials.calls, isEmpty);
    // When explicit wakes arrive first with a null and then a paused lifecycle.
    await scheduler.requestRun();
    _lifecycle(binding, AppLifecycleState.paused);
    await scheduler.requestRun();
    expect(h.opens, 0);
    expect((await h.queue.find(request.id))!.claimCount, 0);
    // When resume authorizes the remembered wake, the existing adapters run.
    h.successfulOriginals(request);
    _lifecycle(binding, AppLifecycleState.resumed);
    await h.closedRun(1);
    await scheduler.close();
    // Then only a matching acceptance completes the immutable durable intent.
    final row = (await h.queue.find(request.id))!;
    expect(row.state, SubmissionState.submitted);
    expect(row.request, request);
    expect(row.acknowledgement!.requestId, request.id);
    expect(h.closeCounts, {1: 1});
    expect(h.maxOwners, 1);
    expect(h.uploaded, [
      SubmissionFixture.photoBytes,
      SubmissionFixture.audioBytes,
    ]);
    expect(
      await h.disk.materials.readMaterial(request.materials.first.original),
      SubmissionFixture.photoBytes,
    );
    expect(h.network.client.closed, isFalse);
  });

  test(
    'wakes during cleanup coalesce and a later serialized Commit is scanned',
    () async {
      // Given an empty real queue whose first run is held inside owned cleanup.
      final h = await _Harness.create();
      addTearDown(h.dispose);
      final cleaning = Completer<void>();
      final release = Completer<void>();
      h.beforeClose = (index) async {
        if (index != 1) return;
        cleaning.complete();
        await release.future;
      };
      final scheduler = h.scheduler(binding);
      addTearDown(scheduler.close);
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      _lifecycle(binding, AppLifecycleState.resumed);
      await Future.wait([scheduler.requestRun(), scheduler.requestRun()]);
      await _deadline(cleaning.future);
      final mainLife = SubmissionRunLifetime(id: 'ui_commit');
      final main = h.service(mainLife, scheduler);
      final request = await h.disk.request(withMaterials: false);
      h.accept(request);
      // When Commit requests a wake while still owning its serialized command.
      final committed = await _deadline(main.commit(request));
      await Future.wait([scheduler.requestRun(), scheduler.requestRun()]);
      // Then Commit returns without waiting for the held run or dispatching overlap.
      expect(committed.schedulingFailure, isNull);
      expect(h.opens, 1);
      expect(h.owners, 1);
      expect((await h.queue.find(request.id))!.acknowledgement, isNull);
      release.complete();
      await h.closedRun(2);
      await scheduler.close();
      // Then one follow-up scan finds the later intent and borrows the same queue.
      expect(h.opens, 2);
      expect(h.maxOwners, 1);
      expect(h.closeCounts, {1: 1, 2: 1});
      expect((await h.queue.list()).single.state, SubmissionState.submitted);
      expect(h.network.client.requests, hasLength(1));
      expect(h.lifetimes.map((life) => life.id).toSet(), hasLength(2));
    },
  );

  test('pause aborts actual HTTP and resume waits for old cleanup before acceptance', () async {
    // Given an immutable no-material intent and an actual held adapter send.
    final h = await _Harness.create();
    addTearDown(h.dispose);
    final request = await h.disk.request(withMaterials: false);
    await h.queue.enqueue(request);
    final entered = Completer<void>();
    final aborted = Completer<void>();
    final held = Completer<http.StreamedResponse>();
    final cleaning = Completer<void>();
    final releaseCleanup = Completer<void>();
    h.network.client.handler = (captured) {
      unawaited(captured.abort.then((_) => aborted.complete()));
      entered.complete();
      return held.future;
    };
    h.beforeClose = (index) async {
      if (index != 1) return;
      cleaning.complete();
      await releaseCleanup.future;
    };
    final scheduler = h.scheduler(binding);
    addTearDown(scheduler.close);
    addTearDown(() {
      if (!held.isCompleted) {
        held.complete(
          submissionJsonResponse(h.network.acknowledgement(request)),
        );
      }
      if (!releaseCleanup.isCompleted) releaseCleanup.complete();
    });
    _lifecycle(binding, AppLifecycleState.resumed);
    await scheduler.requestRun();
    await _deadline(entered.future);
    // When any non-resumed state retires the current lifetime synchronously.
    _lifecycle(binding, AppLifecycleState.inactive);
    expect(h.lifetimes.single.isCurrent, isFalse);
    await _deadline(aborted.future);
    await _deadline(cleaning.future);
    final cancelled = (await h.queue.find(request.id))!;
    expect(cancelled.state, SubmissionState.readyToSubmit);
    expect(cancelled.acknowledgement, isNull);
    // When resume arrives before cleanup settles and the old remote effect returns.
    _lifecycle(binding, AppLifecycleState.resumed);
    held.complete(submissionJsonResponse(h.network.acknowledgement(request)));
    expect(h.opens, 1);
    expect((await h.queue.find(request.id))!.acknowledgement, isNull);
    h.accept(request);
    releaseCleanup.complete();
    await h.closedRun(2);
    await scheduler.close();
    // Then a fresh lifetime alone accepts, without duplicating the persisted intent.
    final rows = await h.queue.list();
    expect(rows, hasLength(1));
    expect(rows.single.request, request);
    expect(rows.single.state, SubmissionState.submitted);
    expect(rows.single.claimCount, 2);
    expect(h.maxOwners, 1);
    expect(h.network.client.requests, hasLength(2));
    expect(h.closeCounts, {1: 1, 2: 1});
  });

  test('offline and predicate failure precede every port and retain explicit intent', () async {
    // Given a real queued request and a policy observed before any opener call.
    final h = await _Harness.create();
    addTearDown(h.dispose);
    final request = await h.disk.request(withMaterials: false);
    final accepted = await h.queue.enqueue(request);
    var allowed = false;
    var failPolicy = false;
    var policyCalls = 0;
    var checked = Completer<void>();
    final scheduler = h.scheduler(
      binding,
      networkAllowed: () {
        policyCalls++;
        checked.complete();
        if (failPolicy) throw StateError('PRIVATE_POLICY_FAILURE');
        return allowed;
      },
    );
    addTearDown(scheduler.close);
    _lifecycle(binding, AppLifecycleState.resumed);
    // When an explicit wake is offline, no resource, credential or queue port opens.
    await scheduler.requestRun();
    await _deadline(checked.future);
    expect(h.opens, 0);
    expect(await h.queue.find(request.id), accepted);
    expect(h.network.credentials.calls, isEmpty);
    // When a later explicit wake encounters a policy failure, retirement cancels
    // its infrastructure retry timer without clearing the same durable intent.
    checked = Completer<void>();
    failPolicy = true;
    await scheduler.requestRun();
    await _deadline(checked.future);
    _lifecycle(binding, AppLifecycleState.paused);
    expect(h.opens, 0);
    expect(await h.queue.find(request.id), accepted);
    // When a later authorized resume rechecks the live policy, delivery can proceed.
    checked = Completer<void>();
    failPolicy = false;
    allowed = true;
    h.accept(request);
    _lifecycle(binding, AppLifecycleState.resumed);
    await h.closedRun(1);
    await scheduler.close();
    // Then policy was checked for each attempt and offline never became success.
    expect(policyCalls, 3);
    expect((await h.queue.find(request.id))!.state, SubmissionState.submitted);
    expect(h.network.credentials.calls, ['server']);
  });

  test('close during acquisition is one immediate retirement and joins late cleanup', () async {
    // Given an accepted opener whose newly acquired owner is held before return.
    final h = await _Harness.create();
    addTearDown(h.dispose);
    final request = await h.disk.request(withMaterials: false);
    final accepted = await h.queue.enqueue(request);
    final entered = Completer<void>();
    final release = Completer<void>();
    h.beforeOpen = (index) async {
      entered.complete();
      await release.future;
    };
    final scheduler = h.scheduler(binding);
    addTearDown(scheduler.close);
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    _lifecycle(binding, AppLifecycleState.resumed);
    await scheduler.requestRun();
    await _deadline(entered.future);
    // When close is requested repeatedly while acquisition is unresolved.
    final closing = scheduler.close();
    expect(scheduler.close(), same(closing));
    expect(h.lifetimes.single.isCurrent, isFalse);
    var finished = false;
    final observed = closing.then((_) => finished = true);
    await expectLater(scheduler.requestRun(), throwsStateError);
    _lifecycle(binding, AppLifecycleState.paused);
    _lifecycle(binding, AppLifecycleState.resumed);
    expect(finished, isFalse);
    release.complete();
    await _deadline(observed);
    // Then the late owner is closed once with no queue, credential or send effect.
    expect(h.opens, 1);
    expect(h.closeCounts, {1: 1});
    expect(await h.queue.find(request.id), accepted);
    expect(h.network.credentials.calls, isEmpty);
    expect(h.network.client.closed, isFalse);
    await h.disk.scheduler.requestRun();
    expect(h.disk.scheduler.calls, 1);
  });

  test(
    'close during actual send aborts promptly and never accepts its late ACK',
    () async {
      // Given a held concrete HTTP transport over one durable no-material request.
      final h = await _Harness.create();
      addTearDown(h.dispose);
      final request = await h.disk.request(withMaterials: false);
      await h.queue.enqueue(request);
      final entered = Completer<void>();
      final aborted = Completer<void>();
      final held = Completer<http.StreamedResponse>();
      h.network.client.handler = (captured) {
        unawaited(captured.abort.then((_) => aborted.complete()));
        entered.complete();
        return held.future;
      };
      final scheduler = h.scheduler(binding);
      addTearDown(scheduler.close);
      addTearDown(() {
        if (!held.isCompleted) {
          held.complete(
            submissionJsonResponse(h.network.acknowledgement(request)),
          );
        }
      });
      _lifecycle(binding, AppLifecycleState.resumed);
      await scheduler.requestRun();
      await _deadline(entered.future);
      // When close retires without waiting for that remote send to settle.
      final closing = scheduler.close();
      expect(scheduler.close(), same(closing));
      expect(h.lifetimes.single.isCurrent, isFalse);
      await _deadline(aborted.future);
      await _deadline(closing);
      held.complete(submissionJsonResponse(h.network.acknowledgement(request)));
      // Then the existing cancellation fence preserves intent and borrowed owners.
      final row = (await h.queue.find(request.id))!;
      expect(row.state, SubmissionState.readyToSubmit);
      expect(row.acknowledgement, isNull);
      expect(h.closeCounts, {1: 1});
      expect(h.network.client.closed, isFalse);
      await expectLater(scheduler.requestRun(), throwsStateError);
    },
  );

  test(
    'mismatched ACK cannot submit and only a later matching ACK accepts',
    () async {
      // Given a concrete transport whose first reply acknowledges another identity.
      final h = await _Harness.create();
      addTearDown(h.dispose);
      final request = await h.disk.request(withMaterials: false);
      await h.queue.enqueue(request);
      h.network.client.handler = (_) => submissionJsonResponse({
        ...h.network.acknowledgement(request),
        'requestId': 'other_request',
      });
      final scheduler = h.scheduler(binding);
      addTearDown(scheduler.close);
      // When a resumed lifecycle authorizes the explicit wake and mismatched reply.
      _lifecycle(binding, AppLifecycleState.resumed);
      await scheduler.requestRun();
      await h.closedRun(1);
      // Then no scheduler terminal substitutes for exact durable acceptance.
      final rejected = (await h.queue.find(request.id))!;
      expect(rejected.state, SubmissionState.submissionFailed);
      expect(rejected.acknowledgement, isNull);
      // When an explicit retry reuses the immutable request and a matching response.
      final main = h.service(SubmissionRunLifetime(id: 'retry_ui'), scheduler);
      h.accept(request);
      await _deadline(main.retry(request.id));
      await h.closedRun(2);
      await scheduler.close();
      // Then one durable intent records the actual matching server acknowledgement.
      expect((await h.queue.list()).single.state, SubmissionState.submitted);
      expect((await h.queue.find(request.id))!.request, request);
    },
  );

  test('queue failure and persisted due time survive pause without coercing old states', () async {
    // Given one due-later retry, one nonretryable row and an unknown saved handoff.
    final h = await _Harness.create();
    addTearDown(h.dispose);
    final request = await h.disk.request(id: 'retry', withMaterials: false);
    await h.queue.enqueue(request);
    final retryClaim = (await h.queue.claimNext(
      now: h.disk.now,
      leaseToken: 'seed_retry',
      leaseDuration: const Duration(minutes: 5),
    ))!;
    final due = h.disk.now.add(const Duration(minutes: 2));
    await h.queue.fail(
      id: request.id,
      leaseToken: retryClaim.leaseToken!,
      now: h.disk.now,
      failure: _failure(h.disk.now, retryClaim.claimCount, true),
      nextAttemptAt: due,
    );
    final excluded = await h.disk.request(
      id: 'excluded',
      subjectId: 'excluded_subject',
      withMaterials: false,
    );
    await h.queue.enqueue(excluded);
    final excludedClaim = (await h.queue.claimNext(
      now: h.disk.now,
      leaseToken: 'seed_excluded',
      leaseDuration: const Duration(minutes: 5),
    ))!;
    final oldFailure = await h.queue.fail(
      id: excluded.id,
      leaseToken: excludedClaim.leaseToken!,
      now: h.disk.now,
      failure: _failure(h.disk.now, excludedClaim.claimCount, false),
    );
    final unknown = await _unknownHandoff(h.queue, h.disk.now);
    final counted = ControlledQueue(h.queue)..failAt = 'claimNext';
    h.runQueue = counted;
    final scheduler = h.scheduler(binding);
    addTearDown(scheduler.close);
    _lifecycle(binding, AppLifecycleState.resumed);
    // When an infrastructure queue failure ends the first bounded run.
    await scheduler.requestRun();
    await h.closedRun(1);
    _lifecycle(binding, AppLifecycleState.paused);
    expect((await h.queue.find(request.id))!.nextAttemptAt, due);
    expect(h.network.client.requests, isEmpty);
    // When resume scans before the persisted due time, no early retry occurs.
    _lifecycle(binding, AppLifecycleState.resumed);
    await h.closedRun(2);
    _lifecycle(binding, AppLifecycleState.paused);
    expect((await h.queue.find(request.id))!.claimCount, retryClaim.claimCount);
    expect((await h.queue.find(request.id))!.nextAttemptAt, due);
    // When a later authorized resume observes that same deadline has passed.
    h.disk.now = due.add(const Duration(seconds: 1));
    h.accept(request);
    _lifecycle(binding, AppLifecycleState.resumed);
    await h.closedRun(3);
    await scheduler.close();
    // Then only eligible intent runs; old nonretryable and unknown states survive.
    expect((await h.queue.find(request.id))!.state, SubmissionState.submitted);
    expect(await h.queue.find(excluded.id), oldFailure);
    expect(
      await h.queue.findHandoffForSource(unknown.sourceRequestId),
      unknown,
    );
    expect(h.network.client.requests, hasLength(1));
  });

  test(
    'reentrant policy close reserves its join before opening any resource',
    () async {
      // Given a policy that synchronously closes the scheduler invoking it.
      final h = await _Harness.create();
      addTearDown(h.dispose);
      final entered = Completer<void>();
      late IosSubmissionForegroundScheduler scheduler;
      late Future<void> closing;
      scheduler = h.scheduler(
        binding,
        networkAllowed: () {
          closing = scheduler.close();
          entered.complete();
          return true;
        },
      );
      addTearDown(scheduler.close);
      _lifecycle(binding, AppLifecycleState.resumed);
      // When the timer reaches the injected predicate under reserved run ownership.
      await scheduler.requestRun();
      await _deadline(entered.future);
      await _deadline(closing);
      // Then close joins without a reentrant dispatch or an unobserved failed future.
      expect(scheduler.close(), same(closing));
      expect(h.opens, 0);
      expect(h.network.credentials.calls, isEmpty);
      expect(await h.queue.list(), isEmpty);
    },
  );

  test(
    'unsupported wake rejects before binding observation or opener IO',
    () async {
      // Given an inert scheduler on every unsupported target platform.
      final h = await _Harness.create();
      addTearDown(h.dispose);
      final scheduler = h.scheduler(binding);
      addTearDown(scheduler.close);
      for (final platform in TargetPlatform.values.where(
        (p) => p != TargetPlatform.iOS,
      )) {
        debugDefaultTargetPlatformOverride = platform;
        // When public requestRun is called, platform rejection precedes all ports.
        await expectLater(scheduler.requestRun(), throwsUnsupportedError);
      }
      // Then even lifecycle changes cannot dispatch an unaccepted wake.
      _lifecycle(binding, AppLifecycleState.resumed);
      expect(h.opens, 0);
      expect(h.network.credentials.calls, isEmpty);
    },
  );
}

void _lifecycle(WidgetsBinding binding, AppLifecycleState state) {
  // Given the actual binding under test, expose the same observer notification
  // used by platform lifecycle delivery, including its stored current state.
  // ignore: invalid_use_of_protected_member
  binding.handleAppLifecycleStateChanged(state);
}

Future<T> _deadline<T>(Future<T> future) =>
    future.timeout(const Duration(seconds: 5));

SubmissionFailure _failure(DateTime now, int count, bool retryable) =>
    SubmissionFailure(
      stage: SubmissionFailureStage.transport,
      code: 'controlledUnavailable',
      message: 'Controlled service unavailable.',
      retryable: retryable,
      occurredAt: now,
      claimCount: count,
    );

Future<RegisteredMaterialHandoffRecord> _unknownHandoff(
  SqliteSubmissionQueueStore queue,
  DateTime now,
) async {
  // Given a source registered through the queue's actual durable checkpoints.
  final request = registeredTestRequest(id: 'registered');
  await queue.enqueue(request);
  const lease = 'registered_seed';
  await queue.claimNext(
    now: now,
    leaseToken: lease,
    leaseDuration: const Duration(minutes: 5),
  );
  await queue.saveTklProgress(
    id: request.id,
    leaseToken: lease,
    now: now,
    progress: TklMaterialDeliverySnapshot(
      deliveryRef: 'saved_delivery',
      requestId: request.id,
      revision: 1,
      destinationId: 'controlled',
      destinationLabel: 'Controlled destination',
      state: TklMaterialDeliveryState.registered,
      materialRef: '  urn:tkl:Material:retained  ',
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
  final source = await queue.completeMaterialRegistration(
    id: request.id,
    leaseToken: lease,
    now: now,
  );
  final target = registeredTestTarget();
  // When a saved handoff reaches an explicit unknown-outcome disposition.
  final handoff = await queue.createHandoff(
    id: 'unknown_handoff',
    source: source,
    target: target,
    now: now,
    packet: registeredTestPacket(
      source: request,
      target: target,
      materialRef: source.tklProgress!.materialRef!,
    ),
  );
  await queue.claimNextHandoff(
    now: now,
    leaseToken: 'unknown_seed',
    leaseDuration: const Duration(minutes: 5),
  );
  // Then the scheduler must preserve this disposition without reconciling it.
  return queue.finishHandoff(
    id: handoff.id,
    leaseToken: 'unknown_seed',
    now: now,
    state: RegisteredMaterialHandoffState.outcomeUnknown,
    failure: RegisteredMaterialHandoffFailure(
      kind: RegisteredMaterialHandoffFailureKind.outcomeUnknown,
      code: 'controlledUnknown',
      message: 'Controlled unknown outcome.',
    ),
  );
}

final class _Harness {
  _Harness(this.disk, this.queue);

  final SubmissionFixture disk;
  final SqliteSubmissionQueueStore queue;
  final network = SubmissionHttpFixture();
  final List<SubmissionRunLifetime> lifetimes = [];
  final Map<int, int> closeCounts = {};
  final Map<int, Completer<void>> _closed = {};
  final List<List<int>> uploaded = [];
  SubmissionQueueStore? runQueue;
  Future<void> Function(int)? beforeOpen;
  Future<void> Function(int)? beforeClose;
  int opens = 0;
  int owners = 0;
  int maxOwners = 0;

  static Future<_Harness> create() async {
    final disk = await SubmissionFixture.create();
    return _Harness(disk, await disk.openQueue());
  }

  IosSubmissionForegroundScheduler scheduler(
    WidgetsBinding binding, {
    bool Function()? networkAllowed,
  }) => IosSubmissionForegroundScheduler(
    openResources: open,
    binding: binding,
    networkAllowed: networkAllowed,
    now: () => disk.now,
  );

  SubmissionService service(
    SubmissionRunLifetime lifetime,
    SubmissionWakeScheduler scheduler, {
    RegisteredMaterialHandoffService? handoffs,
  }) {
    final service = SubmissionService(
      queue: runQueue ?? queue,
      materials: disk.materials,
      scheduler: scheduler,
      now: () => disk.now,
      registeredMaterialHandoffs: handoffs,
      referenceAccessPolicy: disk.referenceAccess,
      storageAdapters: {
        'drive': network.drive(
          isRunCurrent: () => lifetime.isCurrent,
          cancellation: lifetime.cancelled,
        ),
      },
      transports: {
        'server': network.transport(
          isRunCurrent: () => lifetime.isCurrent,
          cancellation: lifetime.cancelled,
        ),
      },
    );
    disk.services.add(service);
    return service;
  }

  Future<SubmissionBackgroundResources> open({
    required SubmissionRunLifetime lifetime,
    required SubmissionWakeScheduler scheduler,
  }) async {
    // Given all durable data and credential/client ports remain test-owned.
    final index = ++opens;
    owners++;
    if (owners > maxOwners) maxOwners = owners;
    lifetimes.add(lifetime);
    final handoffs = RegisteredMaterialHandoffService(
      queue: queue,
      store: queue,
      transports: const {},
      scheduler: scheduler,
      now: () => disk.now,
    );
    final owned = service(lifetime, scheduler, handoffs: handoffs);
    Future<void>? closing;
    Future<void> cleanup() async {
      lifetime.retire();
      await handoffs.close();
      await owned.close();
      await beforeClose?.call(index);
      closeCounts[index] = (closeCounts[index] ?? 0) + 1;
      owners--;
      _closed.putIfAbsent(index, Completer<void>.new).complete();
    }

    final resources = SubmissionBackgroundResources(
      service: owned,
      queue: runQueue ?? queue,
      executionMode: SubmissionExecutionMode.foreground,
      close: () => closing ??= cleanup(),
    );
    // When an acquisition barrier is supplied, it holds this actual fresh owner.
    await beforeOpen?.call(index);
    // Then late acquisition can be retired and closed without closing the queue.
    return resources;
  }

  Future<void> closedRun(int index) =>
      _deadline(_closed.putIfAbsent(index, Completer<void>.new).future);

  void accept(SubmissionRequest request) {
    network.client.handler = (_) =>
        submissionJsonResponse(network.acknowledgement(request));
  }

  void successfulOriginals(SubmissionRequest request) {
    // Given real retained originals and controlled B1 allocation/upload replies.
    var next = 0;
    SubmissionMaterial? pending;
    network.client.handler = (captured) {
      if (captured.uri.host == network.httpConnection.endpoint.host) {
        return submissionJsonResponse(network.acknowledgement(request));
      }
      if (captured.uri.path.endsWith('/generateIds')) {
        return submissionJsonResponse({
          'ids': ['File_${request.materials[next++].key}'],
          'space': 'drive',
          'kind': 'drive#generatedIds',
        });
      }
      if (captured.method == 'POST') {
        pending = request.materials.singleWhere(
          (material) => captured.json['id'] == 'File_${material.key}',
        );
        return submissionEmptyResponse(
          200,
          headers: {'location': SubmissionHttpFixture.uploadLocation},
        );
      }
      uploaded.add(captured.bytes);
      return submissionJsonResponse(
        network.file(request, pending!, 'File_${pending!.key}'),
        status: 201,
      );
    };
  }

  Future<void> dispose() async {
    await disk.dispose();
    network.dispose();
  }
}
