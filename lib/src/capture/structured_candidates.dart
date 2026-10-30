import 'dart:convert';

/// Exact retained text origin; positions use Dart UTF-16 code units.
enum StructuredSourceKind { ocr, transcript }

/// Immutable source snapshot. The application resolves identities to its store.
final class StructuredTextSource {
  StructuredTextSource({
    required this.id,
    required this.materialId,
    required this.kind,
    required this.text,
    this.reportId,
    this.attemptId,
    this.transcriptRevisionIndex,
    this.regionId,
    this.regionRevision,
  }) {
    for (final token in [id, materialId, reportId, attemptId, regionId]) {
      if (token != null) _token(token);
    }
    if ((regionId == null) != (regionRevision == null) ||
        (regionRevision != null && regionRevision! <= 0) ||
        (transcriptRevisionIndex != null && transcriptRevisionIndex! < 0) ||
        (kind == StructuredSourceKind.ocr &&
            (reportId == null ||
                attemptId == null ||
                transcriptRevisionIndex != null)) ||
        (kind == StructuredSourceKind.transcript &&
            (attemptId != null ||
                ((reportId != null) == (transcriptRevisionIndex != null))))) {
      throw ArgumentError('Source fields must identify an exact retained text');
    }
  }
  final String id;
  final String materialId;
  final StructuredSourceKind kind;
  final String text;
  final String? reportId;
  final String? attemptId;
  final int? transcriptRevisionIndex;
  final String? regionId;
  final int? regionRevision;

  Map<String, Object?> toJson() => {
    'id': id,
    'materialId': materialId,
    'kind': kind.name,
    'text': text,
    'reportId': reportId,
    'attemptId': attemptId,
    'transcriptRevisionIndex': transcriptRevisionIndex,
    'regionId': regionId,
    'regionRevision': regionRevision,
  };

  factory StructuredTextSource.fromJson(Object? value) {
    final m = _object(value, {
      'id',
      'materialId',
      'kind',
      'text',
      'reportId',
      'attemptId',
      'transcriptRevisionIndex',
      'regionId',
      'regionRevision',
    });
    return StructuredTextSource(
      id: _string(m['id']),
      materialId: _string(m['materialId']),
      kind: _enum(StructuredSourceKind.values, m['kind']),
      text: _string(m['text']),
      reportId: _optionalString(m['reportId']),
      attemptId: _optionalString(m['attemptId']),
      transcriptRevisionIndex: _optionalInt(m['transcriptRevisionIndex']),
      regionId: _optionalString(m['regionId']),
      regionRevision: _optionalInt(m['regionRevision']),
    );
  }
}

/// A derived value and the exact nonempty source span which supports it.
/// Normalized values may differ from the source slice (e.g. ISBN hyphens).
final class StructuredFieldProposal {
  StructuredFieldProposal({
    required this.id,
    required this.fieldId,
    required this.value,
    required this.sourceId,
    required this.start,
    required this.end,
    required this.providerId,
    required this.method,
  }) {
    for (final token in [id, fieldId, sourceId, providerId, method]) {
      _token(token);
    }
    if (value.trim().isEmpty || start < 0 || end <= start) {
      throw ArgumentError('Proposal needs a value and a nonempty source span');
    }
  }
  final String id;
  final String fieldId;
  final String value;
  final String sourceId;
  final int start;
  final int end;
  final String providerId;
  final String method;
  Map<String, Object?> toJson() => {
    'id': id,
    'fieldId': fieldId,
    'value': value,
    'sourceId': sourceId,
    'start': start,
    'end': end,
    'providerId': providerId,
    'method': method,
  };
  factory StructuredFieldProposal.fromJson(Object? value) {
    final m = _object(value, {
      'id',
      'fieldId',
      'value',
      'sourceId',
      'start',
      'end',
      'providerId',
      'method',
    });
    return StructuredFieldProposal(
      id: _string(m['id']),
      fieldId: _string(m['fieldId']),
      value: _string(m['value']),
      sourceId: _string(m['sourceId']),
      start: _int(m['start']),
      end: _int(m['end']),
      providerId: _string(m['providerId']),
      method: _string(m['method']),
    );
  }
}

enum StructuredDecisionKind { accept, edit, discard }

