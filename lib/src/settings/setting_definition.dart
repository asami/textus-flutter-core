/// A named, ordered group of platform-neutral settings.
class SettingGroup {
  SettingGroup({required this.id, required this.label}) {
    _requireText(id, 'id');
    _requireText(label, 'label');
  }

  /// Stable group identity, independent of its presentation.
  final String id;

  /// User-facing group title.
  final String label;
}

/// One finite typed choice and its non-null JSON scalar representation.
class SettingChoice<T extends Object> {
  SettingChoice({
    required this.value,
    required this.label,
    required this.storedValue,
  }) {
    _requireText(label, 'label');
    if (storedValue is! String &&
        storedValue is! bool &&
        storedValue is! int &&
        !(storedValue is double && (storedValue as double).isFinite)) {
      throw ArgumentError.value(
        storedValue,
        'storedValue',
        'JSON scalar required',
      );
    }
  }

  /// Value consumed by application logic.
  final T value;

  /// User-facing choice title, independent of its wire identity.
  final String label;

  /// Stable String, bool, int or finite double stored in the record.
  final Object storedValue;
}

/// Availability of a setting in the supplied environment.
enum SettingAvailability { available, disabled, hidden }

/// Policy applied when a required capability is unsupported.
enum SettingAvailabilityPolicy {
  always,
  disableWhenUnsupported,
  hideWhenUnsupported,
}

/// Ephemeral supported capabilities; never persisted as preferences.
class SettingsCapabilities {
  SettingsCapabilities({Set<String> supported = const {}})
    : supported = Set.unmodifiable(supported) {
    for (final id in this.supported) {
      _requireText(id, 'supported');
    }
  }

  /// Immutable capability identifiers supplied by application composition.
  final Set<String> supported;

  /// Whether the environment supports this capability.
  bool supports(String id) => supported.contains(id);
}

/// Immutable finite-choice schema, without Widgets or storage dependencies.
class SettingDefinition<T extends Object> {
  SettingDefinition({
    required this.id,
    required this.groupId,
    required this.label,
    required this.defaultValue,
    required List<SettingChoice<T>> choices,
    this.requiredCapability,
    this.availabilityPolicy = SettingAvailabilityPolicy.always,
  }) : choices = List.unmodifiable(choices) {
    _requireText(id, 'id');
    _requireText(groupId, 'groupId');
    _requireText(label, 'label');
    if (requiredCapability != null) {
      _requireText(requiredCapability!, 'requiredCapability');
    }
    if (this.choices.isEmpty) {
      throw ArgumentError.value(
        choices,
        'choices',
        'At least one choice required',
      );
    }
    final values = <T>{};
    final wireValues = <Object>{};
    for (final choice in this.choices) {
      if (!values.add(choice.value) || !wireValues.add(choice.storedValue)) {
        throw ArgumentError.value(choices, 'choices', 'Choices must be unique');
      }
    }
    validate(defaultValue);
  }

  /// Stable setting identity used in records and edit intents.
  final String id;

  /// Identity of the containing registered group.
  final String groupId;

  /// User-facing title.
  final String label;

  /// Effective value inherited when no valid stored value is present.
  final T defaultValue;

  /// Immutable ordered choice catalog.
  final List<SettingChoice<T>> choices;

  /// Optional environment capability, independent of stored values.
  final String? requiredCapability;

  /// How unsupported capability is presented.
  final SettingAvailabilityPolicy availabilityPolicy;

  /// Checks both the Dart type and membership; rejects invalid edit input.
  T validate(Object value) {
    if (value is T) {
      for (final choice in choices) {
        if (choice.value == value) return choice.value;
      }
    }
    throw ArgumentError.value(value, 'value', 'Invalid choice for $id');
  }

  /// Encodes a valid typed choice, throwing for invalid edit input.
  Object encode(Object value) {
    final validated = validate(value);
    return choices
        .firstWhere((choice) => choice.value == validated)
        .storedValue;
  }

  /// Decodes a declared choice; missing/invalid wire values inherit the default.
  /// Numeric equality allows JSON 1 to match a stored multiplier of 1.0.
  T decode(Object? storedValue) {
    for (final choice in choices) {
      if (choice.storedValue == storedValue) return choice.value;
    }
    return defaultValue;
  }

  /// Computes availability without editing or erasing a preference.
  SettingAvailability availability(SettingsCapabilities capabilities) {
    if (availabilityPolicy == SettingAvailabilityPolicy.always ||
        requiredCapability == null ||
        capabilities.supports(requiredCapability!)) {
      return SettingAvailability.available;
    }
    return switch (availabilityPolicy) {
      SettingAvailabilityPolicy.always => SettingAvailability.available,
      SettingAvailabilityPolicy.disableWhenUnsupported =>
        SettingAvailability.disabled,
      SettingAvailabilityPolicy.hideWhenUnsupported =>
        SettingAvailability.hidden,
    };
  }
}

void _requireText(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'Nonempty text required');
  }
}
