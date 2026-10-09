import 'dart:async';

import 'package:flutter/foundation.dart';

import 'setting_definition.dart';
import 'settings_record.dart';
import 'settings_registry.dart';
import 'settings_service.dart';
import 'settings_snapshot.dart';
import 'settings_storage.dart';

/// Settings authority with an explicit read barrier and serialized durable saves.
///
/// Construction does not load. Storage is injected and remains caller-owned.
class SettingsLifecycleController extends ChangeNotifier implements SettingsService {
  /// Uses exactly the supplied registered definitions as common reset defaults.
  /// Construction validates and snapshots the nonempty reset list without I/O.
  SettingsLifecycleController({
    required SettingsRegistry registry,
    required SettingsStorage storage,
    required List<SettingDefinition<Object>> resetDefinitions,
  }) : this._(registry, storage, List.unmodifiable(resetDefinitions));

  SettingsLifecycleController._(
    this.registry,
    this._storage,
    this._resetDefinitions,
  ) {
    if (_resetDefinitions.isEmpty) {
      throw ArgumentError.value(
        _resetDefinitions,
        'resetDefinitions',
        'At least one reset definition required',
      );
    }
    final ids = <String>{};
    for (final definition in _resetDefinitions) {
      if (!ids.add(definition.id)) {
        throw ArgumentError.value(
          definition.id,
          'resetDefinitions',
          'Duplicate reset definition ID',
        );
      }
      registry.requireRegistered(definition);
    }
    _snapshot = SettingsSnapshot(registry: registry);
    _values.addAll(_snapshot.values);
  }

  final List<SettingDefinition<Object>> _resetDefinitions;

  /// Immutable schema authority, readable even after disposal.
  @override
  final SettingsRegistry registry;
  final SettingsStorage _storage;
  late SettingsSnapshot _snapshot;
  final _values = <String, Object>{};
  final _explicitIds = <String>{};
  final _unsavedIds = <String>{};
  final _intentRevisions = <String, int>{};
  final _listeners = <VoidCallback>[];
  int _revision = 0;
  int _savedRevision = 0;
  int? _pendingResetRevision;
  SettingsIntent? _lastIntent;
  SettingsReadState _readState = SettingsReadState.notLoaded;
  SettingsSaveState _saveState = SettingsSaveState.idle;
  Object? _readError;
  Object? _saveError;
  SettingsRecord? _baseline;
  _SettingsRead? _read;
  _SettingsRead? _unsupportedRead;
  _SettingsPump? _pump;
  bool _recoveryAuthorized = false;
  bool _saveFailed = false;
  bool _writeActive = false;
  bool _disposed = false;
  bool _superDisposed = false;
  int _dispatchDepth = 0;

  /// Latest immutable state; a disposed controller retains its last snapshot.
  @override
  SettingsSnapshot get snapshot => _snapshot;

  /// Starts the initial read once; overlapping callers share its Future.
  /// Completion publishes restoration and schedules eligible saves, not durability.
  @override
  Future<void> load() {
    _requireActive();
    if (_read != null) return _read!.completer.future;
    if (_readState != SettingsReadState.notLoaded) return Future.value();
    return _startRead();
  }

  /// Explicitly retries failed/unsupported reads while the write barrier is closed.
  @override
  Future<void> retryLoad() {
    _requireActive();
    if (_read != null) return _read!.completer.future;
    if (_recoveryAuthorized ||
        (_readState != SettingsReadState.notLoaded &&
            _readState != SettingsReadState.failed &&
            _readState != SettingsReadState.unsupported)) {
      return Future.value();
    }
    return _startRead();
  }

  Future<void> _startRead() {
    final read = _SettingsRead(_intentRevisions, _unsavedIds);
    _read = read;
    _readState = SettingsReadState.loading;
    _readError = null;
    _unsupportedRead = null;
    _publish();
    if (_disposed) {
      read.completer.complete();
    } else {
      unawaited(_runRead(read));
    }
    return read.completer.future;
  }

