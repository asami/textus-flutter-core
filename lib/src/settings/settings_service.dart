import 'package:flutter/foundation.dart';

import 'settings_registry.dart';
import 'settings_snapshot.dart';

/// Observable Core settings authority with caller-selected reset defaults.
///
/// Owns validation, state transitions, intent revisions and serialized writes.
/// Public state is immutable. Calls after disposal throw StateError; disposal is
/// idempotent. Async continuations must not notify or mutate after disposal.
abstract interface class SettingsService implements Listenable {
  /// Stable schema shared by snapshots and consumers.
  SettingsRegistry get registry;

  /// Current complete effective values and read/save/intent state.
  SettingsSnapshot get snapshot;

  /// Explicitly begins restoration; construction does not implicitly load.
  /// Late restoration must preserve newer edits and reset intent.
  Future<void> load();

  /// Explicitly retries a failed read without overwriting newer user intent.
  Future<void> retryLoad();

  /// Retries persistence of the latest unsaved values.
  Future<void> retrySave();

  /// Applies a valid choice immediately and emits an intent even if unchanged.
  /// Invalid IDs/types/choices throw ArgumentError before state changes.
  void setValue(String id, Object value);

  /// Emits reset intent for caller-supplied common defaults, preserving other data.
  void resetCommon();

  /// Ends ownership and suppresses all later async notifications; idempotent.
  void dispose();
}
