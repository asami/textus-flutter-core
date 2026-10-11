import 'dart:async';

import 'package:http/http.dart' as http;

import '../repository/file_capture_store.dart';
import 'android_submission_background.dart';
import 'android_submission_configuration.dart';
import 'drive_submission_storage_adapter.dart';
import 'http_submission_transport.dart';
import 'sqlite_submission_queue_store.dart';
import 'submission_adapters.dart';
import 'submission_queue_store.dart';
import 'submission_reference_access.dart';
import 'submission_run_lifetime.dart';
import 'submission_service.dart';

/// Caller-owned service/queue composition. A runner only borrows these resources.
final class SubmissionBackgroundResources {
  /// Retains the owner's cleanup callback. Custom compositions must make close
  /// idempotent and drain service work before closing the queue; never close
  /// borrowed ports. The default factory supplies these guarantees.
  const SubmissionBackgroundResources({
    required this.service,
    required this.queue,
    required Future<void> Function() close,
    // Preserve the public named close callback while storing it privately.
    // ignore: prefer_initializing_formals
  }) : _close = close;

  /// Owned or explicitly borrowed service, as declared by the composing owner.
  final SubmissionService service;

  /// Same durable queue used by the service, borrowed by a runner.
  final SubmissionQueueStore queue;
  final Future<void> Function() _close;

  /// Executes the owner's cleanup; runners never call this operation.
  Future<void> close() => _close();
}

/// Opens an owned Android composition over the existing default application
/// support queue/original roots. No network, consent, scheduling or Commit occurs
/// during open. All persisted definitions are used, regardless of selection.
///
/// The optional scheduler is borrowed; otherwise an owned Android facade is
/// created. Cancellation closes the owned HTTP client immediately. Close retires
/// the lifetime, joins service operations, closes the queue and native config,
/// and attempts every cleanup even if another cleanup fails. Unsupported default
/// platforms throw; partial acquisition is always cleaned without data deletion.
Future<SubmissionBackgroundResources> openDefaultAndroidSubmissionResources({
  required SubmissionRunLifetime lifetime,
  SubmissionWakeScheduler? scheduler,
}) async {
  final configuration = AndroidSubmissionConfigurationStore();
  SubmissionQueueStore? queue;
  SubmissionService? service;
  http.Client? client;
  AndroidSubmissionBackgroundScheduler? ownedScheduler;
  Future<void>? closeFuture;
  var clientClosed = false;
  void closeClient() {
    if (!clientClosed && client != null) {
      clientClosed = true;
      client.close();
    }
  }

  void current() {
    if (!lifetime.isCurrent) throw StateError('Submission run is retired');
  }

  Future<void> cleanup() async {
    lifetime.retire();
    Object? failure;
    StackTrace? failureStack;
    Future<void> attempt(FutureOr<void> Function() action) async {
      try {
        await action();
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }

    await attempt(closeClient);
    if (service != null) await attempt(service.close);
    if (queue != null) await attempt(queue.close);
    await attempt(configuration.close);
    if (ownedScheduler != null) await attempt(ownedScheduler.close);
    if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
  }

  Future<void> close() => closeFuture ??= cleanup();
  try {
    current();
    final snapshot = await configuration.snapshot();
    current();
    queue = await openDefaultSubmissionQueueStore();
    current();
    final materials = await openDefaultCaptureStore();
    current();
    client = http.Client();
    unawaited(
      lifetime.cancelled.then((_) {
        try {
          closeClient();
        } catch (_) {
          // Retirement observes cleanup errors without leaking a late client error.
        }
      }),
    );
    final wake =
        scheduler ?? (ownedScheduler = AndroidSubmissionBackgroundScheduler());
    service = SubmissionService(
      queue: queue,
      materials: materials,
      scheduler: wake,
      referenceAccessPolicy: ConfiguredSubmissionReferenceAccessPolicy(
        configuration: configuration,
      ),
      storageAdapters: {
        for (final connection in snapshot.driveConnections)
          connection.id: DriveSubmissionStorageAdapter(
            connection: connection,
            client: client,
            credentials: configuration,
            isRunCurrent: () => lifetime.isCurrent,
            cancellation: lifetime.cancelled,
          ),
      },
      transports: {
        for (final connection in snapshot.httpConnections)
          connection.id: HttpSubmissionTransport(
            connection: connection,
            client: client,
            credentials: configuration,
            isRunCurrent: () => lifetime.isCurrent,
            cancellation: lifetime.cancelled,
          ),
      },
    );
    current();
    return SubmissionBackgroundResources(
      service: service,
      queue: queue,
      close: close,
    );
  } catch (error, stack) {
    try {
      await close();
    } catch (_) {
      // Partial acquisition cleanup must not obscure the initiating failure.
    }
    Error.throwWithStackTrace(error, stack);
  }
}
