import 'capture_material.dart';
import 'photo_capture.dart';
import 'recognition_configuration.dart';
import 'recognition_operation_context.dart';

/// One native invocation or explicit nonexecuted stage for a saved original.
final class RecognitionProviderAttempt {
  RecognitionProviderAttempt({
    required String id, required String providerId, required String materialId,
    required this.availability, required DateTime startedAt,
    required this.elapsed, required this.executed, required this.result,
    Iterable<String> inputAttemptIds = const [],
  }) : id = _token(id), providerId = _token(providerId),
       materialId = _token(materialId), startedAt = startedAt.toUtc(),
       inputAttemptIds = List.unmodifiable(inputAttemptIds.map(_token)) {
    if (availability.providerId != providerId || elapsed.isNegative ||
        (!executed && (elapsed != Duration.zero || result.hasSuccessfulOutput)) ||
        this.inputAttemptIds.contains(id) ||
        this.inputAttemptIds.toSet().length != this.inputAttemptIds.length) {
      throw ArgumentError('Invalid attempt ownership, timing or input identity');
    }
  }
  final String id;
  final String providerId;
  final String materialId;
  final RecognitionProviderAvailability availability;
  final DateTime startedAt;
  final Duration elapsed;
  final bool executed;
  final ImageRecognitionResult result;
  final List<String> inputAttemptIds;
}

enum RecognitionRunStatus { completed, partial, failed, unavailable }

/// A desired route with actual route, retaining failed enhancement overhead.
final class RecognitionRun {
  RecognitionRun({
    required String desiredConfigurationId,
    String? actualConfigurationId,
    Iterable<String> actualProviderIds = const [],
    String? fallbackReason,
    required Iterable<RecognitionProviderAttempt> attempts,
  }) : desiredConfigurationId = _token(desiredConfigurationId),
       actualConfigurationId = actualConfigurationId == null
           ? null : _token(actualConfigurationId),
       actualProviderIds = List.unmodifiable(actualProviderIds.map(_token)),
       fallbackReason = fallbackReason,
       attempts = List.unmodifiable(attempts) {
    if (this.attempts.isEmpty ||
        this.attempts.map((item) => item.id).toSet().length != this.attempts.length ||
        this.attempts.map((item) => item.providerId).toSet().length !=
            this.attempts.length ||
        this.actualProviderIds.toSet().length != this.actualProviderIds.length) {
      throw ArgumentError('A row requires distinct provider and attempt IDs');
    }
    if (actualConfigurationId == null) {
      if (this.actualProviderIds.isNotEmpty || fallbackReason != null) {
        throw ArgumentError('No actual route permits no providers or fallback');
      }
    } else {
      if (this.actualProviderIds.isEmpty ||
          (actualConfigurationId == desiredConfigurationId && fallbackReason != null) ||
          (actualConfigurationId != desiredConfigurationId &&
              (fallbackReason == null || fallbackReason.trim().isEmpty))) {
        throw ArgumentError('Invalid actual route or fallback reason');
      }
      var position = -1;
      for (final providerId in this.actualProviderIds) {
        final next = this.attempts.indexWhere(
          (item) => item.providerId == providerId && item.executed,
        );
        if (next <= position) throw ArgumentError('Actual providers are not ordered executed stages');
        position = next;
      }
    }
  }
  final String desiredConfigurationId;
  final String? actualConfigurationId;
  final List<String> actualProviderIds;
  final String? fallbackReason;
  final List<RecognitionProviderAttempt> attempts;
  bool get hasFallback => actualConfigurationId != null &&
      actualConfigurationId != desiredConfigurationId;
  Duration get elapsed => attempts.where((item) => item.executed).fold(
    Duration.zero, (total, item) => total + item.elapsed,
  );
  RecognitionRunStatus get status {
    if (actualConfigurationId == null) return RecognitionRunStatus.unavailable;
    final selected = attempts.where(
      (item) => actualProviderIds.contains(item.providerId),
    );
    if (selected.every(_completed)) return RecognitionRunStatus.completed;
    if (selected.any((item) => item.result.hasSuccessfulOutput)) {
      return RecognitionRunStatus.partial;
    }
    return RecognitionRunStatus.failed;
  }
}

bool _completed(RecognitionProviderAttempt attempt) =>
    attempt.result.hasSuccessfulOutput && attempt.result.failures.isEmpty &&
    attempt.availability.capabilities.every((capability) => switch (capability) {
      RecognitionCapability.ocr => attempt.result.text != null,
      RecognitionCapability.barcodes => attempt.result.barcodeCompleted,
      RecognitionCapability.imageInterpretation => attempt.result.interpretation != null,
      RecognitionCapability.candidateOrganization => attempt.result.candidateOrganizationCompleted,
    });

/// Immutable report. Sharing the same attempt object expresses real shared work.
final class RecognitionComparison {
  RecognitionComparison({
    required String id, required this.material, required DateTime createdAt,
    required Iterable<RecognitionRun> runs,
    Map<String, Object?> extensions = const {},
  }) : id = _token(id), createdAt = createdAt.toUtc(),
       runs = List.unmodifiable(runs),
       extensions = CaptureMaterialReference(
         id: 'extensions', mediaType: 'application/json', byteLength: 1,
         capturedAt: createdAt, extensions: extensions,
       ).extensions {
    if (this.extensions.containsKey(RecognitionOperationContext.extensionKey)) {
      try {
        _operationContext = RecognitionOperationContext.fromJson(
          this.extensions[RecognitionOperationContext.extensionKey],
        );
      } on FormatException catch (error) {
        throw ArgumentError('Invalid recognition operation context: $error');
      }
    } else {
      _operationContext = null;
    }
    if (this.runs.isEmpty ||
        this.runs.map((item) => item.desiredConfigurationId).toSet().length !=
            this.runs.length) {
      throw ArgumentError('Comparison rows must be distinct and nonempty');
    }
    final identities = <String, RecognitionProviderAttempt>{};
    for (final run in this.runs) {
      final earlier = <String, int>{};
      for (var index = 0; index < run.attempts.length; index++) {
        final attempt = run.attempts[index];
        if (attempt.materialId != material.id) throw ArgumentError('Attempt has another original');
        final shared = identities[attempt.id];
        if (shared != null && !identical(shared, attempt)) {
          throw ArgumentError('An attempt ID must identify the identical shared object');
        }
        identities[attempt.id] = attempt;
        var previousPosition = -1;
        for (final inputId in attempt.inputAttemptIds) {
          final position = earlier[inputId];
          if (position == null || position <= previousPosition) {
            throw ArgumentError('Inputs must be earlier executed stages in row order');
          }
          previousPosition = position;
        }
        if (attempt.executed) earlier[attempt.id] = index;
      }
    }
  }
  final String id;
  final CaptureMaterialReference material;
  final DateTime createdAt;
  final List<RecognitionRun> runs;
  final Map<String, Object?> extensions;
  late final RecognitionOperationContext? _operationContext;

  /// Requested operation metadata, independent of actual provider execution.
  /// Null means the optional namespace was absent from the raw report.
  RecognitionOperationContext? get operationContext => _operationContext;
}

String _token(String value) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(value)) {
    throw ArgumentError.value(value, 'id', 'unsafe logical token');
  }
  return value;
}
