import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

final _configuration = RecognitionSettings.configuration;
final _configurationId = _configuration.id;

String _wire(
  Map<String, Object?> values, {
  int version = 1,
  Map<String, Object?> extras = const {},
}) => jsonEncode({...extras, 'version': version, 'values': values});

SettingsLifecycleController _controller(
  _ControllableStorage storage, {
  SettingsRegistry? registry,
  List<SettingDefinition<Object>>? resetDefinitions,
}) {
  final controller = SettingsLifecycleController(
    registry: registry ?? RecognitionSettings.registry(),
    storage: storage,
    resetDefinitions: resetDefinitions ?? RecognitionSettings.definitions,
  );
  addTearDown(controller.dispose);
  return controller;
}

Future<SettingsLifecycleController> _ready(_ControllableStorage storage) async {
  final controller = _controller(storage);
  final loaded = controller.load();
  storage.readDurable(storage.reads.length - 1);
  await loaded;
  return controller;
}

Future<void> _flushMicrotasks() async {
  for (var turn = 0; turn < 8; turn++) {
    await Future<void>.value();
  }
}

SettingsRecord _submitted(_ControllableStorage storage, int index) =>
    SettingsRecord.decode(storage.writes[index].record);

void main() {
  group('Desired recognition configuration independent of capability', () {
    test('R01 default and finite choices need no device capability', () {
      // Given a Core-only recognition registry and an empty capability set.
      final registry = RecognitionSettings.registry();
      final snapshot = SettingsSnapshot(registry: registry);
      final capabilities = SettingsCapabilities();

      // When the schema and effective default are read through public APIs.
      final value = snapshot.value(_configuration);
      final availability = _configuration.availability(capabilities);

      // Then standard is inherited and enhanced is always selectable as desired intent.
      expect(value, RecognitionSettings.androidStandard);
      expect(registry.definition(_configurationId), same(_configuration));
      expect(registry.definitions, [_configuration]);
      expect(registry.groups.single.id, 'capture');
      expect(registry.groups.single.label, 'Capture');
      expect(_configuration.label, 'Recognition configuration');
      expect(_configuration.choices.map((choice) => choice.value), [
        RecognitionSettings.androidStandard,
        RecognitionSettings.pixelEnhanced,
      ]);
      expect(_configuration.choices.map((choice) => choice.storedValue), [
        RecognitionSettings.androidStandard,
        RecognitionSettings.pixelEnhanced,
      ]);
      expect(_configuration.choices.map((choice) => choice.label), [
        'Standard Android',
        'Pixel enhanced',
      ]);
      expect(availability, SettingAvailability.available);
      expect(_configuration.availabilityPolicy, SettingAvailabilityPolicy.always);
      expect(_configuration.requiredCapability, isNull);
      expect(snapshot.explicitValueIds, isEmpty);
      expect(() => RecognitionSettings.groups.clear(), throwsUnsupportedError);
      expect(() => RecognitionSettings.definitions.clear(), throwsUnsupportedError);
    });

    test('R02 enhanced preference survives acknowledged save and restart', () async {
      // Given absent storage restored by a Core-only controller.
      final storage = _ControllableStorage();
      final controller = await _ready(storage);
      final SettingsService service = controller;

      // When enhanced intent is saved and a new controller loads its durable record.
      service.setValue(_configurationId, RecognitionSettings.pixelEnhanced);
      await _flushMicrotasks();
      final saving = service.retrySave();
      final beforeAcknowledgement = service.snapshot;
      storage.writes.single.succeed();
      await saving;
      final restored = await _ready(storage);

      // Then only acknowledgement clears unsaved intent and version1 stores the String ID.
      expect(beforeAcknowledgement.hasUnsavedChanges, isTrue);
      expect(beforeAcknowledgement.savedRevision, 0);
      expect(service.snapshot.saveState, SettingsSaveState.idle);
      expect(service.snapshot.savedRevision, 1);
      expect(service.snapshot.unsavedIds, isEmpty);
      final record = SettingsRecord.decode(storage.durableRecord!);
      expect(record.version, 1);
      expect(record.isSupported, isTrue);
      expect(record.values[_configurationId], RecognitionSettings.pixelEnhanced);
      expect(
        restored.snapshot.value(_configuration),
        RecognitionSettings.pixelEnhanced,
      );
      expect(restored.snapshot.hasExplicitValue(_configurationId), isTrue);
      expect(restored.snapshot.lastIntent, isNull);
      expect(storage.writes.length, 1);
    });

    test('R03 invalid configuration and unknown setting leave no intent or write', () async {
      // Given a ready standard preference and observed notifications.
      final storage = _ControllableStorage();
      final controller = await _ready(storage);
      final before = controller.snapshot;
      var notifications = 0;
      controller.addListener(() => notifications++);

      // When undeclared values, wrong types and unknown IDs are submitted.
      final actions = <void Function()>[
        () => controller.setValue(_configurationId, 'unsupportedConfiguration'),
        () => controller.setValue(_configurationId, 42),
        () => controller.setValue(
          'unknown.setting',
          RecognitionSettings.pixelEnhanced,
        ),
      ];

      // Then validation rejects each action before state, intent or adapter mutation.
      for (final action in actions) {
        expect(action, throwsArgumentError);
      }
      await _flushMicrotasks();
      expect(controller.snapshot, same(before));
      expect(
        controller.snapshot.value(_configuration),
        RecognitionSettings.androidStandard,
      );
      expect(controller.snapshot.revision, 0);
      expect(controller.snapshot.lastIntent, isNull);
      expect(controller.snapshot.unsavedIds, isEmpty);
      expect(notifications, 0);
      expect(storage.writes, isEmpty);
    });
  });

  group('Recognition read barrier, failure and caller-selected reset policy', () {
    test('R04 delayed standard restoration preserves enhanced edit and unknown data', () async {
      // Given an initial delayed read and unknown nested envelope/value data.
      final storage = _ControllableStorage();
      final controller = _controller(storage);
      final loaded = controller.load();
      final unknown = {'nested': [true, null, {'future': 'kept'}]};
      final extras = {'futureEnvelope': {'items': [1, 2]}};

      // When enhanced is selected before the older standard record arrives.
      controller.setValue(_configurationId, RecognitionSettings.pixelEnhanced);
      await _flushMicrotasks();
      final writesBeforeRead = storage.writes.length;
      storage.reads.single.succeed(_wire({
        _configurationId: RecognitionSettings.androidStandard,
        'future.preference': unknown,
      }, extras: extras));
      await loaded;
      await _flushMicrotasks();
      final merged = _submitted(storage, 0);
      final saving = controller.retrySave();
      storage.writes.single.succeed();
      await saving;

      // Then no early write occurs and the newer desired value overlays only its key.
      expect(writesBeforeRead, 0);
      expect(
        controller.snapshot.value(_configuration),
        RecognitionSettings.pixelEnhanced,
      );
      expect(merged.values[_configurationId], RecognitionSettings.pixelEnhanced);
      expect(merged.values['future.preference'], unknown);
      expect(merged.extraFields, extras);
      expect(controller.snapshot.savedRevision, 1);
      expect(storage.writes.length, 1);
    });

    test('R05 failed save retries latest choice and restart reads acknowledgement', () async {
      // Given ready absent storage and an explicit enhanced edit awaiting a write.
      final storage = _ControllableStorage();
      final controller = await _ready(storage);
      final failure = StateError('replacement failed');
      controller.setValue(_configurationId, RecognitionSettings.pixelEnhanced);
      await _flushMicrotasks();
      final failedPump = controller.retrySave();

      // When replacement fails, a newer standard edit stays latched until explicit retry.
      storage.writes[0].fail(failure);
      await failedPump;
      final failed = controller.snapshot;
      controller.setValue(_configurationId, RecognitionSettings.androidStandard);
      await _flushMicrotasks();
      final latched = controller.snapshot;
      final writesBeforeRetry = storage.writes.length;
      final retried = controller.retrySave();
      await _flushMicrotasks();
      final latest = _submitted(storage, 1);
      storage.writes[1].succeed();
      await retried;
      final restored = await _ready(storage);

      // Then failure identity/unsaved revisions remain observable and latest choice is durable.
      expect(failed.saveState, SettingsSaveState.failed);
      expect(failed.saveError, same(failure));
      expect(failed.unsavedIds, {_configurationId});
      expect(failed.savedRevision, 0);
      expect(failed.value(_configuration), RecognitionSettings.pixelEnhanced);
      expect(latched.saveError, same(failure));
      expect(latched.saveState, SettingsSaveState.failed);
      expect(latched.unsavedIds, {_configurationId});
      expect(writesBeforeRetry, 1);
      expect(latest.values[_configurationId], RecognitionSettings.androidStandard);
      expect(controller.snapshot.savedRevision, 2);
      expect(controller.snapshot.saveError, isNull);
      expect(controller.snapshot.unsavedIds, isEmpty);
      expect(
        restored.snapshot.value(_configuration),
        RecognitionSettings.androidStandard,
      );
      expect(restored.snapshot.hasExplicitValue(_configurationId), isTrue);
      expect(storage.durableRecord, storage.writes[1].record);
    });

    test('R06 unsupported integer envelope requires explicit configured reset', () async {
      // Given an unsupported durable envelope retaining unknown nested data.
      final unknown = {'nested': [null, 'future']};
      final extras = {'futureEnvelope': {'retained': true}};
      final storage = _ControllableStorage(durableRecord: _wire({
        _configurationId: RecognitionSettings.pixelEnhanced,
        'future.preference': unknown,
      }, version: 9, extras: extras));
      final controller = await _ready(storage);

      // When an enhanced edit is blocked, then explicit resetCommon authorizes recovery.
      controller.setValue(_configurationId, RecognitionSettings.pixelEnhanced);
      await controller.retrySave();
      await _flushMicrotasks();
      final protected = controller.snapshot;
      final writesBeforeReset = storage.writes.length;
      controller.resetCommon();
      final reset = controller.snapshot;
      await _flushMicrotasks();
      final recoveredRecord = _submitted(storage, 0);
      final saving = controller.retrySave();
      storage.writes.single.succeed();
      await saving;
      final restored = await _ready(storage);

      // Then unsupported data is protected until reset and recovery preserves unknown fields.
      expect(protected.readState, SettingsReadState.unsupported);
      expect(protected.readError, isA<StateError>());
      expect(protected.unsavedIds, {_configurationId});
      expect(writesBeforeReset, 0);
      expect(reset.value(_configuration), RecognitionSettings.androidStandard);
      expect(reset.lastIntent!.kind, SettingsIntentKind.resetCommon);
      expect(recoveredRecord.version, SettingsRecord.currentVersion);
      expect(recoveredRecord.values[_configurationId], RecognitionSettings.androidStandard);
      expect(recoveredRecord.values['future.preference'], unknown);
      expect(recoveredRecord.extraFields, extras);
      expect(controller.snapshot.readState, SettingsReadState.ready);
      expect(controller.snapshot.readError, isNull);
      expect(controller.snapshot.unsavedIds, isEmpty);
      expect(
        restored.snapshot.value(_configuration),
        RecognitionSettings.androidStandard,
      );
    });

    test('R07 read failures stay observable and block writes until explicit retry', () async {
      // Given a delayed restoration and a specific adapter read failure.
      final storage = _ControllableStorage();
      final controller = _controller(storage);
      final failure = StateError('read failed');
      final loaded = controller.load();

      // When read fails and reset/edit occur before an explicit successful read retry.
      storage.reads.single.fail(failure);
      await loaded;
      controller.resetCommon();
      controller.setValue(_configurationId, RecognitionSettings.pixelEnhanced);
      await controller.load();
      await controller.retrySave();
      final blocked = controller.snapshot;
      final readsBeforeRetry = storage.reads.length;
      final writesBeforeRetry = storage.writes.length;
      final retried = controller.retryLoad();
      storage.reads[1].succeed(
        _wire({_configurationId: RecognitionSettings.androidStandard}),
      );
      await retried;
      await _flushMicrotasks();
      final saving = controller.retrySave();
      storage.writes.single.succeed();
      await saving;

      // Then the same error remains until retry and the latest enhanced intent survives.
      expect(blocked.readState, SettingsReadState.failed);
      expect(blocked.readError, same(failure));
      expect(blocked.unsavedIds, {_configurationId});
      expect(readsBeforeRetry, 1);
      expect(writesBeforeRetry, 0);
      expect(controller.snapshot.readState, SettingsReadState.ready);
      expect(controller.snapshot.readError, isNull);
      expect(
        controller.snapshot.value(_configuration),
        RecognitionSettings.pixelEnhanced,
      );
      expect(
        _submitted(storage, 0).values[_configurationId],
        RecognitionSettings.pixelEnhanced,
      );
      expect(controller.snapshot.savedRevision, 2);
    });

    test('R08 immutable reset subset preserves another registered explicit preference', () async {
      // Given an extension preference and a mutable caller-selected reset list.
      final flag = SettingDefinition<bool>(
        id: 'example.capture.flag',
        groupId: 'capture',
        label: 'Capture flag',
        defaultValue: false,
        choices: [
          SettingChoice(value: false, label: 'Off', storedValue: false),
          SettingChoice(value: true, label: 'On', storedValue: true),
        ],
      );
      final registry = SettingsRegistry(
        groups: RecognitionSettings.groups,
        definitions: [...RecognitionSettings.definitions, flag],
      );
      final selected = <SettingDefinition<Object>>[_configuration];
      final storage = _ControllableStorage();
      final controller = _controller(
        storage,
        registry: registry,
        resetDefinitions: selected,
      );
      selected.clear();
      final loaded = controller.load();
      storage.reads.single.succeed(_wire({
        _configurationId: RecognitionSettings.pixelEnhanced,
        flag.id: true,
        'future.preference': 'retained',
      }));
      await loaded;

      // When resetCommon uses its constructor snapshot and the record is acknowledged.
      controller.resetCommon();
      final reset = controller.snapshot;
      await _flushMicrotasks();
      final saving = controller.retrySave();
      storage.writes.single.succeed();
      await saving;

      // Then only the declared subset resets while extension values and presence persist.
      expect(reset.value(_configuration), RecognitionSettings.androidStandard);
      expect(reset.value(flag), isTrue);
      expect(reset.hasExplicitValue(flag.id), isTrue);
      expect(reset.unsavedIds, {_configurationId});
      expect(controller.snapshot.value(flag), isTrue);
      expect(_submitted(storage, 0).values[flag.id], isTrue);
      expect(_submitted(storage, 0).values['future.preference'], 'retained');
      expect(
        _submitted(storage, 0).values[_configurationId],
        RecognitionSettings.androidStandard,
      );
      expect(controller.snapshot.savedRevision, 1);
    });

    test('R09 empty duplicated forged and unregistered reset definitions reject', () {
      // Given the registered configuration and a same-ID forged definition.
      final storage = _ControllableStorage();
      final registry = RecognitionSettings.registry();
      final forged = SettingDefinition<String>(
        id: _configurationId,
        groupId: 'capture',
        label: 'Forged configuration',
        defaultValue: RecognitionSettings.androidStandard,
        choices: _configuration.choices,
      );
      final unregistered = SettingDefinition<String>(
        id: 'example.unregistered',
        groupId: 'capture',
        label: 'Unregistered configuration',
        defaultValue: RecognitionSettings.androidStandard,
        choices: _configuration.choices,
      );

      // When invalid reset subsets are supplied before any use.
      final invalid = <List<SettingDefinition<Object>>>[
        [],
        [_configuration, _configuration],
        [forged],
        [unregistered],
      ];

      // Then each is an ArgumentError and construction never performs storage I/O.
      for (final definitions in invalid) {
        expect(
          () => SettingsLifecycleController(
            registry: registry,
            storage: storage,
            resetDefinitions: definitions,
          ),
          throwsArgumentError,
        );
      }
      expect(storage.reads, isEmpty);
      expect(storage.writes, isEmpty);
    });

    test('R10 same-value edit stays unsaved until its own ordered acknowledgement', () async {
      // Given an active write of the desired enhanced configuration.
      final storage = _ControllableStorage();
      final controller = await _ready(storage);
      controller.setValue(_configurationId, RecognitionSettings.pixelEnhanced);
      await _flushMicrotasks();
      final saving = controller.retrySave();

      // When the same value is selected again before the older write acknowledges.
      controller.setValue(_configurationId, RecognitionSettings.pixelEnhanced);
      await _flushMicrotasks();
      final writesWhileActive = storage.writes.length;
      storage.writes[0].succeed();
      await _flushMicrotasks();
      final olderAcknowledgement = controller.snapshot;
      storage.writes[1].succeed();
      await saving;

      // Then serialized writes preserve each explicit intent even with equal values.
      expect(writesWhileActive, 1);
      expect(olderAcknowledgement.revision, 2);
      expect(olderAcknowledgement.savedRevision, 1);
      expect(olderAcknowledgement.unsavedIds, {_configurationId});
      expect(controller.snapshot.lastIntent!.kind, SettingsIntentKind.edit);
      expect(controller.snapshot.savedRevision, 2);
      expect(controller.snapshot.unsavedIds, isEmpty);
      expect(storage.maxActiveWrites, 1);
      expect(storage.writes.length, 2);
    });
  });

  group('Recognition lifecycle disposal', () {
    test('R11 disposal during pending read suppresses completion and future mutations', () async {
      // Given a pending read observed by a listener.
      final storage = _ControllableStorage();
      final controller = _controller(storage);
      var notifications = 0;
      controller.addListener(() => notifications++);
      final loaded = controller.load();
      final before = controller.snapshot;
      final observed = notifications;

      // When disposal is repeated before the late stored enhanced choice arrives.
      controller.dispose();
      controller.dispose();
      storage.reads.single.succeed(
        _wire({_configurationId: RecognitionSettings.pixelEnhanced}),
      );
      await loaded;
      await _flushMicrotasks();

      // Then completion settles callers without mutation, notifications or writes.
      expect(controller.snapshot, same(before));
      expect(notifications, observed);
      expect(storage.writes, isEmpty);
      expect(
        () => controller.setValue(
          _configurationId,
          RecognitionSettings.pixelEnhanced,
        ),
        throwsStateError,
      );
      expect(controller.resetCommon, throwsStateError);
      expect(controller.load, throwsStateError);
      expect(controller.retryLoad, throwsStateError);
      expect(controller.retrySave, throwsStateError);
      expect(() => controller.addListener(() {}), throwsStateError);
    });

    test('R12 disposal during pending write retains last snapshot and settles pump', () async {
      // Given an enhanced write awaiting durable acknowledgement and observed state.
      final storage = _ControllableStorage();
      final controller = await _ready(storage);
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.setValue(_configurationId, RecognitionSettings.pixelEnhanced);
      await _flushMicrotasks();
      final saving = controller.retrySave();
      final before = controller.snapshot;
      final observed = notifications;
      var settled = false;
      unawaited(
        saving.then((_) {
          settled = true;
        }),
      );

      // When disposal precedes acknowledgement of the already active adapter operation.
      controller.dispose();
      controller.dispose();
      await _flushMicrotasks();
      final settledBeforeAcknowledgement = settled;
      storage.writes.single.succeed();
      await saving;
      await _flushMicrotasks();

      // Then adapter durability may finish but disposed controller state never advances.
      expect(settledBeforeAcknowledgement, isFalse);
      expect(settled, isTrue);
      expect(controller.snapshot, same(before));
      expect(controller.snapshot.unsavedIds, {_configurationId});
      expect(controller.snapshot.savedRevision, 0);
      expect(notifications, observed);
      expect(storage.writes.length, 1);
      expect(
        SettingsRecord.decode(storage.durableRecord!).values[_configurationId],
        RecognitionSettings.pixelEnhanced,
      );
      expect(
        () => controller.setValue(
          _configurationId,
          RecognitionSettings.androidStandard,
        ),
        throwsStateError,
      );
    });
  });
}

