import 'setting_definition.dart';

/// Ordered immutable schema authority for common and application settings.
class SettingsRegistry {
  SettingsRegistry({
    required List<SettingGroup> groups,
    required List<SettingDefinition<Object>> definitions,
  }) : groups = List.unmodifiable(groups),
       definitions = List.unmodifiable(definitions) {
    final groupIds = <String>{};
    for (final group in this.groups) {
      if (!groupIds.add(group.id)) {
        throw ArgumentError.value(group.id, 'groups', 'Duplicate group ID');
      }
    }
    final byId = <String, SettingDefinition<Object>>{};
    for (final definition in this.definitions) {
      if (!groupIds.contains(definition.groupId)) {
        throw ArgumentError.value(
          definition.groupId,
          'groupId',
          'Unknown group',
        );
      }
      if (byId.containsKey(definition.id)) {
        throw ArgumentError.value(definition.id, 'definitions', 'Duplicate ID');
      }
      byId[definition.id] = definition;
    }
    _byId = Map.unmodifiable(byId);
  }

  /// Immutable group order for presentation.
  final List<SettingGroup> groups;

  /// Immutable setting order, retaining each registered definition's identity.
  final List<SettingDefinition<Object>> definitions;
  late final Map<String, SettingDefinition<Object>> _byId;

  /// Resolves a stable setting ID, rejecting unknown IDs.
  SettingDefinition<Object> definition(String id) {
    final result = _byId[id];
    if (result == null) throw ArgumentError.value(id, 'id', 'Unknown setting');
    return result;
  }

  /// Verifies the actual registered typed definition, rejecting same-ID forgeries.
  SettingDefinition<T> requireRegistered<T extends Object>(
    SettingDefinition<T> selected,
  ) {
    if (!identical(definition(selected.id), selected)) {
      throw ArgumentError.value(selected, 'definition', 'Not registered');
    }
    return selected;
  }
}
