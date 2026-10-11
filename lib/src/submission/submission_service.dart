import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../repository/local_capture_store.dart';
import 'submission_adapters.dart';
import 'submission_configuration.dart';
import 'submission_json.dart' as j;
import 'submission_queue_store.dart';
import 'submission_record.dart';
import 'submission_reference_access.dart';
import 'submission_request.dart';
import 'submission_transfer_status.dart';

/// Safe scheduler notice; durable intent remains queued despite this notice.
final class SubmissionSchedulingFailure {
  /// Validates safe structured fields; no raw scheduler exception is retained.
  SubmissionSchedulingFailure({required String code, required String message})
    : code = j.token(code),
      message = j.descriptive(message);

  /// Safe diagnostic token.
  final String code;

  /// Safe fixed user-facing message.
  final String message;
  @override
  bool operator ==(Object other) =>
      other is SubmissionSchedulingFailure &&
      code == other.code &&
      message == other.message;
  @override
  int get hashCode => Object.hash(code, message);
}

/// Durable Commit/retry/wake result, optionally with a safe scheduling notice.
final class SubmissionCommitResult {
  /// Retains the immutable durable record and optional scheduling failure.
  const SubmissionCommitResult({required this.record, this.schedulingFailure});

  /// Last accepted queue snapshot; scheduler failure does not undo it.
  final SubmissionRecord record;

  /// Null when scheduling succeeds or submitted intent needs no wake.
  final SubmissionSchedulingFailure? schedulingFailure;
  @override
  bool operator ==(Object other) =>
      other is SubmissionCommitResult &&
      record == other.record &&
      schedulingFailure == other.schedulingFailure;
  @override
  int get hashCode => Object.hash(record, schedulingFailure);
}

/// Observable result of a bounded invocation of the queue driver.
enum SubmissionRunOutcome {
  noWork,
  offline,
  progress,
  submitted,
  failed,
  cancelled,
  leaseLost,
}

/// Driver result. Cancellation before claim/offline/no work may have no record;
/// otherwise the known latest snapshot is returned when available.
final class SubmissionRunResult {
  /// Retains only a safe outcome and immutable optional queue snapshot.
  const SubmissionRunResult({required this.outcome, this.record});

  /// Driver outcome; progress is one prepared/uploaded material checkpoint.
  final SubmissionRunOutcome outcome;

  /// Latest known durable snapshot, or null when no row was selected.
  final SubmissionRecord? record;
  @override
  bool operator ==(Object other) =>
      other is SubmissionRunResult &&
      outcome == other.outcome &&
      record == other.record;
  @override
  int get hashCode => Object.hash(outcome, record);
}

/// Serialized explicit intent and bounded resumable queue driver.
///
/// Queue, originals, connections, access policy and scheduler are borrowed and never closed by
/// this service. No background actor is started. Caller/native driver pumps one
/// operation per processNext. Every public call after close throws [StateError].
final class SubmissionService {
  /// Freezes connection maps and validates provider tokens and positive durations.
  /// Lease duration must exceed the operation timeout. Clock values normalize to
  /// UTC; lease expiry follows supplied wall time, including clock rollback.
  /// Omitted/null access policy is unknown and denies dispatch with materials.
  SubmissionService({
    required this._queue,
    required this._materials,
    required Map<String, SubmissionStorageAdapter> storageAdapters,
    required Map<String, SubmissionTransport> transports,
    required this._scheduler,
    this._referenceAccessPolicy,
    DateTime Function()? now,
    this.leaseDuration = const Duration(minutes: 5),
    this.operationTimeout = const Duration(minutes: 1),
    this.automaticRetryDelay = const Duration(seconds: 30),
  }) : _storage = Map<String, SubmissionStorageAdapter>.unmodifiable(
         storageAdapters,
       ),
       _transports = Map<String, SubmissionTransport>.unmodifiable(transports),
       _now = now ?? DateTime.now {
    if (operationTimeout <= Duration.zero ||
        leaseDuration <= operationTimeout ||
        automaticRetryDelay <= Duration.zero) {
      throw ArgumentError(
        'Positive durations and lease > timeout are required',
      );
    }
    for (final e in _storage.entries) {
      j.token(e.key);
      j.token(e.value.providerId);
    }
    for (final e in _transports.entries) {
      j.token(e.key);
      j.token(e.value.providerId);
    }
  }

