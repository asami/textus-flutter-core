import 'dart:async';
import 'dart:math';

import 'registered_material_handoff_store.dart';
import 'registered_material_submission.dart';
import 'submission_adapters.dart';
import 'submission_connections.dart';
import 'submission_json.dart' as j;
import 'submission_queue_store.dart';
import 'submission_record.dart';
import 'tkl_material_delivery.dart';

enum RegisteredMaterialHandoffRunOutcome {
  noWork, offline, accepted, failed, outcomeUnknown, cancelled, leaseLost,
}

final class RegisteredMaterialHandoffRunResult {
  const RegisteredMaterialHandoffRunResult({required this.outcome, this.record});
  final RegisteredMaterialHandoffRunOutcome outcome;
  final RegisteredMaterialHandoffRecord? record;
}

/// Durable creation/reconciliation survives a safe wake failure.
final class RegisteredMaterialHandoffCommandResult {
  const RegisteredMaterialHandoffCommandResult({
    required this.record, this.schedulingFailed = false,
  });
  final RegisteredMaterialHandoffRecord record;
  final bool schedulingFailed;
}

/// Explicit Registered-source handoff; borrows every port and owns no timer loop.
/// Reads/enqueue never access credentials, originals, storage or TKL clients.
final class RegisteredMaterialHandoffService {
  RegisteredMaterialHandoffService({
    required SubmissionQueueStore queue,
    required RegisteredMaterialHandoffStore store,
    required Map<String, RegisteredMaterialSubmissionTransport> transports,
    required SubmissionWakeScheduler scheduler,
    DateTime Function()? now,
    this.leaseDuration = const Duration(minutes: 5),
    this.operationTimeout = const Duration(minutes: 1),
    // Public named parameters feed private borrowed fields.
    // ignore: prefer_initializing_formals
  }) : _queue = queue,
       // Public named parameters feed private borrowed fields.
       // ignore: prefer_initializing_formals
       _store = store,
       _transports = Map<String, RegisteredMaterialSubmissionTransport>.unmodifiable(transports),
       // Public named parameters feed private borrowed fields.
       // ignore: prefer_initializing_formals
       _scheduler = scheduler, _now = now ?? DateTime.now {
    if (operationTimeout <= Duration.zero || leaseDuration <= operationTimeout) {
      throw ArgumentError('Positive durations and lease > timeout are required');
    }
    for (final key in _transports.keys) { j.token(key); }
  }

  final SubmissionQueueStore _queue;
  final RegisteredMaterialHandoffStore _store;
  final Map<String, RegisteredMaterialSubmissionTransport> _transports;
  final SubmissionWakeScheduler _scheduler;
  final DateTime Function() _now;
  final Duration leaseDuration;
  final Duration operationTimeout;
  final Random _random = Random.secure();
  final Completer<void> _retired = Completer<void>();
  Future<void> _tail = Future<void>.value();
  bool _closing = false;
  Future<void>? _closeFuture;

  DateTime _time() => _now().toUtc();
  String _identity(String prefix) => '$prefix${List.generate(24,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';

  Future<T> _command<T>(Future<T> Function() action) {
    if (_closing) return Future<T>.error(StateError('Handoff service is closed'));
    final result = _tail.then((_) {
      _open();
      return action();
    });
    _tail = result.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return result;
  }

  void _open() {
    if (_closing) throw StateError('Handoff service is closed');
  }

  bool _current(bool Function()? predicate) {
    if (_closing) return false;
    try { return predicate?.call() ?? true; } catch (_) { return false; }
  }

