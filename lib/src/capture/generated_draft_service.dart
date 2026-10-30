import 'dart:async';

import 'generated_draft.dart';

/// Borrowed provider boundary. Preparation is always an explicit caller action.
abstract interface class GeneratedDraftProvider {
  String get id;
  String get promptTemplate;
  String promptFor(GeneratedDraftRequest request);
  Future<GeneratedDraftAvailability> availability({
    required GeneratedDraftOperation operation,
    required String language,
  });
  Future<void> prepare();
  Future<GeneratedDraftProviderOutput> generate(
    GeneratedDraftRequest request, {
    required String prompt,
    String? expectedModelName,
  });
  Future<bool> cancel(String requestId);
}

/// Serial generation with durable provenance and cancellation-safe completion.
final class GeneratedDraftService {
  GeneratedDraftService({
    required GeneratedDraftProvider provider,
    DateTime Function()? clock,
  }) : _provider = provider,
       _providerId = provider.id,
       _promptTemplate = provider.promptTemplate,
       _clock = clock ?? _utcNow {
    _descriptor(_providerId);
    _descriptor(_promptTemplate);
  }

  final GeneratedDraftProvider _provider;
  final String _providerId;
  final String _promptTemplate;
  final DateTime Function() _clock;
  final Set<String> _usedRequestIds = {};
  bool _busy = false;
  _ActiveGeneration? _active;

  bool get isBusy => _busy;

  Future<GeneratedDraftAvailability> availability({
    required GeneratedDraftOperation operation,
    String language = 'ja',
  }) {
    _descriptor(language);
    _begin();
    return _availability(operation, language);
  }

  Future<GeneratedDraftAvailability> _availability(
    GeneratedDraftOperation operation,
    String language,
  ) async {
    try {
      return await _probe(operation, language);
    } finally {
      _busy = false;
    }
  }

  Future<GeneratedDraftAvailability> prepare({
    required GeneratedDraftOperation operation,
    String language = 'ja',
  }) {
    _descriptor(language);
    _begin();
    return _prepare(operation, language);
  }

  Future<GeneratedDraftAvailability> _prepare(
    GeneratedDraftOperation operation,
    String language,
  ) async {
    try {
      final snapshot = await _probe(operation, language);
      if (snapshot.state != GeneratedDraftAvailabilityState.downloadable) {
        return snapshot;
      }
      await _provider.prepare();
      return await _probe(operation, language);
    } finally {
      _busy = false;
    }
  }

  Future<GeneratedDraftAttempt> generate(GeneratedDraftRequest request) {
    if (_busy) throw StateError('Generated draft service is busy');
    if (!_usedRequestIds.add(request.id)) {
      throw StateError('Every generated draft attempt requires a fresh ID');
    }
    _begin();
    final active = _ActiveGeneration(request.id);
    _active = active;
    return _generate(request, active);
  }

