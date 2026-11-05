import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../repository/file_capture_store.dart';
import '../repository/local_capture_store.dart';
import 'drive_submission_storage_adapter.dart';
import 'http_submission_transport.dart';
import 'ios_submission_configuration.dart';
import 'ios_submission_foreground_scheduler.dart';
import 'registered_material_handoff_service.dart';
import 'registered_material_handoff_store.dart';
import 'sqlite_submission_queue_store.dart';
import 'submission_adapters.dart';
import 'submission_background_resources.dart';
import 'submission_connections.dart';
import 'submission_queue_store.dart';
import 'submission_reference_access.dart';
import 'submission_run_lifetime.dart';
import 'submission_service.dart';
import 'tkl_material_delivery_http_client.dart';

/// Opens an inert foreground-only iOS composition over the durable default roots.
/// Credentials and a supplied scheduler are borrowed. An owned default scheduler
/// uses fresh batch configuration/services over this exact shared queue handle.
/// No wake, credential read, network operation or consent occurs during open.
Future<SubmissionBackgroundResources> openDefaultIosSubmissionResources({
  required SubmissionRunLifetime lifetime,
  SubmissionWakeScheduler? scheduler,
  SubmissionCredentialProvider? credentials,
}) => _openIosSubmissionResources(
  lifetime: lifetime,
  scheduler: scheduler,
  credentials: credentials,
);

Future<SubmissionBackgroundResources> _openIosSubmissionResources({
  required SubmissionRunLifetime lifetime,
  SubmissionWakeScheduler? scheduler,
  SubmissionCredentialProvider? credentials,
  SubmissionQueueStore? borrowedQueue,
  LocalCaptureStore? borrowedMaterials,
}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
    throw UnsupportedError('iOS submission resources are unsupported here');
  }
  final owner = _IosSubmissionResourceOwner(
    lifetime: lifetime,
    ownsQueue: borrowedQueue == null,
  );
  try {
    owner.current();
    owner.configuration = await IosSubmissionConfigurationStore.open(
      credentials: credentials,
    );
    owner.current();
    final snapshot = await owner.configuration!.snapshot();
    owner.current();
    owner.queue = borrowedQueue ?? await openDefaultSubmissionQueueStore();
    owner.current();
    final materials = borrowedMaterials ?? await openDefaultCaptureStore();
    owner.current();
    final queue = owner.queue!;
    final configuration = owner.configuration!;
    final wake =
        scheduler ??
        (owner.scheduler = IosSubmissionForegroundScheduler(
          openResources: ({required lifetime, required scheduler}) =>
              _openIosSubmissionResources(
                lifetime: lifetime,
                scheduler: scheduler,
                credentials: credentials,
                borrowedQueue: queue,
                borrowedMaterials: materials,
              ),
        ));
    owner.current();
    final client = owner.client = http.Client();
    unawaited(
      lifetime.cancelled.then((_) {
        try {
          owner.closeClient();
        } catch (_) {
          // The explicit owner cleanup reports only its fixed safe failure.
          owner.cleanupFailed = true;
        }
      }),
    );
    owner.current();
    final transports = {
      for (final connection in snapshot.httpConnections)
        connection.id: HttpSubmissionTransport(
          connection: connection,
          client: client,
          credentials: configuration,
          isRunCurrent: () => lifetime.isCurrent,
          cancellation: lifetime.cancelled,
        ),
    };
    owner.current();
    if (queue is! RegisteredMaterialHandoffStore) {
      throw StateError(
        'Default queue lacks registered Material handoff storage',
      );
    }
    final handoffs = owner.handoffs = RegisteredMaterialHandoffService(
      queue: queue,
      store: queue as RegisteredMaterialHandoffStore,
      transports: transports,
      scheduler: wake,
    );
    owner.current();
    final service = owner.service = SubmissionService(
      queue: queue,
      materials: materials,
      scheduler: wake,
      registeredMaterialHandoffs: handoffs,
      referenceAccessPolicy: ConfiguredSubmissionReferenceAccessPolicy(
        configuration: configuration,
      ),
      tklClients: {
        for (final connection in snapshot.httpConnections.where(
          (connection) =>
              connection.requiresBearerToken &&
              connection.endpoint.path.endsWith('/'),
        ))
          connection.id: TklMaterialDeliveryHttpClient(
            connection: connection,
            client: client,
            credentials: configuration,
            isRunCurrent: () => lifetime.isCurrent,
            cancellation: lifetime.cancelled,
          ),
      },
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
      transports: transports,
    );
    owner.current();
    return SubmissionBackgroundResources(
      service: service,
      queue: queue,
      executionMode: SubmissionExecutionMode.foreground,
      close: owner.close,
    );
  } catch (_) {
    try {
      await owner.close();
    } catch (_) {
      // Attempt every partial owner's cleanup while preserving a safe open error.
    }
    throw StateError('iOS submission resources are unavailable');
  }
}

final class _IosSubmissionResourceOwner {
  _IosSubmissionResourceOwner({
    required this.lifetime,
    required this.ownsQueue,
  });

  final SubmissionRunLifetime lifetime;
  final bool ownsQueue;
  IosSubmissionConfigurationStore? configuration;
  SubmissionQueueStore? queue;
  SubmissionService? service;
  RegisteredMaterialHandoffService? handoffs;
  http.Client? client;
  IosSubmissionForegroundScheduler? scheduler;
  bool cleanupFailed = false;
  bool _clientClosed = false;
  Future<void>? _closeFuture;
  Future<void>? _schedulerDrain;

  void current() {
    if (!lifetime.isCurrent) throw StateError('Submission run is retired');
  }

  void closeClient() {
    if (!_clientClosed && client != null) {
      _clientClosed = true;
      client!.close();
    }
  }

  Future<void> _attempt(FutureOr<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      cleanupFailed = true;
    }
  }

  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;
    final completion = Completer<void>();
    _closeFuture = completion.future;
    lifetime.retire();
    // Invoke and observe scheduler retirement before the first cleanup await.
    // A transient owner has no owned scheduler and never closes the shared one.
    if (scheduler != null) _schedulerDrain = _attempt(scheduler!.close);
    unawaited(
      _cleanup().then(
        (_) => completion.complete(),
        onError: (Object error, StackTrace stack) {
          completion.completeError(
            StateError('iOS submission resources could not be closed'),
          );
        },
      ),
    );
    return completion.future;
  }

  Future<void> _cleanup() async {
    await _attempt(closeClient);
    if (handoffs != null) await _attempt(handoffs!.close);
    if (service != null) await _attempt(service!.close);
    await _schedulerDrain;
    if (ownsQueue && queue != null) await _attempt(queue!.close);
    if (configuration != null) await _attempt(configuration!.close);
    if (cleanupFailed) {
      throw StateError('iOS submission resources could not be closed');
    }
  }
}