/// Human intent is separate from generation. Empty edited text is a clear.
final class StructuredProposalDecision {
  StructuredProposalDecision({
    required this.proposalId,
    required this.kind,
    required DateTime recordedAt,
    this.editedValue,
  }) : recordedAt = recordedAt.toUtc() {
    _token(proposalId);
    if ((kind == StructuredDecisionKind.edit) != (editedValue != null)) {
      throw ArgumentError('Only edit carries an exact edited value');
    }
  }
  final String proposalId;
  final StructuredDecisionKind kind;
  final DateTime recordedAt;
  final String? editedValue;
  Map<String, Object?> toJson() => {
    'proposalId': proposalId,
    'kind': kind.name,
    'recordedAt': recordedAt.toIso8601String(),
    'editedValue': editedValue,
  };
  factory StructuredProposalDecision.fromJson(Object? value) {
    final m = _object(value, {
      'proposalId',
      'kind',
      'recordedAt',
      'editedValue',
    });
    final rawTime = _string(m['recordedAt']);
    final time = DateTime.tryParse(rawTime);
    if (time == null || !rawTime.endsWith('Z')) {
      throw const FormatException('Expected UTC decision time');
    }
    return StructuredProposalDecision(
      proposalId: _string(m['proposalId']),
      kind: _enum(StructuredDecisionKind.values, m['kind']),
      recordedAt: time,
      editedValue: _optionalString(m['editedValue']),
    );
  }
}

/// Additive durable product data; no inference or representative mutation on read.
final class StructuredCandidateWorkspace {
  StructuredCandidateWorkspace({
    Iterable<StructuredTextSource> sources = const [],
    Iterable<StructuredFieldProposal> proposals = const [],
    Iterable<StructuredProposalDecision> decisions = const [],
  }) : sources = List.unmodifiable(sources),
       proposals = List.unmodifiable(proposals),
       decisions = List.unmodifiable(decisions) {
    final bySource = {for (final s in this.sources) s.id: s};
    final byProposal = {for (final p in this.proposals) p.id: p};
    if (bySource.length != this.sources.length ||
        byProposal.length != this.proposals.length) {
      throw ArgumentError('Source and proposal identities must be unique');
    }
    for (final p in this.proposals) {
      final source = bySource[p.sourceId];
      if (source == null ||
          p.end > source.text.length ||
          !_boundary(source.text, p.start) ||
          !_boundary(source.text, p.end)) {
        throw ArgumentError('Proposal span must resolve in its exact source');
      }
    }
    final decided = <String>{};
    DateTime? previous;
    for (final d in this.decisions) {
      if (!byProposal.containsKey(d.proposalId) ||
          !decided.add(d.proposalId) ||
          (previous != null && d.recordedAt.isBefore(previous))) {
        throw ArgumentError(
          'Decisions require a known pending proposal and ordered clock',
        );
      }
      previous = d.recordedAt;
    }
  }
  final List<StructuredTextSource> sources;
  final List<StructuredFieldProposal> proposals;
  final List<StructuredProposalDecision> decisions;
  Iterable<StructuredFieldProposal> get pending =>
      proposals.where((p) => !decisions.any((d) => d.proposalId == p.id));
  StructuredTextSource sourceFor(StructuredFieldProposal p) =>
      sources.singleWhere((s) => s.id == p.sourceId);
  StructuredCandidateWorkspace decide(StructuredProposalDecision d) =>
      StructuredCandidateWorkspace(
        sources: sources,
        proposals: proposals,
        decisions: [...decisions, d],
      );
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'sources': sources.map((s) => s.toJson()).toList(),
    'proposals': proposals.map((p) => p.toJson()).toList(),
    'decisions': decisions.map((d) => d.toJson()).toList(),
  };
  factory StructuredCandidateWorkspace.fromJson(Object? value) {
    try {
      final m = _object(value, {
        'schemaVersion',
        'sources',
        'proposals',
        'decisions',
      });
      if (m['schemaVersion'] is! int || m['schemaVersion'] != 1) {
        throw const FormatException('Unsupported structured schema');
      }
      return StructuredCandidateWorkspace(
        sources: _list(m['sources']).map(StructuredTextSource.fromJson),
        proposals: _list(m['proposals']).map(StructuredFieldProposal.fromJson),
        decisions: _list(m['decisions'])
            .map(StructuredProposalDecision.fromJson),
      );
    } on ArgumentError catch (e) {
      throw FormatException('Invalid structured candidates: $e');
    }
  }
  static void requireRetainedPrefix(
    StructuredCandidateWorkspace old,
    StructuredCandidateWorkspace next,
  ) {
    void prefix(List<Object?> a, List<Object?> b) {
      if (a.length > b.length) {
        throw ArgumentError('Structured history cannot shrink');
      }
      for (var i = 0; i < a.length; i++) {
        if (jsonEncode(a[i]) != jsonEncode(b[i])) {
          throw ArgumentError('Structured history cannot be rewritten');
        }
      }
    }

    prefix(
      old.sources.map((s) => s.toJson()).toList(),
      next.sources.map((s) => s.toJson()).toList(),
    );
    prefix(
      old.proposals.map((s) => s.toJson()).toList(),
      next.proposals.map((s) => s.toJson()).toList(),
    );
    prefix(
      old.decisions.map((s) => s.toJson()).toList(),
      next.decisions.map((s) => s.toJson()).toList(),
    );
  }
}