  /// Reads the actual saved Registered source, then creates one immutable handoff.
  Future<RegisteredMaterialHandoffCommandResult> enqueueRegistered(
    String sourceRequestId, HttpSubmissionConnection target,
  ) => _command(() async {
    final source = await _queue.find(j.token(sourceRequestId));
    _open();
    if (source == null || source.state != SubmissionState.materialRegistered ||
        source.request.tklDelivery == null ||
        source.tklProgress?.state != TklMaterialDeliveryState.registered) {
      throw StateError('A saved Registered source is required');
    }
    final snapshot = source.tklProgress!;
    final packet = RegisteredMaterialSubmissionPacket(
      sourceRequest: source.request, target: target,
      association: RegisteredMaterialAssociation(
        materialRef: snapshot.materialRef!,
        resources: [for (var i = 0; i < source.request.materials.length; i++)
          RegisteredMaterialResource(key: source.request.materials[i].key,
            resourceId: snapshot.resources[i].resourceId)],
      ),
    );
    final saved = await _store.createHandoff(id: _identity('handoff'),
      source: source, target: target, packet: packet, now: _time());
    _open();
    return _wake(saved);
  });

  Future<RegisteredMaterialHandoffRecord?> findForSource(String sourceRequestId) =>
      _command(() async {
        final result = await _store.findHandoffForSource(j.token(sourceRequestId));
        _open();
        return result;
      });

  Future<List<RegisteredMaterialHandoffRecord>> list() => _command(() async {
    final result = await _store.listHandoffs();
    _open();
    return List<RegisteredMaterialHandoffRecord>.unmodifiable(result);
  });

  /// Explicit mutation: replays the same frozen packet/key/target, with a wake.
  Future<RegisteredMaterialHandoffCommandResult> reconcile(String sourceRequestId) =>
      _command(() async {
        final result = await _store.reconcileHandoff(
          sourceRequestId: j.token(sourceRequestId), now: _time());
        _open();
        return _wake(result);
      });

  Future<RegisteredMaterialHandoffCommandResult> _wake(RegisteredMaterialHandoffRecord record) async {
    if (record.state != RegisteredMaterialHandoffState.pending) {
      return RegisteredMaterialHandoffCommandResult(record: record);
    }
    try {
      _open();
      await _scheduler.requestRun();
      _open();
      return RegisteredMaterialHandoffCommandResult(record: record);
    } catch (_) {
      _open();
      return RegisteredMaterialHandoffCommandResult(record: record, schedulingFailed: true);
    }
  }

