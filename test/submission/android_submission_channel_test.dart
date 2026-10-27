import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sqlite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

import '../support/submission_fixture.dart' show ControlledScheduler;
import '../support/submission_background_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.textus.flutter.core/submission');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  late AndroidSubmissionConfigurationStore store;
  late Map<String, Object?> snapshot;
  FutureOr<Object?> Function(MethodCall)? respond;

  setUp(() {
    // Given Android is explicitly selected for this mock-channel behavior suite.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    respond = null;
    snapshot = SubmissionConfigurationSnapshot(
      driveConnections: [],
      httpConnections: [],
    ).toJson();
    store = AndroidSubmissionConfigurationStore(channel: channel);
    // When a native port captures exact calls and supplies controlled safe results.
    messenger.setMockMethodCallHandler(channel, (call) async {
      // Given a real wrapper method has crossed the MethodChannel codec.
      calls.add(call);
      // When a scenario controls that operation, forward only its selected result.
      final selected = respond;
      if (selected != null) return selected(call);
      // Then default reads/writes return strict safe protocol values without Google proof.
      return call.method == 'snapshot' ? snapshot : null;
    });
    // Then every scenario observes actual public facade behavior on this borrowed port.
  });

  tearDown(() async {
    // Given the test owns the facade and mock handler, independently of durable jobs.
    respond = null;
    // When owned calls drain and only this channel hook is removed.
    await store.close();
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
    // Then no mock platform override or open test facade survives the scenario.
    expect(calls.last.method, 'closeConfiguration');
  });

  group('NB3 Android channel', () {
    test('fresh facade after close retains safe configuration and credentials while old calls stay closed', () async {
      // Given persisted controlled definitions and a dedicated credential result on the same channel.
      final http = HttpSubmissionConnection(
        id: 'server',
        endpoint: Uri.parse('https://example.test/submit'),
      );
      snapshot = SubmissionConfigurationSnapshot(
        driveConnections: [],
        httpConnections: [http],
        selectedTransportConnectionId: 'server',
      ).toJson();
      String? token;
      respond = (call) {
        // Given controlled backing persists independently of foreground facade close.
        final arguments = call.arguments as Map;
        // When a dedicated credential write or read crosses the existing codec.
        if (call.method == 'setHttpBearerToken') {
          token = arguments['token'] as String?;
        }
        if (call.method == 'bearerToken') return token;
        // Then safe snapshots retain definitions and scheduler/close operations return only null.
        return call.method == 'snapshot' ? snapshot : null;
      };
      final fresh = AndroidSubmissionConfigurationStore(channel: channel);
      final scheduler = AndroidSubmissionBackgroundScheduler(channel: channel);
      try {
        await store.setHttpBearerToken('server', 'PRIVATE_MARKER_token');
        // When the first facade closes twice and a new facade reads in the same channel lifetime.
        await store.close();
        await store.close();
        final retained = await fresh.snapshot();
        final retainedToken = await fresh.bearerToken('server');
        final beforeClosedCalls = calls.length;
        await expectLater(
          store.snapshot(),
          throwsA(_safeFailure('configurationClosed')),
        );
        await expectLater(
          store.bearerToken('server'),
          throwsA(_safeFailure('configurationClosed')),
        );
        // Then the old facade performs no IO and the fresh facade reads exact safe backing and token.
        expect(calls.length, beforeClosedCalls);
        expect(retained.toJson(), snapshot);
        expect(
          jsonEncode(retained.toJson()),
          isNot(contains('PRIVATE_MARKER')),
        );
        expect(retainedToken, 'PRIVATE_MARKER_token');
        expect(calls.where((c) => c.method == 'closeConfiguration').length, 1);
        // When the independent scheduler registers and wakes after configuration close.
        await scheduler.initialize();
        await scheduler.requestRun();
        // Then callback persistence and the exact wake remain usable without reopening old ownership.
        expect(calls.map((c) => c.method), [
          'setHttpBearerToken',
          'closeConfiguration',
          'snapshot',
          'bearerToken',
          'initializeBackground',
          'scheduleBackground',
        ]);
        expect((calls[4].arguments as Map)['callbackHandle'], isPositive);
        expect(calls.last.arguments, {'delayMs': 0});
      } finally {
        // Given this scenario owns the fresh configuration and scheduler facades.
        // When their operations drain through idempotent close.
        try {
          await fresh.close();
        } finally {
          await scheduler.close();
        }
        // Then the suite can remove its borrowed channel hook without open scenario owners.
      }
    });

    test('default foreground composition reopens real queue and originals after close and snapshot failure cleanup', () async {
      // Given one test-owned application-support directory and scoped real host SQLite.
      sqfliteFfiInit();
      final directory = await Directory.systemTemp.createTemp(
        'submission-default-reopen-',
      );
      final originalFactory = sqlite.databaseFactoryOrNull;
      const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
      final scheduler = ControlledScheduler();
      final resources = <SubmissionBackgroundResources>[];
      final firstLifetime = SubmissionRunLifetime(id: 'foreground_first');
      final failedLifetime = SubmissionRunLifetime(id: 'foreground_failed');
      final freshLifetime = SubmissionRunLifetime(id: 'foreground_fresh');
      var failSnapshot = false;
      respond = (call) {
        // Given the controlled native snapshot is separate from real queue/original persistence.
        if (call.method == 'snapshot' && failSnapshot) {
          // When one fresh acquisition fails before the default queue opens.
          failSnapshot = false;
          throw PlatformException(code: 'configurationUnavailable');
        }
        // Then later fresh acquisition can read safe backing, and close preserves that backing.
        return call.method == 'snapshot' ? snapshot : null;
      };
      try {
        sqlite.databaseFactoryOrNull = databaseFactoryFfi;
        messenger.setMockMethodCallHandler(pathChannel, (call) async {
          // Given every default support-root lookup belongs to this temporary directory.
          // When the actual public default factories request application support.
          expect(call.method, 'getApplicationSupportDirectory');
          // Then both queue and originals receive exactly the same test-owned root.
          return directory.path;
        });
        final first = await openDefaultAndroidSubmissionResources(
          lifetime: firstLifetime,
          scheduler: scheduler,
        );
        resources.add(first);
        final originals = await openDefaultCaptureStore();
        final bytes = Uint8List.fromList([255, 216, 10, 20, 255, 217]);
        final capturedAt = DateTime.utc(2026, 10, 10, 1);
        final original = await originals.saveMaterial(
          bytes: bytes,
          mediaType: 'image/jpeg',
          capturedAt: capturedAt,
          originalName: 'retained.original',
        );
        final request = SubmissionRequest(
          id: 'reopen_commit',
          kind: 'bookMaterial',
          subjectId: 'reopen_subject',
          createdAt: capturedAt,
          document: {'draft': true},
          payload: {'transcript': '  手入力\n原文  '},
          materials: [
            SubmissionMaterial(
              key: 'photo',
              original: original,
              provenance: {'source': 'unchanged'},
            ),
          ],
          transportConnectionId: 'server',
          storageConnectionId: 'drive',
          extensions: {
            'execution': {'locale': 'ja'},
          },
        );
        final accepted = await first.queue.enqueue(request);
        // When the first actual default composition closes completely and repeated close joins it.
        await first.close();
        await first.close();
        // Then its lifetime is permanently retired and the old queue handle rejects reads.
        expect(firstLifetime.isCurrent, isFalse);
        await expectLater(first.queue.find(request.id), throwsStateError);
        expect(scheduler.calls, 0);
        // When a new lifetime's snapshot fails and the actual factory cleans partial acquisition.
        failSnapshot = true;
        await expectLater(
          openDefaultAndroidSubmissionResources(
            lifetime: failedLifetime,
            scheduler: scheduler,
          ),
          throwsA(_safeFailure('configurationUnavailable')),
        );
        // Then cleanup retires only that failed lifetime and closes its configuration once.
        expect(failedLifetime.isCurrent, isFalse);
        expect(calls.map((c) => c.method), [
          'snapshot',
          'closeConfiguration',
          'snapshot',
          'closeConfiguration',
        ]);
        // When a fresh lifetime opens the actual default composition over the retained roots.
        final fresh = await openDefaultAndroidSubmissionResources(
          lifetime: freshLifetime,
          scheduler: scheduler,
        );
        resources.add(fresh);
        final reopenedOriginals = await openDefaultCaptureStore();
        final retained = await fresh.queue.find(request.id);
        final retainedBytes = await reopenedOriginals.readMaterial(original);
        // Then a distinct queue observes the exact durable request/state and unchanged original bytes.
        expect(identical(first.queue, fresh.queue), isFalse);
        expect(retained, accepted);
        expect(retained!.request, request);
        expect(retained.state, SubmissionState.readyToSubmit);
        expect(retainedBytes, orderedEquals(bytes));
        expect(freshLifetime.isCurrent, isTrue);
        expect(firstLifetime.isCurrent, isFalse);
        expect(scheduler.calls, 0);
        expect(calls.map((c) => c.method), [
          'snapshot',
          'closeConfiguration',
          'snapshot',
          'closeConfiguration',
          'snapshot',
        ]);
        // When the reopened owner closes, it drains its service/queue without scheduling or consent.
        await fresh.close();
        // Then both successful owners and the failed owner remain retired with exact config close calls.
        expect(freshLifetime.isCurrent, isFalse);
        expect(scheduler.calls, 0);
        expect(calls.map((c) => c.method), [
          'snapshot',
          'closeConfiguration',
          'snapshot',
          'closeConfiguration',
          'snapshot',
          'closeConfiguration',
        ]);
      } finally {
        // Given every acquired resource and both global test hooks belong to this scenario.
        try {
          // When acquired owners drain before hooks and their temporary files are removed.
          await Future.wait(
            resources.map((resource) {
              // Given this resource was acquired and retained by the scenario.
              // When its owned cleanup is requested again if necessary.
              final closing = resource.close();
              // Then the join observes idempotent drain before global hooks are restored.
              return closing;
            }),
          );
        } finally {
          sqlite.databaseFactoryOrNull = originalFactory;
          messenger.setMockMethodCallHandler(pathChannel, null);
          await directory.delete(recursive: true);
        }
        // Then no scoped SQLite factory, path hook or owned disk artifact survives this test.
      }
    });

    test('closed exact calls return definitions and dedicated ephemeral HTTP credentials', () async {
      // Given accepted B1 definitions whose native serialization is reused unchanged.
      final drive = DriveSubmissionConnection(
        id: 'drive',
        accountId: 'owner@example.test',
        folderId: 'Folder',
      );
      final http = HttpSubmissionConnection(
        id: 'server',
        endpoint: Uri.parse('https://example.test/submit'),
      );
      snapshot = SubmissionConfigurationSnapshot(
        driveConnections: [drive],
        httpConnections: [http],
        selectedStorageConnectionId: 'drive',
        selectedTransportConnectionId: 'server',
      ).toJson();
      respond = (call) {
        // Given this controlled port has no real key, SQL transaction or grant.
        final method = call.method;
        // When dedicated retrieval/state methods are invoked.
        if (method == 'bearerToken') return 'PRIVATE_MARKER_token';
        if (method == 'authorizationState' || method == 'authorizeDrive') {
          return 'available';
        }
        // Then only snapshot receives safe definitions and writes receive null.
        return method == 'snapshot' ? snapshot : null;
      };
      // When every public configuration/credential operation crosses the real codec.
      await store.putDrive(drive);
      await store.putHttp(http);
      await store.select(
        storageConnectionId: 'drive',
        transportConnectionId: 'server',
      );
      await store.setHttpBearerToken('server', 'PRIVATE_MARKER_token');
      final value = await store.snapshot();
      final authorization = await store.authorizeDrive('drive');
      final state = await store.authorizationState('drive');
      final token = await store.bearerToken('server');
      await store.setHttpBearerToken('server', null);
      // Then exact argument maps match the frozen protocol and config omits the secret.
      expect(calls.map((c) => c.method), [
        'putDrive',
        'putHttp',
        'select',
        'setHttpBearerToken',
        'snapshot',
        'authorizeDrive',
        'authorizationState',
        'bearerToken',
        'setHttpBearerToken',
      ]);
      expect(calls[0].arguments, {'connection': drive.toJson()});
      expect(calls[1].arguments, {'connection': http.toJson()});
      expect(calls[2].arguments, {
        'storageConnectionId': 'drive',
        'transportConnectionId': 'server',
      });
      expect(calls[3].arguments, {
        'connectionId': 'server',
        'token': 'PRIVATE_MARKER_token',
      });
      expect(calls[4].arguments, <String, Object?>{});
      expect(calls[5].arguments, {'connectionId': 'drive'});
      expect(calls.last.arguments, {'connectionId': 'server', 'token': null});
      expect(value.toJson(), snapshot);
      expect(jsonEncode(value.toJson()), isNot(contains('PRIVATE_MARKER')));
      expect(authorization, SubmissionAuthorizationState.available);
      expect(state, SubmissionAuthorizationState.available);
      expect(token, 'PRIVATE_MARKER_token');
    });

    test('null authorization-required unavailable and fixed exceptions preserve privacy', () async {
      // Given a controlled native authorization state and a missing ephemeral token.
      var selected = 'authorizationRequired';
      respond = (call) {
        // Given this response contains no actual account grant.
        final method = call.method;
        // When the facade asks only for status or a token.
        if (method == 'authorizationState') return selected;
        // Then a missing token remains null without a fabricated credential.
        return null;
      };
      // When native state changes from authorization-required to unavailable.
      expect(
        await store.authorizationState('drive'),
        SubmissionAuthorizationState.authorizationRequired,
      );
      selected = 'unavailable';
      expect(
        await store.authorizationState('drive'),
        SubmissionAuthorizationState.unavailable,
      );
      expect(await store.bearerToken('drive'), isNull);
      respond = (_) {
        // Given raw SDK-style markers in every untrusted native error field.
        const marker = 'PRIVATE_MARKER owner@example.test';
        // When a native failure carries an unknown code/message/details.
        throw PlatformException(
          code: marker,
          message: marker,
          details: {'token': marker},
        );
        // Then the public facade must replace all fields with its fixed vocabulary.
      };
      // When that untrusted error crosses the channel boundary.
      await expectLater(
        store.bearerToken('drive'),
        throwsA(
          isA<SubmissionConfigurationException>()
              .having((e) => e.code, 'safe code', 'configurationUnavailable')
              .having(
                (e) => '${e.message}$e',
                'no native reflection',
                isNot(contains('PRIVATE_MARKER')),
              ),
        ),
      );
      // Then known safe codes likewise use the fixed message rather than native text.
      respond = (_) => throw PlatformException(
        code: 'connectionConflict',
        message: 'PRIVATE_MARKER',
      );
      await expectLater(
        store.snapshot(),
        throwsA(_safeFailure('connectionConflict')),
      );
    });

    test('invalid native payloads reject instead of becoming empty available or a token', () async {
      // Given schema/type/version corruption, including a secret-bearing extra key.
      for (final malformed in [
        null,
        [],
        {...snapshot, 'version': 3},
        {...snapshot, 'token': 'PRIVATE_MARKER'},
      ]) {
        respond = (_) => malformed;
        // When a strict public snapshot decodes the controlled payload.
        await expectLater(
          store.snapshot(),
          throwsA(_safeFailure('configurationUnavailable')),
        );
        // Then no empty fallback is returned from corruption.
      }
      for (final malformed in ['unknown', true, null]) {
        // Given a value outside the closed authorization enum.
        respond = (_) => malformed;
        // When the public state is decoded.
        await expectLater(
          store.authorizationState('drive'),
          throwsA(_safeFailure('configurationUnavailable')),
        );
        // Then no unknown value becomes available.
      }
      for (final malformed in ['PRIVATE_MARKER\r\n', 3, 'a' * 8193]) {
        // Given a malformed or overlong native bearer value.
        respond = (_) => malformed;
        // When only the dedicated credential operation decodes it.
        await expectLater(
          store.bearerToken('drive'),
          throwsA(isA<SubmissionConfigurationException>()),
        );
        // Then neither token nor raw marker can escape through an exception.
      }
      respond = (_) => 'available';
      // When a write returns a nonnull result in violation of the strict protocol.
      await expectLater(
        store.select(),
        throwsA(_safeFailure('configurationUnavailable')),
      );
      // Then explicit consent cannot return an unverified nonavailable state either.
      respond = (_) => 'authorizationRequired';
      await expectLater(
        store.authorizeDrive('drive'),
        throwsA(_safeFailure('authorizationRequired')),
      );
    });

    test('invalid inputs and unsupported platform make no channel calls', () {
      // Given the public Android preset requires an exact basic Google account email.
      final invalidAccount = DriveSubmissionConnection(
        id: 'drive',
        accountId: 'opaque-account',
        folderId: 'Folder',
      );
      // When malformed ids/accounts/credentials are proposed before native IO.
      expect(() => store.putDrive(invalidAccount), throwsArgumentError);
      expect(
        () => store.select(storageConnectionId: '../unsafe'),
        throwsArgumentError,
      );
      expect(() => store.bearerToken('../unsafe'), throwsArgumentError);
      expect(
        () => store.setHttpBearerToken('server', 'invalid\nPRIVATE_MARKER'),
        throwsArgumentError,
      );
      expect(
        () => store.setHttpBearerToken('server', 'a' * 8193),
        throwsArgumentError,
      );
      // Then no native operation has been invoked.
      expect(calls, isEmpty);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      // When a non-Android caller supplies even a borrowed channel.
      expect(store.snapshot, throwsUnsupportedError);
      expect(
        AndroidSubmissionBackgroundScheduler(channel: channel).initialize,
        throwsUnsupportedError,
      );
      // Then unsupported behavior is explicit and remains before channel IO.
      expect(calls, isEmpty);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    });

    test('close joins owned calls discards late values and sends only its own close', () async {
      // Given a held real channel snapshot invocation and its owner facade.
      final entered = Completer<void>();
      final response = Completer<Object?>();
      respond = (call) {
        // Given closeConfiguration is separate from the held safe snapshot.
        if (call.method == 'closeConfiguration') return null;
        // When a channel read enters and remains pending.
        entered.complete();
        // Then the test can observe whether close actually joins it.
        return response.future;
      };
      final pending = store.snapshot();
      final safeLate = expectLater(
        pending,
        throwsA(_safeFailure('configurationClosed')),
      );
      await entered.future.timeout(const Duration(seconds: 2));
      // When close begins while that read still belongs to this facade.
      final closing = store.close();
      await expectLater(
        store.snapshot(),
        throwsA(_safeFailure('configurationClosed')),
      );
      expect(calls.map((c) => c.method), ['snapshot']);
      response.complete(snapshot);
      await safeLate;
      await closing;
      await store.close();
      // Then close occurs once after the safe late result is discarded, without work cancellation.
      expect(calls.map((c) => c.method), ['snapshot', 'closeConfiguration']);
      expect(calls.last.arguments, <String, Object?>{});
    });

    test('scheduler registers Core callback once before persisted wakes and close preserves jobs', () async {
      // Given the actual Core top-level callback and a controlled native scheduling port.
      final scheduler = AndroidSubmissionBackgroundScheduler(channel: channel);
      // When concurrent initialization and two public wakes are requested.
      await Future.wait([scheduler.initialize(), scheduler.initialize()]);
      await scheduler.requestRun();
      await scheduler.requestRun();
      // Then one positive Core handle is persisted before both exact zero-delay wakes.
      expect(calls.map((c) => c.method), [
        'initializeBackground',
        'scheduleBackground',
        'scheduleBackground',
      ]);
      expect((calls.first.arguments as Map)['callbackHandle'], isPositive);
      expect((calls.first.arguments as Map).keys, ['callbackHandle']);
      expect(calls[1].arguments, {'delayMs': 0});
      expect(calls[2].arguments, {'delayMs': 0});
      await scheduler.close();
      await scheduler.close();
      await expectLater(scheduler.requestRun(), throwsStateError);
      // Then closing only the foreground facade sends no cancel/clear/config/queue operation.
      expect(calls.length, 3);
    });

    test('failed wake reports safe failure while a later wake uses retained initialization', () async {
      // Given Core initialization succeeds but a native persisted enqueue fails.
      final scheduler = AndroidSubmissionBackgroundScheduler(channel: channel);
      var failed = false;
      respond = (call) {
        // Given only scheduling, rather than initialization, is selected to fail once.
        if (call.method == 'scheduleBackground' && !failed) {
          // When the native operation rejects with sensitive untrusted details.
          failed = true;
          throw PlatformException(
            code: 'PRIVATE_MARKER',
            message: 'PRIVATE_MARKER',
          );
        }
        // Then later scheduling can return actual operation completion.
        return null;
      };
      // When the first wake fails and a second request retries the durable enqueue.
      await expectLater(
        scheduler.requestRun(),
        throwsA(_safeFailure('configurationUnavailable')),
      );
      await scheduler.requestRun();
      await scheduler.close();
      // Then callback persistence happened once and no work/queue/config erase was sent.
      expect(calls.map((c) => c.method), [
        'initializeBackground',
        'scheduleBackground',
        'scheduleBackground',
      ]);
    });

    test('failed initialization permits retry and never schedules before persisted handle', () async {
      // Given the first native callback registration cannot be persisted.
      final scheduler = AndroidSubmissionBackgroundScheduler(channel: channel);
      var attempts = 0;
      respond = (call) {
        // Given each initialization attempt is captured before any wake.
        if (call.method == 'initializeBackground') {
          // When persistence rejects the first registration and accepts the next.
          attempts++;
          if (attempts == 1) {
            throw PlatformException(code: 'configurationUnavailable');
          }
        }
        // Then only an actually completed registration may allow a wake.
        return null;
      };
      // When the first request fails and a later request reinitializes.
      await expectLater(
        scheduler.requestRun(),
        throwsA(_safeFailure('configurationUnavailable')),
      );
      expect(calls.map((c) => c.method), ['initializeBackground']);
      await scheduler.requestRun();
      await scheduler.close();
      // Then no wake preceded the second completed persisted registration.
      expect(calls.map((c) => c.method), [
        'initializeBackground',
        'initializeBackground',
        'scheduleBackground',
      ]);
    });
  });

  group('RA5 reference access channel and RA8 live composition', () {
    test('RA5 exact replace and empty revoke retain bindings across fresh facades', () async {
      // Given controlled backing independent of either public facade lifetime.
      final backing = MemorySubmissionConfigurationStore();
      final drive = DriveSubmissionConnection(
        id: 'drive',
        accountId: 'owner@example.test',
        folderId: 'Folder',
      );
      final server = HttpSubmissionConnection(
        id: 'server',
        endpoint: Uri.parse('https://example.test/submit'),
      );
      await backing.putDrive(drive);
      await backing.putHttp(server);
      await backing.putHttp(
        HttpSubmissionConnection(
          id: 'otherServer',
          endpoint: Uri.parse('https://other.example.test/submit'),
        ),
      );
      respond = (call) async {
        // Given mock persistence is a controlled behavioral port, never native SQL/crypto.
        final args = call.arguments as Map;
        // When exact public operations cross the actual MethodChannel codec.
        if (call.method == 'setReferenceAccess') {
          await backing.setReferenceAccess(
            transportConnectionId: args['transportConnectionId'] as String,
            storageConnectionIds: (args['storageConnectionIds'] as List)
                .cast<String>(),
          );
        } else if (call.method == 'select') {
          await backing.select(
            storageConnectionId: args['storageConnectionId'] as String?,
            transportConnectionId: args['transportConnectionId'] as String?,
          );
        } else if (call.method == 'setHttpBearerToken') {
          await backing.setHttpBearerToken(
            args['connectionId'] as String,
            args['token'] as String?,
          );
        } else if (call.method == 'bearerToken') {
          return backing.bearerToken(args['connectionId'] as String);
        } else if (call.method == 'snapshot') {
          return (await backing.snapshot()).toJson();
        }
        // Then only accepted writes/close return null; safe backing remains separate.
        return null;
      };
      final fresh = AndroidSubmissionConfigurationStore(channel: channel);
      try {
        // When one mapping is replaced and another explicitly retained across selection/secret changes.
        await store.setReferenceAccess(
          transportConnectionId: 'server',
          storageConnectionIds: ['drive'],
        );
        await store.setReferenceAccess(
          transportConnectionId: 'otherServer',
          storageConnectionIds: [],
        );
        await store.select(
          storageConnectionId: 'drive',
          transportConnectionId: 'otherServer',
        );
        await store.setHttpBearerToken('server', 'PRIVATE_MARKER_one');
        await store.setHttpBearerToken('server', 'PRIVATE_MARKER_two');
        await store.close();
        final retained = await fresh.snapshot();
        // Then exact method/two-key arguments and retained explicit maps are observable.
        expect(calls.first.method, 'setReferenceAccess');
        expect(calls.first.arguments, {
          'transportConnectionId': 'server',
          'storageConnectionIds': ['drive'],
        });
        expect(calls[1].arguments, {
          'transportConnectionId': 'otherServer',
          'storageConnectionIds': [],
        });
        expect(retained.referenceAccessBindings, {
          'server': ['drive'],
          'otherServer': [],
        });
        expect(retained.selectedTransportConnectionId, 'otherServer');
        expect(await fresh.bearerToken('server'), 'PRIVATE_MARKER_two');
        expect(
          jsonEncode(retained.toJson()),
          isNot(contains('PRIVATE_MARKER')),
        );
        final beforeClosed = calls.length;
        // When the old facade attempts a new access write after its own close.
        await expectLater(
          store.setReferenceAccess(
            transportConnectionId: 'server',
            storageConnectionIds: [],
          ),
          throwsA(_safeFailure('configurationClosed')),
        );
        // Then it stays closed and cannot operate on the fresh native-style owner.
        expect(calls.length, beforeClosed);
        await fresh.setReferenceAccess(
          transportConnectionId: 'server',
          storageConnectionIds: [],
        );
        final revoked = await fresh.snapshot();
        expect(revoked.referenceAccessBindings, {
          'server': [],
          'otherServer': [],
        });
        expect(revoked.selectedStorageConnectionId, 'drive');
        expect(revoked.httpConnections.length, 2);
      } finally {
        // Given this scenario owns the fresh facade and independent test backing.
        // When their accepted calls drain, then the suite's channel remains borrowed.
        await fresh.close();
        await backing.close();
      }
    });

    test('RA5 malformed proposals fail before IO and native write failures stay fixed', () async {
      // Given malformed ids, duplicate access and a per-write overcapacity proposal.
      final proposals = [
        ('../unsafe', <String>[]),
        ('server', ['../unsafe']),
        ('server', ['drive', 'drive']),
        ('server', [for (var i = 0; i < 129; i++) 'drive_$i']),
      ];
      // When each proposal is supplied to the real facade before native IO.
      for (final proposal in proposals) {
        // Then exact syntax/duplicate/count failures are local observable errors.
        expect(
          () => store.setReferenceAccess(
            transportConnectionId: proposal.$1,
            storageConnectionIds: proposal.$2,
          ),
          throwsArgumentError,
        );
      }
      expect(calls, isEmpty);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      // When even valid ids are supplied on an unsupported platform.
      expect(
        () => store.setReferenceAccess(
          transportConnectionId: 'server',
          storageConnectionIds: ['drive'],
        ),
        throwsUnsupportedError,
      );
      // Then no channel call occurs before explicit platform rejection.
      expect(calls, isEmpty);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      respond = (_) {
        // Given untrusted native code/message/details contain sensitive markers.
        // When the new write fails at that borrowed port.
        throw PlatformException(
          code: 'PRIVATE_MARKER',
          message: 'PRIVATE_MARKER',
          details: 'owner@example.test',
        );
        // Then facade must expose only its fixed safe vocabulary.
      };
      await expectLater(
        store.setReferenceAccess(
          transportConnectionId: 'server',
          storageConnectionIds: [],
        ),
        throwsA(_safeFailure('configurationUnavailable')),
      );
      // Given a write response must be exactly null.
      respond = (_) => true;
      // When a nonnull controlled native result is returned, then it rejects safely.
      await expectLater(
        store.setReferenceAccess(
          transportConnectionId: 'server',
          storageConnectionIds: [],
        ),
        throwsA(_safeFailure('configurationUnavailable')),
      );
    });

    test('RA5 exact literal legacy read grants nothing and malformed v2 never falls back', () async {
      // Given an independently literal deployed v1 snapshot with selected exact ids.
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
      respond = (_) => legacy;
      // When the actual public facade decodes historical configuration.
      final retained = await store.snapshot();
      // Then canonical output is v2 and selections imply no fabricated binding.
      expect(retained.toJson()['version'], 2);
      expect(retained.referenceAccessBindings, isEmpty);
      expect(retained.selectedStorageConnectionId, 'drive');
      for (final malformed in [
        {...retained.toJson()}..remove('referenceAccessBindings'),
        {
          ...retained.toJson(),
          'referenceAccessBindings': {
            'server': ['drive', 'drive'],
          },
        },
        {
          ...retained.toJson(),
          'referenceAccessBindings': {
            'server': ['server'],
          },
        },
        {
          ...retained.toJson(),
          'referenceAccessBindings': {'missing': []},
        },
      ]) {
        // Given malformed current backing cannot become empty or available.
        respond = (_) => malformed;
        // When a fresh actual channel read decodes it, then a safe error propagates.
        await expectLater(
          store.snapshot(),
          throwsA(_safeFailure('configurationUnavailable')),
        );
      }
    });

    test(
      'RA5 close joins new owned write and rejects its late result',
      () async {
        // Given a held exact new channel write and independently owned release signal.
        final entered = Completer<void>();
        final response = Completer<Object?>();
        respond = (call) {
          // Given close is independent of the selected pending owned write.
          if (call.method != 'setReferenceAccess') return null;
          // When the real facade sends this exact operation and native return is held.
          entered.complete();
          // Then the scenario observes join order through the actual pending future.
          return response.future;
        };
        final pending = store.setReferenceAccess(
          transportConnectionId: 'server',
          storageConnectionIds: ['drive'],
        );
        final rejected = expectLater(
          pending,
          throwsA(_safeFailure('configurationClosed')),
        );
        Future<void>? closing;
        try {
          await entered.future.timeout(const Duration(seconds: 2));
          // When close retires this owner before the old write result arrives.
          closing = store.close();
          // Then native close has not overtaken its accepted write.
          expect(calls.map((call) => call.method), ['setReferenceAccess']);
          response.complete(null);
          await rejected.timeout(const Duration(seconds: 2));
          await closing;
          // Then the late result is discarded and captured close executes exactly once.
          expect(calls.map((call) => call.method), [
            'setReferenceAccess',
            'closeConfiguration',
          ]);
        } finally {
          // Given every held native-style operation belongs to this scenario.
          if (!response.isCompleted) response.complete(null);
          // When write/close drain, then the suite can remove its borrowed channel hook.
          await rejected.timeout(const Duration(seconds: 2));
          await closing;
        }
      },
    );

    test('RA8 default resources use live binding and fresh owner retains real files and queue', () async {
      // Given actual default factories scoped to test-private files and real host SQLite.
      sqfliteFfiInit();
      final directory = await Directory.systemTemp.createTemp(
        'submission-live-access-',
      );
      final originalFactory = sqlite.databaseFactoryOrNull;
      const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
      final scheduler = ControlledScheduler();
      final owners = <SubmissionBackgroundResources>[];
      final clients = <_NoNetworkHttpClient>[];
      snapshot = SubmissionConfigurationSnapshot(
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
      ).toJson();
      respond = (call) {
        // Given controlled safe snapshots model only local native protocol backing.
        if (call.method == 'snapshot') return snapshot;
        // When a default composition tries any credential or authorization operation.
        if (call.method != 'closeConfiguration') {
          throw StateError(
            'Unexpected native credential or authorization call',
          );
        }
        // Then only configuration close is accepted; real native/Drive proof is excluded.
        return null;
      };
      try {
        sqlite.databaseFactoryOrNull = databaseFactoryFfi;
        messenger.setMockMethodCallHandler(pathChannel, (call) async {
          // Given this scoped path-provider port owns a single private support root.
          // When actual default factories request their support directory.
          expect(call.method, 'getApplicationSupportDirectory');
          // Then original and queue roots share only this test-owned directory.
          return directory.path;
        });
        await HttpOverrides.runZoned(
          () async {
            // Given actual default composition builds its owned HTTP client in this zone.
            final first = await openDefaultAndroidSubmissionResources(
              lifetime: SubmissionRunLifetime(id: 'reference_first'),
              scheduler: scheduler,
            );
            owners.add(first);
            final originals = await openDefaultCaptureStore();
            final bytes = Uint8List.fromList([255, 216, 10, 20, 255, 217]);
            final now = DateTime.now().toUtc();
            // When an actual original and complete controlled receipt are durably retained.
            final original = await originals.saveMaterial(
              bytes: bytes,
              mediaType: 'image/jpeg',
              capturedAt: now,
              originalName: 'unchanged.original',
            );
            final request = SubmissionRequest(
              id: 'live_commit',
              kind: 'bookMaterial',
              subjectId: 'live_subject',
              createdAt: now,
              document: {'draft': true},
              payload: {'transcript': '  手入力\n原文  '},
              materials: [
                SubmissionMaterial(
                  key: 'photo',
                  original: original,
                  provenance: {'source': 'controlled'},
                ),
              ],
              transportConnectionId: 'server',
              storageConnectionId: 'drive',
            );
            await first.queue.enqueue(request);
            final claimed = (await first.queue.claimNext(
              now: now,
              leaseToken: 'seedOwner',
              leaseDuration: const Duration(minutes: 5),
            ))!;
            await first.queue.saveReservation(
              id: request.id,
              leaseToken: claimed.leaseToken!,
              now: now,
              reservation: SubmissionStorageReservation(
                key: 'photo',
                providerId: 'googleDrive',
                data: {'remoteId': 'controlled_photo'},
              ),
            );
            await first.queue.saveReceipt(
              id: request.id,
              leaseToken: claimed.leaseToken!,
              now: now,
              receipt: SubmissionMaterialReceipt(
                key: 'photo',
                providerId: 'googleDrive',
                remoteId: 'controlled_photo',
                accessConnectionId: 'drive',
                storedAt: now,
              ),
            );
            final retained = await first.queue.release(
              id: request.id,
              leaseToken: claimed.leaseToken!,
              now: now,
            );
            final unknown = await first.service.findTransferStatus(
              request.id,
              observedAt: now,
            );
            // Then all receipts succeed while unconfigured submission waits without credentials.
            expect(
              unknown!.upload.state,
              SubmissionTransferOperationState.succeeded,
            );
            expect(
              unknown.submission.waitingReason,
              SubmissionTransferWaitingReason.referenceAccess,
            );
            // When safe backing changes after factory open, without resource recreation.
            snapshot = {
              ...snapshot,
              'referenceAccessBindings': {
                'server': ['drive'],
              },
            };
            final available = await first.service.findTransferStatus(
              request.id,
              observedAt: now,
            );
            snapshot = {
              ...snapshot,
              'referenceAccessBindings': {'server': []},
            };
            final denied = await first.service.processNext(
              networkAllowed: true,
            );
            // Then the same live owned configuration drives current queries and denies dispatch.
            expect(
              available!.submission.state,
              SubmissionTransferOperationState.queued,
            );
            expect(denied.record!.lastFailure!.code, 'referenceAccessRequired');
            expect(denied.record!.transportCheckpoint, isNull);
            expect(denied.record!.receipts, retained.receipts);
            expect(
              calls.where(
                (call) =>
                    call.method == 'bearerToken' ||
                    call.method == 'authorizationState' ||
                    call.method == 'authorizeDrive',
              ),
              isEmpty,
            );
            expect(
              clients.fold<int>(0, (count, client) => count + client.requests),
              0,
            );
            expect(scheduler.calls, 0);
            await first.close();
            // Given a fresh foreground owner reopens the exact unchanged real roots.
            final fresh = await openDefaultAndroidSubmissionResources(
              lifetime: SubmissionRunLifetime(id: 'reference_fresh'),
              scheduler: scheduler,
            );
            owners.add(fresh);
            // When current status, queue and original are read from distinct owned handles.
            final status = await fresh.service.findTransferStatus(
              request.id,
              observedAt: now,
            );
            final reopenedOriginals = await openDefaultCaptureStore();
            final retainedBytes = await reopenedOriginals.readMaterial(
              original,
            );
            // Then explicit empty backing and complete local facts survive owner recreation.
            expect(identical(first.queue, fresh.queue), isFalse);
            expect((await fresh.queue.find(request.id))!.request, request);
            expect(
              status!.submission.waitingReason,
              SubmissionTransferWaitingReason.referenceAccess,
            );
            expect(retainedBytes, bytes);
            expect(status.files.single.receipt, retained.receipts['photo']);
            expect(scheduler.calls, 0);
            expect(
              clients.fold<int>(0, (count, client) => count + client.requests),
              0,
            );
          },
          createHttpClient: (_) {
            // Given default HTTP clients are owned by the actual composing factory.
            // When the zone supplies an explicitly rejecting test network port.
            final client = _NoNetworkHttpClient();
            clients.add(client);
            // Then any attempted HTTP dispatch is observable without real network IO.
            return client;
          },
        );
      } finally {
        // Given every acquired default owner and scoped platform hook belongs here.
        try {
          // When owned compositions drain before original/database files are removed.
          for (final owner in owners) {
            // Given one acquired owner, when closed, then its service reads drain first.
            await owner.close();
          }
        } finally {
          sqlite.databaseFactoryOrNull = originalFactory;
          messenger.setMockMethodCallHandler(pathChannel, null);
          await directory.delete(recursive: true);
        }
        // Then all test clients/roots/hooks are retired; no native SQL/Drive claim follows.
        expect(clients.every((client) => client.closed), isTrue);
        expect(clients.every((client) => client.requests == 0), isTrue);
      }
    });
  });
}

