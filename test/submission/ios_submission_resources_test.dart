import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqlite;
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  sqlite.sqfliteFfiInit();
  late Directory directory;
  TargetPlatform? previousPlatform;
  AppLifecycleState? previousLifecycle;
  sqlite.DatabaseFactory? previousFactory;
  late List<SubmissionBackgroundResources> owners;
  late List<IosSubmissionConfigurationStore> configurations;
  late List<SubmissionQueueStore> queues;
  var pathCalls = 0;

  setUp(() async {
    previousPlatform = debugDefaultTargetPlatformOverride;
    previousLifecycle = binding.lifecycleState;
    previousFactory = sqlite.databaseFactoryOrNull;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    sqlite.databaseFactoryOrNull = sqlite.databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp(
      'ios-submission-resources-',
    );
    owners = [];
    configurations = [];
    queues = [];
    pathCalls = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(paths, (
      call,
    ) async {
      // Given a sandbox owned solely by this test, expose the known path channel.
      expect(call.method, 'getApplicationSupportDirectory');
      pathCalls++;
      // When default production composition resolves its existing durable roots.
      return directory.path;
      // Then native plugins and normal device data are never accessed.
    });
    binding.resetInternalState();
    _lifecycle(binding, AppLifecycleState.resumed);
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
      await directory.delete(recursive: true);
    } finally {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(paths, null);
      sqlite.databaseFactoryOrNull = previousFactory;
      binding.resetInternalState();
      if (previousLifecycle != null) _lifecycle(binding, previousLifecycle!);
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  Future<IosSubmissionConfigurationStore> configuration() async {
    final store = await IosSubmissionConfigurationStore.open();
    configurations.add(store);
    return store;
  }

  Future<SubmissionBackgroundResources> open(
    SubmissionRunLifetime lifetime, {
    SubmissionWakeScheduler? scheduler,
    SubmissionCredentialProvider? credentials,
  }) async {
    final resources = await openDefaultIosSubmissionResources(
      lifetime: lifetime,
      scheduler: scheduler,
      credentials: credentials,
    );
    owners.add(resources);
    return resources;
  }

  test('default open is inert foreground composition and close retains definitions and originals', () async {
    // Given safe operator definitions, current selection and actual original bytes.
    final config = await configuration();
    final drive = DriveSubmissionConnection(
      id: 'drive',
      accountId: 'owner@example.test',
      folderId: 'Folder_1',
    );
    final server = _server('server');
    final lake = _server('lake', path: '/');
    await config.putDrive(drive);
    await config.putHttp(server);
    await config.putHttp(lake);
    await config.select(
      storageConnectionId: drive.id,
      transportConnectionId: lake.id,
    );
    await config.setReferenceAccess(
      transportConnectionId: server.id,
      storageConnectionIds: [drive.id],
    );
    final expected = (await config.snapshot()).toJson();
    final captures = await openDefaultCaptureStore();
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final original = await captures.saveMaterial(
      bytes: bytes,
      mediaType: 'image/jpeg',
      capturedAt: DateTime.utc(2026, 11, 5),
    );
    final credentials = _Credentials((_) async => 'UNUSED_SYNTHETIC_TOKEN');
    final life = SubmissionRunLifetime(id: 'main_inert');
    // When default resources open with their owned, inert foreground scheduler.
    final resources = await open(life, credentials: credentials);
    // Then opening alone creates no job, credential request or lifecycle work.
    expect(resources.executionMode, SubmissionExecutionMode.foreground);
    expect(await resources.queue.list(), isEmpty);
    expect(await resources.service.registeredMaterialHandoffs!.list(), isEmpty);
    expect(credentials.calls, isEmpty);
    expect((await config.snapshot()).toJson(), expected);
    expect(life.isCurrent, isTrue);
    final closing = resources.close();
    expect(resources.close(), same(closing));
    expect(life.isCurrent, isFalse);
    await _deadline(closing);
    // Then owned close preserves the public configuration and borrowed capture data.
    final reopened = await configuration();
    expect((await reopened.snapshot()).toJson(), expected);
    expect(await captures.readMaterial(original), bytes);
    expect(credentials.closed, isFalse);
    expect(credentials.calls, isEmpty);
    final next = await open(SubmissionRunLifetime(id: 'main_reopen'));
    expect(next.executionMode, SubmissionExecutionMode.foreground);
    expect(await next.queue.list(), isEmpty);
    expect(await captures.readMaterial(original), bytes);
  });

  test('supplied scheduler and credentials stay borrowed through default ownership cleanup', () async {
    // Given independently owned wake/credential ports and a durable definition.
    final config = await configuration();
    await config.putHttp(_server('server'));
    final scheduler = _BorrowedScheduler();
    final credentials = _Credentials((_) async => null);
    // When the default composition is given these existing owners.
    final resources = await open(
      SubmissionRunLifetime(id: 'borrowed_ports'),
      scheduler: scheduler,
      credentials: credentials,
    );
    expect(scheduler.calls, 0);
    expect(credentials.calls, isEmpty);
    await _deadline(resources.close());
    // Then it closes only its own handles and leaves both supplied ports usable.
    expect(scheduler.closed, isFalse);
    expect(credentials.closed, isFalse);
    await scheduler.requestRun();
    expect(scheduler.calls, 1);
    expect(await credentials.bearerToken('server'), isNull);
    expect((await config.snapshot()).httpConnections.single.id, 'server');
  });

  test(
    'owned scheduler drains a fresh run before main queue closure',
    () async {
      // Given inert main resources opened before a later operator definition exists.
      final entered = Completer<void>();
      final release = Completer<String?>();
      final credentials = _Credentials((id) {
        expect(id, 'later_server');
        entered.complete();
        return release.future;
      });
      final mainLife = SubmissionRunLifetime(id: 'main_drain');
      final resources = await open(mainLife, credentials: credentials);
      final config = await configuration();
      await config.putHttp(_server('later_server'));
      final request = _request(
        'late_configuration',
        transportId: 'later_server',
      );
      addTearDown(() {
        if (!release.isCompleted) release.complete(null);
      });
      // When Commit wakes the default scheduler, the batch loads fresh definitions
      // and reaches the held borrowed credential read without a network operation.
      final committed = await _deadline(resources.service.commit(request));
      expect(committed.schedulingFailure, isNull);
      await _deadline(entered.future);
      expect(credentials.calls, ['later_server']);
      // When main close retires both main and scheduler ownership before awaiting.
      final closing = resources.close();
      expect(resources.close(), same(closing));
      expect(mainLife.isCurrent, isFalse);
      var finished = false;
      final observed = closing.then((_) => finished = true);
      // Then the exact main queue remains open while transient cleanup is pending.
      final duringClose = (await resources.queue.find(request.id))!;
      expect(duringClose.request, request);
      expect(duringClose.acknowledgement, isNull);
      expect(finished, isFalse);
      // A separate config handle is usable while the run drains its credential read.
      await config.putHttp(_server('still_usable'));
      expect((await config.snapshot()).httpConnections, hasLength(2));
      release.complete(null);
      await _deadline(observed);
      // Then all transient work has drained before the queue's owned close, and
      // reopening sees the original intent and current configuration unchanged.
      await expectLater(resources.queue.list(), throwsStateError);
      final queue = await openDefaultSubmissionQueueStore();
      queues.add(queue);
      final retained = (await queue.list()).single;
      expect(retained.request, request);
      expect(retained.state, SubmissionState.readyToSubmit);
      expect(retained.acknowledgement, isNull);
      expect(credentials.closed, isFalse);
      expect(
        (await (await configuration()).snapshot()).httpConnections,
        hasLength(2),
      );
    },
  );

  test(
    'retired lifetime and unsupported platforms reject before all ports',
    () async {
      // Given an absent sandbox and a visible borrowed credential/scheduler owner.
      final credentials = _Credentials((_) async => 'unused');
      final scheduler = _BorrowedScheduler();
      final retired = SubmissionRunLifetime(id: 'already_retired')..retire();
      // When a retired owner opens on iOS, it fails safely before configuration IO.
      await expectLater(
        openDefaultIosSubmissionResources(
          lifetime: retired,
          scheduler: scheduler,
          credentials: credentials,
        ),
        throwsA(_unavailable()),
      );
      for (final platform in TargetPlatform.values.where(
        (p) => p != TargetPlatform.iOS,
      )) {
        debugDefaultTargetPlatformOverride = platform;
        // When the public factory is asked to open on an unsupported target.
        await expectLater(
          openDefaultIosSubmissionResources(
            lifetime: SubmissionRunLifetime(id: 'unsupported_${platform.name}'),
            scheduler: scheduler,
            credentials: credentials,
          ),
          throwsUnsupportedError,
        );
      }
      // Then neither path resolution nor configuration, queue or credential IO occurs.
      expect(pathCalls, 0);
      expect(await directory.list().toList(), isEmpty);
      expect(credentials.calls, isEmpty);
      expect(scheduler.calls, 0);
      expect(scheduler.closed, isFalse);
    },
  );

  test('corrupt queue gives a fixed safe error and preserves every retained owner', () async {
    // Given valid durable configuration and a test-owned corrupt default queue file.
    final config = await configuration();
    await config.putHttp(_server('retained'));
    final accepted = (await config.snapshot()).toJson();
    final corrupt = File('${directory.path}/textus_submission.sqlite');
    final bytes = Uint8List.fromList('PRIVATE_CORRUPT_QUEUE'.codeUnits);
    await corrupt.writeAsBytes(bytes, flush: true);
    final credentials = _Credentials((_) async => 'unused');
    final scheduler = _BorrowedScheduler();
    final life = SubmissionRunLifetime(id: 'partial_failure');
    // When acquisition fails after the factory acquired its own config handle.
    await expectLater(
      openDefaultIosSubmissionResources(
        lifetime: life,
        scheduler: scheduler,
        credentials: credentials,
      ),
      throwsA(_unavailable()),
    );
    // Then the safe error reveals no path/cause, retires its owner, and neither
    // replaces the corrupt file nor prevents another config owner from working.
    expect(life.isCurrent, isFalse);
    expect(await corrupt.readAsBytes(), bytes);
    expect((await config.snapshot()).toJson(), accepted);
    await config.putHttp(_server('after_failure'));
    expect(
      (await (await configuration()).snapshot()).httpConnections,
      hasLength(2),
    );
    expect(await corrupt.readAsBytes(), bytes);
    expect(credentials.calls, isEmpty);
    expect(credentials.closed, isFalse);
    expect(scheduler.calls, 0);
    expect(scheduler.closed, isFalse);
  });

  test('existing resource constructors retain unknown capability by default', () async {
    // Given existing resources whose service and durable queue can be borrowed.
    final resources = await open(SubmissionRunLifetime(id: 'compatibility'));
    // When a custom composition uses only the original required arguments.
    final custom = SubmissionBackgroundResources(
      service: resources.service,
      queue: resources.queue,
      close: () async {},
    );
    // Then capability remains unknown without affecting the borrowed durable queue.
    expect(custom.executionMode, SubmissionExecutionMode.unknown);
    expect(await custom.queue.list(), isEmpty);
  });
}

HttpSubmissionConnection _server(String id, {String path = '/submit'}) =>
    HttpSubmissionConnection(
      id: id,
      endpoint: Uri.parse('https://example.test$path'),
      requiresBearerToken: true,
    );

SubmissionRequest _request(String id, {required String transportId}) =>
    SubmissionRequest(
      id: id,
      kind: 'bookMaterial',
      subjectId: id,
      createdAt: DateTime.utc(2026, 11, 5),
      document: const {'local': true},
      payload: const {'title': 'retained'},
      materials: const [],
      transportConnectionId: transportId,
    );

Matcher _unavailable() => isA<StateError>().having(
  (error) => error.message,
  'fixed safe error',
  'iOS submission resources are unavailable',
);

Future<T> _deadline<T>(Future<T> future) =>
    future.timeout(const Duration(seconds: 5));

void _lifecycle(WidgetsBinding binding, AppLifecycleState state) {
  // ignore: invalid_use_of_protected_member
  binding.handleAppLifecycleStateChanged(state);
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

final class _BorrowedScheduler implements SubmissionWakeScheduler {
  int calls = 0;
  bool closed = false;

  @override
  Future<void> requestRun() async {
    if (closed) throw StateError('Test scheduler is closed');
    calls++;
  }

  Future<void> close() async {
    closed = true;
  }
}
