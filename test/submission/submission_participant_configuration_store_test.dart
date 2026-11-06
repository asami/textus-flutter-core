import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqlite;
import 'package:textus_flutter_core/src/authentication/native_authentication_credential_store.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqlite.sqfliteFfiInit();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _ConfigurationDisk disk;
  TargetPlatform? previousPlatform;

  setUp(() async {
    previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    disk = _ConfigurationDisk(
      await Directory.systemTemp.createTemp('participant-configuration-'),
    );
  });

  tearDown(() async {
    try {
      await disk.dispose();
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  group('Android participant configuration channel contract', () {
    const channel = MethodChannel('test/participant-submission-configuration');
    late List<MethodCall> calls;
    late List<AndroidSubmissionConfigurationStore> stores;
    late Future<Object?> Function(MethodCall) reply;

    AndroidSubmissionConfigurationStore open() {
      final store = AndroidSubmissionConfigurationStore(channel: channel);
      stores.add(store);
      return store;
    }

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      calls = [];
      stores = [];
      reply = (_) async => null;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'closeConfiguration') return null;
        return reply(call);
      });
    });

    tearDown(() async {
      try {
        for (final store in stores) {
          await store.close();
        }
      } finally {
        messenger.setMockMethodCallHandler(channel, null);
      }
    });

    test('construction is inert and the real optional capability sends exact DTO and null', () async {
      // Given the actual Android store behind the unchanged base interface.
      final configuration = _participant();
      // When construction occurs without invoking any operation.
      final SubmissionConfigurationStore base = open();
      // Then construction sends no channel work and exposes the optional capability.
      expect(calls, isEmpty);
      expect(base, isA<SubmissionParticipantConfigurationStore>());
      final capable = base as SubmissionParticipantConfigurationStore;
      // When the real optional setter provisions and explicitly clears intent.
      await capable.setParticipantAuthentication(configuration);
      await capable.setParticipantAuthentication(null);
      // Then only the exact bridge method and one-key argument maps are sent.
      expect(calls.map((call) => call.method), [
        'setParticipantAuthentication',
        'setParticipantAuthentication',
      ]);
      expect(calls[0].arguments, {'configuration': configuration.toJson()});
      expect(calls[1].arguments, {'configuration': null});
    });

    for (final response in [
      'nonempty-reply',
      'unknown-platform-error',
      'safe-platform-error',
      'unsupported-method',
    ]) {
      test(
        '$response setter failure uses only fixed safe vocabulary',
        () async {
          // Given an actual channel facade whose native setter cannot succeed.
          final store = open();
          reply = (_) async {
            switch (response) {
              case 'nonempty-reply':
                return {'token': 'PRIVATE_NATIVE_VALUE'};
              case 'unknown-platform-error':
                throw PlatformException(
                  code: 'PRIVATE_NATIVE_VALUE',
                  message: 'PRIVATE_NATIVE_VALUE',
                  details: 'PRIVATE_NATIVE_VALUE',
                );
              case 'safe-platform-error':
                throw PlatformException(
                  code: 'configurationInvalid',
                  message: 'PRIVATE_NATIVE_VALUE',
                  details: 'PRIVATE_NATIVE_VALUE',
                );
              default:
                throw MissingPluginException('PRIVATE_NATIVE_VALUE');
            }
          };
          // When the setter actually executes once and its failure is captured.
          final failure = await _capture(
            () => store.setParticipantAuthentication(_participant()),
          );
          // Then unsupported/unknown replies never synthesize successful configuration.
          expect(
            failure,
            _failure(
              response == 'safe-platform-error'
                  ? 'configurationInvalid'
                  : 'configurationUnavailable',
            ),
          );
          expect(calls.single.method, 'setParticipantAuthentication');
        },
      );
    }

    test('snapshot decodes actual shared v3 without credential or auxiliary calls', () async {
      // Given a literal native v3 response, independent of the shared encoder.
      final body = _literalV3();
      final store = open();
      reply = (_) async => body;
      // When the actual facade reads and decodes that response.
      final snapshot = await store.snapshot();
      (body['participantAuthentication']! as Map)['trustedConnectionIds'] = [];
      // Then real shared DTO identity is detached and no credential access occurred.
      expect(snapshot.participantAuthentication, _participant());
      expect(snapshot.toJson(), _literalV3());
      expect(calls.single.method, 'snapshot');
      expect(calls.single.arguments, isEmpty);
    });

    for (final base in [
      'https://authority.example/account///',
      'https://authority.example/a%2fb/',
      'https://authority.example/%2e%2e/',
    ]) {
      test(
        'native authority $base cannot reach authority projection',
        () async {
          // Given structurally plausible native data that common authority policy rejects.
          final body = _literalV3();
          (body['participantAuthentication']! as Map)['authorityBaseUri'] =
              base;
          final store = open();
          reply = (_) async => body;
          final projected = <UserAccountHttpProfile>[];
          // When real snapshot decode runs before any authority can be used for a scope.
          final failure = await _capture(() async {
            final snapshot = await store.snapshot();
            projected.add(snapshot.participantAuthentication!.authority);
            return null;
          });
          // Then the safe invalidity is observable, no scope input exists, and raw data remains.
          expect(failure, _failure('configurationInvalid'));
          expect(projected, isEmpty);
          expect(
            (body['participantAuthentication']! as Map)['authorityBaseUri'],
            base,
          );
          expect(calls.single.method, 'snapshot');
        },
      );
    }

    test('close drains an accepted setter rejects late success and blocks new calls', () async {
      // Given an actual dispatched setter with a test-controlled native completion.
      final entered = Completer<void>();
      final release = Completer<Object?>();
      addTearDown(() {
        if (!release.isCompleted) release.complete(null);
      });
      final store = open();
      reply = (_) {
        entered.complete();
        return release.future;
      };
      final result = _capture(
        () => store.setParticipantAuthentication(_participant()),
      );
      await entered.future;
      // When close retires the owner while its accepted setter is pending.
      final closing = store.close();
      final sameClose = store.close();
      var closed = false;
      final drained = closing.then((_) => closed = true);
      final newCall = await _capture(
        () => store.setParticipantAuthentication(null),
      );
      // Then close waits for settlement and no new setter or premature native close dispatches.
      expect(sameClose, same(closing));
      expect(newCall, _failure('configurationClosed'));
      expect(closed, isFalse);
      expect(calls.map((call) => call.method), [
        'setParticipantAuthentication',
      ]);
      // When native persistence reports its already accepted completion.
      release.complete(null);
      final lateResult = await result;
      await drained;
      // Then the late result is suppressed and exactly this configuration handle closes.
      expect(lateResult, _failure('configurationClosed'));
      expect(closed, isTrue);
      expect(calls.map((call) => call.method), [
        'setParticipantAuthentication',
        'closeConfiguration',
      ]);
    });

    test(
      'unsupported platform rejects setter before the borrowed channel',
      () async {
        // Given an injected channel on an unsupported platform.
        final store = open();
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        // When the actual setter is invoked once.
        final failure = await _capture(
          () => store.setParticipantAuthentication(_participant()),
        );
        // Then injection does not bypass the existing platform guard.
        expect(failure, isA<UnsupportedError>());
        expect(calls, isEmpty);
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
      },
    );
  });

  group('iOS real SQLite participant configuration', () {
    test('optional capability persists v2 to v3 to v2 across independent handles and reopen', () async {
      // Given a real empty durable store with a borrowed credential owner.
      final credentials = _Credentials((_) async => 'UNREAD_TOKEN');
      final first = await disk.open(credentials: credentials);
      await first.putDrive(_drive('drive'));
      await first.putHttp(_http('server'));
      await first.select(
        storageConnectionId: 'drive',
        transportConnectionId: 'server',
      );
      await first.setReferenceAccess(
        transportConnectionId: 'server',
        storageConnectionIds: ['drive'],
      );
      final second = await disk.open();
      final raw = await disk.raw();
      final original = await raw.query('ios_submission_configuration');
      final SubmissionConfigurationStore base = first;
      // When the actual optional capability sets a participant declaration.
      final capable = base as SubmissionParticipantConfigurationStore;
      await capable.setParticipantAuthentication(_participant());
      final fromSecond = await second.snapshot();
      await first.close();
      final reopened = await disk.open(credentials: credentials);
      final persisted = await reopened.snapshot();
      // Then independent fresh reads and reopen retain v3 with no credential reads.
      expect(base, isA<SubmissionParticipantConfigurationStore>());
      expect(fromSecond.participantAuthentication, _participant());
      expect(persisted.toJson(), fromSecond.toJson());
      expect(persisted.toJson()['version'], 3);
      expect(
        jsonDecode(
          (await raw.query('ios_submission_configuration')).single['body']!
              as String,
        ),
        persisted.toJson(),
      );
      expect(credentials.calls, isEmpty);
      // When null explicitly clears only the declaration and the handle reopens.
      await reopened.setParticipantAuthentication(null);
      await reopened.close();
      final cleared = await (await disk.open()).snapshot();
      // Then canonical v2 bytes, definitions, selection and references are restored exactly.
      expect(cleared.participantAuthentication, isNull);
      expect(cleared.toJson()['version'], 2);
      expect(
        cleared.toJson().containsKey('participantAuthentication'),
        isFalse,
      );
      expect(await raw.query('ios_submission_configuration'), original);
      expect((await second.snapshot()).toJson(), cleared.toJson());
      expect(credentials.calls, isEmpty);
      expect(credentials.closed, isFalse);
    });

    test('selection references idempotence and new definitions preserve participant mode', () async {
      // Given two trusted targets plus unrelated same-origin authenticated and anonymous targets.
      final credentials = _Credentials((_) async => 'UNREAD_TOKEN');
      final store = await disk.open(credentials: credentials);
      await store.putDrive(_drive('drive'));
      await store.putHttp(_http('server'));
      await store.putHttp(_http('laterServer'));
      await store.setParticipantAuthentication(
        _participant(ids: ['server', 'laterServer']),
      );
      // When actual existing mutation paths add definitions, select and replace bindings.
      await store.putDrive(_drive('laterDrive'));
      await store.putHttp(_http('untrusted'));
      await store.putHttp(_http('anonymous', bearer: false));
      await store.putHttp(_http('server'));
      await store.putDrive(_drive('drive'));
      await store.select(
        storageConnectionId: 'laterDrive',
        transportConnectionId: 'laterServer',
      );
      await store.setReferenceAccess(
        transportConnectionId: 'server',
        storageConnectionIds: ['drive'],
      );
      await store.setReferenceAccess(
        transportConnectionId: 'untrusted',
        storageConnectionIds: ['laterDrive'],
      );
      await store.setReferenceAccess(
        transportConnectionId: 'server',
        storageConnectionIds: [],
      );
      final snapshot = await store.snapshot();
      // Then _next and direct-selection paths retain exact trust, order and unrelated declarations.
      expect(
        snapshot.participantAuthentication,
        _participant(ids: ['server', 'laterServer']),
      );
      expect(snapshot.selectedStorageConnectionId, 'laterDrive');
      expect(snapshot.selectedTransportConnectionId, 'laterServer');
      expect(snapshot.referenceAccessBindings, {
        'server': <String>[],
        'untrusted': ['laterDrive'],
      });
      expect(snapshot.driveConnections.map((connection) => connection.id), [
        'drive',
        'laterDrive',
      ]);
      expect(snapshot.httpConnections.map((connection) => connection.id), [
        'server',
        'laterServer',
        'untrusted',
        'anonymous',
      ]);
      expect(snapshot.toJson()['version'], 3);
      expect(credentials.calls, isEmpty);
      // When the real selection is explicitly cleared and the file reopens.
      await store.select();
      await store.close();
      final reopened = await (await disk.open()).snapshot();
      // Then mode persists independently of a current transport choice.
      expect(reopened.selectedTransportConnectionId, isNull);
      expect(
        reopened.participantAuthentication,
        snapshot.participantAuthentication,
      );
      expect(
        reopened.referenceAccessBindings,
        snapshot.referenceAccessBindings,
      );
    });

    for (final target in ['missing', 'drive', 'anonymous', 'other']) {
      test(
        'rejected $target declaration preserves complete SQLite rows',
        () async {
          // Given accepted selection/reference state and all relevant registered kinds.
          final credentials = _Credentials((_) async => 'UNREAD_TOKEN');
          final store = await disk.open(credentials: credentials);
          await store.putDrive(_drive('drive'));
          await store.putHttp(_http('server'));
          await store.putHttp(_http('other'));
          await store.putHttp(_http('anonymous', bearer: false));
          await store.select(
            storageConnectionId: 'drive',
            transportConnectionId: 'server',
          );
          await store.setReferenceAccess(
            transportConnectionId: 'other',
            storageConnectionIds: ['drive'],
          );
          await store.setParticipantAuthentication(_participant());
          final raw = await disk.raw();
          final before = await raw.query('ios_submission_configuration');
          // When actual setter validation attempts the rejected declaration exactly once.
          final failure = await _capture(
            () =>
                store.setParticipantAuthentication(_participant(ids: [target])),
          );
          // Then kind/missing errors differ from invalid anonymous/untrusted selection, without writes.
          expect(
            failure,
            _failure(
              target == 'missing' || target == 'drive'
                  ? 'connectionMissing'
                  : 'configurationInvalid',
            ),
          );
          expect(await raw.query('ios_submission_configuration'), before);
          expect(
            (await store.snapshot()).participantAuthentication,
            _participant(),
          );
          expect(credentials.calls, isEmpty);
        },
      );
    }

    test('registered untrusted selection and immutable retarget failures preserve full rows', () async {
      // Given participant mode and a resolver declaration for an untrusted same-origin target.
      final store = await disk.open();
      await store.putDrive(_drive('drive'));
      await store.putHttp(_http('server'));
      await store.putHttp(_http('other'));
      await store.setReferenceAccess(
        transportConnectionId: 'other',
        storageConnectionIds: ['drive'],
      );
      await store.select(transportConnectionId: 'server');
      await store.setParticipantAuthentication(_participant());
      final raw = await disk.raw();
      final before = await raw.query('ios_submission_configuration');
      // When actual selection and definition writes attempt unauthorized changes once each.
      final selectionFailure = await _capture(
        () => store.select(transportConnectionId: 'other'),
      );
      final conflict = await _capture(
        () => store.putHttp(_http('server', bearer: false)),
      );
      // Then membership and immutable identity fail safely with the entire retained body unchanged.
      expect(selectionFailure, _failure('configurationInvalid'));
      expect(conflict, _failure('connectionConflict'));
      expect(await raw.query('ios_submission_configuration'), before);
    });

    test('aggregate reference and definition bounds fail atomically while mode survives', () async {
      // Given 65 storage targets, three HTTP targets and 128 accepted resolver associations.
      final store = await disk.open();
      for (var index = 0; index < 65; index++) {
        await store.putDrive(_drive('drive_$index'));
      }
      for (final id in ['server', 'other', 'third']) {
        await store.putHttp(_http(id));
      }
      final ids = [for (var index = 0; index < 64; index++) 'drive_$index'];
      await store.setReferenceAccess(
        transportConnectionId: 'server',
        storageConnectionIds: ids,
      );
      await store.setReferenceAccess(
        transportConnectionId: 'other',
        storageConnectionIds: ids,
      );
      await store.setParticipantAuthentication(_participant());
      final raw = await disk.raw();
      final referenceBefore = await raw.query('ios_submission_configuration');
      // When a valid single association would exceed the actual aggregate bound.
      final referenceFailure = await _capture(
        () => store.setReferenceAccess(
          transportConnectionId: 'third',
          storageConnectionIds: ['drive_64'],
        ),
      );
      // Then the failed whole-snapshot write preserves every SQLite row and participant value.
      expect(referenceFailure, _failure('configurationInvalid'));
      expect(await raw.query('ios_submission_configuration'), referenceBefore);
      expect(
        (await store.snapshot()).participantAuthentication,
        _participant(),
      );
      // Given additions then fill the exact 128-definition capacity.
      for (var index = 0; index < 60; index++) {
        await store.putHttp(_http('filler_$index'));
      }
      final definitionsBefore = await raw.query('ios_submission_configuration');
      // When a 129th definition executes through the real _next path.
      final definitionFailure = await _capture(
        () => store.putHttp(_http('overflow')),
      );
      // Then rejection also preserves the complete committed mode and definitions.
      expect(definitionFailure, _failure('configurationInvalid'));
      expect(
        await raw.query('ios_submission_configuration'),
        definitionsBefore,
      );
      expect(
        (await store.snapshot()).participantAuthentication,
        _participant(),
      );
    });

    test('concurrent independent setters and registrations retain both committed facts', () async {
      // Given two independently owned handles and an authenticated registered target.
      final first = await disk.open();
      await first.putHttp(_http('server'));
      final second = await disk.open();
      // When an actual setter and independent definition registration are accepted together.
      await Future.wait([
        first.setParticipantAuthentication(_participant()),
        second.putDrive(_drive('laterDrive')),
      ]);
      final firstValue = await first.snapshot();
      final secondValue = await second.snapshot();
      // Then coordination and fresh reads preserve both facts without stale snapshot loss.
      expect(firstValue.participantAuthentication, _participant());
      expect(firstValue.driveConnections.single.id, 'laterDrive');
      expect(secondValue.toJson(), firstValue.toJson());
    });

    test('explicit authority replacement and clear leave actual queue and borrowed protected storage untouched', () async {
      // Given real durable queued participant intent and the existing protected-store channel seam.
      const credentialChannel = MethodChannel(
        'test/participant-protected-storage',
      );
      final nativeCalls = <String>[];
      final slot = <String, Object?>{
        'revision': 'a' * 32,
        'value': Uint8List.fromList([11, 22, 33, 44]),
      };
      final originalSlot = jsonEncode({
        'revision': slot['revision'],
        'value': (slot['value']! as Uint8List).toList(),
      });
      messenger.setMockMethodCallHandler(credentialChannel, (call) async {
        nativeCalls.add(call.method);
        if (call.method == 'read') return slot;
        if (call.method == 'close') return null;
        throw PlatformException(code: 'credentialStoreInvalidArguments');
      });
      final native = NativeAuthenticationCredentialStore(
        channel: credentialChannel,
      );
      addTearDown(() async {
        try {
          await native.close();
        } finally {
          messenger.setMockMethodCallHandler(credentialChannel, null);
        }
      });
      final credentials = _Credentials((_) async {
        await native.read('operator.main');
        return 'UNREAD_TOKEN';
      });
      final store = await disk.open(credentials: credentials);
      await store.putHttp(_http('server'));
      await store.select(transportConnectionId: 'server');
      await store.setParticipantAuthentication(_participant());
      final queue = await disk.queue();
      final request = SubmissionRequest(
        id: 'queued',
        kind: 'document',
        subjectId: 'subject',
        createdAt: DateTime.utc(2026),
        document: {'unchanged': 'local'},
        payload: {'unchanged': 'packet'},
        materials: [],
        transportConnectionId: 'server',
        authenticationBinding: SubmissionAuthenticationBinding(
          authority: _participant().authority,
          userAccountId: 'account-A',
        ),
      );
      await queue.enqueue(request);
      final queueRaw = await disk.queueRaw();
      final queuedRows = await queueRaw.query('submission_jobs');
      final original = (await store.snapshot()).toJson();
      final replacement = _participant(
        profile: 'operator.next',
        base: 'https://next.example/account/',
      );
      // When a different explicit authority replaces intent, then explicit null clears it.
      await store.setParticipantAuthentication(replacement);
      final replaced = (await store.snapshot()).toJson();
      await store.setParticipantAuthentication(null);
      await store.close();
      final reopened = await disk.open(credentials: credentials);
      final cleared = (await reopened.snapshot()).toJson();
      // Then only declaration/version changed; actual queue bytes and protected slot ownership survive.
      expect(replaced, {
        ...original,
        'participantAuthentication': replacement.toJson(),
      });
      final expectedClear = {...original, 'version': 2}
        ..remove('participantAuthentication');
      expect(cleared, expectedClear);
      expect(await queueRaw.query('submission_jobs'), queuedRows);
      expect((await queue.find('queued'))!.request, request);
      expect(credentials.calls, isEmpty);
      expect(credentials.closed, isFalse);
      expect(nativeCalls, isEmpty);
      expect(
        jsonEncode({
          'revision': slot['revision'],
          'value': (slot['value']! as Uint8List).toList(),
        }),
        originalSlot,
      );
      // When the protected owner is explicitly read after configuration has closed/reopened.
      final retained = await native.read('operator.main');
      // Then the borrowed native store is still usable and has its original opaque value.
      expect(retained!.revision, 'a' * 32);
      expect(retained.value, [11, 22, 33, 44]);
      expect(nativeCalls, ['read']);
    });

    test('independent literal legacy v2 reopens without rewrite or participant adoption', () async {
      // Given a real initialized file whose body is replaced by an independent old literal.
      final first = await disk.open();
      await first.close();
      final raw = await disk.raw();
      final literal = _literalV2();
      await raw.update('ios_submission_configuration', {
        'body': jsonEncode(literal),
      });
      final before = await raw.query('ios_submission_configuration');
      // When a new real store opens and reads that exact body.
      final reopened = await disk.open();
      final snapshot = await reopened.snapshot();
      // Then authenticated target presence does not adopt participant mode or rewrite rows.
      expect(snapshot.toJson(), literal);
      expect(snapshot.participantAuthentication, isNull);
      expect(await raw.query('ios_submission_configuration'), before);
    });

    test(
      'participant setter rejects aggregate snapshot overflow before writing',
      () async {
        // Given a real retained v2 body near the aggregate limit with individually valid definitions.
        final store = await disk.open();
        HttpSubmissionConnection largeConnection(String id) {
          final ordinary = _http(id);
          final padding =
              65500 - utf8.encode(jsonEncode(ordinary.toJson())).length;
          return HttpSubmissionConnection(
            id: id,
            endpoint: Uri.parse('${ordinary.endpoint}${'a' * padding}'),
          );
        }

        final current = SubmissionConfigurationSnapshot(
          driveConnections: [],
          httpConnections: [
            for (var index = 0; index < 128; index++)
              largeConnection('server_$index'),
          ],
          selectedTransportConnectionId: 'server_0',
        );
        const prefix = 'https://authority.example/a';
        final ordinary = _participant(ids: ['server_0'], base: '$prefix/');
        final padding =
            65536 - utf8.encode(jsonEncode(ordinary.toJson())).length;
        final declaration = _participant(
          ids: ['server_0'],
          base: '$prefix${'a' * padding}/',
        );
        final raw = await disk.raw();
        await raw.update('ios_submission_configuration', {
          'body': jsonEncode(current.toJson()),
        });
        final before = await raw.query('ios_submission_configuration');
        // When a valid bounded DTO would overflow the complete persisted snapshot.
        final failure = await _capture(
          () => store.setParticipantAuthentication(declaration),
        );
        // Then whole-result validation fails before any SQLite body change or declaration adoption.
        expect(utf8.encode(jsonEncode(declaration.toJson())), hasLength(65536));
        expect(
          utf8.encode(jsonEncode(current.toJson())).length,
          lessThanOrEqualTo(128 * 65536),
        );
        expect(failure, _failure('configurationInvalid'));
        expect(await raw.query('ios_submission_configuration'), before);
        expect((await store.snapshot()).participantAuthentication, isNull);
      },
    );

    final corruptBodies = <String, Object?>{
      'legacy-v1': {..._literalV2(), 'version': 1}
        ..remove('referenceAccessBindings'),
      'future-v4': {..._literalV3(), 'version': 4},
      'malformed': 'PRIVATE_STORED_VALUE',
      'missing-v3-declaration': {..._literalV3()}
        ..remove('participantAuthentication'),
      'null-v3-declaration': {
        ..._literalV3(),
        'participantAuthentication': null,
      },
      'extra-v3-key': {..._literalV3(), 'token': 'PRIVATE_STORED_VALUE'},
      'wrong-v3-type': {..._literalV3(), 'participantAuthentication': []},
      'bad-canonical-authority': {
        ..._literalV3(),
        'participantAuthentication': {
          ..._literalParticipant(),
          'authorityBaseUri': 'https://authority.example/account///',
        },
      },
      'bad-authority-path': {
        ..._literalV3(),
        'participantAuthentication': {
          ..._literalParticipant(),
          'authorityBaseUri': 'https://authority.example/a%2fb/',
        },
      },
    };
    for (final corruption in corruptBodies.entries) {
      test(
        '${corruption.key} raw body is rejected without replacing rows or projecting authority',
        () async {
          // Given a real file with an independently supplied corrupt retained body.
          final first = await disk.open();
          await first.close();
          final raw = await disk.raw();
          final body = corruption.value is String
              ? corruption.value! as String
              : jsonEncode(corruption.value);
          await raw.update('ios_submission_configuration', {'body': body});
          final before = await raw.query('ios_submission_configuration');
          final projected = <UserAccountHttpProfile>[];
          // When strict real open/read is attempted exactly once before any scope projection.
          final failure = await _capture(() async {
            final store = await disk.open();
            final snapshot = await store.snapshot();
            projected.add(snapshot.participantAuthentication!.authority);
            return null;
          });
          // Then invalid retained data stays visible, unchanged, and supplies no usable authority.
          expect(failure, _failure('configurationInvalid'));
          expect(await raw.query('ios_submission_configuration'), before);
          expect(projected, isEmpty);
        },
      );
    }

    test('fresh setter read rejects corruption committed by another handle without repair', () async {
      // Given a live real store whose previously valid singleton is corrupted externally.
      final store = await disk.open();
      await store.putHttp(_http('server'));
      final raw = await disk.raw();
      await raw.update('ios_submission_configuration', {'body': '{}'});
      final before = await raw.query('ios_submission_configuration');
      // When the real setter attempts an explicit clear against its fresh full snapshot.
      final failure = await _capture(
        () => store.setParticipantAuthentication(null),
      );
      // Then no cached valid state or empty fallback replaces the corrupt retained rows.
      expect(failure, _failure('configurationInvalid'));
      expect(await raw.query('ios_submission_configuration'), before);
    });

    test('SQL failure during setter retains unavailable classification and full rows', () async {
      // Given a valid real singleton and a test-owned trigger that refuses UPDATE IO.
      final store = await disk.open();
      await store.putHttp(_http('server'));
      final raw = await disk.raw();
      await raw.execute(
        "CREATE TRIGGER reject_configuration_update BEFORE UPDATE ON ios_submission_configuration BEGIN SELECT RAISE(ABORT, 'PRIVATE_SQL_FAILURE'); END",
      );
      final before = await raw.query('ios_submission_configuration');
      // When model admission succeeds but the actual SQLite write fails once.
      final failure = await _capture(
        () => store.setParticipantAuthentication(_participant()),
      );
      // Then SQL failure is unavailable, never misclassified as invalid model data.
      expect(failure, _failure('configurationUnavailable'));
      expect(await raw.query('ios_submission_configuration'), before);
    });

    test('close drains a dispatched borrowed read and an accepted setter without closing credentials', () async {
      // Given a real handle with a dispatched credential read and another independent handle.
      final entered = Completer<void>();
      final release = Completer<String?>();
      addTearDown(() {
        if (!release.isCompleted) release.complete(null);
      });
      final credentials = _Credentials((_) {
        entered.complete();
        return release.future;
      });
      final store = await disk.open(credentials: credentials);
      await store.putHttp(_http('server'));
      await store.setParticipantAuthentication(_participant());
      final other = await disk.open();
      final before = (await other.snapshot()).toJson();
      final read = _capture(() => store.bearerToken('server'));
      await entered.future;
      // When setter is accepted behind the read and close retires before its dispatch.
      final setter = _capture(() => store.setParticipantAuthentication(null));
      final closing = store.close();
      final sameClose = store.close();
      var closed = false;
      final drained = closing.then((_) => closed = true);
      final newCall = await _capture(
        () => store.setParticipantAuthentication(_participant()),
      );
      final otherValue = await other.snapshot();
      await other.putDrive(_drive('independent'));
      // Then close waits, new calls fail, queued setter has no IO, and the other handle progresses.
      expect(sameClose, same(closing));
      expect(newCall, _failure('configurationClosed'));
      expect(closed, isFalse);
      expect(otherValue.toJson(), before);
      expect(credentials.calls, ['server']);
      expect(credentials.closed, isFalse);
      // When only the test-owned credential completion is released.
      release.complete('LATE_TOKEN');
      final readFailure = await read;
      final setterFailure = await setter;
      await drained;
      final reopened = await (await disk.open()).snapshot();
      // Then accepted late results are closed, declaration persists and borrowing stays intact.
      expect(readFailure, _failure('configurationClosed'));
      expect(setterFailure, _failure('configurationClosed'));
      expect(closed, isTrue);
      expect(reopened.participantAuthentication, _participant());
      expect(reopened.driveConnections.single.id, 'independent');
      expect(credentials.closed, isFalse);
      expect(credentials.calls, ['server']);
    });
  });
}

