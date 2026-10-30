import 'dart:typed_data';

/// Independent derived products; neither operation replaces its original source.
enum GeneratedDraftOperation { imageDescription, textSummary }

enum GeneratedDraftSourceKind { image, text }

enum GeneratedDraftAvailabilityState {
  unsupported,
  unavailable,
  downloadable,
  preparing,
  available,
}

enum GeneratedDraftStatus { success, failed, canceled }

enum GeneratedDraftDecisionKind { accept, edit, discard }

/// Exact caller-owned provenance, without interpreting Book or transcript data.
final class GeneratedDraftSource {
  GeneratedDraftSource({
    required this.id,
    required this.materialId,
    required this.revision,
    required this.kind,
    this.text,
    this.parentMaterialId,
    this.regionId,
    this.regionRevision,
    Map<String, Object?> metadata = const {},
  }) : metadata = _copyMetadata(metadata) {
    for (final identity in [id, materialId, revision, parentMaterialId, regionId]) {
      if (identity != null) _identity(identity);
    }
    if ((kind == GeneratedDraftSourceKind.image && text != null) ||
        (kind == GeneratedDraftSourceKind.text &&
            (text == null || text!.trim().isEmpty))) {
      throw ArgumentError('Source kind must match its exact image or text');
    }
    if ((regionId == null) != (regionRevision == null) ||
        (regionRevision != null && regionRevision! <= 0) ||
        (kind == GeneratedDraftSourceKind.image &&
            regionId != null &&
            parentMaterialId == null)) {
      throw ArgumentError('A region requires its exact revision and parent');
    }
  }

  final String id;
  final String materialId;
  final String revision;
  final GeneratedDraftSourceKind kind;
  final String? text;
  final String? parentMaterialId;
  final String? regionId;
  final int? regionRevision;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => {
    'id': id,
    'materialId': materialId,
    'revision': revision,
    'kind': kind.name,
    'text': text,
    'parentMaterialId': parentMaterialId,
    'regionId': regionId,
    'regionRevision': regionRevision,
    'metadata': metadata,
  };

  factory GeneratedDraftSource.fromJson(Object? value) => _decode(() {
    final object = _object(value, {
      'id',
      'materialId',
      'revision',
      'kind',
      'text',
      'parentMaterialId',
      'regionId',
      'regionRevision',
      'metadata',
    });
    return GeneratedDraftSource(
      id: _string(object['id']),
      materialId: _string(object['materialId']),
      revision: _string(object['revision']),
      kind: _enum(GeneratedDraftSourceKind.values, object['kind']),
      text: _optionalString(object['text']),
      parentMaterialId: _optionalString(object['parentMaterialId']),
      regionId: _optionalString(object['regionId']),
      regionRevision: object['regionRevision'] == null
          ? null
          : _integer(object['regionRevision']),
      metadata: _map(object['metadata']),
    );
  });
}

/// One fresh invocation. Image bytes are copied and never enter durable JSON.
final class GeneratedDraftRequest {
  GeneratedDraftRequest({
    required this.id,
    required this.operation,
    required this.source,
    this.language = 'ja',
    Uint8List? imageBytes,
  }) : imageBytes = imageBytes == null
           ? null
           : Uint8List.fromList(imageBytes).asUnmodifiableView() {
    _identity(id);
    _identity(language);
    switch (operation) {
      case GeneratedDraftOperation.imageDescription:
        if (source.kind != GeneratedDraftSourceKind.image ||
            this.imageBytes == null ||
            this.imageBytes!.isEmpty) {
          throw ArgumentError('Image description requires exact image bytes');
        }
      case GeneratedDraftOperation.textSummary:
        if (source.kind != GeneratedDraftSourceKind.text || imageBytes != null) {
          throw ArgumentError('Text summary requires text without image bytes');
        }
    }
  }

  static const outputTokenLimit = 512;
  static const maxOutputCharacters = 2048;

  final String id;
  final GeneratedDraftOperation operation;
  final GeneratedDraftSource source;
  final String language;
  final Uint8List? imageBytes;
}

/// A truthful operation/language snapshot, separate from explicit preparation.
final class GeneratedDraftAvailability {
  GeneratedDraftAvailability({
    required this.providerId,
    required this.operation,
    required this.language,
    required this.state,
    this.modelName,
    this.reason,
  }) {
    _identity(providerId);
    _identity(language);
    if (state == GeneratedDraftAvailabilityState.available) {
      _nonblank(modelName, 'Available provider needs its actual model');
    } else {
      _nonblank(reason, 'Non-available provider needs a reason');
    }
  }

  final String providerId;
  final GeneratedDraftOperation operation;
  final String language;
  final GeneratedDraftAvailabilityState state;
  final String? modelName;
  final String? reason;

