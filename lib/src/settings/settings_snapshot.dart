import 'setting_definition.dart';
import 'settings_registry.dart';

/// Observable restoration status, including a protected unsupported envelope.
enum SettingsReadState { notLoaded, loading, ready, failed, unsupported }

/// Observable persistence status; failed writes remain unsaved.
enum SettingsSaveState { idle, saving, failed }

/// User intent kinds observed separately from loads and environment changes.
enum SettingsIntentKind { edit, resetCommon }

/// Immutable user-intent sequence entry, not a durability acknowledgement.
class SettingsIntent {
  SettingsIntent({
    required this.revision,
    required this.kind,
    required this.settingId,
  }) {
    if (revision <= 0 ||
        (kind == SettingsIntentKind.edit &&
            (settingId == null || settingId!.trim().isEmpty)) ||
        (kind == SettingsIntentKind.resetCommon && settingId != null)) {
      throw ArgumentError('Invalid settings intent');
    }
  }

  /// Positive user-intent sequence, including same-value edits and every reset.
  final int revision;

  /// Whether this intent edits a setting or resets caller-supplied common defaults.
  final SettingsIntentKind kind;

  /// Registered identity for edits; null for caller-supplied common reset.
  final String? settingId;
}

/// Immutable complete effective values and independent restoration/save status.
class SettingsSnapshot {
  SettingsSnapshot({
    required this.registry,
    Map<String, Object> values = const {},
    Set<String> explicitValueIds = const {},
    Set<String> unsavedIds = const {},
    this.revision = 0,
    this.savedRevision = 0,
    this.readState = SettingsReadState.notLoaded,
    this.saveState = SettingsSaveState.idle,
    this.readError,
    this.saveError,
    this.lastIntent,
  }) : values = _effectiveValues(registry, values),
       explicitValueIds = Set.unmodifiable(explicitValueIds),
       unsavedIds = Set.unmodifiable(unsavedIds) {
    if (revision < 0 || savedRevision < 0 || savedRevision > revision) {
      throw ArgumentError('Invalid settings revisions');
    }
    for (final id in {...this.explicitValueIds, ...this.unsavedIds}) {
      registry.definition(id);
    }
    final intent = lastIntent;
    if (intent != null) {
      if (intent.revision > revision) {
        throw ArgumentError('Intent is newer than snapshot');
      }
      if (intent.kind == SettingsIntentKind.edit) {
        registry.definition(intent.settingId!);
      }
    }
  }

  /// The schema authority for every effective value.
  final SettingsRegistry registry;

  /// Immutable complete effective values, including inherited defaults.
  final Map<String, Object> values;

  /// Valid restored/current explicit values, including explicit defaults.
  /// Presence denotes semantic intent, not acknowledged persistence.
  final Set<String> explicitValueIds;

  /// Identities awaiting acknowledged persistence.
  final Set<String> unsavedIds;

  /// Latest user-intent revision; load/capability events do not increment it.
  final int revision;

  /// Latest acknowledged revision, never newer than [revision].
  final int savedRevision;

  /// Current restoration status.
  final SettingsReadState readState;

  /// Current persistence status.
  final SettingsSaveState saveState;

  /// Nonfatal restoration error, supplied by the service.
  final Object? readError;

  /// Persistence error; it never implies that a value is durable.
  final Object? saveError;

  /// Latest explicit edit/reset intent, independent of notification count.
  final SettingsIntent? lastIntent;

  /// Reads using the registered typed definition, rejecting forged definitions.
  T value<T extends Object>(SettingDefinition<T> definition) {
    registry.requireRegistered(definition);
    return definition.validate(values[definition.id]!);
  }

  /// Distinguishes explicit automatic/default intent from absent inherited values.
  bool hasExplicitValue(String id) {
    registry.definition(id);
    return explicitValueIds.contains(id);
  }

  /// Whether any effective value is awaiting storage acknowledgement.
  bool get hasUnsavedChanges => unsavedIds.isNotEmpty;
}

Map<String, Object> _effectiveValues(
  SettingsRegistry registry,
  Map<String, Object> values,
) {
  final effective = <String, Object>{
    for (final definition in registry.definitions)
      definition.id: definition.defaultValue,
  };
  for (final entry in values.entries) {
    effective[entry.key] = registry.definition(entry.key).validate(entry.value);
  }
  return Map.unmodifiable(effective);
}
