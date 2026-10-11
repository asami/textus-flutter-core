import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqlite;

import 'submission_codec.dart';
import 'submission_json.dart' as j;
import 'submission_queue_store.dart';
import 'submission_record.dart';
import 'submission_request.dart';

/// Opens the owned version 1 database in application support on Android, iOS
/// and macOS. Web/other default platforms throw [UnsupportedError]. Plugin/IO
/// errors propagate, without fallback or deletion. Caller owns and closes it.
Future<SubmissionQueueStore> openDefaultSubmissionQueueStore() async {
  if (kIsWeb ||
      !{
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform)) {
    throw UnsupportedError('Default submission SQLite is unsupported here');
  }
  final directory = await getApplicationSupportDirectory();
  return SqliteSubmissionQueueStore.open(
    '${directory.path}/textus_submission.sqlite',
  );
}

/// Dedicated transactional durable submission database. Each instance owns one
/// independent handle, serializes its operations, and relies on native SQLite
/// for other handles/isolates. No adapter or material IO occurs in transactions.
final class SqliteSubmissionQueueStore implements SubmissionQueueStore {
  SqliteSubmissionQueueStore._(this._database);

  /// Opens an independent handle with FULL synchronous writes and 5s busy wait.
  /// An injected factory supports host tests without changing any global factory.
  /// Unsupported versions, corrupt data and IO errors remain observable.
  static Future<SqliteSubmissionQueueStore> open(
    String databasePath, {
    sqlite.DatabaseFactory? factory,
  }) async {
    if (databasePath.trim().isEmpty || databasePath == ':memory:') {
      throw ArgumentError('A durable database path is required');
    }
    final database = await (factory ?? sqlite.databaseFactory).openDatabase(
      databasePath,
      options: sqlite.OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
        onConfigure: (db) async {
          // Given an acquired independent handle whose schema may be locked,
          // When the result-returning 5000ms wait assignment is awaited as a query,
          await db.rawQuery('PRAGMA busy_timeout = 5000');
          // Then its result is consumed before FULL writes and schema access.
          await db.execute('PRAGMA synchronous = FULL');
        },
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE submission_jobs ('
            'request_id TEXT PRIMARY KEY, kind TEXT NOT NULL, '
            'subject_id TEXT NOT NULL, body TEXT NOT NULL, '
            'UNIQUE(kind, subject_id))',
          );
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          throw const FormatException(
            'Unsupported submission database version',
          );
        },
        onDowngrade: (db, oldVersion, newVersion) async {
          throw const FormatException(
            'Unsupported submission database version',
          );
        },
      ),
    );
    return SqliteSubmissionQueueStore._(database);
  }

  final sqlite.Database _database;
  Future<void> _tail = Future<void>.value();
  Future<void>? _closeFuture;
  bool _closing = false;

  Future<T> _transaction<T>(Future<T> Function(sqlite.Transaction) action) {
    if (_closing) return Future<T>.error(StateError('Queue is closed'));
    final result = _tail.then((_) => _transactionWithEntranceRetry<T>(action));
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  /// Retries only contended entrance; an entered callback is never replayed.
  Future<T> _transactionWithEntranceRetry<T>(
    Future<T> Function(sqlite.Transaction) action,
  ) async {
    for (var attempt = 0; ; attempt++) {
      var entered = false;
      try {
        return await _database.transaction<T>((tx) {
          entered = true;
          return action(tx);
        }, exclusive: true);
      } on sqlite.DatabaseException catch (error) {
        final code = error.getResultCode();
        final primaryCode = code == null ? null : code & 0xff;
        if (entered || attempt >= 2 || (primaryCode != 5 && primaryCode != 6)) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }
  }

  SubmissionRecord _decode(Map<String, Object?> row) {
    final record = SubmissionCodec.recordFromJson(
      j.object(jsonDecode(j.string(row['body']))),
    );
    if (record.request.id != row['request_id'] ||
        record.request.kind != row['kind'] ||
        record.request.subjectId != row['subject_id']) {
      throw const FormatException('Submission indexed identity mismatch');
    }
    return record;
  }

  Future<SubmissionRecord?> _read(sqlite.Transaction tx, String id) async {
    final rows = await tx.query(
      'submission_jobs',
      where: 'request_id = ?',
      whereArgs: [j.token(id)],
    );
    return rows.isEmpty ? null : _decode(rows.single);
  }

  Future<List<SubmissionRecord>> _all(sqlite.Transaction tx) async {
    final rows = await tx.query('submission_jobs');
    final records = rows.map(_decode).toList();
    records.sort((a, b) {
      final time = a.request.createdAt.compareTo(b.request.createdAt);
      return time == 0 ? a.request.id.compareTo(b.request.id) : time;
    });
    return records;
  }

  Future<SubmissionRecord> _write(
    sqlite.Transaction tx,
    SubmissionRecord value,
  ) async {
    final count = await tx.update(
      'submission_jobs',
      {'body': jsonEncode(SubmissionCodec.recordToJson(value))},
      where: 'request_id = ?',
      whereArgs: [value.request.id],
    );
    if (count != 1) {
      throw StateError('Submission disappeared during transition');
    }
    return value;
  }

  SubmissionRecord _next(
    SubmissionRecord old,
    DateTime now, {
    required SubmissionState state,
    int? claimCount,
    String? leaseToken,
    DateTime? leaseExpiresAt,
    DateTime? nextAttemptAt,
    Map<String, SubmissionStorageReservation>? reservations,
    Map<String, SubmissionMaterialReceipt>? receipts,
    List<SubmissionFailure>? history,
    SubmissionAcknowledgement? acknowledgement,
    SubmissionTransportCheckpoint? transportCheckpoint,
    bool clearTransportCheckpoint = false,
  }) => SubmissionRecord(
    request: old.request,
    state: state,
    claimCount: claimCount ?? old.claimCount,
    updatedAt: now.toUtc().isAfter(old.updatedAt) ? now : old.updatedAt,
    leaseToken: leaseToken,
    leaseExpiresAt: leaseExpiresAt,
    nextAttemptAt: nextAttemptAt,
    reservations: reservations ?? old.reservations,
    receipts: receipts ?? old.receipts,
    failureHistory: history ?? old.failureHistory,
    acknowledgement: acknowledgement,
    transportCheckpoint: clearTransportCheckpoint
        ? null
        : transportCheckpoint ?? old.transportCheckpoint,
  );

  Future<SubmissionRecord> _owned(
    sqlite.Transaction tx,
    String id,
    String leaseToken,
    DateTime now,
  ) async {
    j.token(leaseToken);
    final value = await _read(tx, id);
    if (value == null ||
        value.state != SubmissionState.submitting ||
        value.leaseToken != leaseToken ||
        !value.leaseExpiresAt!.isAfter(now.toUtc())) {
      throw SubmissionLeaseLostException(id);
    }
    return value;
  }

  void _positive(Duration duration) {
    if (duration <= Duration.zero) {
      throw ArgumentError('Duration must be positive');
    }
  }

  @override
  Future<SubmissionRecord> enqueue(SubmissionRequest request) => _transaction((
    tx,
  ) async {
    final old = await _read(tx, request.id);
    if (old != null) {
      if (old.request != request) throw StateError('Conflicting request id');
      return old;
    }
    final subjects = await tx.query(
      'submission_jobs',
      where: 'kind = ? AND subject_id = ?',
      whereArgs: [request.kind, request.subjectId],
    );
    if (subjects.isNotEmpty) {
      _decode(subjects.single);
      throw StateError('Subject already has an immutable Commit');
    }
    final value = SubmissionRecord(
      request: request,
      state: SubmissionState.readyToSubmit,
      claimCount: 0,
      updatedAt: request.createdAt,
    );
    await tx.insert('submission_jobs', {
      'request_id': request.id,
      'kind': request.kind,
      'subject_id': request.subjectId,
      'body': jsonEncode(SubmissionCodec.recordToJson(value)),
    });
    return value;
  });

  @override
  Future<SubmissionRecord?> find(String id) =>
      _transaction((tx) => _read(tx, id));

  @override
  Future<SubmissionRecord?> findForSubject(String kind, String subjectId) =>
      _transaction((tx) async {
        final rows = await tx.query(
          'submission_jobs',
          where: 'kind = ? AND subject_id = ?',
          whereArgs: [j.token(kind), j.token(subjectId)],
        );
        return rows.isEmpty ? null : _decode(rows.single);
      });

  @override
  Future<List<SubmissionRecord>> list() => _transaction(
    (tx) async => List<SubmissionRecord>.unmodifiable(await _all(tx)),
  );

  @override
  Future<SubmissionRecord?> claimNext({
    required DateTime now,
    required String leaseToken,
    required Duration leaseDuration,
  }) => _transaction((tx) async {
    j.token(leaseToken);
    _positive(leaseDuration);
    final records = await _all(tx);
    if (records.any((r) => r.leaseToken == leaseToken)) {
      throw ArgumentError('Lease token must be unique');
    }
    for (final value in records) {
      final eligible = switch (value.state) {
        SubmissionState.readyToSubmit => true,
        SubmissionState.submitted => false,
        SubmissionState.submitting => !value.leaseExpiresAt!.isAfter(
          now.toUtc(),
        ),
        SubmissionState.submissionFailed =>
          value.lastFailure!.retryable &&
              !value.nextAttemptAt!.isAfter(now.toUtc()),
      };
      if (eligible) {
        return _write(
          tx,
          _next(
            value,
            now,
            state: SubmissionState.submitting,
            claimCount: value.claimCount + 1,
            leaseToken: leaseToken,
            leaseExpiresAt: now.toUtc().add(leaseDuration),
          ),
        );
      }
    }
    return null;
  });

  @override
  Future<SubmissionRecord> renewLease({
    required String id,
    required String leaseToken,
    required DateTime now,
    required Duration leaseDuration,
  }) => _transaction((tx) async {
    _positive(leaseDuration);
    final old = await _owned(tx, id, leaseToken, now);
    return _write(
      tx,
      _next(
        old,
        now,
        state: old.state,
        leaseToken: leaseToken,
        leaseExpiresAt: now.toUtc().add(leaseDuration),
      ),
    );
  });

  @override
  Future<SubmissionRecord> saveReservation({
    required String id,
    required String leaseToken,
    required SubmissionStorageReservation reservation,
    required DateTime now,
  }) => _transaction((tx) async {
    final old = await _owned(tx, id, leaseToken, now);
    if (!old.request.materials.any((m) => m.key == reservation.key)) {
      throw StateError('Unknown reservation material');
    }
    final existing = old.reservations[reservation.key];
    if (existing != null) {
      if (existing != reservation) throw StateError('Reservation replacement');
      return old;
    }
    return _write(
      tx,
      _next(
        old,
        now,
        state: old.state,
        leaseToken: leaseToken,
        leaseExpiresAt: old.leaseExpiresAt,
        reservations: {...old.reservations, reservation.key: reservation},
      ),
    );
  });

  @override
  Future<SubmissionRecord> saveReceipt({
    required String id,
    required String leaseToken,
    required SubmissionMaterialReceipt receipt,
    required DateTime now,
  }) => _transaction((tx) async {
    final old = await _owned(tx, id, leaseToken, now);
    final reservation = old.reservations[receipt.key];
    if (reservation == null || reservation.providerId != receipt.providerId) {
      throw StateError('Receipt does not match reservation');
    }
    final existing = old.receipts[receipt.key];
    if (existing != null) {
      if (existing != receipt) throw StateError('Receipt replacement');
      return old;
    }
    return _write(
      tx,
      _next(
        old,
        now,
        state: old.state,
        leaseToken: leaseToken,
        leaseExpiresAt: old.leaseExpiresAt,
        receipts: {...old.receipts, receipt.key: receipt},
      ),
    );
  });

  @override
  Future<SubmissionRecord> markTransportDispatch({
    required String id,
    required String leaseToken,
    required DateTime now,
  }) => _transaction((tx) async {
    final old = await _owned(tx, id, leaseToken, now);
    if (old.receipts.length != old.request.materials.length) {
      throw StateError('Dispatch requires all material receipts');
    }
    if (old.transportCheckpoint != null) return old;
    return _write(
      tx,
      _next(
        old,
        now,
        state: old.state,
        leaseToken: leaseToken,
        leaseExpiresAt: old.leaseExpiresAt,
        transportCheckpoint: SubmissionTransportCheckpoint.pending(
          claimCount: old.claimCount,
          startedAt: now,
        ),
      ),
    );
  });

  @override
  Future<SubmissionRecord> complete({
    required String id,
    required String leaseToken,
    required SubmissionAcknowledgement acknowledgement,
    required DateTime now,
  }) => _transaction((tx) async {
    final old = await _owned(tx, id, leaseToken, now);
    if (acknowledgement.requestId != old.request.id ||
        acknowledgement.subjectId != old.request.subjectId ||
        old.receipts.length != old.request.materials.length) {
      throw StateError('Incomplete or mismatched server acceptance');
    }
    return _write(
      tx,
      _next(
        old,
        now,
        state: SubmissionState.submitted,
        acknowledgement: acknowledgement,
        clearTransportCheckpoint: true,
      ),
    );
  });

  @override
  Future<SubmissionRecord> fail({
    required String id,
    required String leaseToken,
    required SubmissionFailure failure,
    required DateTime now,
    DateTime? nextAttemptAt,
    SubmissionTransportFailureOutcome transportFailureOutcome =
        SubmissionTransportFailureOutcome.unknown,
  }) => _transaction((tx) async {
    final old = await _owned(tx, id, leaseToken, now);
    final conclusive =
        transportFailureOutcome != SubmissionTransportFailureOutcome.unknown;
    if (conclusive &&
        failure.stage != SubmissionFailureStage.transport &&
        failure.stage != SubmissionFailureStage.configuration) {
      throw ArgumentError('Transport outcome requires a transport failure');
    }
    if (failure.claimCount != old.claimCount ||
        failure.occurredAt != now.toUtc() ||
        failure.retryable != (nextAttemptAt != null) ||
        (nextAttemptAt != null &&
            !nextAttemptAt.toUtc().isAfter(now.toUtc()))) {
      throw ArgumentError('Failure must match executing claim/time and retry');
    }
    return _write(
      tx,
      _next(
        old,
        now,
        state: SubmissionState.submissionFailed,
        nextAttemptAt: nextAttemptAt,
        history: [...old.failureHistory, failure],
        clearTransportCheckpoint:
            conclusive &&
            old.transportCheckpoint != null &&
            !old.transportCheckpoint!.isLegacyUnknown &&
            old.transportCheckpoint!.claimCount == old.claimCount,
      ),
    );
  });

  @override
  Future<SubmissionRecord> release({
    required String id,
    required String leaseToken,
    required DateTime now,
  }) => _transaction((tx) async {
    final old = await _owned(tx, id, leaseToken, now);
    return _write(tx, _next(old, now, state: SubmissionState.readyToSubmit));
  });

  @override
  Future<SubmissionRecord> retry({required String id, required DateTime now}) =>
      _transaction((tx) async {
        final old = await _read(tx, id);
        if (old == null) throw StateError('Unknown submission');
        if (old.state == SubmissionState.submitting) {
          throw StateError('Cannot retry an active claim');
        }
        if (old.state != SubmissionState.submissionFailed) return old;
        return _write(
          tx,
          _next(old, now, state: SubmissionState.readyToSubmit),
        );
      });

  @override
  Future<void> close() {
    _closing = true;
    return _closeFuture ??= _tail.then((_) => _database.close());
  }
}