  Map<String, Object?> toJson() => {
    'providerId': providerId,
    'operation': operation.name,
    'language': language,
    'state': state.name,
    'modelName': modelName,
    'reason': reason,
  };

  factory GeneratedDraftAvailability.fromJson(Object? value) => _decode(() {
    final object = _object(value, {
      'providerId',
      'operation',
      'language',
      'state',
      'modelName',
      'reason',
    });
    return GeneratedDraftAvailability(
      providerId: _string(object['providerId']),
      operation: _enum(GeneratedDraftOperation.values, object['operation']),
      language: _string(object['language']),
      state: _enum(GeneratedDraftAvailabilityState.values, object['state']),
      modelName: _optionalString(object['modelName']),
      reason: _optionalString(object['reason']),
    );
  });
}

/// Ephemeral provider response. Failures may retain any exact raw response.
final class GeneratedDraftProviderOutput {
  GeneratedDraftProviderOutput({
    required this.status,
    this.text,
    this.modelName,
    this.errorCode,
    this.errorMessage,
    Iterable<String> cleanupFailures = const [],
  }) : cleanupFailures = _cleanup(cleanupFailures) {
    _resultFields(status, text, modelName, errorCode, errorMessage);
  }

  final GeneratedDraftStatus status;
  final String? text;
  final String? modelName;
  final String? errorCode;
  final String? errorMessage;
  final List<String> cleanupFailures;
}

/// Durable generation evidence, independent of any later human decision.
final class GeneratedDraftAttempt {
  GeneratedDraftAttempt({
    required this.id,
    required this.operation,
    required this.source,
    required this.language,
    required this.providerId,
    required this.promptTemplate,
    required this.startedAt,
    required this.completedAt,
    required this.status,
    this.availability,
    this.prompt,
    this.modelName,
    this.rawText,
    this.errorCode,
    this.errorMessage,
    Iterable<String> cleanupFailures = const [],
  }) : cleanupFailures = _cleanup(cleanupFailures) {
    for (final identity in [id, language, providerId, promptTemplate]) {
      _identity(identity);
    }
    _utc(startedAt);
    _utc(completedAt);
    if (completedAt.isBefore(startedAt)) {
      throw ArgumentError('Completion cannot precede generation start');
    }
    if ((operation == GeneratedDraftOperation.imageDescription) !=
        (source.kind == GeneratedDraftSourceKind.image)) {
      throw ArgumentError('Attempt operation must match its exact source');
    }
    final snapshot = availability;
    if (snapshot != null &&
        (snapshot.providerId != providerId ||
            snapshot.operation != operation ||
            snapshot.language != language)) {
      throw ArgumentError('Availability identity must match its attempt');
    }
    _resultFields(status, rawText, modelName, errorCode, errorMessage);
    if (status == GeneratedDraftStatus.success) {
      _nonblank(prompt, 'Successful attempt requires its exact prompt');
      if (snapshot == null ||
          snapshot.state != GeneratedDraftAvailabilityState.available ||
          snapshot.modelName != modelName) {
        throw ArgumentError('Success requires its matching available model');
      }
    }
  }

  final String id;
  final GeneratedDraftOperation operation;
  final GeneratedDraftSource source;
  final String language;
  final String providerId;
  final String promptTemplate;
  final DateTime startedAt;
  final DateTime completedAt;
  final GeneratedDraftStatus status;
  final GeneratedDraftAvailability? availability;
  final String? prompt;
  final String? modelName;
  final String? rawText;
  final String? errorCode;
  final String? errorMessage;
  final List<String> cleanupFailures;

  Map<String, Object?> toJson() => {
    'id': id,
    'operation': operation.name,
    'source': source.toJson(),
    'language': language,
    'providerId': providerId,
    'promptTemplate': promptTemplate,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt.toIso8601String(),
    'status': status.name,
    'availability': availability?.toJson(),
    'prompt': prompt,
    'modelName': modelName,
    'rawText': rawText,
    'errorCode': errorCode,
    'errorMessage': errorMessage,
    'cleanupFailures': cleanupFailures,
  };

  factory GeneratedDraftAttempt.fromJson(Object? value) => _decode(() {
    final object = _object(value, {
      'id',
      'operation',
      'source',
      'language',
      'providerId',
      'promptTemplate',
      'startedAt',
      'completedAt',
      'status',
      'availability',
      'prompt',
      'modelName',
      'rawText',
      'errorCode',
      'errorMessage',
      'cleanupFailures',
    });
    return GeneratedDraftAttempt(
      id: _string(object['id']),
      operation: _enum(GeneratedDraftOperation.values, object['operation']),
      source: GeneratedDraftSource.fromJson(object['source']),
      language: _string(object['language']),
      providerId: _string(object['providerId']),
      promptTemplate: _string(object['promptTemplate']),
      startedAt: _date(object['startedAt']),
      completedAt: _date(object['completedAt']),
      status: _enum(GeneratedDraftStatus.values, object['status']),
      availability: object['availability'] == null
          ? null
          : GeneratedDraftAvailability.fromJson(object['availability']),
      prompt: _optionalString(object['prompt']),
      modelName: _optionalString(object['modelName']),
      rawText: _optionalString(object['rawText']),
      errorCode: _optionalString(object['errorCode']),
      errorMessage: _optionalString(object['errorMessage']),
      cleanupFailures: _list(object['cleanupFailures']).map(_string),
    );
  });
}

