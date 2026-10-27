import 'dart:math';

import 'capture_material.dart';
import 'photo_capture.dart';
import 'recognition_configuration.dart';
import 'recognition_operation_context.dart';
import 'recognition_report.dart';

/// Caller-owned provider with explicit preparation separate from inference.
abstract interface class ImageRecognitionProvider {
  RecognitionProviderDescriptor get descriptor;
  Future<RecognitionProviderAvailability> availability();
  Future<void> prepare();
  Future<ImageRecognitionResult> recognize(ImageRecognitionInput input);
}

/// Optional finite JSON describing provider configuration, not executed work.
///
/// Existing providers need not implement this interface. The service snapshots
/// and deeply freezes participating providers' metadata before any native work.
abstract interface class ImageRecognitionProviderProvenance {
  Map<String, Object?> get provenance;
}

/// Immutable registration order and descriptor snapshots, without global state.
final class RecognitionProviderRegistry {
  RecognitionProviderRegistry({required Iterable<ImageRecognitionProvider> providers})
    : providers = List.unmodifiable(providers) {
    final snapshots = <RecognitionProviderDescriptor>[];
    final byId = <String, ImageRecognitionProvider>{};
    for (final provider in this.providers) {
      final descriptor = provider.descriptor;
      if (byId.containsKey(descriptor.id)) {
        throw ArgumentError('Duplicate provider ${descriptor.id}');
      }
      byId[descriptor.id] = provider;
      snapshots.add(RecognitionProviderDescriptor(
        id: descriptor.id, label: descriptor.label,
        capabilities: descriptor.capabilities,
      ));
    }
    descriptors = List.unmodifiable(snapshots);
    _byId = Map.unmodifiable(byId);
  }
  final List<ImageRecognitionProvider> providers;
  late final List<RecognitionProviderDescriptor> descriptors;
  late final Map<String, ImageRecognitionProvider> _byId;
  ImageRecognitionProvider? find(String id) => _byId[id];
}