  /// Only pending work dispatches. Unknown/failed results require reconcile.
  /// An ACK save error propagates; the durable sending/unknown row cannot accept
  /// a late result. Cancellation and timeouts observe/discard late transport work.
  Future<RegisteredMaterialHandoffRunResult> processNext({
    required bool networkAllowed, bool Function()? isRunCurrent,
  }) => _command(() async {
    if (!_current(isRunCurrent)) {
      return const RegisteredMaterialHandoffRunResult(
        outcome: RegisteredMaterialHandoffRunOutcome.cancelled);
    }
    if (!networkAllowed) {
      return const RegisteredMaterialHandoffRunResult(
        outcome: RegisteredMaterialHandoffRunOutcome.offline);
    }
    final claim = await _store.claimNextHandoff(now: _time(),
      leaseToken: _identity('lease'), leaseDuration: leaseDuration);
    if (claim == null) {
      return RegisteredMaterialHandoffRunResult(
        outcome: _current(isRunCurrent) ? RegisteredMaterialHandoffRunOutcome.noWork
            : RegisteredMaterialHandoffRunOutcome.cancelled);
    }
    try {
      if (!_current(isRunCurrent)) return await _finishUnknown(claim, 'runRetired');
      final transport = _transports[claim.target.id];
      if (transport == null || !sameRegisteredMaterialTarget(transport.connection, claim.target)) {
        final saved = await _store.finishHandoff(id: claim.id,
          leaseToken: claim.leaseToken!, now: _time(),
          state: RegisteredMaterialHandoffState.failed,
          failure: RegisteredMaterialHandoffFailure(
            kind: RegisteredMaterialHandoffFailureKind.configuration,
            code: 'connectionMismatch', message: 'The frozen Studio target is unavailable.',
          ));
        return RegisteredMaterialHandoffRunResult(
          outcome: RegisteredMaterialHandoffRunOutcome.failed, record: saved);
      }
      if (!_current(isRunCurrent)) return await _finishUnknown(claim, 'runRetired');
      SubmissionAcknowledgement acknowledgement;
      try {
        acknowledgement = await Future.any<SubmissionAcknowledgement>([
          Future<SubmissionAcknowledgement>.sync(
            () => transport.submitRegisteredMaterial(claim.packet)).timeout(operationTimeout),
          _retired.future.then<SubmissionAcknowledgement>((_) => throw const _HandoffRetired()),
        ]);
      } on SubmissionAdapterException catch (error) {
        if (!_current(isRunCurrent) ||
            error.transportFailureOutcome == SubmissionTransportFailureOutcome.unknown) {
          return await _finishUnknown(claim, 'acceptanceUnknown');
        }
        final notSent = error.transportFailureOutcome == SubmissionTransportFailureOutcome.notSent;
        final saved = await _store.finishHandoff(id: claim.id,
          leaseToken: claim.leaseToken!, now: _time(), state: RegisteredMaterialHandoffState.failed,
          failure: RegisteredMaterialHandoffFailure(
            kind: notSent ? RegisteredMaterialHandoffFailureKind.notSent
                : RegisteredMaterialHandoffFailureKind.rejected,
            code: notSent ? 'handoffNotSent' : 'handoffRejected',
            message: notSent ? 'The Studio handoff was not sent.' : 'Studio refused this handoff.',
          ));
        return RegisteredMaterialHandoffRunResult(
          outcome: RegisteredMaterialHandoffRunOutcome.failed, record: saved);
      } catch (_) {
        return await _finishUnknown(claim, 'acceptanceUnknown');
      }
      if (!_current(isRunCurrent)) return await _finishUnknown(claim, 'runRetired');
      if (acknowledgement.requestId != claim.sourceRequest.id ||
          acknowledgement.subjectId != claim.sourceRequest.subjectId) {
        return await _finishUnknown(claim, 'acknowledgementMismatch');
      }
      // Keep the durable ACK save outside the transport-failure catch. Failure
      // propagates without rewriting the existing sending checkpoint.
      final saved = await _store.finishHandoff(id: claim.id,
        leaseToken: claim.leaseToken!, now: _time(),
        state: RegisteredMaterialHandoffState.accepted, acknowledgement: acknowledgement);
      return RegisteredMaterialHandoffRunResult(
        outcome: _current(isRunCurrent) ? RegisteredMaterialHandoffRunOutcome.accepted
            : RegisteredMaterialHandoffRunOutcome.cancelled,
        record: saved);
    } on RegisteredMaterialHandoffLeaseLostException {
      return RegisteredMaterialHandoffRunResult(
        outcome: RegisteredMaterialHandoffRunOutcome.leaseLost, record: claim);
    }
  });

  Future<RegisteredMaterialHandoffRunResult> _finishUnknown(
    RegisteredMaterialHandoffRecord claim, String code,
  ) async {
    try {
      final saved = await _store.finishHandoff(id: claim.id,
        leaseToken: claim.leaseToken!, now: _time(),
        state: RegisteredMaterialHandoffState.outcomeUnknown,
        failure: RegisteredMaterialHandoffFailure(
          kind: RegisteredMaterialHandoffFailureKind.outcomeUnknown,
          code: code, message: 'Studio acceptance is unknown; explicit reconciliation is required.',
        ));
      return RegisteredMaterialHandoffRunResult(
        outcome: RegisteredMaterialHandoffRunOutcome.outcomeUnknown, record: saved);
    } on RegisteredMaterialHandoffLeaseLostException {
      return RegisteredMaterialHandoffRunResult(
        outcome: RegisteredMaterialHandoffRunOutcome.leaseLost, record: claim);
    }
  }

  /// Fences immediately, drains accepted commands and never closes borrowed ports.
  Future<void> close() {
    _closing = true;
    if (!_retired.isCompleted) _retired.complete();
    return _closeFuture ??= _tail;
  }
}

final class _HandoffRetired implements Exception { const _HandoffRetired(); }
