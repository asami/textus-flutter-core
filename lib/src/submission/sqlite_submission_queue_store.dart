import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqlite;

import 'submission_queue_store.dart';
import 'submission_queue_engine.dart';

/// Opens the owned version 2 database in application support on Android, iOS
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
final class SqliteSubmissionQueueStore extends SubmissionQueueEngine {
  SqliteSubmissionQueueStore._(sqlite.Database database)
    : super(_SqliteQueuePersistence(database));

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
        version: 2,
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
          await _createHandoffTable(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion == 1 && newVersion == 2) {
            await _createHandoffTable(db);
            return;
          }
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

  static Future<void> _createHandoffTable(sqlite.DatabaseExecutor db) =>
      db.execute(
        'CREATE TABLE registered_material_handoffs ('
        'handoff_id TEXT PRIMARY KEY, source_request_id TEXT NOT NULL UNIQUE, '
        'body TEXT NOT NULL)',
      );
}

final class _SqliteQueuePersistence implements SubmissionQueuePersistence {
  _SqliteQueuePersistence(this.database);
  final sqlite.Database database;
  @override
  Future<T> transaction<T>(
    Future<T> Function(SubmissionQueueTransaction) action,
  ) async {
    // Only contended entrance may retry; an entered callback never replays.
    for (var attempt = 0; ; attempt++) {
      var entered = false;
      try {
        return await database.transaction<T>((tx) {
          entered = true;
          return action(_SqliteQueueTransaction(tx));
        }, exclusive: true);
      } on sqlite.DatabaseException catch (error) {
        final code = error.getResultCode();
        final primary = code == null ? null : code & 0xff;
        if (entered || attempt >= 2 || (primary != 5 && primary != 6)) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }
  }

  @override
  Future<void> close() => database.close();
}

final class _SqliteQueueTransaction implements SubmissionQueueTransaction {
  _SqliteQueueTransaction(this.transaction);
  final sqlite.Transaction transaction;
  String _table(SubmissionStoreTable table) => switch (table) {
    SubmissionStoreTable.jobs => 'submission_jobs',
    SubmissionStoreTable.handoffs => 'registered_material_handoffs',
  };
  String? _where(SubmissionStoreTable table, Map<String, Object?> equals) {
    final allowed = table == SubmissionStoreTable.jobs
        ? const {'request_id', 'kind', 'subject_id'}
        : const {'handoff_id', 'source_request_id'};
    if (!equals.keys.every(allowed.contains)) {
      throw ArgumentError('Invalid queue index');
    }
    return equals.isEmpty
        ? null
        : equals.keys.map((key) => '$key = ?').join(' AND ');
  }

  @override
  Future<List<Map<String, Object?>>> rows(
    SubmissionStoreTable table, {
    Map<String, Object?> equals = const {},
  }) => transaction.query(
    _table(table),
    where: _where(table, equals),
    whereArgs: equals.isEmpty ? null : equals.values.toList(),
  );
  @override
  Future<void> insert(
    SubmissionStoreTable table,
    Map<String, Object?> values,
  ) async {
    await transaction.insert(_table(table), values);
  }

  @override
  Future<int> update(
    SubmissionStoreTable table,
    Map<String, Object?> values, {
    required Map<String, Object?> equals,
  }) => transaction.update(
    _table(table),
    values,
    where: _where(table, equals),
    whereArgs: equals.values.toList(),
  );
}