/// Executes frozen provider chains with one availability snapshot and shared work.
final class ImageRecognitionService {
  ImageRecognitionService({
    required this.registry,
    Iterable<RecognitionConfiguration>? configurations,
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) : configurations = List.unmodifiable(configurations ?? RecognitionConfigurations.all),
       _clock = clock ?? DateTime.now,
       _idGenerator = idGenerator ?? _secureId {
    final catalog = <String, RecognitionConfiguration>{};
    for (final configuration in this.configurations) {
      if (catalog.containsKey(configuration.id)) {
        throw ArgumentError('Duplicate configuration');
      }
      catalog[configuration.id] = configuration;
    }
    for (final desired in this.configurations) {
      final visited = <String>{desired.id};
      var current = desired;
      while (current.fallbackConfigurationId != null) {
        final fallback = catalog[current.fallbackConfigurationId];
        if (fallback == null || !visited.add(fallback.id) ||
            !_strictPrefix(fallback, current)) {
          throw ArgumentError('Fallback must be an existing identical strict prefix');
        }
        current = fallback;
      }
    }
    _catalog = Map.unmodifiable(catalog);
  }

  final RecognitionProviderRegistry registry;
  final List<RecognitionConfiguration> configurations;
  final DateTime Function() _clock;
  final String Function() _idGenerator;
  late final Map<String, RecognitionConfiguration> _catalog;
  bool _busy = false;

  Future<List<RecognitionProviderAvailability>> availability() => _operate(() {
    _snapshotProvenance(registry.descriptors.map((item) => item.id));
    return _probeAll();
  });

  Future<RecognitionProviderAvailability> prepareProvider(String providerId) => _operate(() async {
    final provider = registry.find(providerId);
    if (provider == null) {
      throw ArgumentError.value(providerId, 'providerId', 'not registered');
    }
    _snapshotProvenance([providerId]);
    final snapshot = await _probe(providerId);
    switch (snapshot.state) {
      case RecognitionProviderState.available:
      case RecognitionProviderState.preparing:
        return snapshot;
      case RecognitionProviderState.unavailable:
        throw UnsupportedError(snapshot.reason!);
      case RecognitionProviderState.downloadable:
        await provider.prepare();
        return _probe(providerId);
    }
  });

  Future<RecognitionComparison> recognize({
    required ImageRecognitionInput input,
    required Iterable<String> configurationIds,
  }) => _operate(() async {
    final selection = List<String>.of(configurationIds);
    if (selection.isEmpty || selection.toSet().length != selection.length ||
        selection.any((id) => !_catalog.containsKey(id))) {
      throw ArgumentError('Select distinct known configurations');
    }
    final extensions = <String, Object?>{..._snapshotProvenance({
      for (final id in selection)
        for (final requirement in _catalog[id]!.providers) requirement.providerId,
    }),
      if (input.operationContext != null)
        RecognitionOperationContext.extensionKey: input.operationContext!.toJson(),
    };
    final original = ImageRecognitionInput(
      material: input.material, bytes: input.bytes,
      previousResults: input.previousResults,
      operationContext: input.operationContext,
    );
    final usedIds = <String>{};
    String nextId() {
      final id = _idGenerator();
      if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(id) ||
          !usedIds.add(id)) {
        throw StateError('Invalid or colliding generated identity: $id');
      }
      return id;
    }
    final comparisonId = nextId();
    final createdAt = _clock().toUtc();
    final snapshots = {for (final item in await _probeAll()) item.providerId: item};
    final cache = <String, RecognitionProviderAttempt>{};
    final runs = <RecognitionRun>[];
    for (final selectedId in selection) {
      final desired = _catalog[selectedId]!;
      final attempts = <RecognitionProviderAttempt>[];
      var stopped = false;
      for (final requirement in desired.providers) {
        final key = '${requirement.providerId}|${attempts.map((item) => item.id).join('|')}';
        var snapshot = snapshots[requirement.providerId]!;
        final provider = registry.find(requirement.providerId);
        final declared = registry.descriptors.where((item) => item.id == requirement.providerId);
        if (snapshot.state == RecognitionProviderState.available &&
            (!snapshot.capabilities.containsAll(requirement.capabilities) ||
                declared.isEmpty ||
                !declared.single.capabilities.containsAll(requirement.capabilities))) {
          snapshot = RecognitionProviderAvailability(
            providerId: requirement.providerId, state: RecognitionProviderState.unavailable,
            capabilities: snapshot.capabilities, reason: 'missingCapabilities',
            modelName: snapshot.modelName,
          );
        }
        final executed = !stopped && snapshot.state == RecognitionProviderState.available;
        var attempt = executed ? cache[key] : null;
        if (attempt == null) {
          final inputAttempts = attempts.where((item) => item.executed).toList();
          final attemptId = nextId();
          final startedAt = _clock().toUtc();
          var elapsed = Duration.zero;
          ImageRecognitionResult result;
          if (!executed) {
            result = ImageRecognitionResult(failures: [
              if (snapshot.state != RecognitionProviderState.available)
                ImageRecognitionFailure(
                  stage: ImageRecognitionStage.availability,
                  code: 'providerUnavailable',
                  message: snapshot.reason ?? snapshot.state.name,
                ),
              if (stopped) ImageRecognitionFailure(
                stage: ImageRecognitionStage.provider, code: 'dependencyUnavailable',
                message: 'An earlier provider in the requested chain was unavailable',
              ),
            ]);
          } else {
            final stopwatch = Stopwatch()..start();
            try {
              result = await provider!.recognize(ImageRecognitionInput(
                material: original.material, bytes: original.bytes,
                previousResults: inputAttempts.map((item) => item.result),
                operationContext: original.operationContext,
              ));
              if (!result.hasSuccessfulOutput && result.failures.isEmpty) {
                result = ImageRecognitionResult(failures: [ImageRecognitionFailure(
                  stage: ImageRecognitionStage.provider, code: 'emptyResult',
                  message: 'Provider returned no completed stage or failure',
                )]);
              }
            } catch (error) {
              result = ImageRecognitionResult(failures: [ImageRecognitionFailure(
                stage: ImageRecognitionStage.provider, code: 'recognitionFailed',
                message: _description(error),
              )]);
            } finally {
              stopwatch.stop();
              elapsed = stopwatch.elapsed;
            }
          }
          attempt = RecognitionProviderAttempt(
            id: attemptId, providerId: requirement.providerId,
            materialId: original.material.id, availability: snapshot,
            startedAt: startedAt, elapsed: elapsed, executed: executed, result: result,
            inputAttemptIds: inputAttempts.map((item) => item.id),
          );
          if (attempt.executed) {
            cache[key] = attempt;
          }
        }
        attempts.add(attempt);
        if (!attempt.executed) {
          stopped = true;
        }
      }
      RecognitionConfiguration? actual;
      if (attempts.every((item) => item.executed) &&
          (desired.fallbackConfigurationId == null || attempts.last.result.hasSuccessfulOutput)) {
        actual = desired;
      } else {
        var fallbackId = desired.fallbackConfigurationId;
        while (fallbackId != null) {
          final fallback = _catalog[fallbackId]!;
          if (attempts.take(fallback.providers.length).every((item) => item.executed)) {
            actual = fallback;
            break;
          }
          fallbackId = fallback.fallbackConfigurationId;
        }
      }
      String? fallbackReason;
      if (actual != null && actual.id != desired.id) {
        fallbackReason = attempts.skip(actual.providers.length).map((item) {
          final reasons = item.result.failures.map((failure) => '${failure.code}: ${failure.message}');
          return '${item.providerId}: ${reasons.isEmpty ? (item.availability.reason ?? 'noSuccessfulOutput') : reasons.join('; ')}';
        }).join('; ');
      }
      runs.add(RecognitionRun(
        desiredConfigurationId: desired.id, actualConfigurationId: actual?.id,
        actualProviderIds: actual?.providers.map((item) => item.providerId) ?? const [],
        fallbackReason: fallbackReason, attempts: attempts,
      ));
    }
    return RecognitionComparison(
      id: comparisonId, material: original.material, createdAt: createdAt, runs: runs,
      extensions: extensions,
    );
  });