/// Explicit terminal intent. An empty edit is an intentional clear.
final class GeneratedDraftDecision {
  GeneratedDraftDecision({
    required this.attemptId,
    required this.kind,
    required this.recordedAt,
    this.editedText,
  }) {
    _identity(attemptId);
    _utc(recordedAt);
    if ((kind == GeneratedDraftDecisionKind.edit) != (editedText != null)) {
      throw ArgumentError('Only edit carries exact edited text');
    }
  }

  final String attemptId;
  final GeneratedDraftDecisionKind kind;
  final DateTime recordedAt;
  final String? editedText;

  Map<String, Object?> toJson() => {
    'attemptId': attemptId,
    'kind': kind.name,
    'recordedAt': recordedAt.toIso8601String(),
    'editedText': editedText,
  };

  factory GeneratedDraftDecision.fromJson(Object? value) => _decode(() {
    final object = _object(value, {
      'attemptId',
      'kind',
      'recordedAt',
      'editedText',
    });
    return GeneratedDraftDecision(
      attemptId: _string(object['attemptId']),
      kind: _enum(GeneratedDraftDecisionKind.values, object['kind']),
      recordedAt: _date(object['recordedAt']),
      editedText: _optionalString(object['editedText']),
    );
  });
}

/// Additive product history. Loading never generates, adopts or rewrites data.
final class GeneratedDraftWorkspace {
  GeneratedDraftWorkspace({
    Iterable<GeneratedDraftAttempt> attempts = const [],
    Iterable<GeneratedDraftDecision> decisions = const [],
  }) : attempts = List.unmodifiable(attempts),
       decisions = List.unmodifiable(decisions) {
    final byId = <String, GeneratedDraftAttempt>{};
    final sources = <String, GeneratedDraftSource>{};
    for (final attempt in this.attempts) {
      if (byId.containsKey(attempt.id)) {
        throw ArgumentError('Attempt identities must be unique');
      }
      byId[attempt.id] = attempt;
      final previous = sources[attempt.source.id];
      if (previous != null &&
          !_sameJson(previous.toJson(), attempt.source.toJson())) {
        throw ArgumentError('A source identity cannot change its exact value');
      }
      sources[attempt.source.id] = attempt.source;
    }
    final decided = <String>{};
    for (final decision in this.decisions) {
      final attempt = byId[decision.attemptId];
      if (attempt == null ||
          attempt.status != GeneratedDraftStatus.success ||
          !decided.add(decision.attemptId) ||
          decision.recordedAt.isBefore(attempt.completedAt)) {
        throw ArgumentError('Decision requires one completed successful attempt');
      }
    }
  }

  final List<GeneratedDraftAttempt> attempts;
  final List<GeneratedDraftDecision> decisions;

  Iterable<GeneratedDraftAttempt> get pending {
    final decided = decisions.map((decision) => decision.attemptId).toSet();
    return attempts.where(
      (attempt) =>
          attempt.status == GeneratedDraftStatus.success &&
          !decided.contains(attempt.id),
    );
  }

  GeneratedDraftWorkspace append(GeneratedDraftAttempt attempt) =>
      GeneratedDraftWorkspace(
        attempts: [...attempts, attempt],
        decisions: decisions,
      );

  GeneratedDraftWorkspace decide(GeneratedDraftDecision decision) =>
      GeneratedDraftWorkspace(
        attempts: attempts,
        decisions: [...decisions, decision],
      );

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'attempts': attempts.map((attempt) => attempt.toJson()).toList(),
    'decisions': decisions.map((decision) => decision.toJson()).toList(),
  };

  factory GeneratedDraftWorkspace.fromJson(Object? value) => _decode(() {
    final object = _object(value, {'schemaVersion', 'attempts', 'decisions'});
    if (_integer(object['schemaVersion']) != 1) {
      throw const FormatException('Unsupported generated draft schema');
    }
    return GeneratedDraftWorkspace(
      attempts: _list(object['attempts']).map(GeneratedDraftAttempt.fromJson),
      decisions: _list(object['decisions']).map(GeneratedDraftDecision.fromJson),
    );
  });

  /// Enforces retained application history by semantic product value.
  static void requireRetainedPrefix(
    GeneratedDraftWorkspace previous,
    GeneratedDraftWorkspace next,
  ) {
    void requirePrefix(List<Object?> before, List<Object?> after) {
      if (before.length > after.length) {
        throw ArgumentError('Generated draft history cannot shrink');
      }
      for (var index = 0; index < before.length; index++) {
        if (!_sameJson(before[index], after[index])) {
          throw ArgumentError('Generated draft history cannot be rewritten');
        }
      }
    }

    requirePrefix(
      previous.attempts.map((attempt) => attempt.toJson()).toList(),
      next.attempts.map((attempt) => attempt.toJson()).toList(),
    );
    requirePrefix(
      previous.decisions.map((decision) => decision.toJson()).toList(),
      next.decisions.map((decision) => decision.toJson()).toList(),
    );
  }
}