/// Test-only whole-record adapter with explicitly completed indexed requests.
class _ControllableStorage implements SettingsStorage {
  _ControllableStorage({String? durableRecord}) : this._(durableRecord);

  _ControllableStorage._(this._durableRecord);

  String? _durableRecord;
  final _reads = <_PendingRead>[];
  final _writes = <_PendingWrite>[];

  /// Last acknowledged image, including null for absent storage.
  String? get durableRecord => _durableRecord;

  /// Immutable request inventories; each request rejects double completion.
  List<_PendingRead> get reads => List.unmodifiable(_reads);
  List<_PendingWrite> get writes => List.unmodifiable(_writes);

  int readCount = 0;
  int writeCount = 0;
  int activeReads = 0;
  int activeWrites = 0;
  int maxActiveReads = 0;
  int maxActiveWrites = 0;

  /// Optional one-shot synchronous adapter failures.
  Object? nextReadError;
  Object? nextWriteError;

  @override
  Future<String?> read() {
    readCount++;
    final error = nextReadError;
    nextReadError = null;
    if (error != null) throw error;
    activeReads++;
    if (activeReads > maxActiveReads) maxActiveReads = activeReads;
    final request = _PendingRead._(() => activeReads--);
    _reads.add(request);
    return request._completer.future;
  }

