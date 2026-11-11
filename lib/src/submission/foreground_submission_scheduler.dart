import 'dart:async';

import 'package:flutter/widgets.dart';

import 'submission_adapters.dart';
import 'submission_background_resources.dart';
import 'submission_background_runner.dart';
import 'submission_run_lifetime.dart';

/// Acquires one owned batch while borrowing its lifetime and wake scheduler.
/// Opening or cleanup must never await the enclosing scheduler's close.
typedef ForegroundSubmissionResourcesOpener =
    Future<SubmissionBackgroundResources> Function({
      required SubmissionRunLifetime lifetime,
      required SubmissionWakeScheduler scheduler,
    });

/// Explicit-wake foreground driver that runs only while the application is resumed.
/// Construction is inert; no OS or headless background delivery is provided.
class ForegroundSubmissionScheduler
    with WidgetsBindingObserver
    implements SubmissionWakeScheduler {
  /// Retains borrowed callbacks and an optional binding without accessing them.
  ForegroundSubmissionScheduler({
    required this._openResources,
    this._binding,
    bool Function()? networkAllowed,
    DateTime Function()? now,
    this.onBatchSettled,
  }) : _networkAllowed = networkAllowed ?? (() => true),
       _now = now ?? (() => DateTime.now().toUtc());

  final ForegroundSubmissionResourcesOpener _openResources;
  final WidgetsBinding? _binding;
  final bool Function() _networkAllowed;
  final DateTime Function() _now;
  final VoidCallback? onBatchSettled;
  WidgetsBinding? _observedBinding;
  Timer? _timer;
  _IosForegroundRun? _run;
  bool _active = false;
  bool _requested = false;
  bool _closed = false;
  int _generation = 0;
  int _runCounter = 0;
  Future<void>? _closeFuture;

  /// Explicitly composed platform capability; the legacy iOS wrapper keeps its gate.
  bool get isPlatformSupported => true;

  /// Accepts durable-work wake intent without joining queue processing. This
  /// allows Commit to finish while it still holds its serialized command.
  @override
  Future<void> requestRun() async {
    if (!isPlatformSupported) {
      throw UnsupportedError('Foreground submission is unsupported here');
    }
    if (_closed) throw StateError('Foreground submission scheduler is closed');
    if (_observedBinding == null) {
      final selected = _binding ?? WidgetsBinding.instance;
      selected.addObserver(this);
      _observedBinding = selected;
      _active = selected.lifecycleState == AppLifecycleState.resumed;
    }
    _requested = true;
    _generation++;
    _schedule(Duration.zero);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_closed) return;
    _active = state == AppLifecycleState.resumed;
    if (!_active) {
      _timer?.cancel();
      _timer = null;
      final run = _run;
      if (run != null) {
        run.cancelled = true;
        run.lifetime.retire();
      }
    } else {
      _schedule(Duration.zero);
    }
  }

  bool _current(_IosForegroundRun run) =>
      !_closed && _active && identical(_run, run) && run.lifetime.isCurrent;

  void _schedule(Duration delay) {
    if (_closed || !_active || !_requested || _run != null) return;
    _timer?.cancel();
    final bounded = Duration(
      microseconds: delay.inMicroseconds.clamp(
        0,
        const Duration(days: 1).inMicroseconds,
      ),
    );
    _timer = Timer(bounded, () {
      _timer = null;
      if (_closed || !_active || !_requested || _run != null) return;
      // Reserve completion and ownership before any injected callback can
      // reentrantly request another wake or close this scheduler.
      final run = _IosForegroundRun(
        SubmissionRunLifetime(id: 'ios_foreground_${++_runCounter}'),
        _generation,
      );
      _run = run;
      unawaited(_execute(run));
    });
  }

  Future<void> _execute(_IosForegroundRun run) async {
    SubmissionBackgroundResources? resources;
    SubmissionBackgroundRunResult? result;
    var failed = false;
    try {
      if (!_current(run)) return;
      final allowed = _networkAllowed();
      if (!_current(run)) return;
      if (!allowed) {
        result = SubmissionBackgroundRunResult(
          outcome: SubmissionBackgroundOutcome.offline,
        );
      } else {
        resources = await _openResources(
          lifetime: run.lifetime,
          scheduler: this,
        );
        if (!_current(run)) return;
        result = await SubmissionBackgroundRunner(
          resources: resources,
          lifetime: run.lifetime,
          now: _now,
        ).run(networkAllowed: true);
        if (!_current(run)) return;
      }
    } catch (_) {
      failed = true;
    } finally {
      final retiredBeforeCleanup = !_current(run);
      try {
        if (resources != null) await resources.close();
      } catch (_) {
        failed = true;
        run.cleanupFailed = true;
      }
      // Resource cleanup may itself retire the run, so retain whether it was
      // cancelled separately from the owner's ordinary cleanup retirement.
      final cancelled =
          retiredBeforeCleanup || run.cancelled || _closed || !_active;
      run.lifetime.retire();
      if (identical(_run, run)) _run = null;
      run.completion.complete();
      if (!_closed) {
        try {
          onBatchSettled?.call();
        } catch (_) {
          /* Observation cannot change execution. */
        }
      }
      if (!_closed && _active && _requested) {
        if (failed) {
          _schedule(const Duration(seconds: 30));
        } else if (cancelled) {
          _schedule(Duration.zero);
        } else if (_generation != run.generation) {
          _schedule(Duration.zero);
        } else {
          switch (result?.outcome) {
            case SubmissionBackgroundOutcome.drained:
              _requested = false;
            case SubmissionBackgroundOutcome.pending:
            case SubmissionBackgroundOutcome.failure:
              _schedule(result?.nextDelay ?? const Duration(seconds: 30));
            case SubmissionBackgroundOutcome.cancelled:
              _schedule(Duration.zero);
            case SubmissionBackgroundOutcome.offline:
              break;
            case null:
              _schedule(const Duration(seconds: 30));
          }
        }
      }
    }
  }

  /// Retires synchronously, then joins the sole acquisition/run/cleanup owner.
  /// Repeated close returns the same join and never closes borrowed ports.
  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;
    final completion = Completer<void>();
    _closeFuture = completion.future;
    _closed = true;
    _timer?.cancel();
    _timer = null;
    final run = _run;
    run?.lifetime.retire();
    var failed = false;
    try {
      _observedBinding?.removeObserver(this);
    } catch (_) {
      failed = true;
    }
    _observedBinding = null;
    unawaited(() async {
      try {
        await run?.completion.future;
        if (failed || (run?.cleanupFailed ?? false)) {
          throw StateError('iOS submission scheduler could not be closed');
        }
        completion.complete();
      } catch (_) {
        completion.completeError(
          StateError('iOS submission scheduler could not be closed'),
        );
      }
    }());
    return completion.future;
  }
}

final class _IosForegroundRun {
  _IosForegroundRun(this.lifetime, this.generation);

  final SubmissionRunLifetime lifetime;
  final int generation;
  final Completer<void> completion = Completer<void>();
  bool cancelled = false;
  bool cleanupFailed = false;
}
