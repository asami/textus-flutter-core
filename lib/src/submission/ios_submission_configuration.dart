import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqlite;

import 'submission_configuration.dart';
import 'submission_connections.dart';
import 'submission_json.dart' as j;

/// Owned iOS durable public configuration and a borrowed credential read port.
///
/// Only safe connection definitions, selections and reference declarations are
/// stored. Credentials remain ephemeral and owned by the supplied provider.
final class IosSubmissionConfigurationStore
    implements SubmissionConfigurationStore, SubmissionCredentialProvider {
  IosSubmissionConfigurationStore._(
    this._database,
    this._credentials,
    this._coordinator,
  );

  /// Opens an independent durable iOS handle without consent or credential IO.
  /// Unsupported platforms fail before path-provider or database acquisition.
  static Future<IosSubmissionConfigurationStore> open({
    String? databasePath,
    sqlite.DatabaseFactory? factory,
    SubmissionCredentialProvider? credentials,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      throw UnsupportedError(
        'iOS submission configuration is unsupported here',
      );
    }
    if (databasePath != null &&
        (databasePath.trim().isEmpty || databasePath == ':memory:')) {
      throw ArgumentError('A durable database path is required');
    }
    sqlite.Database? acquired;
    _IosSubmissionSqlCoordinator? coordinator;
    var failureCode = 'configurationUnavailable';
    try {
      final path =
          databasePath ??
          '${(await getApplicationSupportDirectory()).path}/'
              'textus_ios_submission_configuration.sqlite';
      final selected = _IosSubmissionSqlCoordinator.retain(path);
      coordinator = selected;
      return await selected.run(() async {
        try {
          final database = await (factory ?? sqlite.databaseFactory)
              .openDatabase(
                path,
                options: sqlite.OpenDatabaseOptions(
                  version: 1,
                  singleInstance: false,
                  onConfigure: (db) async {
                    acquired = db;
                    await db.rawQuery('PRAGMA busy_timeout = 5000');
                    await db.execute('PRAGMA synchronous = FULL');
                  },
                  onCreate: (db, version) async {
                    await db.execute(
                      'CREATE TABLE ios_submission_configuration ('
                      'singleton INTEGER PRIMARY KEY CHECK(singleton = 1), '
                      'body TEXT NOT NULL)',
                    );
                    await db.insert('ios_submission_configuration', {
                      'singleton': 1,
                      'body': jsonEncode(
                        SubmissionConfigurationSnapshot(
                          driveConnections: [],
                          httpConnections: [],
                        ).toJson(),
                      ),
                    });
                  },
                  onUpgrade: (db, oldVersion, newVersion) async {
                    failureCode = 'configurationInvalid';
                    throw SubmissionConfigurationException.safe(failureCode);
                  },
                  onDowngrade: (db, oldVersion, newVersion) async {
                    failureCode = 'configurationInvalid';
                    throw SubmissionConfigurationException.safe(failureCode);
                  },
                ),
              );
          acquired = database;
          final store = IosSubmissionConfigurationStore._(
            database,
            credentials,
            selected,
          );
          // Open already holds coordination, including initial validation.
          await database.transaction(store._read);
          return store;
        } catch (_) {
          try {
            await acquired?.close();
          } catch (_) {
            // Cleanup must preserve the primary fixed safe acquisition failure.
          }
          rethrow;
        }
      });
    } catch (error) {
      coordinator?.release();
      throw error is SubmissionConfigurationException
          ? SubmissionConfigurationException.safe(error.code)
          : SubmissionConfigurationException.safe(failureCode);
    }
  }

  final sqlite.Database _database;
  final SubmissionCredentialProvider? _credentials;
  final _IosSubmissionSqlCoordinator _coordinator;
  Future<void> _tail = Future<void>.value();
  Future<void>? _closeFuture;
  bool _closing = false;

  Future<T> _operation<T>(Future<T> Function() action) {
    if (_closing) {
      return Future<T>.error(
        SubmissionConfigurationException.safe('configurationClosed'),
      );
    }
    final result = _tail.then<T>((_) async {
      if (_closing) {
        throw SubmissionConfigurationException.safe('configurationClosed');
      }
      try {
        final value = await action();
        if (_closing) {
          throw SubmissionConfigurationException.safe('configurationClosed');
        }
        return value;
      } catch (error) {
        if (_closing) {
          throw SubmissionConfigurationException.safe('configurationClosed');
        }
        if (error is SubmissionConfigurationException) rethrow;
        throw SubmissionConfigurationException.safe('configurationUnavailable');
      }
    });
    // Observe internal failures while preserving each caller's original result.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<T> _transaction<T>(Future<T> Function(sqlite.Transaction) action) =>
      _coordinator.run(() {
        // A handle may retire while waiting for another handle's SQL operation.
        if (_closing) {
          throw SubmissionConfigurationException.safe('configurationClosed');
        }
        return _database.transaction(action);
      });

  Future<SubmissionConfigurationSnapshot> _read(sqlite.Transaction tx) async {
    final rows = await tx.query('ios_submission_configuration');
    try {
      if (rows.length != 1 || rows.single['singleton'] != 1) {
        throw const FormatException('Invalid configuration singleton');
      }
      final body = j.string(rows.single['body']);
      if (utf8.encode(body).length > 128 * 65536) {
        throw const FormatException('Configuration exceeds its bound');
      }
      final decoded = j.object(jsonDecode(body));
      if (j.integer(decoded['version']) != 2) {
        throw const FormatException('Unsupported iOS configuration version');
      }
      return SubmissionConfigurationSnapshot.fromJson(decoded);
    } catch (_) {
      throw SubmissionConfigurationException.safe('configurationInvalid');
    }
  }

  SubmissionConfigurationSnapshot _next(
    SubmissionConfigurationSnapshot current, {
    List<DriveSubmissionConnection>? drives,
    List<HttpSubmissionConnection>? http,
    Map<String, List<String>>? bindings,
  }) {
    try {
      return SubmissionConfigurationSnapshot(
        driveConnections: drives ?? current.driveConnections,
        httpConnections: http ?? current.httpConnections,
        selectedStorageConnectionId: current.selectedStorageConnectionId,
        selectedTransportConnectionId: current.selectedTransportConnectionId,
        referenceAccessBindings: bindings ?? current.referenceAccessBindings,
      );
    } catch (_) {
      throw SubmissionConfigurationException.safe('configurationInvalid');
    }
  }

  Future<void> _write(
    sqlite.Transaction tx,
    SubmissionConfigurationSnapshot value,
  ) async {
    final count = await tx.update(
      'ios_submission_configuration',
      {'body': jsonEncode(value.toJson())},
      where: 'singleton = ?',
      whereArgs: [1],
    );
    if (count != 1) {
      throw SubmissionConfigurationException.safe('configurationInvalid');
    }
  }

  void _definition(Map<String, Object?> definition) {
    if (utf8.encode(jsonEncode(definition)).length > 65536) {
      throw ArgumentError('Submission definition exceeds its bound');
    }
  }

  Map<String, Object?>? _definitionFor(
    SubmissionConfigurationSnapshot value,
    String id,
  ) {
    for (final connection in value.driveConnections) {
      if (connection.id == id) return connection.toJson();
    }
    for (final connection in value.httpConnections) {
      if (connection.id == id) return connection.toJson();
    }
    return null;
  }

  @override
  Future<SubmissionConfigurationSnapshot> snapshot() =>
      _operation(() => _transaction(_read));

  @override
  Future<void> putDrive(DriveSubmissionConnection connection) {
    _definition(connection.toJson());
    return _put(
      connection.id,
      connection.toJson(),
      (current) =>
          _next(current, drives: [...current.driveConnections, connection]),
    );
  }

  @override
  Future<void> putHttp(HttpSubmissionConnection connection) {
    _definition(connection.toJson());
    return _put(
      connection.id,
      connection.toJson(),
      (current) =>
          _next(current, http: [...current.httpConnections, connection]),
    );
  }

  Future<void> _put(
    String id,
    Map<String, Object?> definition,
    SubmissionConfigurationSnapshot Function(SubmissionConfigurationSnapshot)
    add,
  ) => _operation(
    () => _transaction((tx) async {
      final current = await _read(tx);
      final existing = _definitionFor(current, id);
      if (existing != null) {
        if (!j.deepEquals(existing, definition)) {
          throw SubmissionConfigurationException.safe('connectionConflict');
        }
        return;
      }
      await _write(tx, add(current));
    }),
  );

  @override
  Future<void> select({
    String? storageConnectionId,
    String? transportConnectionId,
  }) {
    if (storageConnectionId != null) j.token(storageConnectionId);
    if (transportConnectionId != null) j.token(transportConnectionId);
    return _operation(
      () => _transaction((tx) async {
        final current = await _read(tx);
        if ((storageConnectionId != null &&
                !current.driveConnections.any(
                  (c) => c.id == storageConnectionId,
                )) ||
            (transportConnectionId != null &&
                !current.httpConnections.any(
                  (c) => c.id == transportConnectionId,
                ))) {
          throw SubmissionConfigurationException.safe('connectionMissing');
        }
        await _write(
          tx,
          SubmissionConfigurationSnapshot(
            driveConnections: current.driveConnections,
            httpConnections: current.httpConnections,
            selectedStorageConnectionId: storageConnectionId,
            selectedTransportConnectionId: transportConnectionId,
            referenceAccessBindings: current.referenceAccessBindings,
          ),
        );
      }),
    );
  }

  @override
  Future<void> setReferenceAccess({
    required String transportConnectionId,
    required List<String> storageConnectionIds,
  }) {
    j.token(transportConnectionId);
    final ids = List<String>.of(storageConnectionIds);
    for (final id in ids) {
      j.token(id);
    }
    if (ids.length > 128 || ids.toSet().length != ids.length) {
      throw ArgumentError('Invalid reference access binding');
    }
    return _operation(
      () => _transaction((tx) async {
        final current = await _read(tx);
        if (!current.httpConnections.any(
              (c) => c.id == transportConnectionId,
            ) ||
            ids.any((id) => !current.driveConnections.any((c) => c.id == id))) {
          throw SubmissionConfigurationException.safe('connectionMissing');
        }
        await _write(
          tx,
          _next(
            current,
            bindings: {
              ...current.referenceAccessBindings,
              transportConnectionId: ids,
            },
          ),
        );
      }),
    );
  }

  @override
  Future<String?> bearerToken(String connectionId) {
    j.token(connectionId);
    return _operation(() async {
      final definition = await _transaction((tx) async {
        final value = _definitionFor(await _read(tx), connectionId);
        if (value == null) {
          throw SubmissionConfigurationException.safe('connectionMissing');
        }
        return value;
      });
      if (_closing) {
        throw SubmissionConfigurationException.safe('configurationClosed');
      }
      if (definition['requiresBearerToken'] == false || _credentials == null) {
        return null;
      }
      try {
        final token = await _credentials.bearerToken(connectionId);
        if (token != null) {
          final match = RegExp(r'[A-Za-z0-9._~+/-]+=*').matchAsPrefix(token);
          if (token.length > 8192 ||
              match == null ||
              match.end != token.length) {
            throw SubmissionConfigurationException.safe(
              'credentialUnavailable',
            );
          }
        }
        return token;
      } catch (_) {
        throw SubmissionConfigurationException.safe('credentialUnavailable');
      }
    });
  }

  /// Retires immediately, joins accepted calls and closes only this DB handle.
  /// Dispatched writes may commit; close never logs out or deletes durable data.
  @override
  Future<void> close() {
    _closing = true;
    return _closeFuture ??= () async {
      await _tail;
      try {
        await _coordinator.run(_database.close);
      } catch (_) {
        throw SubmissionConfigurationException.safe('configurationUnavailable');
      } finally {
        _coordinator.release();
      }
    }();
  }
}

/// Same-isolate SQL ordering for independently owned handles of one path.
final class _IosSubmissionSqlCoordinator {
  _IosSubmissionSqlCoordinator._(this._path);

  static final Map<String, _IosSubmissionSqlCoordinator> _registry = {};

  static _IosSubmissionSqlCoordinator retain(String path) {
    final coordinator = _registry.putIfAbsent(
      path,
      () => _IosSubmissionSqlCoordinator._(path),
    );
    coordinator._references++;
    return coordinator;
  }

  final String _path;
  int _references = 0;
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then<T>((_) => action());
    // A failed owner must not poison the next owner's SQL operation.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void release() {
    _references--;
    if (_references == 0 && identical(_registry[_path], this)) {
      _registry.remove(_path);
    }
  }
}
