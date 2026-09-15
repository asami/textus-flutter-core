import '../capture/capture_identifiers.dart';
import '../capture/capture_session.dart';

/// Consumer-supplied boundary for local capture-session persistence.
///
/// The consumer or integration layer supplies the implementation. Core defines
/// no storage mechanism, lifecycle policy, sync state, retry behavior, or
/// submission result.
abstract interface class CaptureLocalRepository {
  /// Reads the session identified by [id], if it is available locally.
  Future<CaptureSession?> read(CaptureSessionId id);

  /// Saves [session] through the consumer-provided local implementation.
  Future<void> save(CaptureSession session);
}

/// Consumer-supplied boundary for remote capture-session submission.
///
/// The consumer or integration layer supplies the implementation. Core defines
/// no HTTP/API behavior, sync state, retry behavior, submission result, or
/// domain policy.
abstract interface class CaptureRemoteRepository {
  /// Submits [session] through the consumer-provided remote implementation.
  Future<void> submit(CaptureSession session);
}
