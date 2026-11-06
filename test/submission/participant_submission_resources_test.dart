import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqlite;
import 'package:textus_flutter_core/textus_flutter_core.dart';

import 'registered_material_submission_test.dart' show registeredTestRequest;
import 'submission_participant_runtime_test.dart'
    show
        ParticipantHttp,
        ParticipantLegacyCredentials,
        ParticipantLogin,
        ParticipantNativeStore,
        participantAccount,
        participantBinding,
        participantCapture,
        participantCredentialChannel,
        participantSnapshot,
        participantTarget;

const _configurationChannel = MethodChannel(
  'org.textus.flutter.core/submission',
);
const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');
const _backgroundChannel = MethodChannel(
  'org.textus.flutter.core/submission-background',
);
final _now = DateTime.utc(2026, 11, 6);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  sqlite.sqfliteFfiInit();
  late Directory directory;
  TargetPlatform? previousPlatform;
  AppLifecycleState? previousLifecycle;
  sqlite.DatabaseFactory? previousFactory;
  late ParticipantNativeStore native;
  late SubmissionConfigurationSnapshot androidSnapshot;
  late List<SubmissionBackgroundResources> owners;
  late List<SubmissionConfigurationStore> configurations;
  late List<SubmissionQueueStore> queues;
  late List<ParticipantLogin> logins;
  late List<MethodCall> configurationCalls;
  late List<_DeliveryHttp> deliveryClients;
  var pathCalls = 0;
  var failConfigurationClose = false;

  setUp(() async {
    previousPlatform = debugDefaultTargetPlatformOverride;
    previousLifecycle = binding.lifecycleState;
    previousFactory = sqlite.databaseFactoryOrNull;
    sqlite.databaseFactoryOrNull = sqlite.databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('participant-resources-');
    native = ParticipantNativeStore();
    owners = [];
    configurations = [];
    queues = [];
    logins = [];
    configurationCalls = [];
    deliveryClients = [];
    pathCalls = 0;
    failConfigurationClose = false;
    androidSnapshot = _snapshot();
    messenger.setMockMethodCallHandler(
      participantCredentialChannel,
      native.handle,
    );
    messenger.setMockMethodCallHandler(_pathChannel, (call) async {
      expect(call.method, 'getApplicationSupportDirectory');
      pathCalls++;
      return directory.path;
    });
    messenger.setMockMethodCallHandler(_configurationChannel, (call) async {
      configurationCalls.add(call);
      if (call.method == 'snapshot') return androidSnapshot.toJson();
      if (call.method == 'bearerToken') {
        final id = (call.arguments as Map)['connectionId'];
        return id == 'drive' ? 'SYNTHETIC.GOOGLE=' : 'SYNTHETIC.LEGACY=';
      }
      if (call.method == 'closeConfiguration' && failConfigurationClose) {
        throw PlatformException(
          code: 'configurationUnavailable',
          message: 'PRIVATE.CONFIG',
        );
      }
      return null;
    });
    binding.resetInternalState();
    await _lifecycle(binding, AppLifecycleState.resumed);
  });

  tearDown(() async {
    try {
      for (final owner in owners) {
        await owner.close();
      }
      for (final configuration in configurations) {
        await configuration.close();
      }
      for (final queue in queues) {
        await queue.close();
      }
      for (final login in logins) {
        await login.close();
      }
      await directory.delete(recursive: true);
    } finally {
      messenger.setMockMethodCallHandler(participantCredentialChannel, null);
      messenger.setMockMethodCallHandler(_pathChannel, null);
      messenger.setMockMethodCallHandler(_configurationChannel, null);
      messenger.setMockMethodCallHandler(_backgroundChannel, null);
      _backgroundChannel.setMethodCallHandler(null);
      sqlite.databaseFactoryOrNull = previousFactory;
      binding.resetInternalState();
      if (previousLifecycle != null) {
        await _lifecycle(binding, previousLifecycle!);
      }
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  Future<void> configure(
    TargetPlatform platform, {
    bool declared = true,
  }) async {
    debugDefaultTargetPlatformOverride = platform;
    final snapshot = _snapshot(declared: declared);
    if (platform == TargetPlatform.android) {
      androidSnapshot = snapshot;
    } else {
      final store = await IosSubmissionConfigurationStore.open();
      configurations.add(store);
      for (final connection in snapshot.httpConnections) {
        await store.putHttp(connection);
      }
      for (final connection in snapshot.driveConnections) {
        await store.putDrive(connection);
      }
      await store.setReferenceAccess(
        transportConnectionId: 'server',
        storageConnectionIds: ['drive'],
      );
      await store.setParticipantAuthentication(
        snapshot.participantAuthentication,
      );
    }
  }

  Future<ParticipantLogin> login({String account = 'A'}) async {
    final result = ParticipantLogin();
    logins.add(result);
    await result.signIn(account: account);
    return result;
  }

  Future<SubmissionBackgroundResources> open({
    UserAccountSubmissionScope? scope,
    SubmissionRunLifetime? lifetime,
    bool required = false,
    bool ownedScheduler = false,
    SubmissionCredentialProvider? credentials,
    _DeliveryHttp? delivery,
  }) async {
    final client = delivery ?? _DeliveryHttp();
    deliveryClients.add(client);
    final life = lifetime ?? SubmissionRunLifetime(id: 'platform');
    final scheduler = ownedScheduler ? null : _BorrowedScheduler();
    final result = await http.runWithClient(
      () => defaultTargetPlatform == TargetPlatform.iOS
          ? openDefaultIosSubmissionResources(
              lifetime: life,
              scheduler: scheduler,
              credentials: credentials,
              authenticationScope: scope,
              requiresAuthentication: required,
            )
          : openDefaultAndroidSubmissionResources(
              lifetime: life,
              scheduler: scheduler,
              authenticationScope: scope,
              requiresAuthentication: required,
            ),
      () => client,
    );
    owners.add(result);
    return result;
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    group('${platform.name} actual participant resources', () {
      for (final declared in [false, true]) {
        test(
          'required policy with declaration $declared reads saved status but gates both services',
          () async {
            // Given actual configured roots and saved ordinary/TKL intent without any scope.
            await configure(platform, declared: declared);
            final legacy = ParticipantLegacyCredentials();
            final queue = await openDefaultSubmissionQueueStore();
            queues.add(queue);
            final request = _request('saved_legacy', withMissingOriginal: true);
            final sourceRequest = _registeredRequest('saved_registered');
            final source = await _saveRegistered(queue, sourceRequest);
            final saved = await queue.enqueue(request);
            final calls = List<String>.of(native.calls);
            // When explicit required mode opens and reads real queue/history before dispatch.
            final resources = await open(required: true, credentials: legacy);
            final status = await resources.service.findTransferStatus(
              request.id,
              observedAt: _now,
            );
            final handoffs = resources.service.registeredMaterialHandoffs!;
            await handoffs.enqueueRegistered(
              sourceRequest.id,
              participantTarget(),
            );
            final ordinary = await resources.service.processNext(
              networkAllowed: true,
            );
            final handoff = await handoffs.processNext(networkAllowed: true);
            // Then saved state is readable and neither service falls back to legacy IO.
            expect(resources.service.requiresAuthentication, isTrue);
            expect(handoffs.requiresAuthentication, isTrue);
            expect(status!.requestId, saved.request.id);
            expect(status.upload.completedCount, 0);
            expect(
              ordinary.record!.lastFailure!.code,
              'authenticationRequired',
            );
            expect(handoff.record!.failure!.code, 'authenticationRequired');
            expect((await resources.queue.find(sourceRequest.id)), source);
            expect(
              (await resources.service.list()).map((row) => row.request.id),
              containsAll([request.id, sourceRequest.id]),
            );
            expect(native.calls, calls);
            expect(legacy.calls, isEmpty);
            expect(_credentialCalls(configurationCalls), isEmpty);
            expect(deliveryClients.single.requests, isEmpty);
          },
        );
      }

      test('bound A sends under A while a same-origin undeclared target has no adapter', () async {
        // Given accepted A, actual config, and a same-origin target outside the declaration.
        await configure(platform);
        final accepted = await login();
        final scope = accepted.scope();
        final legacy = ParticipantLegacyCredentials();
        final delivery = _DeliveryHttp();
        final resources = await open(
          scope: scope,
          credentials: legacy,
          delivery: delivery,
        );
        final request = _request('bound_a', binding: scope.binding);
        final outsider = _request(
          'outside_a',
          binding: scope.binding,
          transport: 'outside',
        );
        await resources.queue.enqueue(request);
        await resources.queue.enqueue(outsider);
        // When the actual service processes A and then the explicitly undeclared target.
        final acceptedRun = await resources.service.processNext(
          networkAllowed: true,
        );
        final reads = native.calls.where((method) => method == 'read').length;
        final rejectedRun = await resources.service.processNext(
          networkAllowed: true,
        );
        // Then only the declared HTTP adapter obtains A ACCESS and dispatches.
        expect(acceptedRun.outcome, SubmissionRunOutcome.submitted);
        expect(
          acceptedRun.record!.request.authenticationBinding,
          scope.binding,
        );
        expect(rejectedRun.record!.lastFailure!.code, 'transportMissing');
        expect(
          native.calls.where((method) => method == 'read'),
          hasLength(reads),
        );
        expect(delivery.requests, hasLength(1));
        expect(delivery.requests.single.url, participantTarget().endpoint);
        expect(
          delivery.requests.single.headers['Authorization'],
          'Bearer ${ParticipantLogin.access('A')}',
        );
        expect(
          delivery.bodies.single,
          isNot(contains('authenticationBinding')),
        );
        expect(legacy.calls, isEmpty);
        expect(_credentialCalls(configurationCalls), isEmpty);
        await resources.close();
        expect(scope.context.isCurrent, isTrue);
        expect(accepted.transport.closeCalls, 0);
      });

      for (final actor in ['B', 'unbound', 'missing', 'retired']) {
        test(
          '$actor cannot process A originals or registered handoffs',
          () async {
            // Given A intent, missing originals, and a mismatching/absent/retired real scope.
            await configure(platform);
            UserAccountSubmissionScope? scope;
            if (actor != 'missing') {
              final accepted = await login(account: actor == 'B' ? 'B' : 'A');
              scope = accepted.scope(isCurrent: () => actor != 'retired');
            }
            final resources = await open(scope: scope);
            final binding = actor == 'unbound' ? null : participantBinding();
            final request = _request(
              'denied',
              binding: binding,
              withMissingOriginal: true,
            );
            final sourceRequest = _registeredRequest(
              'denied_registered',
              binding: binding,
            );
            await _saveRegistered(resources.queue, sourceRequest);
            await resources.queue.enqueue(request);
            final handoffs = resources.service.registeredMaterialHandoffs!;
            await handoffs.enqueueRegistered(
              sourceRequest.id,
              participantTarget(),
            );
            final calls = List<String>.of(native.calls);
            // When both actual service gates encounter those saved participant rows.
            final result = await resources.service.processNext(
              networkAllowed: true,
            );
            final handoff = await handoffs.processNext(networkAllowed: true);
            // Then authentication denial precedes missing-original, token and HTTP work.
            expect(result.outcome, SubmissionRunOutcome.failed);
            expect(result.record!.lastFailure!.code, 'authenticationRequired');
            expect(result.record!.reservations, isEmpty);
            expect(result.record!.transportCheckpoint, isNull);
            expect(handoff.outcome, RegisteredMaterialHandoffRunOutcome.failed);
            expect(handoff.record!.failure!.code, 'authenticationRequired');
            expect(native.calls, calls);
            expect(_credentialCalls(configurationCalls), isEmpty);
            expect(deliveryClients.single.requests, isEmpty);
            expect(
              (await resources.service.findTransferStatus(
                request.id,
                observedAt: _now,
              )),
              isNotNull,
            );
            expect((await resources.queue.find(request.id))!.request, request);
          },
        );
      }

      test(
        'actual TKL client captures A binding and excludes undeclared TKL root',
        () async {
          // Given a real A scope and declared/undeclared authenticated service roots.
          await configure(platform);
          final accepted = await login();
          final scope = accepted.scope();
          final delivery = _DeliveryHttp();
          delivery.handler = (request) async => ParticipantHttp.reply(
            request.url.path.endsWith('findForRequest')
                ? {'found': false}
                : {'availability': 'unavailable'},
          );
          final resources = await open(scope: scope, delivery: delivery);
          await resources.queue.enqueue(
            _request(
              'tkl_a',
              binding: scope.binding,
              transport: 'lake',
              tkl: true,
            ),
          );
          await resources.queue.enqueue(
            _request(
              'tkl_outside',
              binding: scope.binding,
              transport: 'outside_lake',
              tkl: true,
            ),
          );
          // When the actual TKL adapter discovers its destination and another row selects the outsider.
          final result = await resources.service.processNext(
            networkAllowed: true,
          );
          final outsider = await resources.service.processNext(
            networkAllowed: true,
          );
          // Then advanced lookup succeeded using the captured A binding only at the declared root.
          expect(result.record!.lastFailure!.code, 'lakeConfigurationRequired');
          expect(outsider.record!.lastFailure!.code, 'lakeConnectionRequired');
          expect(delivery.requests.map((request) => request.url.path), [
            '/delivery/findForRequest',
            '/delivery/getDestination',
          ]);
          expect(
            delivery.requests.every(
              (request) =>
                  request.headers['Authorization'] ==
                  'Bearer ${ParticipantLogin.access('A')}',
            ),
            isTrue,
          );
          expect(_credentialCalls(configurationCalls), isEmpty);
          expect(
            native.calls.where((method) => method == 'read'),
            hasLength(3),
          );
        },
      );

      test('registered handoff sends the unchanged v2 packet under A and excludes outsider', () async {
        // Given two actual saved Registered checkpoints, bound to accepted A.
        await configure(platform);
        final accepted = await login();
        final scope = accepted.scope();
        final resources = await open(scope: scope);
        final first = _registeredRequest(
          'registered_a',
          binding: scope.binding,
        );
        final other = _registeredRequest(
          'registered_outside',
          binding: scope.binding,
        );
        final saved = await _saveRegistered(resources.queue, first);
        await _saveRegistered(resources.queue, other);
        final handoffs = resources.service.registeredMaterialHandoffs!;
        await handoffs.enqueueRegistered(first.id, participantTarget());
        await handoffs.enqueueRegistered(
          other.id,
          participantTarget(id: 'outside'),
        );
        // When the actual Registered service uses its factory-wired context and target map.
        final result = await handoffs.processNext(networkAllowed: true);
        final outsider = await handoffs.processNext(networkAllowed: true);
        // Then only A's declared packet receives actual controlled server acceptance.
        expect(result.outcome, RegisteredMaterialHandoffRunOutcome.accepted);
        expect(outsider.record!.failure!.code, 'connectionMismatch');
        expect((await resources.queue.find(first.id)), saved);
        final delivery = deliveryClients.single;
        expect(delivery.requests, hasLength(1));
        expect(
          delivery.requests.single.headers['Authorization'],
          'Bearer ${ParticipantLogin.access('A')}',
        );
        final packet = jsonDecode(delivery.bodies.single) as Map;
        expect(packet['version'], 2);
        expect(packet.containsKey('authenticationBinding'), isFalse);
        expect(packet['registeredMaterial'], isNotNull);
      });

      test('participant Drive adapter retains its separate Google credential purpose', () async {
        // Given real retained original bytes, a participant A scope and a separate Drive token.
        await configure(platform);
        final accepted = await login();
        final legacy = _GoogleCredentials();
        final delivery = _DeliveryHttp()
          ..handler = (_) async => ParticipantHttp.reply({}, status: 403);
        final resources = await open(
          scope: accepted.scope(),
          credentials: legacy,
          delivery: delivery,
        );
        final captures = await openDefaultCaptureStore();
        final original = await captures.saveMaterial(
          bytes: Uint8List.fromList([1, 2, 3]),
          mediaType: 'image/jpeg',
          capturedAt: _now,
        );
        final request = _request(
          'drive_a',
          binding: participantBinding(),
          original: original,
        );
        await resources.queue.enqueue(request);
        final calls = List<String>.of(native.calls);
        // When actual Drive reservation attempts its existing Google endpoint.
        final result = await resources.service.processNext(
          networkAllowed: true,
        );
        // Then UA ACCESS is never forwarded to Google and the participant owner stays intact.
        expect(result.outcome, SubmissionRunOutcome.failed);
        expect(delivery.requests, hasLength(1));
        expect(delivery.requests.single.url.host, 'www.googleapis.com');
        expect(
          delivery.requests.single.headers['Authorization'],
          'Bearer SYNTHETIC.GOOGLE=',
        );
        expect(native.calls, calls);
        expect(
          legacy.calls,
          platform == TargetPlatform.iOS ? ['drive'] : isEmpty,
        );
        if (platform == TargetPlatform.android) {
          expect(
            (_credentialCalls(configurationCalls).single.arguments
                as Map)['connectionId'],
            'drive',
          );
        }
        expect(await captures.readMaterial(original), [1, 2, 3]);
      });

      test('omitted policy preserves actual legacy factory dispatch', () async {
        // Given ordinary config, an unbound saved request and the existing legacy provider.
        await configure(platform, declared: false);
        final legacy = ParticipantLegacyCredentials();
        final resources = await open(credentials: legacy);
        final request = _request('legacy_dispatch');
        await resources.queue.enqueue(request);
        // When existing callers use the source-compatible factory defaults.
        final result = await resources.service.processNext(
          networkAllowed: true,
        );
        // Then the unchanged legacy credential purpose and HTTP packet still work.
        expect(resources.service.requiresAuthentication, isFalse);
        expect(
          resources.service.registeredMaterialHandoffs!.requiresAuthentication,
          isFalse,
        );
        expect(result.outcome, SubmissionRunOutcome.submitted);
        expect(
          deliveryClients.single.requests.single.headers['Authorization'],
          'Bearer SYNTHETIC.LEGACY=',
        );
        expect(native.calls, isEmpty);
      });
    });
  }

  test('iOS finished batches preserve borrowed queue and root scope without reviving retired scope', () async {
    // Given resumed iOS and a real root A scope independent of every batch lifetime.
    await configure(TargetPlatform.iOS);
    final accepted = await login();
    var rootCurrent = true;
    final scope = accepted.scope(isCurrent: () => rootCurrent);
    final root = await open(scope: scope, ownedScheduler: true);
    final first = _request('batch_one', binding: scope.binding);
    final second = _request('batch_two', binding: scope.binding);
    Future<void> commitBatch(SubmissionRequest request) async {
      final closed = Completer<void>();
      final delivery = _DeliveryHttp()..onClosed = closed.complete;
      deliveryClients.add(delivery);
      await http.runWithClient(
        () => root.service.commit(request),
        () => delivery,
      );
      await closed.future;
    }

    // When two separate fresh scheduler batches finish over the shared queue/root scope.
    await commitBatch(first);
    final firstSaved = await root.queue.find(first.id);
    final afterFirst = scope.context.isCurrent;
    await commitBatch(second);
    final secondSaved = await root.queue.find(second.id);
    await root.close();
    // Then batch cleanup preserved the queue and the exact borrowed scope/backend.
    expect(firstSaved!.state, SubmissionState.submitted);
    expect(secondSaved!.state, SubmissionState.submitted);
    expect(afterFirst, isTrue);
    expect(scope.context.isCurrent, isTrue);
    expect(accepted.transport.closeCalls, 0);
    expect(native.calls.where((method) => method == 'close'), isEmpty);
    // When the root retires and a later callback tries to revive that same scope.
    rootCurrent = false;
    final retired = scope.context.isCurrent;
    rootCurrent = true;
    final stale = await open(scope: scope);
    await stale.queue.enqueue(_request('stale_batch', binding: scope.binding));
    final denied = await stale.service.processNext(networkAllowed: true);
    final freshScope = accepted.scope();
    final fresh = await open(scope: freshScope);
    // Then the old scope stays invalid, while only a newly composed scope can be current.
    expect(retired, isFalse);
    expect(scope.context.isCurrent, isFalse);
    expect(denied.record!.lastFailure!.code, 'authenticationRequired');
    expect(freshScope.context.isCurrent, isTrue);
    expect(await fresh.queue.find(first.id), firstSaved);
  });

  test('iOS fresh batch propagates explicit required policy when operator declaration is absent', () async {
    // Given missing participant setup and a default scheduler with a visible legacy port.
    await configure(TargetPlatform.iOS, declared: false);
    final legacy = ParticipantLegacyCredentials();
    final root = await open(
      required: true,
      ownedScheduler: true,
      credentials: legacy,
    );
    final request = _request('required_batch');
    final closed = Completer<void>();
    final delivery = _DeliveryHttp()..onClosed = closed.complete;
    deliveryClients.add(delivery);
    // When Commit wakes a fresh batch through the factory's captured required policy.
    await http.runWithClient(
      () => root.service.commit(request),
      () => delivery,
    );
    await closed.future;
    final saved = await root.queue.find(request.id);
    // Then an unbound legacy row cannot escape through fresh composition defaults.
    expect(saved!.lastFailure!.code, 'authenticationRequired');
    expect(legacy.calls, isEmpty);
    expect(delivery.requests, isEmpty);
    expect(native.calls, isEmpty);
  });

  test(
    'Android headless offline start precedes all resource/auth/original IO',
    () async {
      // Given a fresh actual headless handler with observable local/native/HTTP seams.
      await configure(TargetPlatform.android);
      final ready = Completer<void>();
      messenger.setMockMethodCallHandler(_backgroundChannel, (call) async {
        expect(call.method, 'ready');
        ready.complete();
        return null;
      });
      await http.runWithClient(() async {
        submissionBackgroundCallback();
        await ready.future;
      }, () => throw StateError('Unexpected offline HTTP construction'));
      // When native starts a run with network explicitly disallowed.
      final result = await http.runWithClient(
        () => _fromNative(binding, 'start', {
          'runId': 'offline',
          'networkAllowed': false,
        }),
        () => throw StateError('Unexpected offline HTTP construction'),
      );
      // Then no configuration, support path, protected record, queue or original is read.
      expect((result as Map)['outcome'], 'offline');
      expect(result['operations'], 0);
      expect(configurationCalls, isEmpty);
      expect(pathCalls, 0);
      expect(native.calls, isEmpty);
      expect(await directory.list().toList(), isEmpty);
    },
  );

  test('Android headless stop during owned restore drains auth and never runs saved queue', () async {
    // Given a real retained A login and actual saved queue whose next restore read is held.
    await configure(TargetPlatform.android);
    final accepted = await login();
    await accepted.close();
    final queue = await openDefaultSubmissionQueueStore();
    queues.add(queue);
    final request = _request(
      'held_restore_queue',
      binding: participantBinding(),
    );
    final saved = await queue.enqueue(request);
    final entry = native.read();
    final entered = Completer<void>();
    final release = Completer<Object?>();
    native.onRead = (_) {
      entered.complete();
      return release.future;
    };
    final ready = Completer<void>();
    messenger.setMockMethodCallHandler(_backgroundChannel, (_) async {
      ready.complete();
      return null;
    });
    final authHttp = ParticipantHttp();
    http.runWithClient(submissionBackgroundCallback, () => authHttp);
    await ready.future;
    final starting = http.runWithClient(
      () => _fromNative(binding, 'start', {
        'runId': 'held_headless',
        'networkAllowed': true,
      }),
      () => authHttp,
    );
    await entered.future;
    // When the matching native stop retires the owner before restore can publish.
    await _fromNative(binding, 'stop', {'runId': 'held_headless'});
    release.complete(entry);
    final result = await starting;
    // Then actual owned auth cleanup completes and saved queue intent was never claimed.
    expect((result as Map)['outcome'], 'cancelled');
    expect(result['operations'], 0);
    expect(authHttp.closeCalls, 1);
    expect(authHttp.requests, isEmpty);
    expect(native.calls.where((method) => method == 'close'), hasLength(2));
    expect(configurationCalls.map((call) => call.method), [
      'snapshot',
      'closeConfiguration',
    ]);
    expect(await queue.find(request.id), saved);
    expect(native.read(), entry);
  });

  test('Android partial open after real restore attempts auth and config cleanup without erasure', () async {
    // Given actual retained credentials and a corrupt test-owned default queue file.
    await configure(TargetPlatform.android);
    final accepted = await login();
    await accepted.close();
    final retained = native.read();
    final corrupt = File('${directory.path}/textus_submission.sqlite');
    final corruptBytes = utf8.encode('PRIVATE.OWNED.CORRUPT.QUEUE');
    await corrupt.writeAsBytes(corruptBytes, flush: true);
    final authHttp = ParticipantHttp()..json(participantAccount('A'));
    final life = SubmissionRunLifetime(id: 'partial_owned_restore');
    // When explicit owned restore succeeds but subsequent actual SQLite acquisition fails.
    final error = await participantCapture(
      () => http.runWithClient(
        () => openDefaultAndroidSubmissionResources(
          lifetime: life,
          restoreParticipantAuthentication: true,
        ),
        () => authHttp,
      ),
    );
    // Then every acquired owner is retired/closed and both retained artifacts remain exact.
    expect(error, isNotNull);
    expect(life.isCurrent, isFalse);
    expect(authHttp.closeCalls, 1);
    expect(native.calls.where((method) => method == 'close'), hasLength(2));
    expect(configurationCalls.map((call) => call.method), [
      'snapshot',
      'closeConfiguration',
    ]);
    expect(native.read(), retained);
    expect(await corrupt.readAsBytes(), corruptBytes);
  });

  test('Android close attempts delivery auth queue and config after independent cleanup failures', () async {
    // Given a genuine owned restore and delivery HTTP/native/config owners that fail close.
    await configure(TargetPlatform.android);
    final accepted = await login();
    await accepted.close();
    final retained = native.read();
    final authHttp = ParticipantHttp()..json(participantAccount('A'));
    final delivery = _DeliveryHttp()..failClose = true;
    var constructions = 0;
    final resources = await http.runWithClient(
      () => openDefaultAndroidSubmissionResources(
        lifetime: SubmissionRunLifetime(id: 'all_cleanup'),
        scheduler: _BorrowedScheduler(),
        restoreParticipantAuthentication: true,
      ),
      () => constructions++ == 0 ? authHttp : delivery,
    );
    final request = _request(
      'retained_on_close',
      binding: participantBinding(),
    );
    await resources.queue.enqueue(request);
    native.onClose = (_) async =>
        throw PlatformException(code: 'unavailable', message: 'PRIVATE.NATIVE');
    failConfigurationClose = true;
    // When explicit owner cleanup encounters all independent failures.
    final closing = resources.close();
    final error = await participantCapture(() => closing);
    // Then the honest fixed safe failure preserves the same join and attempts every owner.
    expect(
      error,
      isA<SubmissionConfigurationException>().having(
        (e) => e.code,
        'code',
        'configurationUnavailable',
      ),
    );
    expect('$error', isNot(contains('PRIVATE')));
    expect(resources.close(), same(closing));
    expect(delivery.closeCalls, 1);
    expect(authHttp.closeCalls, 1);
    expect(configurationCalls.last.method, 'closeConfiguration');
    expect(native.calls.where((method) => method == 'close'), hasLength(2));
    final queueError = await participantCapture(resources.queue.list);
    expect(queueError, isA<StateError>());
    final reopened = await openDefaultSubmissionQueueStore();
    queues.add(reopened);
    expect((await reopened.find(request.id))!.request, request);
    expect(native.read(), retained);
    native.onClose = null;
    failConfigurationClose = false;
  });

  test('iOS partial open leaves borrowed auth scheduler and credential owners usable', () async {
    // Given actual iOS config/root A and a corrupt queue under test-only support roots.
    await configure(TargetPlatform.iOS);
    final accepted = await login();
    final scope = accepted.scope();
    final scheduler = _BorrowedScheduler();
    final credentials = ParticipantLegacyCredentials();
    final corrupt = File('${directory.path}/textus_submission.sqlite');
    final bytes = utf8.encode('PRIVATE.IOS.QUEUE');
    await corrupt.writeAsBytes(bytes, flush: true);
    final life = SubmissionRunLifetime(id: 'partial_ios');
    final calls = List<String>.of(native.calls);
    // When the actual factory must unwind config/helper acquisition after queue failure.
    final error = await participantCapture(
      () => openDefaultIosSubmissionResources(
        lifetime: life,
        authenticationScope: scope,
        scheduler: scheduler,
        credentials: credentials,
      ),
    );
    // Then the safe failure neither closes borrowed roots nor changes queue/config/credentials.
    expect(
      error,
      isA<StateError>().having(
        (e) => e.message,
        'safe message',
        'iOS submission resources are unavailable',
      ),
    );
    expect(life.isCurrent, isFalse);
    expect(native.calls, calls);
    expect(scope.context.isCurrent, isTrue);
    expect(accepted.transport.closeCalls, 0);
    expect(credentials.calls, isEmpty);
    await scheduler.requestRun();
    expect(scheduler.calls, 1);
    expect(await corrupt.readAsBytes(), bytes);
    expect(
      (await configurations.single.snapshot()).participantAuthentication,
      isNotNull,
    );
  });
}

SubmissionConfigurationSnapshot _snapshot({bool declared = true}) {
  final base = participantSnapshot(declared: declared);
  return SubmissionConfigurationSnapshot(
    driveConnections: [
      DriveSubmissionConnection(
        id: 'drive',
        accountId: 'google@example.test',
        folderId: 'Folder_1',
      ),
    ],
    httpConnections: [
      ...base.httpConnections,
      participantTarget(id: 'outside_lake', path: '/outside/'),
    ],
    referenceAccessBindings: const {
      'server': ['drive'],
    },
    participantAuthentication: base.participantAuthentication,
  );
}

SubmissionRequest _request(
  String id, {
  SubmissionAuthenticationBinding? binding,
  String transport = 'server',
  bool withMissingOriginal = false,
  CaptureMaterialReference? original,
  bool tkl = false,
}) => SubmissionRequest(
  id: id,
  kind: 'bookMaterial',
  subjectId: id,
  createdAt: _now,
  document: const {'local': true},
  payload: const {'title': 'retained'},
  materials: withMissingOriginal || original != null
      ? [
          SubmissionMaterial(
            key: 'photo',
            original:
                original ??
                CaptureMaterialReference(
                  id: 'missing_original',
                  mediaType: 'image/jpeg',
                  byteLength: 3,
                  capturedAt: _now,
                ),
          ),
        ]
      : const [],
  storageConnectionId: withMissingOriginal || original != null ? 'drive' : null,
  transportConnectionId: transport,
  authenticationBinding: binding,
  tklDelivery: tkl
      ? TklMaterialDeliveryRequest(
          requestId: id,
          contribution: const {'originals': []},
        )
      : null,
);

SubmissionRequest _registeredRequest(
  String id, {
  SubmissionAuthenticationBinding? binding,
}) {
  final source = registeredTestRequest(id: id, mediaTypes: const []);
  return SubmissionRequest(
    id: source.id,
    kind: source.kind,
    subjectId: source.subjectId,
    createdAt: source.createdAt,
    document: source.document,
    payload: source.payload,
    materials: source.materials,
    transportConnectionId: source.transportConnectionId,
    tklDelivery: source.tklDelivery,
    extensions: source.extensions,
    authenticationBinding: binding,
  );
}

Future<SubmissionRecord> _saveRegistered(
  SubmissionQueueStore queue,
  SubmissionRequest request,
) async {
  await queue.enqueue(request);
  final lease = 'registration_${request.id}';
  final claimed = await queue.claimNext(
    now: _now,
    leaseToken: lease,
    leaseDuration: const Duration(minutes: 5),
  );
  expect(claimed!.request.id, request.id);
  await queue.saveTklProgress(
    id: request.id,
    leaseToken: lease,
    now: _now,
    progress: TklMaterialDeliverySnapshot(
      deliveryRef: 'saved_${request.id}',
      requestId: request.id,
      revision: 1,
      destinationId: 'selected',
      destinationLabel: 'Synthetic selected',
      state: TklMaterialDeliveryState.registered,
      materialRef: 'urn:material:${request.id}',
      resources: const [],
    ),
  );
  return queue.completeMaterialRegistration(
    id: request.id,
    leaseToken: lease,
    now: _now,
  );
}

List<MethodCall> _credentialCalls(List<MethodCall> calls) => calls
    .where(
      (call) => [
        'bearerToken',
        'authorizeDrive',
        'authorizationState',
      ].contains(call.method),
    )
    .toList();

Future<Object?> _fromNative(
  WidgetsBinding binding,
  String method,
  Map<String, Object?> arguments,
) {
  final completion = Completer<Object?>();
  const codec = StandardMethodCodec();
  binding.channelBuffers.push(
    _backgroundChannel.name,
    codec.encodeMethodCall(MethodCall(method, arguments)),
    (reply) {
      try {
        completion.complete(codec.decodeEnvelope(reply!));
      } catch (error, stack) {
        completion.completeError(error, stack);
      }
    },
  );
  return completion.future;
}

Future<void> _lifecycle(WidgetsBinding binding, AppLifecycleState state) {
  final completion = Completer<void>();
  binding.channelBuffers.push(
    'flutter/lifecycle',
    const StringCodec().encodeMessage(state.toString()),
    (_) => completion.complete(),
  );
  return completion.future;
}

final class _BorrowedScheduler implements SubmissionWakeScheduler {
  int calls = 0;
  @override
  Future<void> requestRun() async {
    calls++;
  }
}

final class _GoogleCredentials implements SubmissionCredentialProvider {
  final calls = <String>[];
  @override
  Future<String?> bearerToken(String connectionId) async {
    calls.add(connectionId);
    return 'SYNTHETIC.GOOGLE=';
  }
}

final class _DeliveryHttp extends http.BaseClient {
  final requests = <http.BaseRequest>[];
  final bodies = <String>[];
  FutureOr<http.StreamedResponse> Function(http.BaseRequest)? handler;
  void Function()? onClosed;
  bool failClose = false;
  int closeCalls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final body = utf8.decode(await request.finalize().toBytes());
    bodies.add(body);
    if (handler != null) return await handler!(request);
    final packet = jsonDecode(body) as Map;
    return ParticipantHttp.reply(
      SubmissionCodec.acknowledgementToJson(
        SubmissionAcknowledgement(
          requestId: packet['requestId'] as String,
          subjectId: packet['subjectId'] as String,
          serverId: 'synthetic/server',
          receivedAt: _now,
        ),
      ),
      status: 201,
    );
  }

  @override
  void close() {
    closeCalls++;
    onClosed?.call();
    if (failClose) throw StateError('PRIVATE.DELIVERY.CLOSE');
  }
}
