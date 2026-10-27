import 'setting_definition.dart';
import 'settings_registry.dart';

/// Desired recognition configuration, independent of current provider capability.
/// An unavailable enhanced provider must preserve the user's saved preference.
abstract final class RecognitionSettings {
  /// Stable preference for common camera acquisition and standard recognition.
  static const androidStandard = 'androidStandard';

  /// Stable preference for standard recognition plus enhanced interpretation.
  static const pixelEnhanced = 'pixelEnhanced';

  /// Finite desired configuration; availability never implies model readiness.
  static final configuration = SettingDefinition<String>(
    id: 'textus.capture.recognitionConfiguration',
    groupId: 'capture',
    label: 'Recognition configuration',
    defaultValue: androidStandard,
    choices: [
      SettingChoice(
        value: androidStandard,
        label: 'Standard Android',
        storedValue: androidStandard,
      ),
      SettingChoice(
        value: pixelEnhanced,
        label: 'Pixel enhanced',
        storedValue: pixelEnhanced,
      ),
    ],
  );

  /// Immutable capture group for standalone or extension composition.
  static final List<SettingGroup> groups = List.unmodifiable([
    SettingGroup(id: 'capture', label: 'Capture'),
  ]);

  /// Immutable preference catalog containing exactly the desired configuration.
  static final List<SettingDefinition<Object>> definitions = List.unmodifiable([
    configuration,
  ]);

  /// Creates a standalone registry containing the capture preference.
  static SettingsRegistry registry() =>
      SettingsRegistry(groups: groups, definitions: definitions);
}
