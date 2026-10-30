import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

StructuredTextSource source({String text = '書名：源氏物語\nコメント'}) =>
    StructuredTextSource(
      id: 'source',
      materialId: 'photo',
      kind: StructuredSourceKind.ocr,
      text: text,
      reportId: 'report',
      attemptId: 'attempt',
    );
StructuredFieldProposal proposal({
  String id = 'proposal',
  String field = 'title',
  String provider = 'standard',
  int start = 3,
  int end = 7,
}) => StructuredFieldProposal(
  id: id,
  fieldId: field,
  value: '源氏物語',
  sourceId: 'source',
  start: start,
  end: end,
  providerId: provider,
  method: 'labelled',
);

void main() {
  test(
    'resolved fields do not probe or claim unsupported provider capability',
    () async {
      // Given a registered local provider and an already resolved title.
      final local = _Provider();
      // When supplementation is requested for that resolved field only.
      final result = await const StructuredCandidateService().supplement(
        sources: [source()],
        fields: {'title'},
        standard: [proposal()],
        provider: local,
      );
      // Then no capability or inference call is attributed to the provider.
      expect(result.providerState, StructuredProviderState.notRequested);
      expect(result.providerId, isNull);
      expect(local.calls, 0);
    },
  );
  test(
    'exact Japanese source span and decisions survive independent JSON reload',
    () {
      // Given a Japanese source and an undecided proposal over its exact title.
      final s = source();
      final w = StructuredCandidateWorkspace(
        sources: [s],
        proposals: [proposal()],
      );
      // Then a source slice resolves the unmodified title before selection.
      expect(w.pending.single.value, '源氏物語');
      expect(
        s.text.substring(w.proposals.single.start, w.proposals.single.end),
        '源氏物語',
      );
      // When an explicit clear and its history pass through detached JSON.
      final edited = w.decide(
        StructuredProposalDecision(
          proposalId: 'proposal',
          kind: StructuredDecisionKind.edit,
          recordedAt: DateTime.utc(2026, 10, 30),
          editedValue: '',
        ),
      );
      final restored = StructuredCandidateWorkspace.fromJson(
        jsonDecode(jsonEncode(edited.toJson())),
      );
      // Then the clear is distinct from absence and the original evidence remains.
      expect(restored.pending, isEmpty);
      expect(restored.decisions.single.editedValue, '');
      expect(restored.sources.single.text, s.text);
      expect(restored.proposals.single.value, '源氏物語');
      StructuredCandidateWorkspace.requireRetainedPrefix(w, restored);
      expect(
        () => StructuredCandidateWorkspace.requireRetainedPrefix(restored, w),
        throwsArgumentError,
      );
    },
  );
  test(
    'unresolved sources, out of bounds and split surrogate spans are rejected',
    () {
      // Given a proposal whose referenced source is absent.
      expect(
        // When the workspace resolves that proposal's source identity.
        () => StructuredCandidateWorkspace(proposals: [proposal()]),
        // Then the missing source is rejected.
        throwsArgumentError,
      );
      // Given an oversized span, construction must reject the invalid boundary.
      expect(
        () => StructuredCandidateWorkspace(
          sources: [source()],
          proposals: [proposal(end: 99)],
        ),
        throwsArgumentError,
      );
      // Given a split surrogate pair, construction must reject the partial span.
      expect(
        () => StructuredCandidateWorkspace(
          sources: [source(text: 'a😀b')],
          proposals: [proposal(start: 1, end: 2)],
        ),
        throwsArgumentError,
      );
      // A complete surrogate pair remains an accepted span.
      expect(
        () => StructuredCandidateWorkspace(
          sources: [source(text: 'a😀b')],
          proposals: [proposal(start: 1, end: 3)],
        ),
        returnsNormally,
      );
    },
  );
  test('source shapes distinguish OCR, report and transcript correction', () {
    // Given OCR text without the required report and attempt identity.
    expect(
      // When that incomplete OCR origin is constructed.
      () => StructuredTextSource(
        id: 's',
        materialId: 'm',
        kind: StructuredSourceKind.ocr,
        text: 'text',
      ),
      // Then the source cannot claim a resolvable OCR origin.
      throwsArgumentError,
    );
    // Contradictory transcript report/revision links are rejected too.
    expect(
      () => StructuredTextSource(
        id: 's',
        materialId: 'm',
        kind: StructuredSourceKind.transcript,
        text: 'text',
        reportId: 'r',
        transcriptRevisionIndex: 0,
      ),
      throwsArgumentError,
    );
    // An exact revision-only transcript link is accepted.
    expect(
      () => StructuredTextSource(
        id: 's',
        materialId: 'm',
        kind: StructuredSourceKind.transcript,
        text: 'text',
        transcriptRevisionIndex: 0,
      ),
      returnsNormally,
    );
  });
  test('accept and discard stay distinct and cannot be applied twice', () {
    for (final kind in [
      StructuredDecisionKind.accept,
      StructuredDecisionKind.discard,
    ]) {
      // Given one pending proposal and this explicit human decision kind.
      final w = StructuredCandidateWorkspace(
        sources: [source()],
        proposals: [proposal()],
      );
      final d = StructuredProposalDecision(
        proposalId: 'proposal',
        kind: kind,
        recordedAt: DateTime.utc(2026, 10, 30),
      );
      // When that decision is recorded once.
      final decided = w.decide(d);
      // Then its kind survives and a repeated decision is rejected.
      expect(decided.decisions.single.kind, kind);
      expect(() => decided.decide(d), throwsArgumentError);
    }
  });
  test('malformed and unsupported documents fail explicitly', () {
    // Given the current supported workspace wire representation.
    final w = StructuredCandidateWorkspace(
      sources: [source()],
      proposals: [proposal()],
    );
    // When schema, keys or a numeric position have an invalid representation.
    // Then strict decoding rejects each malformed document rather than dropping it.
    expect(
      () => StructuredCandidateWorkspace.fromJson({
        ...w.toJson(),
        'schemaVersion': 2,
      }),
      throwsFormatException,
    );
    expect(
      () =>
          StructuredCandidateWorkspace.fromJson({...w.toJson(), 'extra': null}),
      throwsFormatException,
    );
    final wire = w.toJson();
    (wire['proposals'] as List).single['start'] = 1.0;
    expect(
      () => StructuredCandidateWorkspace.fromJson(wire),
      throwsFormatException,
    );
  });
  test(
    'no provider and remote providers preserve standard results without calls',
    () async {
      // Given a standard title and either no supplementer or a remote provider.
      final remote = _Provider(local: false);
      for (final p in <StructuredCandidateProvider?>[null, remote]) {
        // When only the unresolved annotation would need supplementation.
        final r = await const StructuredCandidateService().supplement(
          sources: [source()],
          fields: {'title', 'annotationText'},
          standard: [proposal()],
          provider: p,
        );
        // Then the standard result survives without remote invocation.
        expect(r.proposals.single.value, '源氏物語');
        expect(r.providerState, StructuredProviderState.unavailable);
      }
      expect(remote.calls, 0);
    },
  );
  test('available local provider receives only unresolved fields', () async {
    // Given a ready local provider and an already extracted title.
    final local = _Provider();
    // When the caller also requests an unresolved annotation field.
    final r = await const StructuredCandidateService().supplement(
      sources: [source()],
      fields: {'title', 'annotationText'},
      standard: [proposal()],
      provider: local,
    );
    // Then local generation receives only that unresolved field.
    expect(local.fields, {'annotationText'});
    expect(r.providerState, StructuredProviderState.available);
    expect(r.proposals.map((p) => p.fieldId), ['title', 'annotationText']);
  });
  test(
    'unavailable and malformed local outputs retain deterministic baseline',
    () async {
      for (final p in [
        _Provider(state: StructuredProviderState.unavailable),
        _Provider(bad: true),
      ]) {
        // Given an unavailable provider or one returning a forbidden resolved field.
        // When supplementation is attempted for the unresolved annotation only.
        final r = await const StructuredCandidateService().supplement(
          sources: [source()],
          fields: {'title', 'annotationText'},
          standard: [proposal()],
          provider: p,
        );
        // Then failure remains explicit and the standard title stays usable.
        expect(r.proposals.map((p) => p.fieldId), ['title']);
        expect(
          r.providerState,
          p.bad
              ? StructuredProviderState.failed
              : StructuredProviderState.unavailable,
        );
        expect(r.reason, isNotEmpty);
      }
    },
  );
}

class _Provider implements StructuredCandidateProvider {
  _Provider({
    this.local = true,
    this.bad = false,
    this.state = StructuredProviderState.available,
  });
  final bool local;
  final bool bad;
  final StructuredProviderState state;
  int calls = 0;
  Set<String>? fields;
  @override
  String get id => 'local';
  @override
  bool get runsLocally => local;
  @override
  Future<StructuredProviderState> probe(
    List<StructuredTextSource> sources,
    Set<String> fields,
  ) async {
    calls++;
    return state;
  }

  @override
  Future<List<StructuredFieldProposal>> propose(
    List<StructuredTextSource> sources,
    Set<String> fields,
  ) async {
    this.fields = fields;
    return [
      proposal(
        id: 'local-proposal',
        field: bad ? 'title' : 'annotationText',
        provider: id,
      ),
    ];
  }
}