  Future<void> _runRead(_SettingsRead read) async {
    try {
      final source = await _storage.read();
      if (_disposed) return;
      final record = source == null
          ? SettingsRecord.empty()
          : SettingsRecord.decode(source);
      _baseline = record;
      _read = null;
      if (record.isSupported) {
        _readState = SettingsReadState.ready;
        _readError = null;
        _restore(record, read);
      } else {
        _readState = SettingsReadState.unsupported;
        _readError = StateError(
          'Unsupported settings version ${record.version}',
        );
        _unsupportedRead = read;
        _recoveryAuthorized = _pendingResetRevision != null;
        if (_recoveryAuthorized) _restore(record, read, extensionsOnly: true);
      }
      _ensurePump();
      _publish();
    } catch (error) {
      if (_disposed) return;
      _read = null;
      _readState = SettingsReadState.failed;
      _readError = error;
      _recoveryAuthorized = false;
      _publish();
    } finally {
      read.completer.complete();
    }
  }

  void _restore(
    SettingsRecord record,
    _SettingsRead read, {
    bool extensionsOnly = false,
  }) {
    for (final definition in registry.definitions) {
      final id = definition.id;
      if ((extensionsOnly && _resetDefinitions.contains(definition)) ||
          read.unsavedIds.contains(id) ||
          (_intentRevisions[id] ?? 0) != (read.intentRevisions[id] ?? 0)) {
        continue;
      }
      final raw = record.values[id];
      final valid =
          record.values.containsKey(id) &&
          definition.choices.any((choice) => choice.storedValue == raw);
      _values[id] = valid ? definition.decode(raw) : definition.defaultValue;
      if (valid) {
        _explicitIds.add(id);
      } else {
        _explicitIds.remove(id);
      }
    }
  }

  /// Applies and publishes each valid edit, including explicit same-value intent.
  @override
  void setValue(String id, Object value) {
    _requireActive();
    final validated = registry.definition(id).validate(value);
    _revision++;
    _values[id] = validated;
    _explicitIds.add(id);
    _unsavedIds.add(id);
    _intentRevisions[id] = _revision;
    _lastIntent = SettingsIntent(
      revision: _revision,
      kind: SettingsIntentKind.edit,
      settingId: id,
    );
    _ensurePump();
    _publish();
  }

  /// Resets exactly the caller-supplied common defaults and authorizes version reset.
  /// Unread, malformed and failed reads still require [retryLoad].
  @override
  void resetCommon() {
    _requireActive();
    _revision++;
    _pendingResetRevision = _revision;
    for (final definition in _resetDefinitions) {
      final id = definition.id;
      _values[id] = definition.defaultValue;
      _explicitIds.add(id);
      _unsavedIds.add(id);
      _intentRevisions[id] = _revision;
    }
    _lastIntent = SettingsIntent(
      revision: _revision,
      kind: SettingsIntentKind.resetCommon,
      settingId: null,
    );
    if (_readState == SettingsReadState.unsupported) {
      _recoveryAuthorized = true;
      _restore(_baseline!, _unsupportedRead!, extensionsOnly: true);
    }
    _ensurePump();
    _publish();
  }

  bool get _canWrite =>
      _baseline != null &&
      (_readState == SettingsReadState.ready ||
          (_readState == SettingsReadState.unsupported && _recoveryAuthorized));

  void _ensurePump() {
    if (_disposed || !_canWrite || _unsavedIds.isEmpty || _saveFailed) return;
    _saveState = SettingsSaveState.saving;
    if (_pump != null) return;
    final pump = _SettingsPump();
    _pump = pump;
    scheduleMicrotask(() => unawaited(_runPump(pump)));
  }

  /// Clears a save failure only explicitly and awaits the serialized pump's drain.
  /// A normal completion may still expose failure; inspect [snapshot] for durability.
  @override
  Future<void> retrySave() {
    _requireActive();
    if (_pump != null) return _pump!.completer.future;
    if (!_canWrite || _unsavedIds.isEmpty) return Future.value();
    _saveFailed = false;
    _saveError = null;
    _ensurePump();
    final future = _pump!.completer.future;
    _publish();
    return future;
  }