  @override
  Future<void> write(String record) {
    writeCount++;
    final error = nextWriteError;
    nextWriteError = null;
    if (error != null) throw error;
    activeWrites++;
    if (activeWrites > maxActiveWrites) maxActiveWrites = activeWrites;
    final request = _PendingWrite._(record, (success) {
      activeWrites--;
      if (success) _durableRecord = record;
    });
    _writes.add(request);
    return request._completer.future;
  }

  /// Completes a normal restart read with the last durable image.
  void readDurable(int index) => _reads[index].succeed(_durableRecord);
}

/// One delayed read, able to return an explicitly chosen stale image.
class _PendingRead {
  _PendingRead._(this._finish);

  final void Function() _finish;
  final _completer = Completer<String?>();

  bool get isCompleted => _completer.isCompleted;

  void succeed(String? record) {
    _requirePending();
    _finish();
    _completer.complete(record);
  }

  void fail(Object error) {
    _requirePending();
    _finish();
    _completer.completeError(error);
  }

  void _requirePending() {
    if (isCompleted) throw StateError('Read already completed');
  }
}

/// Immutable submitted record and its explicit durable acknowledgement.
class _PendingWrite {
  _PendingWrite._(this.record, this._finish);

  final String record;
  final void Function(bool success) _finish;
  final _completer = Completer<void>();

  bool get isCompleted => _completer.isCompleted;

  void succeed() {
    _requirePending();
    _finish(true);
    _completer.complete();
  }

  void fail(Object error) {
    _requirePending();
    _finish(false);
    _completer.completeError(error);
  }

  void _requirePending() {
    if (isCompleted) throw StateError('Write already completed');
  }
}
