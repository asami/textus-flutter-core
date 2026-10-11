import 'submission_background_resources.dart';
import 'submission_queue_store.dart';
import 'submission_record.dart';
import 'submission_run_lifetime.dart';
import 'submission_service.dart';

/// Safe bounded background outcome; none substitutes for a queue acknowledgement.
enum SubmissionBackgroundOutcome {
  drained,
  pending,
  offline,
  cancelled,
  failure,
}

/// Safe native terminal value, without queue contents or raw failures.
final class SubmissionBackgroundRunResult {
  /// Validates dispatch count and an optional delay bounded to one day.
  SubmissionBackgroundRunResult({
    required this.outcome,
    this.operations = 0,
    this.nextDelay,
  }) {
    if (operations < 0 ||
        operations > 8 ||
        (nextDelay != null &&
            (nextDelay! < Duration.zero ||
                nextDelay! > const Duration(days: 1)))) {
      throw ArgumentError('Invalid background result');
    }
  }

  /// Safe scheduling outcome.
  final SubmissionBackgroundOutcome outcome;

  /// Number of processNext dispatches, including a no-work scan.
  final int operations;

  /// Earliest eligible due time relative to the injected UTC clock, or null.
  final Duration? nextDelay;

  /// Strict native terminal schema; no request, account, path or token is sent.
  Map<String, Object?> toJson() => {
    'outcome': outcome.name,
    'operations': operations,
    'nextDelayMs': nextDelay?.inMilliseconds,
  };
}

/// Bounded single-flight queue runner. Resources are borrowed and never closed.
final class SubmissionBackgroundRunner {
  /// Validates 1..8 dispatches and a positive budget no greater than 180 seconds.
  SubmissionBackgroundRunner({
    required this.resources,
    required this.lifetime,
    DateTime Function()? now,
    this.maxOperations = 8,
    this.runBudget = const Duration(seconds: 180),
  }) : _now = now ?? DateTime.now {
    if (maxOperations < 1 ||
        maxOperations > 8 ||
        runBudget <= Duration.zero ||
        runBudget > const Duration(seconds: 180)) {
      throw ArgumentError('Invalid background dispatch budget');
    }
  }

  /// Caller-owned resources, borrowed for each run.
  final SubmissionBackgroundResources resources;

  /// Same current predicate and cancellation used by the composition's adapters.
  final SubmissionRunLifetime lifetime;

  /// Maximum dispatch count for this invocation.
  final int maxOperations;

  /// Monotonic dispatch budget; an already dispatched operation may finish.
  final Duration runBudget;
  final DateTime Function() _now;
  bool _running = false;

  /// Offline/retired returns before all ports. Concurrent calls fail with
  /// StateError. Queue failures become a fixed 30s infrastructure wake, without
  /// retrying/rewriting records or exposing exceptions. Every await is fenced.
  Future<SubmissionBackgroundRunResult> run({
    required bool networkAllowed,
  }) async {
    if (_running) throw StateError('Background runner is already running');
    _running = true;
    var operations = 0;
    final watch = Stopwatch()..start();
    SubmissionBackgroundRunResult cancelled() => SubmissionBackgroundRunResult(
      outcome: SubmissionBackgroundOutcome.cancelled,
      operations: operations,
    );
    try {
      if (!lifetime.isCurrent) return cancelled();
      if (!networkAllowed) {
        return SubmissionBackgroundRunResult(
          outcome: SubmissionBackgroundOutcome.offline,
        );
      }
      while (operations < maxOperations && watch.elapsed < runBudget) {
        if (!lifetime.isCurrent) return cancelled();
        operations++;
        final result = await resources.service.processNext(
          networkAllowed: true,
          isRunCurrent: () => lifetime.isCurrent,
        );
        if (!lifetime.isCurrent) return cancelled();
        if (result.outcome == SubmissionRunOutcome.cancelled) {
          return cancelled();
        }
        if (result.outcome == SubmissionRunOutcome.offline) {
          return SubmissionBackgroundRunResult(
            outcome: SubmissionBackgroundOutcome.offline,
            operations: operations,
          );
        }
        if (result.outcome == SubmissionRunOutcome.noWork ||
            result.outcome == SubmissionRunOutcome.leaseLost) {
          break;
        }
      }
      if (!lifetime.isCurrent) return cancelled();
      final records = await resources.queue.list();
      if (!lifetime.isCurrent) return cancelled();
      final now = _now().toUtc();
      DateTime? due;
      for (final record in records) {
        final candidate = switch (record.state) {
          SubmissionState.readyToSubmit => now,
          SubmissionState.submitting => record.leaseExpiresAt,
          SubmissionState.submissionFailed =>
            record.lastFailure!.retryable ? record.nextAttemptAt : null,
          SubmissionState.submitted => null,
        };
        if (candidate != null && (due == null || candidate.isBefore(due))) {
          due = candidate;
        }
      }
      if (due == null) {
        return SubmissionBackgroundRunResult(
          outcome: SubmissionBackgroundOutcome.drained,
          operations: operations,
        );
      }
      final microseconds = due.difference(now).inMicroseconds;
      final milliseconds =
          (microseconds <= 0 ? 0 : (microseconds + 999) ~/ 1000).clamp(
            0,
            86400000,
          );
      return SubmissionBackgroundRunResult(
        outcome: SubmissionBackgroundOutcome.pending,
        operations: operations,
        nextDelay: Duration(milliseconds: milliseconds),
      );
    } on SubmissionLeaseLostException {
      return lifetime.isCurrent
          ? SubmissionBackgroundRunResult(
              outcome: SubmissionBackgroundOutcome.failure,
              operations: operations,
              nextDelay: const Duration(seconds: 30),
            )
          : cancelled();
    } catch (_) {
      return lifetime.isCurrent
          ? SubmissionBackgroundRunResult(
              outcome: SubmissionBackgroundOutcome.failure,
              operations: operations,
              nextDelay: const Duration(seconds: 30),
            )
          : cancelled();
    } finally {
      watch.stop();
      _running = false;
    }
  }
}