  Map<String, Object?> _snapshotProvenance(Iterable<String> ids) {
    final metadata = <String, Object?>{};
    for (final id in ids.toSet()) {
      final provider = registry.find(id);
      if (provider is ImageRecognitionProviderProvenance) {
        metadata[id] = (provider as ImageRecognitionProviderProvenance).provenance;
      }
    }
    return CaptureMaterialReference(
      id: 'provider-provenance', mediaType: 'application/json', byteLength: 1,
      capturedAt: DateTime.utc(1970),
      extensions: metadata.isEmpty ? const {} : {'providerProvenance': metadata},
    ).extensions;
  }

  Future<T> _operate<T>(Future<T> Function() operation) async {
    if (_busy) {
      throw StateError('A recognition operation is already active');
    }
    _busy = true;
    try {
      return await operation();
    } finally {
      _busy = false;
    }
  }

  Future<List<RecognitionProviderAvailability>> _probeAll() async {
    final ids = <String>{
      for (final configuration in configurations)
        for (final requirement in configuration.providers) requirement.providerId,
      for (final descriptor in registry.descriptors) descriptor.id,
    };
    final snapshots = <RecognitionProviderAvailability>[];
    for (final id in ids) { snapshots.add(await _probe(id)); }
    return List.unmodifiable(snapshots);
  }

  Future<RecognitionProviderAvailability> _probe(String id) async {
    final provider = registry.find(id);
    if (provider == null) {
      return RecognitionProviderAvailability(
        providerId: id, state: RecognitionProviderState.unavailable, reason: 'providerNotRegistered',
      );
    }
    try {
      final frozen = registry.descriptors.firstWhere((item) => item.id == id);
      final current = provider.descriptor;
      if (!_sameDescriptor(frozen, current)) {
        throw StateError('Registered descriptor changed for $id');
      }
      final snapshot = await provider.availability();
      if (!_sameDescriptor(frozen, provider.descriptor) || snapshot.providerId != id ||
          !frozen.capabilities.containsAll(snapshot.capabilities)) {
        throw StateError('Conflicting availability identity or capabilities for $id');
      }
      return snapshot;
    } catch (error) {
      return RecognitionProviderAvailability(
        providerId: id, state: RecognitionProviderState.unavailable,
        reason: _description(error),
      );
    }
  }
}

bool _sameDescriptor(RecognitionProviderDescriptor first, RecognitionProviderDescriptor second) =>
    first.id == second.id && first.label == second.label &&
    first.capabilities.length == second.capabilities.length &&
    first.capabilities.containsAll(second.capabilities);

bool _strictPrefix(RecognitionConfiguration prefix, RecognitionConfiguration desired) {
  if (prefix.providers.length >= desired.providers.length) {
    return false;
  }
  for (var index = 0; index < prefix.providers.length; index++) {
    final first = prefix.providers[index];
    final second = desired.providers[index];
    if (first.providerId != second.providerId || first.capabilities.length != second.capabilities.length ||
        !first.capabilities.containsAll(second.capabilities)) {
      return false;
    }
  }
  return true;
}

String _secureId() {
  final random = Random.secure();
  return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}
String _description(Object error) => error.toString().trim().isEmpty
    ? error.runtimeType.toString() : error.toString();