/// Test-only network tripwire for actual default-client construction.
final class _NoNetworkHttpClient implements HttpClient {
  int requests = 0;
  bool closed = false;
  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    // Given denied reference access must prevent any HTTP client dispatch.
    requests++;
    // When an attempted request reaches this explicit test tripwire.
    throw StateError('Unexpected controlled HTTP dispatch');
    // Then no real socket, authorization or remote permission is exercised.
  }

  @override
  void close({bool force = false}) {
    // Given the actual default factory owns this controlled client lifetime.
    // When its idempotent cleanup closes the client, then closure is observable.
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    // Given this test port admits only construction, dispatch tripwire and close.
    // When an unadmitted operation is attempted, then it fails without networking.
    throw UnsupportedError('Unsupported controlled HTTP operation');
  }
}

Matcher _safeFailure(String code) {
  // Given a fixed code from the public safe configuration vocabulary.
  final expected = code;
  // When assertions inspect an actual facade failure.
  final matcher = isA<SubmissionConfigurationException>()
      .having((e) => e.code, 'safe code', expected)
      .having(
        (e) => '${e.message}$e',
        'private native data absent',
        isNot(contains('PRIVATE_MARKER')),
      );
  // Then no mock result is mistaken for native storage or real Google authorization proof.
  return matcher;
}
