import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

import '../support/submission_background_fixture.dart';

void main() {
  group('NB2 immutable configuration', () {
    test('roundtrip freezes caller lists and exposes only safe definitions', () {
      // Given mutable caller lists of the accepted B1 safe connection values.
      final drive = DriveSubmissionConnection(
        id: 'drive',
        accountId: 'owner@example.test',
        folderId: 'Folder_1',
      );
      final http = HttpSubmissionConnection(
        id: 'http',
        endpoint: Uri.parse('https://example.test/v1/submit'),
      );
      final supplied = [drive];
      // When a public snapshot freezes the lists and roundtrips its closed codec.
      final snapshot = SubmissionConfigurationSnapshot(
        driveConnections: supplied,
        httpConnections: [http],
        selectedStorageConnectionId: 'drive',
        selectedTransportConnectionId: 'http',
      );
      supplied.clear();
      final restored = SubmissionConfigurationSnapshot.fromJson(
        snapshot.toJson(),
      );
      // Then identity/selection survives and callers cannot alter either list.
      expect(restored.toJson(), snapshot.toJson());
      expect(snapshot.driveConnections.single, same(drive));
      expect(() => snapshot.driveConnections.clear(), throwsUnsupportedError);
      expect(() => snapshot.httpConnections.clear(), throwsUnsupportedError);
      expect(
        snapshot.toJson().keys,
        unorderedEquals([
          'version',
          'driveConnections',
          'httpConnections',
          'selectedStorageConnectionId',
          'selectedTransportConnectionId',
          'referenceAccessBindings',
        ]),
      );
    });

    test('rejects closed schema version types duplicate kinds missing selections and capacity', () {
      // Given a legitimate empty snapshot only representing an absent test store.
      final empty = SubmissionConfigurationSnapshot(
        driveConnections: [],
        httpConnections: [],
      );
      final drive = DriveSubmissionConnection(
        id: 'one',
        accountId: 'owner@example.test',
        folderId: 'Folder',
      );
      final http = HttpSubmissionConnection(
        id: 'one',
        endpoint: Uri.parse('https://example.test/submit'),
      );
      // When malformed native/schema values or inconsistent selections are decoded.
      for (final json in [
        {...empty.toJson(), 'version': 3},
        {...empty.toJson(), 'version': 1.0},
        {...empty.toJson(), 'token': 'PRIVATE_MARKER'},
        {...empty.toJson()}..remove('httpConnections'),
        {...empty.toJson(), 'driveConnections': 'not-a-list'},
        {...empty.toJson(), 'selectedStorageConnectionId': 'absent'},
        {
          ...empty.toJson(),
          'httpConnections': [http.toJson()],
          'selectedStorageConnectionId': 'one',
        },
      ]) {
        // Then corruption is an observable error and never a fabricated empty store.
        expect(
          () => SubmissionConfigurationSnapshot.fromJson(json),
          throwsFormatException,
        );
      }
      // When constructors receive duplicate ids across kinds or more than 128 targets.
      expect(
        () => SubmissionConfigurationSnapshot(
          driveConnections: [drive],
          httpConnections: [http],
        ),
        throwsArgumentError,
      );
      expect(
        () => SubmissionConfigurationSnapshot(
          driveConnections: [drive, drive],
          httpConnections: [],
        ),
        throwsArgumentError,
      );
      expect(
        () => SubmissionConfigurationSnapshot(
          driveConnections: [],
          httpConnections: [
            for (var i = 0; i < 129; i++)
              HttpSubmissionConnection(
                id: 'http_$i',
                endpoint: Uri.parse('https://example.test/submit'),
              ),
          ],
        ),
        throwsArgumentError,
      );
      // Then the original empty value remains a valid unchanged version 2 snapshot.
      expect(empty.driveConnections, isEmpty);
      expect(empty.selectedStorageConnectionId, isNull);
    });

    test('idempotent writes conflict atomically on account folder endpoint auth or kind', () async {
      // Given a behavioral test port holding one immutable Drive and one HTTP target.
      final store = MemorySubmissionConfigurationStore();
      final drive = DriveSubmissionConnection(
        id: 'drive',
        accountId: 'owner@example.test',
        folderId: 'Folder',
      );
      final http = HttpSubmissionConnection(
        id: 'http',
        endpoint: Uri.parse('https://example.test/submit'),
      );
      await store.putDrive(drive);
      await store.putHttp(http);
      addTearDown(() async {
        // Given only this test owns its configuration handle.
        final owned = store;
        // When teardown retires it.
        await owned.close();
        // Then subsequent calls fail rather than silently reopen.
        await expectLater(
          owned.snapshot(),
          throwsA(isA<SubmissionConfigurationException>()),
        );
      });
      final accepted = (await store.snapshot()).toJson();
      // When identical definitions are put again and each identity component is changed.
      await store.putDrive(DriveSubmissionConnection.fromJson(drive.toJson()));
      await store.putHttp(HttpSubmissionConnection.fromJson(http.toJson()));
      for (final proposed in [
        DriveSubmissionConnection(
          id: 'drive',
          accountId: 'other@example.test',
          folderId: 'Folder',
        ),
        DriveSubmissionConnection(
          id: 'drive',
          accountId: 'owner@example.test',
          folderId: 'OtherFolder',
        ),
      ]) {
        // Then a changed storage identity cannot replace the previously accepted row.
        await expectLater(
          store.putDrive(proposed),
          throwsA(_configurationFailure('connectionConflict')),
        );
        expect((await store.snapshot()).toJson(), accepted);
      }
      for (final proposed in [
        HttpSubmissionConnection(
          id: 'http',
          endpoint: Uri.parse('https://example.test/other'),
        ),
        HttpSubmissionConnection(
          id: 'http',
          endpoint: http.endpoint,
          requiresBearerToken: false,
        ),
        HttpSubmissionConnection(id: 'drive', endpoint: http.endpoint),
      ]) {
        // When HTTP endpoint/auth requirement/kind attempts to reuse an immutable id.
        await expectLater(
          store.putHttp(proposed),
          throwsA(_configurationFailure('connectionConflict')),
        );
        // Then even the selection and other definitions remain unchanged.
        expect((await store.snapshot()).toJson(), accepted);
      }
    });

    test('HTTP rotation and selection affect new intent only and never expose secrets', () async {
      // Given an existing immutable queue request refers to previously selected ids.
      final fixture = await SubmissionBackgroundFixture.create();
      addTearDown(fixture.dispose);
      final request = await fixture.disk.request();
      final queue = await fixture.disk.openQueue();
      await queue.enqueue(request);
      final store = fixture.configuration;
      await store.putDrive(
        DriveSubmissionConnection(
          id: 'laterDrive',
          accountId: 'later@example.test',
          folderId: 'LaterFolder',
        ),
      );
      await store.putHttp(
        HttpSubmissionConnection(
          id: 'laterServer',
          endpoint: Uri.parse('https://later.example.test/submit'),
        ),
      );
      // When selection changes and the matching old HTTP secret rotates then clears.
      await store.select(
        storageConnectionId: 'laterDrive',
        transportConnectionId: 'laterServer',
      );
      await store.setHttpBearerToken('server', 'PRIVATE_MARKER_1');
      expect(await store.bearerToken('server'), 'PRIVATE_MARKER_1');
      await store.setHttpBearerToken('server', 'PRIVATE_MARKER_2');
      expect(await store.bearerToken('server'), 'PRIVATE_MARKER_2');
      await store.setHttpBearerToken('server', null);
      // Then all old definitions and original intent survive, while config has no token.
      expect(await store.bearerToken('server'), isNull);
      final snapshot = await store.snapshot();
      expect(snapshot.driveConnections.map((c) => c.id), contains('drive'));
      expect(snapshot.httpConnections.map((c) => c.id), contains('server'));
      expect((await queue.find(request.id))!.request, request);
      expect(snapshot.selectedStorageConnectionId, 'laterDrive');
      expect(jsonEncode(snapshot.toJson()), isNot(contains('PRIVATE_MARKER')));
      // When a wrong-kind selection, anonymous secret or malformed token is proposed.
      await expectLater(
        store.select(
          storageConnectionId: 'server',
          transportConnectionId: 'laterServer',
        ),
        throwsArgumentError,
      );
      await store.putHttp(
        HttpSubmissionConnection(
          id: 'anonymous',
          endpoint: Uri.parse('https://example.test/anon'),
          requiresBearerToken: false,
        ),
      );
      await expectLater(
        store.setHttpBearerToken('anonymous', 'PRIVATE_MARKER'),
        throwsA(_configurationFailure('configurationInvalid')),
      );
      await expectLater(
        store.setHttpBearerToken('server', 'invalid\r\nPRIVATE_MARKER'),
        throwsA(_configurationFailure('configurationInvalid')),
      );
      // Then rejected writes preserve the prior selection and null credential.
      expect(
        (await store.snapshot()).selectedStorageConnectionId,
        'laterDrive',
      );
      expect(await store.bearerToken('server'), isNull);
    });

    test('fixed failure vocabulary refuses arbitrary messages and sanitizes unknown codes', () {
      // Given untrusted SDK-style text containing account/token markers.
      const raw = 'PRIVATE_MARKER owner@example.test';
      // When an unknown native code is sanitized or arbitrary text is proposed.
      final safe = SubmissionConfigurationException.safe(raw);
      // Then no input/cause reaches the public exception vocabulary.
      expect(safe.code, 'configurationUnavailable');
      expect('${safe.message}$safe', isNot(contains('PRIVATE_MARKER')));
      expect(
        () => SubmissionConfigurationException(
          code: 'connectionConflict',
          message: raw,
        ),
        throwsArgumentError,
      );
    });
  });

  group('RA2 explicit reference access configuration', () {
    test('literal v1 grants nothing and v2 deeply freezes mandatory bindings', () {
      // Given an independent exact old literal snapshot and mutable v2 inputs.
      final legacy = <String, Object?>{
        'version': 1,
        'driveConnections': [
          {
            'version': 1,
            'type': 'googleDrive',
            'id': 'drive',
            'accountId': 'owner@example.test',
            'folderId': 'Folder',
          },
        ],
        'httpConnections': [
          {
            'version': 1,
            'type': 'http',
            'id': 'server',
            'endpoint': 'https://example.test/submit',
            'requiresBearerToken': true,
          },
        ],
        'selectedStorageConnectionId': 'drive',
        'selectedTransportConnectionId': 'server',
      };
      final old = SubmissionConfigurationSnapshot.fromJson(legacy);
      final ids = ['drive'];
      final bindings = {'server': ids};
      // When v2 snapshots detach inputs and return detached wire values.
      final current = SubmissionConfigurationSnapshot(
        driveConnections: old.driveConnections,
        httpConnections: old.httpConnections,
        selectedStorageConnectionId: 'drive',
        selectedTransportConnectionId: 'server',
        referenceAccessBindings: bindings,
      );
      ids.clear();
      bindings.clear();
      final wire = current.toJson();
      final restored = SubmissionConfigurationSnapshot.fromJson(wire);
      (wire['referenceAccessBindings']! as Map)['server'].clear();
      // Then legacy selection grants no access and frozen v2 retains exact ids.
      expect(old.referenceAccessBindings, isEmpty);
      expect(old.toJson()['version'], 2);
      expect(current.referenceAccessBindings, {
        'server': ['drive'],
      });
      expect(restored.toJson(), current.toJson());
      expect(
        () => current.referenceAccessBindings.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => current.referenceAccessBindings['server']!.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => SubmissionConfigurationSnapshot.fromJson({
          ...legacy,
          'referenceAccessBindings': {},
        }),
        throwsFormatException,
      );
    });

    test('closed v2 rejects unsafe duplicate dangling wrong-kind and bounded maps', () {
      // Given valid exact kinds independent of any credentials or remote grants.
      final base = SubmissionConfigurationSnapshot(
        driveConnections: [
          DriveSubmissionConnection(
            id: 'drive',
            accountId: 'owner@example.test',
            folderId: 'Folder',
          ),
        ],
        httpConnections: [
          HttpSubmissionConnection(
            id: 'server',
            endpoint: Uri.parse('https://example.test/submit'),
          ),
        ],
        referenceAccessBindings: {
          'server': ['drive'],
        },
      ).toJson();
      final malformed = <Map<String, Object?>>[
        {...base}..remove('referenceAccessBindings'),
        {...base, 'extra': null},
        {...base, 'version': '2'},
        {...base, 'version': 2.0},
        {...base, 'version': 3},
        for (final bindings in [
          null,
          [],
          {'server': 'drive'},
          {
            'server': [9],
          },
          {
            'server': ['drive', 'drive'],
          },
          {'../unsafe': []},
          {
            'server': ['../unsafe'],
          },
          {'missing': []},
          {'drive': []},
          {
            'server': ['server'],
          },
          {
            'server': ['missing'],
          },
          {for (var i = 0; i < 129; i++) 'server_$i': <String>[]},
        ])
          {...base, 'referenceAccessBindings': bindings},
      ];
      // When each malformed current schema is independently decoded.
      for (final value in malformed) {
        // Then every failure is observable without a fabricated empty binding.
        expect(
          () => SubmissionConfigurationSnapshot.fromJson(value),
          throwsFormatException,
        );
      }
      // Given 65 Drive ids and two HTTP ids fit the combined definition bound.
      final drives = [
        for (var i = 0; i < 65; i++)
          DriveSubmissionConnection(
            id: 'drive_$i',
            accountId: 'owner@example.test',
            folderId: 'Folder',
          ),
      ];
      final servers = [
        for (var i = 0; i < 2; i++)
          HttpSubmissionConnection(
            id: 'server_$i',
            endpoint: Uri.parse('https://example.test/submit'),
          ),
      ];
      // When 130 distinct associations across two maps exceed the aggregate limit.
      // Then repeated ids across different transports still count toward capacity.
      expect(
        () => SubmissionConfigurationSnapshot(
          driveConnections: drives,
          httpConnections: servers,
          referenceAccessBindings: {
            for (final server in servers)
              server.id: drives.map((c) => c.id).toList(),
          },
        ),
        throwsArgumentError,
      );
      expect(
        SubmissionConfigurationSnapshot.fromJson(base).referenceAccessBindings,
        {
          'server': ['drive'],
        },
      );
    });

    test('replace revoke and equal writes are atomic and preserve all other intent', () async {
      // Given real queued immutable intent and explicitly provisioned test bindings.
      final fixture = await SubmissionBackgroundFixture.create();
      addTearDown(fixture.dispose);
      final store = fixture.configuration;
      final queue = await fixture.disk.openQueue();
      final request = await fixture.disk.request();
      await queue.enqueue(request);
      await store.putDrive(
        DriveSubmissionConnection(
          id: 'laterDrive',
          accountId: 'later@example.test',
          folderId: 'LaterFolder',
        ),
      );
      await store.putHttp(
        HttpSubmissionConnection(
          id: 'laterServer',
          endpoint: Uri.parse('https://later.example.test/submit'),
        ),
      );
      await store.setReferenceAccess(
        transportConnectionId: 'laterServer',
        storageConnectionIds: ['laterDrive'],
      );
      final input = ['drive', 'laterDrive'];
      // When one binding is replaced, equal writes repeat, selection/secret rotate.
      await store.setReferenceAccess(
        transportConnectionId: 'server',
        storageConnectionIds: input,
      );
      input.clear();
      await store.setReferenceAccess(
        transportConnectionId: 'server',
        storageConnectionIds: ['drive', 'laterDrive'],
      );
      await store.select(
        storageConnectionId: 'laterDrive',
        transportConnectionId: 'laterServer',
      );
      await store.setHttpBearerToken('server', 'PRIVATE_MARKER_token');
      await store.setHttpBearerToken('server', null);
      final beforeInvalid = (await store.snapshot()).toJson();
      for (final pair in [
        ('server', ['drive', 'drive']),
        ('drive', <String>[]),
        ('server', ['server']),
        ('missing', <String>[]),
      ]) {
        // Given a proposal invalid under the whole-map registered kind policy.
        // When its actual write is rejected before committing any changed map.
        await expectLater(
          store.setReferenceAccess(
            transportConnectionId: pair.$1,
            storageConnectionIds: pair.$2,
          ),
          throwsArgumentError,
        );
        // Then every safe definition, selection and other binding is unchanged.
        expect((await store.snapshot()).toJson(), beforeInvalid);
      }
      // When the old transport is explicitly revoked with an empty replacement.
      await store.setReferenceAccess(
        transportConnectionId: 'server',
        storageConnectionIds: [],
      );
      final retained = await store.snapshot();
      // Then explicit empty differs from unknown and preserves unrelated data.
      expect(retained.referenceAccessBindings, {
        'server': [],
        'laterServer': ['laterDrive'],
      });
      expect(retained.selectedStorageConnectionId, 'laterDrive');
      expect(retained.selectedTransportConnectionId, 'laterServer');
      expect(retained.driveConnections.length, 2);
      expect(retained.httpConnections.length, 2);
      expect((await queue.find(request.id))!.request, request);
      expect(await store.bearerToken('server'), isNull);
      expect(jsonEncode(retained.toJson()), isNot(contains('PRIVATE_MARKER')));
    });
  });
}

Matcher _configurationFailure(String code) {
  // Given a selected safe public failure identity.
  final expected = code;
  // When a scenario inspects its observable public exception.
  final matcher = isA<SubmissionConfigurationException>().having(
    (e) => e.code,
    'safe code',
    expected,
  );
  // Then assertions match behavior rather than implementation text or native crypto.
  return matcher;
}