  final SubmissionQueueStore _queue;
  final LocalCaptureStore _materials;
  final SubmissionWakeScheduler _scheduler;
  final SubmissionReferenceAccessPolicy? _referenceAccessPolicy;
  final Map<String, SubmissionStorageAdapter> _storage;
  final Map<String, SubmissionTransport> _transports;
  final DateTime Function() _now;
  final Random _random = Random.secure();

  /// Fresh lease duration renewed immediately before each remote dispatch.
  final Duration leaseDuration;

  /// Bound for a single adapter operation; late completion is observed/discarded.
  final Duration operationTimeout;

  /// Positive automatic retry delay for safe retryable adapter failures.
  final Duration automaticRetryDelay;
  Future<void> _tail = Future<void>.value();
  final Set<Future<void>> _reads = {};
  final Map<String, SubmissionRecord> _claims = {};
  bool _closing = false;
  Future<void>? _closeFuture;

  DateTime _time() => _now().toUtc();

  Future<T> _command<T>(Future<T> Function() action) {
    if (_closing) {
      return Future<T>.error(StateError('Submission service is closed'));
    }
    final result = _tail.then((_) {
      if (_closing) throw StateError('Submission service is closed');
      return action();
    });
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<T> _read<T>(Future<T> Function() action) {
    if (_closing) {
      return Future<T>.error(StateError('Submission service is closed'));
    }
    final result = Future<T>.sync(action);
    final settled = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    _reads.add(settled);
    settled.then((_) => _reads.remove(settled));
    return result;
  }

  /// Validates every new original before atomically enqueueing explicit intent.
  /// Equal existing intent avoids original reads. Conflicts/IO fail before wake;
  /// wake failure after durable enqueue returns a safe notice, without rollback.
  Future<SubmissionCommitResult> commit(SubmissionRequest request) =>
      _command(() async {
        final existing = await _queue.find(request.id);
        if (existing != null) {
          if (existing.request != request) {
            throw StateError('Conflicting request id');
          }
          return _wake(existing);
        }
        final subject = await _queue.findForSubject(
          request.kind,
          request.subjectId,
        );
        if (subject != null) {
          throw StateError('Subject already has immutable intent');
        }
        for (final material in request.materials) {
          if (_closing) throw StateError('Submission service is closed');
          try {
            final bytes = await _materials.readMaterial(material.original);
            if (bytes.length != material.original.byteLength) {
              throw StateError('Original length mismatch');
            }
          } catch (_) {
            throw SubmissionAdapterException(
              stage: SubmissionFailureStage.localMaterial,
              code: 'originalUnavailable',
              message: 'Original material is missing or invalid.',
              retryable: false,
            );
          }
        }
        if (_closing) throw StateError('Submission service is closed');
        final record = await _queue.enqueue(request);
        return _wake(record);
      });

  /// Explicitly requeues failure before requesting a wake; unknown/active id
  /// fails without scheduling. Submitted is unchanged and needs no wake.
  Future<SubmissionCommitResult> retry(String id) => _command(() async {
    final record = await _queue.retry(id: id, now: _time());
    return _wake(record);
  });

  /// Reads existing intent freshly in command order and requests its usual wake.
  /// Missing ids throw [StateError]; submitted needs no wake. Every other queue
  /// state may request wake without requeueing, claiming or any remote operation.
  /// Scheduler failure returns a safe notice; borrowed resources stay open.
  Future<SubmissionCommitResult> requestRun(String id) => _command(() async {
    final record = await _queue.find(id);
    if (record == null) throw StateError('Unknown submission');
    return _wake(record);
  });

  Future<SubmissionCommitResult> _wake(SubmissionRecord record) async {
    if (record.state == SubmissionState.submitted) {
      return SubmissionCommitResult(record: record);
    }
    try {
      await _scheduler.requestRun();
      return SubmissionCommitResult(record: record);
    } catch (_) {
      return SubmissionCommitResult(
        record: record,
        schedulingFailure: SubmissionSchedulingFailure(
          code: 'wakeUnavailable',
          message:
              'Submission is queued; scheduling is temporarily unavailable.',
        ),
      );
    }
  }

  /// Strict uncached borrowed queue read; null only when absent.
  Future<SubmissionRecord?> find(String id) => _read(() => _queue.find(id));

  /// Strict uncached borrowed queue read by safe consumer kind/subject.
  Future<SubmissionRecord?> findForSubject(String kind, String subjectId) =>
      _read(() => _queue.findForSubject(kind, subjectId));

  /// Strict immutable borrowed queue list; persistence/corruption errors propagate.
  Future<List<SubmissionRecord>> list() => _read(_queue.list);

  /// Fresh queue and local access observation by id; absent returns null before
  /// policy IO. No wake, claim, retry, credentials, originals or network calls.
  /// Policy failure/timeout throws fixed configurationUnavailable; queue errors
  /// propagate. Close joins this bounded read and rejects any late result.
  Future<SubmissionTransferStatus?> findTransferStatus(
    String id, {
    required DateTime observedAt,
    SubmissionNetworkState networkState = SubmissionNetworkState.unknown,
  }) => _read(() async {
    final record = await _queue.find(id);
    _queryOpen();
    if (record == null) return null;
    return _transferStatus(record, observedAt, networkState);
  });

  /// Same strict current observation by exact consumer kind/subject. Network
  /// observation defaults independently to unknown on every call, never cached.
  Future<SubmissionTransferStatus?> findTransferStatusForSubject(
    String kind,
    String subjectId, {
    required DateTime observedAt,
    SubmissionNetworkState networkState = SubmissionNetworkState.unknown,
  }) => _read(() async {
    final record = await _queue.findForSubject(kind, subjectId);
    _queryOpen();
    if (record == null) return null;
    return _transferStatus(record, observedAt, networkState);
  });

  /// Immutable fresh list, evaluating required reference observations separately
  /// for each durable record. Partial upload, submitted and no-upload skip policy.
  /// No observation is persisted; failure is an error rather than an empty list.
  Future<List<SubmissionTransferStatus>> listTransferStatuses({
    required DateTime observedAt,
    SubmissionNetworkState networkState = SubmissionNetworkState.unknown,
  }) => _read(() async {
    final records = await _queue.list();
    _queryOpen();
    final statuses = <SubmissionTransferStatus>[];
    for (final record in records) {
      statuses.add(await _transferStatus(record, observedAt, networkState));
      _queryOpen();
    }
    return List<SubmissionTransferStatus>.unmodifiable(statuses);
  });

  void _queryOpen() {
    if (_closing) throw StateError('Submission service is closed');
  }

  Future<SubmissionReferenceAccessState> _access(SubmissionPacket packet) {
    final policy = _referenceAccessPolicy;
    if (policy == null) {
      return Future.value(SubmissionReferenceAccessState.unknown);
    }
    return Future<SubmissionReferenceAccessState>.sync(
      () => policy.evaluate(packet),
    ).timeout(operationTimeout);
  }

  Future<SubmissionTransferStatus> _transferStatus(
    SubmissionRecord record,
    DateTime observedAt,
    SubmissionNetworkState networkState,
  ) async {
    _queryOpen();
    var access = SubmissionReferenceAccessState.unknown;
    if (record.acknowledgement == null &&
        record.request.materials.isNotEmpty &&
        record.receipts.length == record.request.materials.length) {
      final packet = SubmissionPacket(
        request: record.request,
        receipts: record.receipts,
      );
      try {
        access = await _access(packet);
      } catch (_) {
        _queryOpen();
        throw SubmissionConfigurationException.safe('configurationUnavailable');
      }
      _queryOpen();
    }
    return SubmissionTransferStatus.fromRecord(
      record,
      observedAt: observedAt,
      networkState: networkState,
      referenceAccessState: access,
    );
  }

  Future<void> _guardReferenceAccess(
    SubmissionPacket packet,
    bool Function()? predicate,
  ) async {
    _guard(predicate);
    if (packet.request.materials.isEmpty) return;
    SubmissionReferenceAccessState access;
    try {
      access = await _access(packet);
    } catch (_) {
      _guard(predicate);
      throw const _StageFailure(
        SubmissionFailureStage.configuration,
        'referenceAccessUnavailable',
        'Server access configuration is unavailable.',
        true,
        transportFailureOutcome: SubmissionTransportFailureOutcome.notSent,
      );
    }
    _guard(predicate);
    if (access != SubmissionReferenceAccessState.available) {
      throw const _StageFailure(
        SubmissionFailureStage.configuration,
        'referenceAccessRequired',
        'Server access to uploaded materials must be configured.',
        false,
        transportFailureOutcome: SubmissionTransportFailureOutcome.notSent,
      );
    }
  }

  bool _current(bool Function()? predicate) {
    if (_closing) return false;
    try {
      return predicate?.call() ?? true;
    } catch (error, stack) {
      throw _PredicateError(error, stack);
    }
  }

  void _guard(bool Function()? predicate) {
    if (!_current(predicate)) throw const _Cancelled();
  }

  String _token() =>
      'lease_${List.generate(24, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';

  Future<SubmissionRecord> _renew(
    SubmissionRecord record,
    bool Function()? predicate,
  ) async {
    _guard(predicate);
    final renewed = await _queue.renewLease(
      id: record.request.id,
      leaseToken: record.leaseToken!,
      now: _time(),
      leaseDuration: leaseDuration,
    );
    _claims[record.request.id] = renewed;
    _guard(predicate);
    return renewed;
  }

  Future<T> _remote<T>(
    SubmissionFailureStage stage,
    Future<T> Function() action,
  ) async {
    try {
      // Future.timeout observes the original future even after a late result;
      // only the awaited timed result is allowed to reach a checkpoint.
      return await Future<T>.sync(action).timeout(operationTimeout);
    } on SubmissionAdapterException catch (error) {
      throw _StageFailure(
        error.stage,
        error.code,
        error.message,
        error.retryable,
        transportFailureOutcome: error.transportFailureOutcome,
      );
    } on TimeoutException {
      throw _StageFailure(
        stage,
        'operationTimeout',
        'Submission operation timed out.',
        true,
      );
    } catch (_) {
      throw _StageFailure(
        stage,
        'operationFailed',
        'Submission operation could not be completed.',
        true,
      );
    }
  }

  /// Offline returns before any queue/original/adapter/scheduler call. Online
  /// performs at most one prepare, upload or transport operation. Valid owner
  /// cancellation releases to ready; lost ownership never changes another claim.
  /// DB/corruption/write errors propagate without local acknowledgement. Predicate
  /// exceptions best-effort release the valid claim then propagate the primary
  /// error. Remote idempotency remains required after timeout or local write loss.
  Future<SubmissionRunResult> processNext({
    required bool networkAllowed,
    bool Function()? isRunCurrent,
  }) => _command(() async {
    if (!networkAllowed) {
      return const SubmissionRunResult(outcome: SubmissionRunOutcome.offline);
    }
    SubmissionRecord? record;
    try {
      if (!_current(isRunCurrent)) {
        return const SubmissionRunResult(
          outcome: SubmissionRunOutcome.cancelled,
        );
      }
      record = await _queue.claimNext(
        now: _time(),
        leaseToken: _token(),
        leaseDuration: leaseDuration,
      );
      if (record == null) {
        return const SubmissionRunResult(outcome: SubmissionRunOutcome.noWork);
      }
      _claims[record.request.id] = record;
      _guard(isRunCurrent);
      final request = record.request;
      for (final material in request.materials) {
        if (record!.reservations.containsKey(material.key)) continue;
        final storage = _storage[request.storageConnectionId];
        if (storage == null) {
          throw const _StageFailure(
            SubmissionFailureStage.configuration,
            'storageMissing',
            'Storage connection is not configured.',
            false,
          );
        }
        record = await _renew(record, isRunCurrent);
        final prepared = await _remote(
          SubmissionFailureStage.storage,
          () => storage.prepare(request: request, material: material),
        );
        _guard(isRunCurrent);
        if (prepared.key != material.key ||
            prepared.providerId != storage.providerId) {
          throw const _StageFailure(
            SubmissionFailureStage.configuration,
            'reservationMismatch',
            'Storage reservation does not match.',
            false,
          );
        }
        record = await _queue.saveReservation(
          id: request.id,
          leaseToken: record.leaseToken!,
          reservation: prepared,
          now: _time(),
        );
        _claims[request.id] = record;
        _guard(isRunCurrent);
        return await _release(record, SubmissionRunOutcome.progress);
      }
      for (final material in request.materials) {
        final storage = _storage[request.storageConnectionId];
        if (storage == null) {
          throw const _StageFailure(
            SubmissionFailureStage.configuration,
            'storageMissing',
            'Storage connection is not configured.',
            false,
          );
        }
        final reservation = record!.reservations[material.key]!;
        if (reservation.providerId != storage.providerId) {
          throw const _StageFailure(
            SubmissionFailureStage.configuration,
            'providerMismatch',
            'Storage provider does not match reservation.',
            false,
          );
        }
        if (!record.receipts.containsKey(material.key)) {
          final bytes = await _original(material);
          _guard(isRunCurrent);
          record = await _renew(record, isRunCurrent);
          final receipt = await _remote(
            SubmissionFailureStage.storage,
            () => storage.upload(
              request: request,
              material: material,
              reservation: reservation,
              bytes: bytes,
            ),
          );
          _guard(isRunCurrent);
          if (receipt.key != material.key ||
              receipt.providerId != storage.providerId) {
            throw const _StageFailure(
              SubmissionFailureStage.configuration,
              'receiptMismatch',
              'Storage receipt does not match reservation.',
              false,
            );
          }
          record = await _queue.saveReceipt(
            id: request.id,
            leaseToken: record.leaseToken!,
            receipt: receipt,
            now: _time(),
          );
          _claims[request.id] = record;
          _guard(isRunCurrent);
          return await _release(record, SubmissionRunOutcome.progress);
        }
      }
      final transport = _transports[request.transportConnectionId];
      if (transport == null) {
        throw const _StageFailure(
          SubmissionFailureStage.configuration,
          'transportMissing',
          'Transport connection is not configured.',
          false,
        );
      }
      final packet = SubmissionPacket(
        request: request,
        receipts: record!.receipts,
      );
      await _guardReferenceAccess(packet, isRunCurrent);
      _guard(isRunCurrent);
      record = await _queue.markTransportDispatch(
        id: request.id,
        leaseToken: record.leaseToken!,
        now: _time(),
      );
      _claims[request.id] = record;
      _guard(isRunCurrent);
      record = await _renew(record, isRunCurrent);
      await _guardReferenceAccess(packet, isRunCurrent);
      _guard(isRunCurrent);
      record = await _renew(record, isRunCurrent);
      final acknowledgement = await _remote(
        SubmissionFailureStage.transport,
        () => transport.submit(packet),
      );
      _guard(isRunCurrent);
      if (acknowledgement.requestId != request.id ||
          acknowledgement.subjectId != request.subjectId) {
        throw const _StageFailure(
          SubmissionFailureStage.configuration,
          'acknowledgementMismatch',
          'Server acknowledgement does not match.',
          false,
        );
      }
      record = await _queue.complete(
        id: request.id,
        leaseToken: record.leaseToken!,
        acknowledgement: acknowledgement,
        now: _time(),
      );
      _claims.remove(request.id);
      return SubmissionRunResult(
        outcome: SubmissionRunOutcome.submitted,
        record: record,
      );
    } on _Cancelled {
      return _cancel(record);
    } on SubmissionLeaseLostException {
      return _lost(record);
    } on _StageFailure catch (failure) {
      try {
        _guard(isRunCurrent);
        final at = _time();
        final failed = await _queue.fail(
          id: record!.request.id,
          leaseToken: record.leaseToken!,
          now: at,
          failure: SubmissionFailure(
            stage: failure.stage,
            code: failure.code,
            message: failure.message,
            retryable: failure.retryable,
            occurredAt: at,
            claimCount: record.claimCount,
          ),
          nextAttemptAt: failure.retryable ? at.add(automaticRetryDelay) : null,
          transportFailureOutcome: failure.transportFailureOutcome,
        );
        _claims.remove(record.request.id);
        return SubmissionRunResult(
          outcome: SubmissionRunOutcome.failed,
          record: failed,
        );
      } on _Cancelled {
        return _cancel(record);
      } on SubmissionLeaseLostException {
        return _lost(record);
      } on _PredicateError catch (error) {
        await _releasePrimary(record);
        Error.throwWithStackTrace(error.error, error.stack);
      }
    } on _PredicateError catch (error) {
      await _releasePrimary(record);
      Error.throwWithStackTrace(error.error, error.stack);
    }
  });

  Future<Uint8List> _original(SubmissionMaterial material) async {
    try {
      final bytes = await _materials.readMaterial(material.original);
      if (bytes.length != material.original.byteLength) {
        throw StateError('Original length mismatch');
      }
      return bytes;
    } catch (_) {
      throw const _StageFailure(
        SubmissionFailureStage.localMaterial,
        'originalUnavailable',
        'Original material is missing or invalid.',
        false,
      );
    }
  }

  Future<SubmissionRunResult> _release(
    SubmissionRecord record,
    SubmissionRunOutcome outcome,
  ) async {
    final released = await _queue.release(
      id: record.request.id,
      leaseToken: record.leaseToken!,
      now: _time(),
    );
    _claims.remove(record.request.id);
    return SubmissionRunResult(outcome: outcome, record: released);
  }

  Future<SubmissionRunResult> _cancel(SubmissionRecord? record) async {
    if (record == null) {
      return const SubmissionRunResult(outcome: SubmissionRunOutcome.cancelled);
    }
    try {
      return await _release(record, SubmissionRunOutcome.cancelled);
    } on SubmissionLeaseLostException {
      return _lost(record);
    }
  }

  Future<SubmissionRunResult> _lost(SubmissionRecord? record) async {
    if (record == null) {
      return const SubmissionRunResult(outcome: SubmissionRunOutcome.leaseLost);
    }
    _claims.remove(record.request.id);
    return SubmissionRunResult(
      outcome: SubmissionRunOutcome.leaseLost,
      record: await _queue.find(record.request.id),
    );
  }

  Future<void> _releasePrimary(SubmissionRecord? record) async {
    if (record == null) return;
    try {
      await _queue.release(
        id: record.request.id,
        leaseToken: record.leaseToken!,
        now: _time(),
      );
    } catch (_) {
      // The caller predicate's primary error takes precedence over cleanup.
    }
    _claims.remove(record.request.id);
  }

  /// Invalidates run ownership immediately, drains accepted work/read calls and
  /// best-effort releases unfinished valid claims. Borrowed resources remain
  /// usable. Repeated close joins the same future; no remote operation is started.
  Future<void> close() {
    _closing = true;
    return _closeFuture ??= _drain();
  }

  Future<void> _drain() async {
    await _tail;
    await Future.wait(_reads.toList());
    for (final record in _claims.values.toList()) {
      await _releasePrimary(record);
    }
  }
}

final class _Cancelled implements Exception {
  const _Cancelled();
}

final class _PredicateError implements Exception {
  _PredicateError(this.error, this.stack);
  final Object error;
  final StackTrace stack;
}

final class _StageFailure implements Exception {
  const _StageFailure(
    this.stage,
    this.code,
    this.message,
    this.retryable, {
    this.transportFailureOutcome = SubmissionTransportFailureOutcome.unknown,
  });
  final SubmissionFailureStage stage;
  final String code;
  final String message;
  final bool retryable;
  final SubmissionTransportFailureOutcome transportFailureOutcome;
}
