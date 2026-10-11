import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:textus_flutter_core/textus_flutter_core.dart';

import '../support/submission_background_fixture.dart';
import '../support/submission_fixture.dart';
import '../support/submission_http_fixture.dart';

void main() {
  test('NB1', () async {
    // Given actual original files, a real file SQLite queue and immutable A intent.
    final fixture = await SubmissionBackgroundFixture.create();
    addTearDown(fixture.dispose);
    final request = await fixture.disk.request(
      document: {
        'localDocumentMarker': '/private/editor/local-document',
        'editor': {'draft': true},
      },
    );
    final foregroundLife = SubmissionRunLifetime(id: 'foreground_nb1');
    final foreground = await fixture.resources(foregroundLife);
    await foreground.service.commit(request);
    fixture.successfulHttp(request);
    // When an offline runner is asked to process the committed request.
    final offline = await SubmissionBackgroundRunner(
      resources: foreground,
      lifetime: foregroundLife,
      now: () => fixture.disk.now,
    ).run(networkAllowed: false);
    // Then no queue claim, credential or HTTP operation occurs and intent is durable.
    expect(offline.outcome, SubmissionBackgroundOutcome.offline);
    expect(offline.operations, 0);
    expect((await foreground.queue.find(request.id))!.claimCount, 0);
    expect(fixture.network.credentials.calls, isEmpty);
    expect(fixture.network.client.requests, isEmpty);
    await foreground.close();
    await fixture.configuration.putDrive(
      DriveSubmissionConnection(
        id: 'nextDrive',
        accountId: 'next@example.test',
        folderId: 'NextFolder',
      ),
    );
    await fixture.configuration.putHttp(
      HttpSubmissionConnection(
        id: 'nextServer',
        endpoint: Uri.parse('https://next.example.test/submit'),
      ),
    );
    await fixture.configuration.select(
      storageConnectionId: 'nextDrive',
      transportConnectionId: 'nextServer',
    );
    // When a separate queue/service lifetime reopens and uses every stored definition.
    final onlineLife = SubmissionRunLifetime(id: 'online_nb1');
    final reopened = await fixture.resources(onlineLife);
    final result = await SubmissionBackgroundRunner(
      resources: reopened,
      lifetime: onlineLife,
      now: () => fixture.disk.now,
    ).run(networkAllowed: true);
    // Then prepare/upload/matching acknowledgement completes within eight dispatches.
    expect(result.outcome, SubmissionBackgroundOutcome.drained);
    expect(result.operations, inInclusiveRange(5, 8));
    expect(fixture.uploads.length, 2);
    expect(
      fixture.uploads[0].bytes,
      orderedEquals(SubmissionFixture.photoBytes),
    );
    expect(
      fixture.uploads[1].bytes,
      orderedEquals(SubmissionFixture.audioBytes),
    );
    expect(fixture.serverPacket!['payload'], request.payload);
    expect(fixture.serverPacket!['extensions'], request.extensions);
    expect(
      jsonEncode(fixture.serverPacket),
      isNot(contains('localDocumentMarker')),
    );
    expect(
      jsonEncode(fixture.serverPacket),
      isNot(contains(ControlledSubmissionCredentials.secret)),
    );
    expect(fixture.serverPacket!.containsKey('document'), isFalse);
    await reopened.close();
    final readback = await fixture.disk.openQueue();
    final submitted = (await readback.find(request.id))!;
    expect(submitted.state, SubmissionState.submitted);
    expect(submitted.request, request);
    expect(submitted.request.payload['transcript'], '  手入力\n原文  ');
    expect(
      submitted.request.materials.first.provenance,
      request.materials.first.provenance,
    );
    expect(submitted.acknowledgement!.serverId, isNotEmpty);

    // Given another immutable no-material request and a held real B1 HTTP send.
    final cancelledRequest = await fixture.disk.request(
      id: 'cancel_nb1',
      subjectId: 'cancel_subject',
      withMaterials: false,
    );
    await readback.enqueue(cancelledRequest);
    final entered = Completer<void>();
    final held = Completer<http.StreamedResponse>();
    fixture.network.client.handler = (captured) async {
      // Given the exact configured server has received this request once.
      expect(captured.method, 'POST');
      // When the controlled network exposes an actual unresolved send await.
      entered.complete();
      final response = await held.future;
      // Then any later controlled response remains an already dispatched effect.
      return response;
    };
    final cancelledLife = SubmissionRunLifetime(id: 'cancel_run_nb1');
    final cancelledResources = await fixture.resources(cancelledLife);
    final pendingRun = SubmissionBackgroundRunner(
      resources: cancelledResources,
      lifetime: cancelledLife,
      now: () => fixture.disk.now,
    ).run(networkAllowed: true);
    var cancellationSends = 0;
    try {
      await submissionEntered(entered);
      cancellationSends = fixture.network.client.requests.length;
      // When retirement aborts the adapter before the held acknowledgement returns.
      cancelledLife.retire();
      final cancelled = await pendingRun.timeout(const Duration(seconds: 2));
      // Then no late checkpoint or second dispatch can acknowledge the queue.
      expect(cancelled.outcome, SubmissionBackgroundOutcome.cancelled);
      expect(cancelled.operations, 1);
      expect(
        (await readback.find(cancelledRequest.id))!.acknowledgement,
        isNull,
      );
      expect(
        (await readback.find(cancelledRequest.id))!.state,
        SubmissionState.readyToSubmit,
      );
    } finally {
      // Given teardown owns the held HTTP response even after cancellation.
      final late = submissionJsonResponse(
        fixture.network.acknowledgement(cancelledRequest),
      );
      // When the late effect is released and observed by the accepted adapter.
      if (!held.isCompleted) held.complete(late);
      await pendingRun;
      // Then resource closure can join without an unresolved network completer.
      await cancelledResources.close();
    }
    // Then releasing the late controlled acknowledgement cannot publish or dispatch again.
    expect((await readback.find(cancelledRequest.id))!.acknowledgement, isNull);
    expect(fixture.network.client.requests.length, cancellationSends);
    // Given the cancelled row is excluded with a safe nonretryable test failure.
    final excluded = (await readback.claimNext(
      now: fixture.disk.now,
      leaseToken: 'exclude_nb1',
      leaseDuration: const Duration(minutes: 5),
    ))!;
    await readback.fail(
      id: excluded.request.id,
      leaseToken: excluded.leaseToken!,
      now: fixture.disk.now,
      failure: SubmissionFailure(
        stage: SubmissionFailureStage.configuration,
        code: 'testExcluded',
        message: 'Controlled nonretryable test failure.',
        retryable: false,
        occurredAt: fixture.disk.now,
        claimCount: excluded.claimCount,
      ),
    );
    final leasedRequest = await fixture.disk.request(
      id: 'leased_nb1',
      subjectId: 'leased_subject',
      withMaterials: false,
    );
    await readback.enqueue(leasedRequest);
    final leased = (await readback.claimNext(
      now: fixture.disk.now,
      leaseToken: 'dead_engine_nb1',
      leaseDuration: const Duration(minutes: 5),
    ))!;
    final beforeExpiryLife = SubmissionRunLifetime(id: 'scan_nb1');
    final beforeExpiry = await fixture.resources(beforeExpiryLife);
    // When no-work scans the unexpired claim left by another engine.
    final scheduled = await SubmissionBackgroundRunner(
      resources: beforeExpiry,
      lifetime: beforeExpiryLife,
      now: () => fixture.disk.now,
    ).run(networkAllowed: true);
    // Then the lease expiry is scheduled without stealing the live claim.
    expect(scheduled.outcome, SubmissionBackgroundOutcome.pending);
    expect(scheduled.nextDelay, const Duration(minutes: 5));
    expect(
      (await readback.find(leasedRequest.id))!.leaseToken,
      leased.leaseToken,
    );
    await beforeExpiry.close();
    fixture.disk.now = fixture.disk.now.add(
      const Duration(minutes: 5, seconds: 1),
    );
    fixture.network.client.respond(
      submissionJsonResponse(fixture.network.acknowledgement(leasedRequest)),
    );
    final recoveryLife = SubmissionRunLifetime(id: 'recovery_nb1');
    final recovery = await fixture.resources(recoveryLife);
    // When a new owner runs after the injected clock crosses that expiry.
    final recovered = await SubmissionBackgroundRunner(
      resources: recovery,
      lifetime: recoveryLife,
      now: () => fixture.disk.now,
    ).run(networkAllowed: true);
    // Then only matching B1 HTTP acceptance submits, with one recovered claim.
    expect(recovered.outcome, SubmissionBackgroundOutcome.drained);
    final finalRow = (await readback.find(leasedRequest.id))!;
    expect(finalRow.state, SubmissionState.submitted);
    expect(finalRow.claimCount, 2);
    expect(finalRow.request, leasedRequest);
    await recovery.close();
  });

  group('NB4 bounded lifetime', () {
    test('safe lifetime retires once and rejects unsafe identity', () async {
      // Given one current run with a safe externally matched identity.
      final lifetime = SubmissionRunLifetime(id: 'run_nb4');
      var cancellations = 0;
      final observed = lifetime.cancelled.then((_) {
        // Given one listener attached to the public cancellation future.
        final previous = cancellations;
        // When retirement is observed.
        cancellations = previous + 1;
        // Then the listener count proves one completion despite repeated retire.
        expect(cancellations, 1);
      });
      expect(lifetime.isCurrent, isTrue);
      // When retirement is repeated and its cancellation future is joined.
      lifetime.retire();
      lifetime.retire();
      await observed;
      // Then ownership is permanently false and unsafe ids cannot be constructed.
      expect(lifetime.isCurrent, isFalse);
      expect(cancellations, 1);
      expect(
        () => SubmissionRunLifetime(id: '../private'),
        throwsArgumentError,
      );
    });

    test('offline and retired avoid every queue service credential and owner close', () async {
      // Given a real queue wrapped to count every public queue call.
      final fixture = await SubmissionBackgroundFixture.create();
      addTearDown(fixture.dispose);
      final counted = ControlledQueue(await fixture.disk.openQueue());
      final life = SubmissionRunLifetime(id: 'guard_nb4');
      final resources = await fixture.resources(life, queue: counted);
      // When offline is dispatched, then retirement is dispatched with network allowed.
      final offline = await SubmissionBackgroundRunner(
        resources: resources,
        lifetime: life,
      ).run(networkAllowed: false);
      life.retire();
      final retired = await SubmissionBackgroundRunner(
        resources: resources,
        lifetime: life,
      ).run(networkAllowed: true);
      // Then no borrowed port was touched or closed by either runner.
      expect(offline.outcome, SubmissionBackgroundOutcome.offline);
      expect(retired.outcome, SubmissionBackgroundOutcome.cancelled);
      expect(counted.calls, 0);
      expect(fixture.network.credentials.calls, isEmpty);
      expect(fixture.closes, 0);
      expect(fixture.network.client.closed, isFalse);
    });

    test('retirement during queue await prevents adapter dispatch', () async {
      // Given a real queued request and a barrier after actual claim persistence.
      final fixture = await SubmissionBackgroundFixture.create();
      addTearDown(fixture.dispose);
      final real = await fixture.disk.openQueue();
      final request = await fixture.disk.request(withMaterials: false);
      await real.enqueue(request);
      final queue = ControlledQueue(real);
      final entered = Completer<void>();
      final release = Completer<void>();
      queue.after = (name) async {
        // Given only the real claimNext operation is selected for delay.
        if (name != 'claimNext') return;
        // When its accepted SQLite result is held before the service resumes.
        entered.complete();
        await release.future;
        // Then the service must recheck ownership before any adapter call.
      };
      final life = SubmissionRunLifetime(id: 'queue_wait_nb4');
      final resources = await fixture.resources(life, queue: queue);
      final running = SubmissionBackgroundRunner(
        resources: resources,
        lifetime: life,
        now: () => fixture.disk.now,
      ).run(networkAllowed: true);
      try {
        await submissionEntered(entered);
        // When the lifetime retires during that actual queue await.
        life.retire();
        release.complete();
        final result = await running;
        // Then no credential/HTTP or further process operation can follow.
        expect(result.outcome, SubmissionBackgroundOutcome.cancelled);
        expect(result.operations, 1);
        expect(fixture.network.client.requests, isEmpty);
        expect(
          (await real.find(request.id))!.state,
          SubmissionState.readyToSubmit,
        );
      } finally {
        // Given this test owns the held queue barrier.
        if (!release.isCompleted) release.complete();
        // When the runner is joined and the explicit owner closes resources.
        await running;
        await resources.close();
        // Then no unresolved queue operation survives teardown.
        expect(fixture.closes, 1);
      }
    });

    test('max eight dispatches continue through business failures and bound ready wake', () async {
      // Given nine immutable no-material jobs and a real queue with missing transports.
      final disk = await SubmissionFixture.create();
      addTearDown(disk.dispose);
      final queue = await disk.openQueue();
      for (var i = 0; i < 9; i++) {
        await queue.enqueue(
          await disk.request(
            id: 'job_$i',
            subjectId: 'subject_$i',
            withMaterials: false,
          ),
        );
      }
      final service = disk.service(queue, transports: {});
      var closed = 0;
      final resources = SubmissionBackgroundResources(
        service: service,
        queue: queue,
        close: () async {
          // Given the caller owns the resource close callback.
          final previous = closed;
          // When explicitly invoked, record the owner's closure.
          closed = previous + 1;
          // Then runner borrowing can be verified independently.
        },
      );
      // When the default runner handles safe nonretryable missing-connection failures.
      final result = await SubmissionBackgroundRunner(
        resources: resources,
        lifetime: SubmissionRunLifetime(id: 'max_nb4'),
        now: () => disk.now,
      ).run(networkAllowed: true);
      // Then eight rows fail, the ninth stays ready, and its next wake is immediate.
      expect(result.operations, 8);
      expect(result.outcome, SubmissionBackgroundOutcome.pending);
      expect(result.nextDelay, Duration.zero);
      final rows = await queue.list();
      expect(
        rows.where((r) => r.state == SubmissionState.submissionFailed).length,
        8,
      );
      expect(
        rows.where((r) => r.state == SubmissionState.readyToSubmit).length,
        1,
      );
      expect(closed, 0);
    });

    test('retry due time is retained and long future lease wakes clamp to one day', () async {
      // Given real SQLite rows with a retryable failure and an unexpired owner.
      final disk = await SubmissionFixture.create();
      addTearDown(disk.dispose);
      final queue = await disk.openQueue();
      final request = await disk.request(withMaterials: false);
      await queue.enqueue(request);
      final claim = (await queue.claimNext(
        now: disk.now,
        leaseToken: 'retry_nb4',
        leaseDuration: const Duration(minutes: 5),
      ))!;
      await queue.fail(
        id: request.id,
        leaseToken: claim.leaseToken!,
        now: disk.now,
        failure: SubmissionFailure(
          stage: SubmissionFailureStage.transport,
          code: 'serviceUnavailable',
          message: 'Controlled retryable service failure.',
          retryable: true,
          occurredAt: disk.now,
          claimCount: claim.claimCount,
        ),
        nextAttemptAt: disk.now.add(const Duration(minutes: 2)),
      );
      final resources = _borrow(disk.service(queue), queue);
      // When no-work scans the business deadline rather than inventing an early retry.
      final result = await SubmissionBackgroundRunner(
        resources: resources,
        lifetime: SubmissionRunLifetime(id: 'due_nb4'),
        now: () => disk.now,
      ).run(networkAllowed: true);
      // Then the exact two-minute due time is returned and the failure is unchanged.
      expect(result.nextDelay, const Duration(minutes: 2));
      expect(
        (await queue.find(request.id))!.state,
        SubmissionState.submissionFailed,
      );
      await queue.retry(id: request.id, now: disk.now);
      final shortClaim = (await queue.claimNext(
        now: disk.now,
        leaseToken: 'fraction_nb4',
        leaseDuration: const Duration(minutes: 5),
      ))!;
      await queue.fail(
        id: request.id,
        leaseToken: shortClaim.leaseToken!,
        now: disk.now,
        failure: SubmissionFailure(
          stage: SubmissionFailureStage.transport,
          code: 'serviceUnavailable',
          message: 'Controlled retryable service failure.',
          retryable: true,
          occurredAt: disk.now,
          claimCount: shortClaim.claimCount,
        ),
        nextAttemptAt: disk.now.add(const Duration(microseconds: 1)),
      );
      // When a business due time has a positive sub-millisecond remainder.
      final fractional = await SubmissionBackgroundRunner(
        resources: resources,
        lifetime: SubmissionRunLifetime(id: 'fraction_run_nb4'),
        now: () => disk.now,
      ).run(networkAllowed: true);
      // Then rounding schedules after the due time instead of dispatching an early retry.
      expect(fractional.nextDelay, const Duration(milliseconds: 1));
      expect((await queue.find(request.id))!.claimCount, shortClaim.claimCount);
      await queue.retry(id: request.id, now: disk.now);
      await queue.claimNext(
        now: disk.now,
        leaseToken: 'long_lease_nb4',
        leaseDuration: const Duration(days: 3),
      );
      // When a subsequent scan sees a due time more than one day away.
      final long = await SubmissionBackgroundRunner(
        resources: resources,
        lifetime: SubmissionRunLifetime(id: 'long_nb4'),
        now: () => disk.now,
      ).run(networkAllowed: true);
      // Then the wake is bounded to a day while the three-day lease remains untouched.
      expect(long.nextDelay, const Duration(days: 1));
      expect(
        (await queue.find(request.id))!.leaseExpiresAt,
        disk.now.add(const Duration(days: 3)),
      );
    });

    test('single-flight rejects overlapping runs and retirement during list await wins', () async {
      // Given an empty real queue with an awaited list barrier after noWork.
      final disk = await SubmissionFixture.create();
      addTearDown(disk.dispose);
      final real = await disk.openQueue();
      final queue = ControlledQueue(real);
      final entered = Completer<void>();
      final release = Completer<void>();
      queue.after = (name) async {
        // Given the final list is the only held queue operation.
        if (name != 'list') return;
        // When the real list has completed but its result is not yet delivered.
        entered.complete();
        await release.future;
        // Then retirement must be observed before terminal scheduling.
      };
      final life = SubmissionRunLifetime(id: 'single_nb4');
      final runner = SubmissionBackgroundRunner(
        resources: _borrow(disk.service(queue), queue),
        lifetime: life,
        now: () => disk.now,
      );
      final running = runner.run(networkAllowed: true);
      try {
        await submissionEntered(entered);
        // When a concurrent invocation is attempted and the original retires.
        await expectLater(runner.run(networkAllowed: true), throwsStateError);
        life.retire();
        release.complete();
        final result = await running;
        // Then the first result is cancelled and the queue is still empty.
        expect(result.outcome, SubmissionBackgroundOutcome.cancelled);
        expect(await real.list(), isEmpty);
      } finally {
        // Given this test owns the final list barrier and pending invocation.
        if (!release.isCompleted) release.complete();
        // When teardown joins the pending work.
        await running;
        // Then the fixture can safely close its owned handle.
      }
    });

    test('unknown queue failure returns safe infrastructure delay without rewriting rows', () async {
      // Given one immutable real row and a controlled failure at claim entrance.
      final disk = await SubmissionFixture.create();
      addTearDown(disk.dispose);
      final real = await disk.openQueue();
      final request = await disk.request(withMaterials: false);
      final accepted = await real.enqueue(request);
      final queue = ControlledQueue(real)..failAt = 'claimNext';
      // When a runner observes the unexpected queue failure.
      final result = await SubmissionBackgroundRunner(
        resources: _borrow(disk.service(queue), queue),
        lifetime: SubmissionRunLifetime(id: 'failure_nb4'),
        now: () => disk.now,
      ).run(networkAllowed: true);
      // Then only a safe terminal and 30-second wake are returned; data is unchanged.
      expect(result.outcome, SubmissionBackgroundOutcome.failure);
      expect(result.nextDelay, const Duration(seconds: 30));
      expect(
        result.toJson().keys,
        unorderedEquals(['outcome', 'operations', 'nextDelayMs']),
      );
      expect(await real.find(request.id), accepted);
      expect(disk.transport.submits, 0);
    });

    test('monotonic budget and constructor limits bound dispatch without clock sleeps', () async {
      // Given a ready real queue and a wall clock unrelated to the monotonic budget.
      final disk = await SubmissionFixture.create();
      addTearDown(disk.dispose);
      final queue = await disk.openQueue();
      await queue.enqueue(await disk.request(withMaterials: false));
      final resources = _borrow(disk.service(queue), queue);
      final life = SubmissionRunLifetime(id: 'budget_nb4');
      // When a one-microsecond dispatch budget has expired before loop entrance.
      final result = await SubmissionBackgroundRunner(
        resources: resources,
        lifetime: life,
        runBudget: const Duration(microseconds: 1),
        now: () => disk.now,
      ).run(networkAllowed: true);
      // Then the ready row still requests a bounded wake and at most one dispatch occurred.
      expect(result.operations, inInclusiveRange(0, 1));
      expect(result.nextDelay, anyOf(isNull, Duration.zero));
      for (final count in [0, 9]) {
        expect(
          () => SubmissionBackgroundRunner(
            resources: resources,
            lifetime: life,
            maxOperations: count,
          ),
          throwsArgumentError,
        );
      }
      for (final budget in [Duration.zero, const Duration(seconds: 181)]) {
        expect(
          () => SubmissionBackgroundRunner(
            resources: resources,
            lifetime: life,
            runBudget: budget,
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => SubmissionBackgroundRunResult(
          outcome: SubmissionBackgroundOutcome.pending,
          operations: 9,
        ),
        throwsArgumentError,
      );
      expect(
        () => SubmissionBackgroundRunResult(
          outcome: SubmissionBackgroundOutcome.pending,
          nextDelay: const Duration(days: 2),
        ),
        throwsArgumentError,
      );
    });
  });
}

SubmissionBackgroundResources _borrow(
  SubmissionService service,
  SubmissionQueueStore queue,
) {
  // Given fixture-owned handles whose runner must not take ownership.
  final borrowed = queue;
  // When a resource wrapper supplies an observable forbidden close callback.
  final resources = SubmissionBackgroundResources(
    service: service,
    queue: borrowed,
    close: () async {
      // Given only the fixture is authorized to close these borrowed handles.
      final failure = StateError('Runner closed borrowed resources');
      // When an unexpected owner closure is attempted.
      throw failure;
      // Then the scenario fails instead of silently accepting ownership transfer.
    },
  );
  // Then runner behavior is exercised against real ports without resource closure.
  return resources;
}