void _identity(String value) {
  if (value.trim().isEmpty ||
      value != value.trim() ||
      value.contains('\u0000')) {
    throw ArgumentError('Expected an exact nonblank identity without NUL');
  }
}

void _nonblank(String? value, String message) {
  if (value == null || value.trim().isEmpty) throw ArgumentError(message);
}

void _utc(DateTime value) {
  if (!value.isUtc) throw ArgumentError('Expected an actual UTC timestamp');
}

List<String> _cleanup(Iterable<String> values) {
  final result = List<String>.unmodifiable(values);
  for (final value in result) {
    _nonblank(value, 'Cleanup diagnostics must be nonblank');
  }
  return result;
}

void _resultFields(
  GeneratedDraftStatus status,
  String? text,
  String? modelName,
  String? errorCode,
  String? errorMessage,
) {
  if (status == GeneratedDraftStatus.success) {
    _nonblank(text, 'Success requires nonblank output');
    _nonblank(modelName, 'Success requires its actual model');
    if (errorCode != null || errorMessage != null) {
      throw ArgumentError('Success cannot carry error fields');
    }
  } else {
    _nonblank(errorCode, 'Failure or cancellation requires an error code');
    _nonblank(errorMessage, 'Failure or cancellation requires an explanation');
  }
}

Map<String, Object?> _copyMetadata(Map<String, Object?> value) =>
    _copyJson(value, Set<Object>.identity()) as Map<String, Object?>;

Object? _copyJson(Object? value, Set<Object> ancestors) {
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  if (value is double && value.isFinite) return value;
  if (value is Map || value is List) {
    if (!ancestors.add(value)) {
      throw ArgumentError('Metadata must be finite acyclic JSON');
    }
    try {
      if (value is Map) {
        final result = <String, Object?>{};
        for (final entry in value.entries) {
          if (entry.key is! String) {
            throw ArgumentError('Metadata object keys must be strings');
          }
          result[entry.key as String] = _copyJson(entry.value, ancestors);
        }
        return Map<String, Object?>.unmodifiable(result);
      }
      return List<Object?>.unmodifiable(
        (value as List).map((item) => _copyJson(item, ancestors)),
      );
    } finally {
      ancestors.remove(value);
    }
  }
  throw ArgumentError('Metadata supports finite JSON values only');
}

bool _sameJson(Object? left, Object? right) {
  if (left is Map && right is Map) {
    return left.length == right.length &&
        left.keys.every(
          (key) => right.containsKey(key) && _sameJson(left[key], right[key]),
        );
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!_sameJson(left[index], right[index])) return false;
    }
    return true;
  }
  return left == right;
}

T _decode<T>(T Function() decode) {
  try {
    return decode();
  } on ArgumentError catch (error) {
    throw FormatException('Invalid generated draft value: $error');
  }
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Expected a string-keyed JSON object');
  }
  return Map<String, Object?>.from(value);
}

Map<String, Object?> _object(Object? value, Set<String> keys) {
  final result = _map(value);
  if (result.length != keys.length || !keys.every(result.containsKey)) {
    throw const FormatException('Unexpected generated draft object keys');
  }
  return result;
}

String _string(Object? value) {
  if (value is! String) throw const FormatException('Expected a string');
  return value;
}

String? _optionalString(Object? value) => value == null ? null : _string(value);

int _integer(Object? value) {
  if (value is! int) throw const FormatException('Expected an integer');
  return value;
}

List<Object?> _list(Object? value) {
  if (value is! List) throw const FormatException('Expected a list');
  return List<Object?>.of(value);
}

T _enum<T extends Enum>(List<T> values, Object? value) {
  for (final item in values) {
    if (item.name == value) return item;
  }
  throw const FormatException('Unsupported generated draft enum');
}

DateTime _date(Object? value) {
  final text = _string(value);
  final parsed = DateTime.tryParse(text);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != text) {
    throw const FormatException('Expected a canonical UTC ISO8601 timestamp');
  }
  return parsed;
}