  Future<GeneratedDraftAttempt> _generate(
    GeneratedDraftRequest request,
    _ActiveGeneration active,
  ) async {
    try {
      final startedAt = _readClock();
      GeneratedDraftAvailability? snapshot;
      GeneratedDraftProviderOutput? output;
      String? prompt;
      var status = GeneratedDraftStatus.failed;
      String? errorCode;
      String? errorMessage;
      try {
        snapshot = await _probe(request.operation, request.language);
        if (!active.cancelRequested) {
          if (snapshot.state != GeneratedDraftAvailabilityState.available) {
            errorCode = switch (snapshot.state) {
              GeneratedDraftAvailabilityState.unsupported =>
                'unsupportedOperation',
              GeneratedDraftAvailabilityState.unavailable =>
                'providerUnavailable',
              GeneratedDraftAvailabilityState.downloadable =>
                'preparationRequired',
              GeneratedDraftAvailabilityState.preparing => 'providerPreparing',
              GeneratedDraftAvailabilityState.available =>
                throw StateError('Available snapshot requires inference'),
            };
            errorMessage = snapshot.reason;
          } else {
            prompt = _provider.promptFor(request);
            if (prompt.trim().isEmpty) {
              throw StateError('Provider returned a blank prompt');
            }
            if (!active.cancelRequested) {
              output = await _provider.generate(
                request,
                prompt: prompt,
                expectedModelName: snapshot.modelName,
              );
              status = output.status;
              errorCode = output.errorCode;
              errorMessage = output.errorMessage;
              if (status == GeneratedDraftStatus.success) {
                if (output.modelName != snapshot.modelName) {
                  status = GeneratedDraftStatus.failed;
                  errorCode = 'modelChanged';
                  errorMessage = 'Generated model differs from availability';
                } else if (output.text!.runes.length >
                    GeneratedDraftRequest.maxOutputCharacters) {
                  status = GeneratedDraftStatus.failed;
                  errorCode = 'outputTooLarge';
                  errorMessage = 'Output exceeds 2048 Unicode scalar values';
                }
              }
            }
          }
        }
      } catch (error) {
        status = GeneratedDraftStatus.failed;
        errorCode = 'providerFailure';
        errorMessage = _description(error);
      }

      // Cancellation owns its captured request until both provider paths settle.
      if (active.cancelRequested) {
        await active.cancellation;
        status = GeneratedDraftStatus.canceled;
        errorCode = 'canceled';
        errorMessage = 'Cancellation requested for ${request.id}';
      }
      final completedAt = _readClock();
      if (completedAt.isBefore(startedAt)) {
        throw StateError('Generated draft clock moved backward');
      }
      return GeneratedDraftAttempt(
        id: request.id,
        operation: request.operation,
        source: request.source,
        language: request.language,
        providerId: _providerId,
        promptTemplate: _promptTemplate,
        startedAt: startedAt,
        completedAt: completedAt,
        status: status,
        availability: snapshot,
        prompt: prompt,
        modelName: output?.modelName,
        rawText: output?.text,
        errorCode: errorCode,
        errorMessage: errorMessage,
        cleanupFailures: [
          ...?output?.cleanupFailures,
          ...active.cleanupFailures,
        ],
      );
    } finally {
      _active = null;
      _busy = false;
    }
  }

  /// Records intent before asking the provider; late success cannot be adopted.
  Future<bool> cancel() {
    final active = _active;
    if (active == null) return Future.value(false);
    final pending = active.cancellation;
    if (pending != null) return pending;
    active.cancelRequested = true;
    final completion = Completer<bool>();
    active.cancellation = completion.future;
    unawaited(_cancelProvider(active, completion));
    return completion.future;
  }

  Future<void> _cancelProvider(
    _ActiveGeneration active,
    Completer<bool> completion,
  ) async {
    try {
      completion.complete(await _provider.cancel(active.requestId));
    } catch (error) {
      active.cleanupFailures.add('Cancellation failed: ${_description(error)}');
      completion.complete(false);
    }
  }

  Future<GeneratedDraftAvailability> _probe(
    GeneratedDraftOperation operation,
    String language,
  ) async {
    final snapshot = await _provider.availability(
      operation: operation,
      language: language,
    );
    if (snapshot.providerId != _providerId ||
        snapshot.operation != operation ||
        snapshot.language != language) {
      throw StateError('Provider availability identity does not match request');
    }
    return snapshot;
  }

  void _begin() {
    if (_busy) throw StateError('Generated draft service is busy');
    _busy = true;
  }

  DateTime _readClock() {
    final value = _clock();
    if (!value.isUtc) {
      throw StateError('Generated draft clock must return actual UTC');
    }
    return value;
  }
}

final class _ActiveGeneration {
  _ActiveGeneration(this.requestId);

  final String requestId;
  bool cancelRequested = false;
  Future<bool>? cancellation;
  final List<String> cleanupFailures = [];
}

DateTime _utcNow() => DateTime.now().toUtc();

void _descriptor(String value) {
  if (value.trim().isEmpty ||
      value.trim() != value ||
      value.contains('\u0000')) {
    throw ArgumentError('Provider descriptors and language must be exact');
  }
}

String _description(Object error) {
  final text = '$error';
  return text.trim().isEmpty ? '${error.runtimeType}' : text;
}
