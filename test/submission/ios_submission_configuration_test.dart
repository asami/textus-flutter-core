import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqlite;
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqlite.sqfliteFfiInit();
  late _ConfigurationDisk disk;
  TargetPlatform? previousPlatform;

  setUp(() async {
    previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    disk = _ConfigurationDisk(
      await Directory.systemTemp.createTemp('ios-submission-configuration-'),
    );
  });

  tearDown(() async {
    try {
      await disk.dispose();
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  group('iOS durable public submission configuration', () {
    test('fresh definitions selections and access survive close and reopen', () async {
      // Given a legitimate absent file and an optional borrowed credential port.
      final credentials = _Credentials((_) async => 'unused.token');
      var store = await disk.open(credentials: credentials);
      final empty = await store.snapshot();
      expect(empty.driveConnections, isEmpty);
      expect(empty.httpConnections, isEmpty);
      expect(empty.referenceAccessBindings, isEmpty);
      expect(empty.selectedStorageConnectionId, isNull);
      expect(empty.selectedTransportConnectionId, isNull);
      final drive = _drive('drive');
      final http = _http('http');
      // When both kinds, exact selections and a caller-owned access list persist.
      await store.putDrive(drive);
      await store.putHttp(http);
      await store.select(
        storageConnectionId: 'drive',
        transportConnectionId: 'http',
      );
      final ids = ['drive'];
      final binding = store.setReferenceAccess(
        transportConnectionId: 'http',
        storageConnectionIds: ids,
      );
      ids.clear();
      await binding;
      final accepted = await store.snapshot();
      await store.close();
      store = await disk.open();
      // Then exact definitions/selection/bindings are durable and deeply frozen.
      expect((await store.snapshot()).toJson(), accepted.toJson());
      expect(accepted.driveConnections.single.toJson(), drive.toJson());
      expect(accepted.httpConnections.single.toJson(), http.toJson());
      expect(accepted.referenceAccessBindings, {
        'http': ['drive'],
      });
      expect(() => accepted.driveConnections.clear(), throwsUnsupportedError);
      expect(
        () => accepted.referenceAccessBindings.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => accepted.referenceAccessBindings['http']!.clear(),
        throwsUnsupportedError,
      );
      final detached = accepted.toJson();
      (detached['driveConnections']! as List).clear();
      expect((await store.snapshot()).driveConnections, hasLength(1));
      expect(credentials.calls, isEmpty);
      // When null clears selection and an empty binding explicitly revokes access.
      await store.select();
      await store.setReferenceAccess(
        transportConnectionId: 'http',
        storageConnectionIds: [],
      );
      await store.close();
      store = await disk.open();
      final revoked = await store.snapshot();
      // Then revocation survives without deleting either immutable definition.
      expect(revoked.selectedStorageConnectionId, isNull);
      expect(revoked.selectedTransportConnectionId, isNull);
      expect(revoked.referenceAccessBindings, {'http': <String>[]});
      expect(revoked.driveConnections, hasLength(1));
      expect(revoked.httpConnections, hasLength(1));
    });

    test('identical writes are idempotent and conflicts preserve accepted state', () async {
      // Given accepted exact kinds, selected identities and an access declaration.
      final store = await disk.open();
      final drive = _drive('drive');
      final http = _http('http');
      await store.putDrive(drive);
      await store.putHttp(http);
      await store.select(
        storageConnectionId: 'drive',
        transportConnectionId: 'http',
      );
      await store.setReferenceAccess(
        transportConnectionId: 'http',
        storageConnectionIds: ['drive'],
      );
      final accepted = (await store.snapshot()).toJson();
      // When identical definitions are inserted again.
      await store.putDrive(DriveSubmissionConnection.fromJson(drive.toJson()));
      await store.putHttp(HttpSubmissionConnection.fromJson(http.toJson()));
      // Then idempotence preserves the complete accepted configuration.
      expect((await store.snapshot()).toJson(), accepted);
      for (final attempt in <Future<void> Function()>[
        () => store.putDrive(_drive('drive', account: 'other@example.test')),
        () => store.putDrive(_drive('drive', folder: 'OtherFolder')),
        () => store.putDrive(_drive('http')),
        () => store.putHttp(_http('http', path: '/other')),
        () => store.putHttp(_http('http', bearer: false)),
        () => store.putHttp(_http('drive')),
      ]) {
        // When an existing id's account/folder/endpoint/auth/kind is changed.
        await expectLater(attempt(), throwsA(_failure('connectionConflict')));
        // Then no partial replacement or change to selection/bindings commits.
        expect((await store.snapshot()).toJson(), accepted);
      }
      for (final attempt in <Future<void> Function()>[
        () => store.select(storageConnectionId: 'missing'),
        () => store.select(storageConnectionId: 'http'),
        () => store.select(transportConnectionId: 'drive'),
        () => store.select(transportConnectionId: 'missing'),
        () => store.setReferenceAccess(
          transportConnectionId: 'missing',
          storageConnectionIds: ['drive'],
        ),
        () => store.setReferenceAccess(
          transportConnectionId: 'drive',
          storageConnectionIds: ['drive'],
        ),
        () => store.setReferenceAccess(
          transportConnectionId: 'http',
          storageConnectionIds: ['missing'],
        ),
        () => store.setReferenceAccess(
          transportConnectionId: 'http',
          storageConnectionIds: ['http'],
        ),
      ]) {
        // When selection or access refers to an unknown or wrong-kind identity.
        await expectLater(attempt(), throwsA(_failure('connectionMissing')));
        // Then all previously accepted state remains intact.
        expect((await store.snapshot()).toJson(), accepted);
      }
    });

    test('invalid public identities and access lists reject before dispatch', () async {
      // Given a retired handle on which no new IO is permitted.
      final store = await disk.open();
      await store.close();
      // When syntax, duplicate ids or the input association bound are invalid.
      for (final attempt in <Object? Function()>[
        () => store.select(storageConnectionId: 'unsafe id'),
        () => store.select(transportConnectionId: ''),
        () => store.bearerToken('unsafe id'),
        () => store.setReferenceAccess(
          transportConnectionId: 'unsafe id',
          storageConnectionIds: [],
        ),
        () => store.setReferenceAccess(
          transportConnectionId: 'http',
          storageConnectionIds: ['unsafe id'],
        ),
        () => store.setReferenceAccess(
          transportConnectionId: 'http',
          storageConnectionIds: ['drive', 'drive'],
        ),
        () => store.setReferenceAccess(
          transportConnectionId: 'http',
          storageConnectionIds: [for (var i = 0; i < 129; i++) 'drive_$i'],
        ),
      ]) {
        // Then safe synchronous ArgumentError validation precedes retired IO.
        expect(attempt, throwsArgumentError);
      }
      // When an explicit path is blank or is the in-memory sentinel.
      for (final path in ['', '  ', ':memory:']) {
        // Then opening rejects the path before acquiring any database.
        await expectLater(
          IosSubmissionConfigurationStore.open(
            databasePath: path,
            factory: sqlite.databaseFactoryFfi,
          ),
          throwsArgumentError,
        );
      }
    });

    test('independent handles retain concurrent targets and one same-id winner', () async {
      // Given two concurrently opened independent handles to one durable file.
      final handles = await Future.wait([disk.open(), disk.open()]);
      final first = handles[0];
      final second = handles[1];
      // When each handle concurrently registers a distinct target.
      await Future.wait([
        first.putDrive(_drive('drive')),
        second.putHttp(_http('http')),
      ]);
      // Then fresh transactions on both handles see both writes.
      expect((await first.snapshot()).driveConnections.single.id, 'drive');
      expect((await first.snapshot()).httpConnections.single.id, 'http');
      expect(
        (await second.snapshot()).toJson(),
        (await first.snapshot()).toJson(),
      );
      // When both concurrently claim a previously unused id with different folders.
      final outcomes = await Future.wait([
        _outcome(() => first.putDrive(_drive('contested', folder: 'Folder_A'))),
        _outcome(
          () => second.putDrive(_drive('contested', folder: 'Folder_B')),
        ),
      ]);
      // Then exactly one immutable identity wins and the loser is a fixed conflict.
      expect(outcomes, unorderedEquals(['accepted', 'connectionConflict']));
      final accepted = await first.snapshot();
      final winner = accepted.driveConnections.singleWhere(
        (c) => c.id == 'contested',
      );
      expect(
        winner.folderId,
        outcomes.first == 'accepted' ? 'Folder_A' : 'Folder_B',
      );
      expect((await second.snapshot()).toJson(), accepted.toJson());
      await first.close();
      await second.putHttp(_http('later'));
      // Then closing the first handle leaves the second independent and usable.
      expect((await second.snapshot()).httpConnections, hasLength(2));
    });

    test(
      'connection capacity rejects the extra target without a partial commit',
      () async {
        // Given the full 128 immutable target capacity on a durable handle.
        var store = await disk.open();
        for (var i = 0; i < 128; i++) {
          await store.putHttp(_http('http_$i'));
        }
        final accepted = (await store.snapshot()).toJson();
        // When a 129th definition would exceed the shared snapshot bound.
        await expectLater(
          store.putDrive(_drive('overflow')),
          throwsA(_failure('configurationInvalid')),
        );
        await store.close();
        store = await disk.open();
        // Then reopening sees every accepted target and no partial extra definition.
        expect((await store.snapshot()).toJson(), accepted);
        await expectLater(
          store.bearerToken('overflow'),
          throwsA(_failure('connectionMissing')),
        );
      },
    );

    test('aggregate reference capacity preserves earlier bindings atomically', () async {
      // Given 65 storage targets and two complete 64-association declarations.
      final store = await disk.open();
      for (var i = 0; i < 65; i++) {
        await store.putDrive(_drive('drive_$i'));
      }
      for (final id in ['http_a', 'http_b', 'http_c']) {
        await store.putHttp(_http(id));
      }
      final ids = [for (var i = 0; i < 64; i++) 'drive_$i'];
      for (final id in ['http_a', 'http_b']) {
        await store.setReferenceAccess(
          transportConnectionId: id,
          storageConnectionIds: ids,
        );
      }
      final accepted = (await store.snapshot()).toJson();
      // When a individually valid binding would exceed 128 total associations.
      await expectLater(
        store.setReferenceAccess(
          transportConnectionId: 'http_c',
          storageConnectionIds: ['drive_64'],
        ),
        throwsA(_failure('configurationInvalid')),
      );
      // Then no partial declaration or change to accepted definitions is persisted.
      expect((await store.snapshot()).toJson(), accepted);
      // When an existing binding is explicitly revoked and capacity is freed.
      await store.setReferenceAccess(
        transportConnectionId: 'http_a',
        storageConnectionIds: [],
      );
      await store.setReferenceAccess(
        transportConnectionId: 'http_c',
        storageConnectionIds: ['drive_64'],
      );
      // Then replacement and revocation preserve the other declaration.
      expect((await store.snapshot()).referenceAccessBindings, {
        'http_a': <String>[],
        'http_b': ids,
        'http_c': ['drive_64'],
      });
    });

    for (final corruption in [
      'malformed',
      'missing',
      'version',
      'legacy-version1',
      'extra-key',
      'extra-row',
    ]) {
      test(
        '$corruption stored singleton fails visibly without replacement',
        () async {
          // Given accepted data in a file whose test-owned singleton is then damaged.
          final store = await disk.open();
          await store.putDrive(_drive('retained'));
          final accepted = (await store.snapshot()).toJson();
          await store.close();
          final raw = await disk.raw();
          switch (corruption) {
            case 'malformed':
              await raw.update('ios_submission_configuration', {
                'body': 'PRIVATE_CORRUPT_VALUE',
              });
            case 'missing':
              await raw.delete('ios_submission_configuration');
            case 'version':
              await raw.update('ios_submission_configuration', {
                'body': jsonEncode({...accepted, 'version': 999}),
              });
            case 'legacy-version1':
              final legacy = {...accepted, 'version': 1}
                ..remove('referenceAccessBindings');
              await raw.update('ios_submission_configuration', {
                'body': jsonEncode(legacy),
              });
            case 'extra-key':
              await raw.update('ios_submission_configuration', {
                'body': jsonEncode({
                  ...accepted,
                  'credential': 'PRIVATE_CORRUPT_VALUE',
                }),
              });
            case 'extra-row':
              await raw.execute('PRAGMA ignore_check_constraints = ON');
              await raw.insert('ios_submission_configuration', {
                'singleton': 2,
                'body': jsonEncode(accepted),
              });
          }
          final damaged = await raw.query('ios_submission_configuration');
          // When opening repeatedly attempts strict singleton validation.
          for (var attempt = 0; attempt < 2; attempt++) {
            await expectLater(
              disk.open(),
              throwsA(_failure('configurationInvalid')),
            );
            // Then corruption remains visible and no empty fallback/replacement is written.
            expect(await raw.query('ios_submission_configuration'), damaged);
          }
        },
      );
    }

    test(
      'a newer database version fails without downgrade or deletion',
      () async {
        // Given a test-owned file whose schema version belongs to a future writer.
        final store = await disk.open();
        await store.putDrive(_drive('retained'));
        await store.close();
        final raw = await disk.raw();
        final accepted = await raw.query('ios_submission_configuration');
        await raw.execute('PRAGMA user_version = 2');
        // When the version-one store attempts to open it.
        await expectLater(
          disk.open(),
          throwsA(_failure('configurationInvalid')),
        );
        // Then the future version and all configuration remain untouched.
        expect(await raw.rawQuery('PRAGMA user_version'), [
          {'user_version': 2},
        ]);
        expect(await raw.query('ios_submission_configuration'), accepted);
      },
    );

    test(
      'corruption after open is observed by reads and writes without caching',
      () async {
        // Given a live handle whose last valid state has an immutable Drive target.
        final store = await disk.open();
        await store.putDrive(_drive('retained'));
        final raw = await disk.raw();
        await raw.update('ios_submission_configuration', {'body': '{}'});
        // When both a fresh read and a proposed mutation encounter corrupt storage.
        await expectLater(
          store.snapshot(),
          throwsA(_failure('configurationInvalid')),
        );
        await expectLater(
          store.putHttp(_http('new')),
          throwsA(_failure('configurationInvalid')),
        );
        // Then neither the old cached state nor a synthesized empty value replaces it.
        expect(
          (await raw.query('ios_submission_configuration')).single['body'],
          '{}',
        );
      },
    );

    test('exact targets read current borrowed credentials independently of selection', () async {
      // Given exact Drive/authenticated/anonymous targets and a controllable owner.
      final values = <String, String?>{
        'drive': 'SYNTHETIC_DRIVE_TOKEN',
        'http_a': 'SYNTHETIC_TOKEN_A',
        'http_b': 'SYNTHETIC_TOKEN_B',
      };
      final credentials = _Credentials((id) async => values[id]);
      final store = await disk.open(credentials: credentials);
      await store.putDrive(_drive('drive'));
      await store.putHttp(_http('http_a'));
      await store.putHttp(_http('http_b'));
      await store.putHttp(_http('anonymous', bearer: false));
      await store.select(
        storageConnectionId: 'drive',
        transportConnectionId: 'http_a',
      );
      expect(credentials.calls, isEmpty);
      // When selection changes while an explicit caller continues reading http_a.
      expect(await store.bearerToken('http_a'), 'SYNTHETIC_TOKEN_A');
      await store.select(transportConnectionId: 'http_b');
      values['http_a'] = 'SYNTHETIC_ROTATED_TOKEN';
      expect(await store.bearerToken('http_a'), 'SYNTHETIC_ROTATED_TOKEN');
      expect(await store.bearerToken('drive'), 'SYNTHETIC_DRIVE_TOKEN');
      values['http_a'] = null;
      expect(await store.bearerToken('http_a'), isNull);
      // Then each read delegates the exact id afresh without retargeting or caching.
      expect(credentials.calls, ['http_a', 'http_a', 'drive', 'http_a']);
      // When anonymous, absent-provider and unknown-id paths are requested.
      expect(await store.bearerToken('anonymous'), isNull);
      final withoutProvider = await disk.open();
      expect(await withoutProvider.bearerToken('http_b'), isNull);
      expect(await withoutProvider.bearerToken('drive'), isNull);
      await expectLater(
        store.bearerToken('missing'),
        throwsA(_failure('connectionMissing')),
      );
      // Then none invokes the credential owner or persists any returned secret.
      expect(credentials.calls, ['http_a', 'http_a', 'drive', 'http_a']);
      final snapshot = (await store.snapshot()).toJson();
      final raw = await disk.raw();
      final body =
          (await raw.query('ios_submission_configuration')).single['body']!
              as String;
      expect(jsonDecode(body), snapshot);
      expect(
        snapshot.keys,
        unorderedEquals([
          'version',
          'driveConnections',
          'httpConnections',
          'selectedStorageConnectionId',
          'selectedTransportConnectionId',
          'referenceAccessBindings',
        ]),
      );
      for (final forbidden in [
        'SYNTHETIC_',
        'credential',
        'Authorization',
        'password',
      ]) {
        expect(body, isNot(contains(forbidden)));
        expect(jsonEncode(snapshot), isNot(contains(forbidden)));
      }
    });

    test('malformed credentials and provider failures expose only fixed safe errors', () async {
      // Given a registered authenticated target and a borrowed provider.
      final credentials = _Credentials((_) async => null);
      final store = await disk.open(credentials: credentials);
      await store.putHttp(_http('http'));
      final accepted = (await store.snapshot()).toJson();
      // When a value violates full bearer syntax, length, or the owner throws.
      for (final token in [
        '',
        '=',
        'a=b',
        'a b',
        'a\n',
        'a\r',
        'a\u0000',
        'a' * 8193,
      ]) {
        credentials.read = (_) async => token;
        await expectLater(
          store.bearerToken('http'),
          throwsA(_failure('credentialUnavailable')),
        );
      }
      credentials.read = (_) async =>
          throw StateError('PRIVATE_PROVIDER_FAILURE');
      await expectLater(
        store.bearerToken('http'),
        throwsA(_failure('credentialUnavailable')),
      );
      credentials.read = (_) async =>
          throw SubmissionConfigurationException.safe('connectionMissing');
      await expectLater(
        store.bearerToken('http'),
        throwsA(_failure('credentialUnavailable')),
      );
      // Then safe failures do not alter configuration or retain private values.
      expect((await store.snapshot()).toJson(), accepted);
      // When valid full-match bearer alphabet and its length boundary are supplied.
      for (final token in ['a', 'A.z_~+/-09==', 'a' * 8192]) {
        credentials.read = (_) async => token;
        // Then tokens are returned ephemerally without reinterpretation.
        expect(await store.bearerToken('http'), token);
      }
    });

    test('close joins accepted credentials suppresses late results and preserves other handles', () async {
      // Given a borrowed credential read whose settlement the test controls.
      final entered = Completer<void>();
      final release = Completer<String?>();
      final credentials = _Credentials((_) {
        entered.complete();
        return release.future;
      });
      addTearDown(() {
        if (!release.isCompleted) release.complete(null);
      });
      final store = await disk.open(credentials: credentials);
      final other = await disk.open();
      await store.putHttp(_http('http'));
      final accepted = (await store.snapshot()).toJson();
      final read = store.bearerToken('http');
      final readCheck = expectLater(
        read,
        throwsA(_failure('configurationClosed')),
      );
      await entered.future;
      final queued = store.bearerToken('http');
      final queuedCheck = expectLater(
        queued,
        throwsA(_failure('configurationClosed')),
      );
      // When close retires synchronously during an already dispatched read.
      final closing = store.close();
      expect(store.close(), same(closing));
      var closed = false;
      final observedClose = closing.then((_) => closed = true);
      await expectLater(
        store.snapshot(),
        throwsA(_failure('configurationClosed')),
      );
      await expectLater(
        store.bearerToken('http'),
        throwsA(_failure('configurationClosed')),
      );
      // Then close waits, queued credentials do not dispatch, and no transaction
      // holds the other handle hostage while the borrowed provider is pending.
      expect((await other.snapshot()).toJson(), accepted);
      await other.putDrive(_drive('later'));
      expect(closed, isFalse);
      expect(credentials.calls, ['http']);
      release.complete('LATE_SYNTHETIC_TOKEN');
      await readCheck;
      await queuedCheck;
      await observedClose;
      // Then accepted late results are closed, borrowed ownership and data survive.
      expect(closed, isTrue);
      expect(credentials.closed, isFalse);
      expect(credentials.calls, ['http']);
      expect((await other.snapshot()).driveConnections.single.id, 'later');
      await other.putHttp(_http('still_usable'));
      final reopened = await disk.open();
      expect((await reopened.snapshot()).httpConnections.map((c) => c.id), [
        'http',
        'still_usable',
      ]);
    });

    test(
      'unsupported platforms reject before creating the supplied database',
      () async {
        // Given a supplied nonexistent file and a credential owner with visible calls.
        final credentials = _Credentials((_) async => 'unused');
        for (final platform in TargetPlatform.values.where(
          (p) => p != TargetPlatform.iOS,
        )) {
          debugDefaultTargetPlatformOverride = platform;
          // When a caller injects a host factory on an unsupported platform.
          await expectLater(
            IosSubmissionConfigurationStore.open(
              databasePath: disk.path,
              factory: sqlite.databaseFactoryFfi,
              credentials: credentials,
            ),
            throwsUnsupportedError,
          );
          // Then platform rejection occurs before any supplied database/provider IO.
          expect(await File(disk.path).exists(), isFalse);
          expect(credentials.calls, isEmpty);
        }
      },
    );

    test(
      'database acquisition errors do not expose supplied paths or causes',
      () async {
        // Given a test-owned directory where a database file would be required.
        // When SQLite acquisition fails against that directory path.
        await expectLater(
          IosSubmissionConfigurationStore.open(
            databasePath: disk.directory.path,
            factory: sqlite.databaseFactoryFfi,
          ),
          // Then only the fixed unavailable error is observable to the caller.
          throwsA(_failure('configurationUnavailable')),
        );
      },
    );
  });
}

DriveSubmissionConnection _drive(
  String id, {
  String account = 'owner@example.test',
  String folder = 'Folder_1',
}) => DriveSubmissionConnection(id: id, accountId: account, folderId: folder);

HttpSubmissionConnection _http(
  String id, {
  String path = '/submit',
  bool bearer = true,
}) => HttpSubmissionConnection(
  id: id,
  endpoint: Uri.parse('https://example.test$path'),
  requiresBearerToken: bearer,
);

Matcher _failure(String code) => isA<SubmissionConfigurationException>()
    .having((error) => error.code, 'fixed code', code)
    .having(
      (error) => error.message,
      'fixed message',
      SubmissionConfigurationException.messages[code],
    )
    .having(
      (error) => error.toString(),
      'safe diagnostic',
      'SubmissionConfigurationException($code)',
    );

Future<String> _outcome(Future<void> Function() action) async {
  try {
    await action();
    return 'accepted';
  } on SubmissionConfigurationException catch (error) {
    return error.code;
  }
}

final class _Credentials implements SubmissionCredentialProvider {
  _Credentials(this.read);

  Future<String?> Function(String) read;
  final List<String> calls = [];
  bool closed = false;

  @override
  Future<String?> bearerToken(String connectionId) {
    calls.add(connectionId);
    return read(connectionId);
  }

  void close() => closed = true;
}

final class _ConfigurationDisk {
  _ConfigurationDisk(this.directory);

  final Directory directory;
  final List<IosSubmissionConfigurationStore> _stores = [];
  final List<sqlite.Database> _databases = [];

  String get path => '${directory.path}/configuration.sqlite';

  Future<IosSubmissionConfigurationStore> open({
    SubmissionCredentialProvider? credentials,
  }) async {
    final store = await IosSubmissionConfigurationStore.open(
      databasePath: path,
      factory: sqlite.databaseFactoryFfi,
      credentials: credentials,
    );
    _stores.add(store);
    return store;
  }

  Future<sqlite.Database> raw() async {
    final database = await sqlite.databaseFactoryFfi.openDatabase(
      path,
      options: sqlite.OpenDatabaseOptions(singleInstance: false),
    );
    _databases.add(database);
    return database;
  }

  Future<void> dispose() async {
    try {
      for (final store in _stores) {
        await store.close();
      }
      for (final database in _databases) {
        await database.close();
      }
    } finally {
      await directory.delete(recursive: true);
    }
  }
}
