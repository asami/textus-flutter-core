import 'dart:async';

import 'submission_json.dart' as j;

/// Monotonic run ownership shared with queue and abortable adapter operations.
final class SubmissionRunLifetime {
  /// Validates a safe run identity without starting work.
  SubmissionRunLifetime({required String id}) : id = j.token(id);

  /// Safe identity for matching native start/stop messages.
  final String id;
  final Completer<void> _cancelled = Completer<void>();

  /// True until retirement; it can never become true again.
  bool get isCurrent => !_cancelled.isCompleted;

  /// Completes once on retirement, without errors, to abort adapter IO.
  Future<void> get cancelled => _cancelled.future;

  /// Immediately retires this run; repeated calls have no further effect.
  void retire() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}
