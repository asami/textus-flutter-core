import '../settings/recognition_settings.dart';

enum RecognitionCapability { ocr, barcodes, imageInterpretation, candidateOrganization }
enum RecognitionProviderState { available, unavailable, downloadable, preparing }

/// Immutable public capabilities declared by one registered provider.
final class RecognitionProviderDescriptor {
  RecognitionProviderDescriptor({
    required String id, required String label,
    required Iterable<RecognitionCapability> capabilities,
  }) : id = _token(id), label = _nonblank(label),
       capabilities = Set.unmodifiable(capabilities) {
    if (this.capabilities.isEmpty) throw ArgumentError('Capabilities are empty');
  }
  final String id;
  final String label;
  final Set<RecognitionCapability> capabilities;
}

/// Historical readiness and model snapshot, never a perpetual readiness claim.
final class RecognitionProviderAvailability {
  RecognitionProviderAvailability({
    required String providerId, required this.state,
    Iterable<RecognitionCapability> capabilities = const [],
    String? reason, String? modelName,
  }) : providerId = _token(providerId),
       capabilities = Set.unmodifiable(capabilities),
       reason = reason == null ? null : _nonblank(reason),
       modelName = modelName == null ? null : _nonblank(modelName) {
    if (state == RecognitionProviderState.unavailable && reason == null) {
      throw ArgumentError('An unavailable provider requires a reason');
    }
  }
  final String providerId;
  final RecognitionProviderState state;
  final Set<RecognitionCapability> capabilities;
  final String? reason;
  final String? modelName;
}

/// One ordered provider stage and the capabilities required for that stage.
final class RecognitionProviderRequirement {
  RecognitionProviderRequirement({
    required String providerId,
    required Iterable<RecognitionCapability> capabilities,
  }) : providerId = _token(providerId),
       capabilities = Set.unmodifiable(capabilities) {
    if (this.capabilities.isEmpty) throw ArgumentError('Requirements are empty');
  }
  final String providerId;
  final Set<RecognitionCapability> capabilities;
}

/// Desired ordered route; the service validates fallback catalog relationships.
final class RecognitionConfiguration {
  RecognitionConfiguration({
    required String id, required String label,
    required Iterable<RecognitionProviderRequirement> providers,
    String? fallbackConfigurationId,
  }) : id = _token(id), label = _nonblank(label),
       providers = List.unmodifiable(providers),
       fallbackConfigurationId = fallbackConfigurationId == null
           ? null : _token(fallbackConfigurationId) {
    if (this.providers.isEmpty ||
        this.providers.map((item) => item.providerId).toSet().length !=
            this.providers.length || this.fallbackConfigurationId == id) {
      throw ArgumentError('Invalid provider chain or self fallback');
    }
  }
  final String id;
  final String label;
  final List<RecognitionProviderRequirement> providers;
  final String? fallbackConfigurationId;
}

/// Presets selected through actual providers rather than device-brand checks.
abstract final class RecognitionConfigurations {
  static const standardProviderId = 'mlkitStandard';
  static const enhancedProviderId = 'geminiNano';
  static final androidStandard = RecognitionConfiguration(
    id: RecognitionSettings.androidStandard, label: 'Standard Android',
    providers: [RecognitionProviderRequirement(
      providerId: standardProviderId,
      capabilities: {RecognitionCapability.ocr, RecognitionCapability.barcodes},
    )],
  );
  static final pixelEnhanced = RecognitionConfiguration(
    id: RecognitionSettings.pixelEnhanced, label: 'Pixel enhanced',
    providers: [
      ...androidStandard.providers,
      RecognitionProviderRequirement(
        providerId: enhancedProviderId,
        capabilities: {
          RecognitionCapability.imageInterpretation,
          RecognitionCapability.candidateOrganization,
        },
      ),
    ],
    fallbackConfigurationId: RecognitionSettings.androidStandard,
  );
  static final List<RecognitionConfiguration> all = List.unmodifiable([
    androidStandard, pixelEnhanced,
  ]);
}

String _token(String value) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(value)) {
    throw ArgumentError.value(value, 'id', 'unsafe logical token');
  }
  return value;
}
String _nonblank(String value) {
  if (value.trim().isEmpty) throw ArgumentError('Blank label or description');
  return value;
}
