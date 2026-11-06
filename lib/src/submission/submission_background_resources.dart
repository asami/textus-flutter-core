import 'dart:async';

import 'package:http/http.dart' as http;

import '../authentication/user_account_http_authentication_backend.dart';
import '../repository/file_capture_store.dart';
import 'android_submission_background.dart';
import 'android_submission_configuration.dart';
import 'drive_submission_storage_adapter.dart';
import 'http_submission_transport.dart';
import 'registered_material_handoff_service.dart';
import 'registered_material_handoff_store.dart';
import 'sqlite_submission_queue_store.dart';
import 'submission_adapters.dart';
import 'submission_configuration.dart';
import 'submission_participant_runtime.dart';
import 'submission_queue_store.dart';
import 'submission_reference_access.dart';
import 'submission_run_lifetime.dart';
import 'submission_service.dart';
import 'tkl_material_delivery_http_client.dart';

/// Observed execution capability; never queue, network or identity authority.
enum SubmissionExecutionMode { unknown, foreground, background }

/// Caller-owned service/queue composition. A runner only borrows these resources.
final class SubmissionBackgroundResources {
  /// Retains the owner's cleanup callback. Custom compositions must make close
  /// idempotent and drain service work before closing the queue; never close
  /// borrowed ports. The default factory supplies these guarantees.
  const SubmissionBackgroundResources({
    required this.service,
    required this.queue,
    required Future<void> Function() close,
    this.executionMode = SubmissionExecutionMode.unknown,
    // Preserve the public named close callback while storing it privately.
    // ignore: prefer_initializing_formals
  }) : _close = close;

  /// Owned or explicitly borrowed service, as declared by the composing owner.
  final SubmissionService service;

  /// Same durable queue used by the service, borrowed by a runner.
  final SubmissionQueueStore queue;

  /// Platform execution capability for presentation, independent of readiness.
  final SubmissionExecutionMode executionMode;
  final Future<void> Function() _close;

  /// Executes the owner's cleanup; runners never call this operation.
  Future<void> close() => _close();
}

/// Opens an owned Android composition over the existing default application
/// support queue/original roots. Opening is inert unless declared participant
/// authentication restoration is explicitly requested by the headless owner.
/// A supplied authentication scope is borrowed without credential or network IO.
///
/// The optional scheduler is borrowed; otherwise an owned Android facade is
/// created. Cancellation closes the owned HTTP client immediately. Close retires
/// the lifetime, joins service operations, closes the queue and native config,
/// and attempts every cleanup even if another cleanup fails. Unsupported default
/// platforms throw; partial acquisition is always cleaned without data deletion.
Future<SubmissionBackgroundResources> openDefaultAndroidSubmissionResources({
  required SubmissionRunLifetime lifetime,
  SubmissionWakeScheduler? scheduler,
  UserAccountSubmissionScope? authenticationScope,
  bool restoreParticipantAuthentication = false,
  bool requiresAuthentication = false,
}) async {
  final configuration = AndroidSubmissionConfigurationStore();
  SubmissionQueueStore? queue;
  SubmissionService? service;
  RegisteredMaterialHandoffService? handoffs;
  SubmissionParticipantRuntime? participant;
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
    var cleanupFailed = false;
    Future<void> attempt(FutureOr<void> Function() action) async {
      try {
        await action();
      } catch (_) {
        cleanupFailed = true;
      }
    }

    await attempt(closeClient);
    if (handoffs != null) await attempt(handoffs.close);
    if (service != null) await attempt(service.close);
    if (participant != null) await attempt(participant.close);
    if (queue != null) await attempt(queue.close);
    await attempt(configuration.close);
    if (ownedScheduler != null) await attempt(ownedScheduler.close);
    if (cleanupFailed) {
      throw SubmissionConfigurationException.safe('configurationUnavailable');
    }
  }

  Future<void> close() => closeFuture ??= cleanup();
  try {
    current();
    final snapshot = await configuration.snapshot();
    current();
    final authentication = participant = await SubmissionParticipantRuntime.open(
      snapshot: snapshot,
      legacyCredentials: configuration,
      lifetime: lifetime,
      authenticationScope: authenticationScope,
      restoreParticipantAuthentication: restoreParticipantAuthentication,
      requiresAuthentication: requiresAuthentication,
    );
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
    bool runCurrent() => lifetime.isCurrent && authentication.isCurrent;
    final transports = {
      for (final connection in snapshot.httpConnections.where(
        authentication.permits,
      ))
        connection.id: HttpSubmissionTransport(
          connection: connection,
          client: client,
          credentials: authentication.credentials,
          isRunCurrent: runCurrent,
          cancellation: lifetime.cancelled,
        ),
    };
    final handoffStore = queue;
    if (handoffStore is! RegisteredMaterialHandoffStore) {
      throw StateError('Default queue lacks registered Material handoff storage');
    }
    handoffs = RegisteredMaterialHandoffService(
      queue: queue, store: handoffStore as RegisteredMaterialHandoffStore,
      transports: transports, scheduler: wake,
      requiresAuthentication: authentication.requiresAuthentication,
      authenticationContext: authentication.authenticationContext,
    );
    service = SubmissionService(
      queue: queue,
      materials: materials,
      scheduler: wake,
      registeredMaterialHandoffs: handoffs,
      requiresAuthentication: authentication.requiresAuthentication,
      authenticationContext: authentication.authenticationContext,
      referenceAccessPolicy: ConfiguredSubmissionReferenceAccessPolicy(
        configuration: configuration,
      ),
      tklClients: {
        for (final connection in snapshot.httpConnections.where(
          (connection) =>
              authentication.permits(connection) &&
              connection.requiresBearerToken &&
              connection.endpoint.path.endsWith('/'),
        ))
          connection.id: TklMaterialDeliveryHttpClient(
            connection: connection,
            client: client,
            credentials: authentication.credentials,
            authenticationBinding: authentication.binding,
            isRunCurrent: runCurrent,
            cancellation: lifetime.cancelled,
          ),
      },
      storageAdapters: {
        for (final connection in snapshot.driveConnections)
          connection.id: DriveSubmissionStorageAdapter(
            connection: connection,
            client: client,
            credentials: configuration,
            isRunCurrent: runCurrent,
            cancellation: lifetime.cancelled,
          ),
      },
      transports: transports,
    );
    current();
    return SubmissionBackgroundResources(
      service: service,
      queue: queue,
      close: close,
      executionMode: SubmissionExecutionMode.background,
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