  Future<void> _runPump(_SettingsPump pump) async {
    if (_disposed) {
      if (!pump.completer.isCompleted) pump.completer.complete();
      return;
    }
    while (!_disposed && _canWrite && _unsavedIds.isNotEmpty && !_saveFailed) {
      final ids = Set<String>.of(_unsavedIds);
      final revisions = {for (final id in ids) id: _intentRevisions[id]!};
      final revision = _revision;
      final resetRevision = _pendingResetRevision;
      final recovering = !_baseline!.isSupported && _recoveryAuthorized;
      _writeActive = true;
      try {
        final record = _baseline!.withUpdates({
          for (final id in ids)
            id: registry.definition(id).encode(_values[id]!),
        }, resetVersion: recovering);
        await _storage.write(record.encode());
        if (_disposed) break;
        _writeActive = false;
        _baseline = record;
        _savedRevision = revision;
        for (final id in ids) {
          if (_intentRevisions[id] == revisions[id]) _unsavedIds.remove(id);
        }
        if (_pendingResetRevision == resetRevision) {
          _pendingResetRevision = null;
        }
        if (recovering) {
          _readState = SettingsReadState.ready;
          _readError = null;
          _recoveryAuthorized = false;
          _unsupportedRead = null;
        }
        _saveState = _unsavedIds.isEmpty
            ? SettingsSaveState.idle
            : SettingsSaveState.saving;
        _saveError = null;
        _publish();
      } catch (error) {
        if (_disposed) break;
        _writeActive = false;
        _saveFailed = true;
        _saveState = SettingsSaveState.failed;
        _saveError = error;
        _pump = null;
        _publish();
        break;
      }
    }
    if (!_disposed && identical(_pump, pump)) _pump = null;
    if (!pump.completer.isCompleted) pump.completer.complete();
  }

  void _publish() {
    if (_disposed) return;
    _snapshot = SettingsSnapshot(
      registry: registry,
      values: _values,
      explicitValueIds: _explicitIds,
      unsavedIds: _unsavedIds,
      revision: _revision,
      savedRevision: _savedRevision,
      readState: _readState,
      saveState: _saveState,
      readError: _readError,
      saveError: _saveError,
      lastIntent: _lastIntent,
    );
    notifyListeners();
  }

  void _requireActive() {
    if (_disposed) throw StateError('SettingsLifecycleController is disposed');
  }

  /// Attaches an observer while the controller owns an active lifecycle.
  @override
  void addListener(VoidCallback listener) {
    _requireActive();
    _listeners.add(listener);
    super.addListener(listener);
  }

  /// Harmless after disposal, allowing borrowed views to finish detaching.
  @override
  void removeListener(VoidCallback listener) {
    if (_superDisposed) return;
    _listeners.remove(listener);
    super.removeListener(listener);
  }

  /// Dispatches consistently established state and defers physical disposal.
  @override
  void notifyListeners() {
    if (_disposed) return;
    _dispatchDepth++;
    try {
      super.notifyListeners();
    } finally {
      _dispatchDepth--;
      if (_disposed && _dispatchDepth == 0) _disposeNotifier();
    }
  }

  /// Immediately ends ownership; an already active adapter operation may finish.
  /// Its completion settles callers without mutating or notifying this controller.
  /// _disposeNotifier invokes super.dispose exactly once, deferred until
  /// notification dispatch unwinds when disposal occurs during dispatch.
  @override
  // ignore: must_call_super
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final listener in _listeners) {
      super.removeListener(listener);
    }
    _listeners.clear();
    final pump = _pump;
    if (!_writeActive && pump != null && !pump.completer.isCompleted) {
      pump.completer.complete();
    }
    if (_dispatchDepth == 0) _disposeNotifier();
  }

  void _disposeNotifier() {
    if (_superDisposed) return;
    _superDisposed = true;
    super.dispose();
  }
}

class _SettingsRead {
  _SettingsRead(Map<String, int> revisions, Set<String> unsaved)
    : intentRevisions = Map.unmodifiable(revisions),
      unsavedIds = Set.unmodifiable(unsaved);

  final Map<String, int> intentRevisions;
  final Set<String> unsavedIds;
  final completer = Completer<void>();
}

class _SettingsPump {
  final completer = Completer<void>();
}