/// A local-only optional provider must report capability before invocation.
enum StructuredProviderState {
  notRequested,
  available,
  unavailable,
  unsupported,
  failed,
}

abstract interface class StructuredCandidateProvider {
  String get id;
  bool get runsLocally;
  Future<StructuredProviderState> probe(
    List<StructuredTextSource> sources,
    Set<String> fields,
  );
  Future<List<StructuredFieldProposal>> propose(
    List<StructuredTextSource> sources,
    Set<String> fields,
  );
}

final class StructuredGenerationResult {
  StructuredGenerationResult({
    required Iterable<StructuredFieldProposal> proposals,
    required this.providerState,
    this.providerId,
    this.reason,
  }) : proposals = List.unmodifiable(proposals);
  final List<StructuredFieldProposal> proposals;
  final StructuredProviderState providerState;
  final String? providerId;
  final String? reason;
}

/// Standard proposals win per field. No provider installation or remote fallback.
final class StructuredCandidateService {
  const StructuredCandidateService();
  Future<StructuredGenerationResult> supplement({
    required List<StructuredTextSource> sources,
    required Set<String> fields,
    required List<StructuredFieldProposal> standard,
    StructuredCandidateProvider? provider,
  }) async {
    sources = List.unmodifiable(sources);
    fields = Set.unmodifiable(fields);
    standard = List.unmodifiable(standard);
    void validate(
      List<StructuredFieldProposal> candidates,
      Set<String> supported,
    ) {
      StructuredCandidateWorkspace(sources: sources, proposals: candidates);
      if (candidates.any((p) => !supported.contains(p.fieldId))) {
        throw ArgumentError('Unsupported proposed field');
      }
    }

    validate(standard, fields);
    final unresolved = fields.difference(
      standard.map((p) => p.fieldId).toSet(),
    );
    if (unresolved.isEmpty) {
      return StructuredGenerationResult(
        proposals: standard,
        providerState: StructuredProviderState.notRequested,
        reason: 'No unresolved fields',
      );
    }
    if (provider == null || !provider.runsLocally) {
      return StructuredGenerationResult(
        proposals: standard,
        providerState: StructuredProviderState.unavailable,
        reason: 'No registered local structuring provider',
      );
    }
    try {
      final state = await provider.probe(
        List.unmodifiable(sources),
        Set.unmodifiable(unresolved),
      );
      if (state != StructuredProviderState.available) {
        return StructuredGenerationResult(
          proposals: standard,
          providerState: state,
          providerId: provider.id,
          reason: 'Local provider is not ready for these sources and fields',
        );
      }
      final extra = await provider.propose(
        List.unmodifiable(sources),
        Set.unmodifiable(unresolved),
      );
      validate(extra, unresolved);
      if (extra.any((p) => p.providerId != provider.id)) {
        throw ArgumentError('Provider identity mismatch');
      }
      validate([...standard, ...extra], fields);
      return StructuredGenerationResult(
        proposals: [...standard, ...extra],
        providerState: state,
        providerId: provider.id,
      );
    } catch (e) {
      return StructuredGenerationResult(
        proposals: standard,
        providerState: StructuredProviderState.failed,
        providerId: provider.id,
        reason: '$e',
      );
    }
  }
}

void _token(String v) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(v)) {
    throw ArgumentError('Invalid structured identity');
  }
}

bool _boundary(String text, int offset) =>
    offset == 0 ||
    offset == text.length ||
    !(text.codeUnitAt(offset - 1) >= 0xd800 &&
        text.codeUnitAt(offset - 1) <= 0xdbff &&
        text.codeUnitAt(offset) >= 0xdc00 &&
        text.codeUnitAt(offset) <= 0xdfff);
Map<String, Object?> _object(Object? value, Set<String> keys) {
  if (value is! Map ||
      value.keys.any((k) => k is! String) ||
      value.length != keys.length ||
      !keys.every(value.containsKey)) {
    throw const FormatException('Unexpected structured object keys');
  }
  return Map<String, Object?>.from(value);
}

String _string(Object? v) {
  if (v is! String) throw const FormatException('Expected text');
  return v;
}

String? _optionalString(Object? v) => v == null ? null : _string(v);
int _int(Object? v) {
  if (v is! int) throw const FormatException('Expected integer');
  return v;
}

int? _optionalInt(Object? v) => v == null ? null : _int(v);
List<Object?> _list(Object? v) {
  if (v is! List) throw const FormatException('Expected list');
  return v;
}

T _enum<T extends Enum>(List<T> values, Object? v) {
  for (final item in values) {
    if (item.name == v) return item;
  }
  throw const FormatException('Unknown structured enum');
}