SubmissionParticipantAuthenticationConfiguration _participant({
  List<String> ids = const ['server'],
  String profile = 'operator.main',
  String base = 'https://authority.example/account/',
}) => SubmissionParticipantAuthenticationConfiguration(
  authorityProfileId: profile,
  authorityBaseUri: base,
  trustedConnectionIds: ids,
);

DriveSubmissionConnection _drive(String id) => DriveSubmissionConnection(
  id: id,
  accountId: 'owner@example.test',
  folderId: 'Folder_1',
);

HttpSubmissionConnection _http(String id, {bool bearer = true}) =>
    HttpSubmissionConnection(
      id: id,
      endpoint: Uri.parse('https://example.test/submit'),
      requiresBearerToken: bearer,
    );

Map<String, Object?> _literalParticipant() => {
  'version': 1,
  'authorityProfileId': 'operator.main',
  'authorityBaseUri': 'https://authority.example/account/',
  'trustedConnectionIds': ['server'],
};

Map<String, Object?> _literalV2() => {
  'version': 2,
  'driveConnections': [
    {
      'version': 1,
      'type': 'googleDrive',
      'id': 'drive',
      'accountId': 'owner@example.test',
      'folderId': 'Folder_1',
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
  'referenceAccessBindings': {
    'server': ['drive'],
  },
};

Map<String, Object?> _literalV3() => {
  ..._literalV2(),
  'version': 3,
  'participantAuthentication': _literalParticipant(),
};

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

Future<Object?> _capture(FutureOr<Object?> Function() action) async {
  try {
    await action();
    return null;
  } catch (error) {
    return error;
  }
}

final class _Credentials implements SubmissionCredentialProvider {
  _Credentials(this.read);

  final Future<String?> Function(String) read;
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
  final List<SqliteSubmissionQueueStore> _queues = [];

  String get path => '${directory.path}/configuration.sqlite';
  String get queuePath => '${directory.path}/queue.sqlite';

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

  Future<sqlite.Database> raw() => _raw(path);
  Future<sqlite.Database> queueRaw() => _raw(queuePath);

  Future<sqlite.Database> _raw(String databasePath) async {
    final database = await sqlite.databaseFactoryFfi.openDatabase(
      databasePath,
      options: sqlite.OpenDatabaseOptions(singleInstance: false),
    );
    _databases.add(database);
    return database;
  }

  Future<SqliteSubmissionQueueStore> queue() async {
    final queue = await SqliteSubmissionQueueStore.open(
      queuePath,
      factory: sqlite.databaseFactoryFfi,
    );
    _queues.add(queue);
    return queue;
  }

  Future<void> dispose() async {
    try {
      for (final store in _stores) {
        await store.close();
      }
      for (final queue in _queues) {
        await queue.close();
      }
      for (final database in _databases) {
        await database.close();
      }
    } finally {
      await directory.delete(recursive: true);
    }
  }
}
