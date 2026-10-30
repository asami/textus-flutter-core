import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  group('generated draft source and request', () {
    test('image bytes and nested exact provenance are immutable snapshots', () {
      // Given caller-owned image bytes and nested Japanese origin metadata.
      final bytes = Uint8List.fromList([1, 2, 3]);
      final origins = <Object?>[
        <String, Object?>{'report': '文字起こし報告', 'index': 2},
      ];
      final metadata = <String, Object?>{'origins': origins};
      final source = GeneratedDraftSource(
        id: '領域画像',
        materialId: '切り出し画像',
        revision: '改訂一',
        kind: GeneratedDraftSourceKind.image,
        parentMaterialId: '原画像',
        regionId: '領域一',
        regionRevision: 3,
        metadata: metadata,
      );
      // When a request captures them and the caller later changes its buffers.
      final request = GeneratedDraftRequest(
        id: '画像試行一',
        operation: GeneratedDraftOperation.imageDescription,
        source: source,
        imageBytes: bytes,
      );
      bytes[0] = 99;
      (origins.single as Map<String, Object?>)['index'] = 9;
      origins.clear();
      metadata.clear();
      // Then neither external edits nor exposed collections rewrite the input.
      expect(request.imageBytes, orderedEquals([1, 2, 3]));
      expect(source.metadata, {
        'origins': [
          {'report': '文字起こし報告', 'index': 2},
        ],
      });
      expect(() => request.imageBytes![0] = 4, throwsUnsupportedError);
      expect(() => source.metadata['extra'] = true, throwsUnsupportedError);
      final retained = source.metadata['origins'] as List;
      expect(() => retained.add(null), throwsUnsupportedError);
      expect(() => (retained.single as Map)['index'] = 4,
          throwsUnsupportedError);
      expect(request.source, same(source));
      expect(request.language, 'ja');
      expect(GeneratedDraftRequest.outputTokenLimit, 512);
      expect(GeneratedDraftRequest.maxOutputCharacters, 2048);
    });

    test('text summary retains whitespace and never needs a dummy image', () {
      // Given exact retained Unicode text including surrounding whitespace.
      const text = '  日本語の原文😀\n';
      final source = _textSource(text: text);
      // When a text-only request is constructed and its source is reloaded.
      final request = GeneratedDraftRequest(
        id: 'text-request',
        operation: GeneratedDraftOperation.textSummary,
        source: source,
      );
      final reloaded = GeneratedDraftSource.fromJson(_detached(source.toJson()));
      // Then exact raw text and provenance survive without image bytes.
      expect(request.imageBytes, isNull);
      expect(reloaded.text, text);
      expect(reloaded.toJson(), source.toJson());
    });

    final malformedSources = <String, GeneratedDraftSource Function()>{
      'blank identity': () => _textSource(id: ' '),
      'trimmed identity': () => _textSource(id: ' source'),
      'NUL identity': () => _textSource(id: 'source\u0000id'),
      'blank text': () => _textSource(text: '\n  '),
      'image carrying text': () => GeneratedDraftSource(
        id: 'image', materialId: 'material', revision: '1',
        kind: GeneratedDraftSourceKind.image, text: '原文',
      ),
      'text without text': () => GeneratedDraftSource(
        id: 'text', materialId: 'material', revision: '1',
        kind: GeneratedDraftSourceKind.text,
      ),
      'region without revision': () => GeneratedDraftSource(
        id: 'image', materialId: 'material', revision: '1',
        kind: GeneratedDraftSourceKind.image, regionId: 'region',
        parentMaterialId: 'parent',
      ),
      'revision without region': () => GeneratedDraftSource(
        id: 'image', materialId: 'material', revision: '1',
        kind: GeneratedDraftSourceKind.image, regionRevision: 1,
      ),
      'zero region revision': () => GeneratedDraftSource(
        id: 'image', materialId: 'material', revision: '1',
        kind: GeneratedDraftSourceKind.image, regionId: 'region',
        regionRevision: 0, parentMaterialId: 'parent',
      ),
      'image region without parent': () => GeneratedDraftSource(
        id: 'image', materialId: 'material', revision: '1',
        kind: GeneratedDraftSourceKind.image, regionId: 'region',
        regionRevision: 1,
      ),
      'nonfinite metadata': () => _textSource(metadata: {'value': double.nan}),
      'non-JSON metadata': () => _textSource(metadata: {'value': _time}),
      'nonstring nested key': () => _textSource(metadata: {'value': {1: 'x'}}),
      'cyclic metadata': () {
        final cycle = <Object?>[];
        cycle.add(cycle);
        return _textSource(metadata: {'value': cycle});
      },
    };
    for (final entry in malformedSources.entries) {
      test('rejects ${entry.key} before it becomes source provenance', () {
        // Given a source construction with this malformed origin or payload.
        final construct = entry.value;
        // When the caller tries to retain that source.
        void retain() => construct();
        // Then invalid provenance fails explicitly at the public boundary.
        expect(retain, throwsArgumentError);
      });
    }

    test('rejects mismatched operations, missing bytes and text image routes', () {
      // Given genuine text and image sources rather than dummy image payloads.
      final text = _textSource();
      final image = _imageSource();
      // When requests pair an operation with an incompatible source or bytes.
      final invalid = <GeneratedDraftRequest Function()>[
        () => GeneratedDraftRequest(id: 'a',
          operation: GeneratedDraftOperation.imageDescription, source: text,
          imageBytes: Uint8List.fromList([1])),
        () => GeneratedDraftRequest(id: 'b',
          operation: GeneratedDraftOperation.imageDescription, source: image),
        () => GeneratedDraftRequest(id: 'c',
          operation: GeneratedDraftOperation.imageDescription, source: image,
          imageBytes: Uint8List(0)),
        () => GeneratedDraftRequest(id: 'd',
          operation: GeneratedDraftOperation.textSummary, source: image),
        () => GeneratedDraftRequest(id: 'e',
          operation: GeneratedDraftOperation.textSummary, source: text,
          imageBytes: Uint8List.fromList([1])),
        () => GeneratedDraftRequest(id: 'f', language: ' ja',
          operation: GeneratedDraftOperation.textSummary, source: text),
      ];
      // Then each incompatible invocation is rejected before any provider work.
      for (final construct in invalid) {
        expect(construct, throwsArgumentError);
      }
    });
  });

  group('generated draft durable workspace', () {
    for (final operation in [
      GeneratedDraftOperation.textProofreading,
      GeneratedDraftOperation.textReadability,
    ]) {
      test('${operation.name} retains exact text without image bytes', () {
        // Given exact selected Japanese text with whitespace and Unicode.
        const text = ' \n「引用😀」と個人の注釈 e\u0301。\t ';
        final source = _textSource(text: text);
        // When the selected operation captures a source reloaded from JSON.
        final request = GeneratedDraftRequest(
          id: operation.name,
          operation: operation,
          source: GeneratedDraftSource.fromJson(_detached(source.toJson())),
        );
        // Then source spelling and identity are exact and no image is invented.
        expect(request.operation, operation);
        expect(request.source.text, text);
        expect(request.source.toJson(), source.toJson());
        expect(request.imageBytes, isNull);
      });

      test('${operation.name} rejects blank text, images and any image bytes', () {
        // Given this text operation and invalid source or byte combinations.
        final invalid = <GeneratedDraftRequest Function()>[
          for (final text in ['', ' \n\t '])
            () => GeneratedDraftRequest(
              id: 'blank', operation: operation,
              source: _textSource(text: text),
            ),
          () => GeneratedDraftRequest(
            id: 'image', operation: operation, source: _imageSource(),
          ),
          for (final bytes in [Uint8List(0), Uint8List.fromList([1])])
            () => GeneratedDraftRequest(
              id: 'bytes', operation: operation,
              source: _textSource(), imageBytes: bytes,
            ),
        ];
        for (final construct in invalid) {
          // When an incompatible text request is constructed.
          // Then it fails before any provider can receive it.
          expect(construct, throwsArgumentError);
        }
      });
    }

    test('new text operations append to exact v2 image and summary schema1 history', () {
      // Given retained v2 attempts for both original operations in a v1 workspace.
      Map<String, Object?> evidence(GeneratedDraftOperation operation, String template) {
        final base = _attempt(operation.name).toJson();
        return {
          ...base,
          'operation': operation.name,
          'source': operation == GeneratedDraftOperation.imageDescription
              ? _imageSource().toJson() : _textSource().toJson(),
          'promptTemplate': template,
          'availability': {..._availability().toJson(), 'operation': operation.name},
        };
      }
      final historicalJson = {
        'schemaVersion': 1,
        'attempts': [
          evidence(GeneratedDraftOperation.imageDescription, 'textus.generated-draft.ja.v2'),
          evidence(GeneratedDraftOperation.textSummary, 'textus.generated-draft.ja.v2'),
        ],
        'decisions': <Object?>[],
      };
      final historical = GeneratedDraftWorkspace.fromJson(_detached(historicalJson));
      // When both new operations are appended and the whole history is reloaded.
      var appended = historical;
      for (final operation in [
        GeneratedDraftOperation.textProofreading,
        GeneratedDraftOperation.textReadability,
      ]) {
        appended = appended.append(GeneratedDraftAttempt.fromJson(
          evidence(operation, 'textus.generated-draft.ja.v3'),
        ));
      }
      final restored = GeneratedDraftWorkspace.fromJson(_detached(appended.toJson()));
      // Then all operations round-trip under the unchanged schema and historical prefix.
      expect(historical.toJson(), historicalJson);
      expect(restored.toJson(), appended.toJson());
      expect(restored.toJson().keys.toSet(), {'schemaVersion', 'attempts', 'decisions'});
      expect(restored.toJson()['schemaVersion'], 1);
      expect(restored.attempts.map((attempt) => attempt.operation), GeneratedDraftOperation.values);
      expect(restored.attempts.take(2).map((attempt) => attempt.promptTemplate),
          everyElement('textus.generated-draft.ja.v2'));
      expect(restored.attempts.last.toJson().keys.toSet(), historical.attempts.last.toJson().keys.toSet());
      expect(() => GeneratedDraftWorkspace.requireRetainedPrefix(historical, restored), returnsNormally);
      expect(() => GeneratedDraftAttempt.fromJson({
        ...restored.attempts.last.toJson(), 'revisionProposal': true,
      }), throwsFormatException);
      expect(() => restored.append(GeneratedDraftAttempt.fromJson({
        ...evidence(GeneratedDraftOperation.textReadability, 'textus.generated-draft.ja.v3'),
        'id': 'rewritten-source',
        'source': _textSource(text: '別の原文').toJson(),
      })), throwsArgumentError);
    });

    test('Japanese raw data and all explicit decisions survive detached JSON', () {
      // Given five exact derived drafts with retained Japanese origin metadata.
      const input = ' \n原文😀、表記を変えない。  ';
      const output = '\n 生成された説明😀。 \n';
      final source = _textSource(
        text: input,
        metadata: {
          'transcript': {'reportId': '報告一', 'revisionIndex': 2},
          'annotation': ['注記一', null, true, 1.5],
        },
      );
      final attempts = List.generate(5,
        (index) => _attempt('attempt-$index', source: source, rawText: output));
      final mutableDecisions = <GeneratedDraftDecision>[];
      final before = GeneratedDraftWorkspace(
        attempts: attempts, decisions: mutableDecisions);
      // When accept, edit, explicit empty clear and discard are separately recorded.
      final decided = before
          .decide(_decision('attempt-0', GeneratedDraftDecisionKind.accept))
          .decide(_decision('attempt-1', GeneratedDraftDecisionKind.edit,
              editedText: ' 編集後の日本語😀 \n'))
          .decide(_decision('attempt-2', GeneratedDraftDecisionKind.edit,
              editedText: ''))
          .decide(_decision('attempt-3', GeneratedDraftDecisionKind.discard));
      final reloaded = GeneratedDraftWorkspace.fromJson(
        _detached(decided.toJson()));
      attempts.clear();
      mutableDecisions.add(_decision('attempt-4', GeneratedDraftDecisionKind.accept));
      // Then product history is detached, raw input/output unchanged, one draft pending.
      expect(reloaded.toJson(), decided.toJson());
      expect(before.attempts, hasLength(5));
      expect(before.decisions, isEmpty);
      expect(before.pending.map((attempt) => attempt.id),
          orderedEquals(List.generate(5, (index) => 'attempt-$index')));
      expect(reloaded.pending.map((attempt) => attempt.id), ['attempt-4']);
      expect(reloaded.attempts.every((attempt) => attempt.source.text == input),
          isTrue);
      expect(reloaded.attempts.every((attempt) => attempt.rawText == output),
          isTrue);
      expect(reloaded.decisions.map((decision) => decision.kind), [
        GeneratedDraftDecisionKind.accept, GeneratedDraftDecisionKind.edit,
        GeneratedDraftDecisionKind.edit, GeneratedDraftDecisionKind.discard,
      ]);
      expect(reloaded.decisions[1].editedText, ' 編集後の日本語😀 \n');
      expect(reloaded.decisions[2].editedText, '');
      expect(() => reloaded.attempts.clear(), throwsUnsupportedError);
      expect(() => reloaded.decisions.clear(), throwsUnsupportedError);
      expect(reloaded.toJson().containsKey('imageBytes'), isFalse);
      expect(reloaded.attempts.first.toJson().containsKey('imageBytes'), isFalse);
    });

    test('map insertion order does not rewrite exact source or retained prefix', () {
      // Given a retained source with nested JSON provenance.
      final source = _textSource(metadata: {
        'a': 1, 'b': {'x': true, 'y': [null, '日本語']},
      });
      final first = _attempt('first', source: source);
      final previous = GeneratedDraftWorkspace(attempts: [first]);
      final reordered = _textSource(metadata: {
        'b': {'y': [null, '日本語'], 'x': true}, 'a': 1,
      });
      // When reloaded product values reorder only map keys and append a new attempt.
      final equivalent = _attempt('first', source: reordered);
      final next = GeneratedDraftWorkspace(attempts: [
        equivalent, _attempt('second', source: source),
      ]);
      // Then semantic source identity and exact history prefix remain valid.
      expect(() => GeneratedDraftWorkspace.requireRetainedPrefix(previous, next),
          returnsNormally);
      expect(next.pending.map((attempt) => attempt.id), ['first', 'second']);
      expect(previous.attempts, hasLength(1));
    });

    test('rejects duplicate attempts, changed sources and invalid decisions', () {
      // Given successful, failed and canceled attempts with exact source identity.
      final success = _attempt('success');
      final failed = _attempt('failed', status: GeneratedDraftStatus.failed);
      final canceled = _attempt('canceled', status: GeneratedDraftStatus.canceled);
      final workspace = GeneratedDraftWorkspace(attempts: [success, failed, canceled]);
      // When histories reuse IDs, change source data, or record invalid intent.
      final invalid = <void Function()>[
        () => workspace.append(success),
        () => workspace.append(_attempt('changed-text',
            source: _textSource(text: '別の原文'))),
        () => workspace.append(_attempt('changed-origin',
            source: _textSource(metadata: {'report': '別の報告'}))),
        () => workspace.decide(_decision('missing', GeneratedDraftDecisionKind.accept)),
        () => workspace.decide(_decision('failed', GeneratedDraftDecisionKind.accept)),
        () => workspace.decide(_decision('canceled', GeneratedDraftDecisionKind.edit,
            editedText: '編集')),
        () => workspace.decide(GeneratedDraftDecision(attemptId: 'success',
            kind: GeneratedDraftDecisionKind.accept, recordedAt: _time)),
        () => workspace.decide(_decision('success', GeneratedDraftDecisionKind.accept))
            .decide(_decision('success', GeneratedDraftDecisionKind.discard)),
      ];
      // Then only successful undecided attempts can receive one timely decision.
      for (final change in invalid) {
        expect(change, throwsArgumentError);
      }
      expect(workspace.pending.map((attempt) => attempt.id), ['success']);
    });

    test('retained histories reject rewrite, deletion and reorder of both lists', () {
      // Given two decided successful products in their retained order.
      final first = _attempt('first');
      final second = _attempt('second');
      final accept = _decision('first', GeneratedDraftDecisionKind.accept);
      final discard = _decision('second', GeneratedDraftDecisionKind.discard);
      final previous = GeneratedDraftWorkspace(attempts: [first, second],
          decisions: [accept, discard]);
      // When a consumer tries valid standalone workspaces that erase retained values.
      final rewrites = [
        GeneratedDraftWorkspace(attempts: [first], decisions: [accept]),
        GeneratedDraftWorkspace(attempts: [second, first], decisions: [accept, discard]),
        GeneratedDraftWorkspace(attempts: [_attempt('first', rawText: '書き換え'), second],
            decisions: [accept, discard]),
        GeneratedDraftWorkspace(attempts: [first, second], decisions: [accept]),
        GeneratedDraftWorkspace(attempts: [first, second], decisions: [discard, accept]),
        GeneratedDraftWorkspace(attempts: [first, second], decisions: [
          _decision('first', GeneratedDraftDecisionKind.edit, editedText: ''), discard,
        ]),
      ];
      // Then application append-only checks reject every deletion/rewrite/reorder.
      for (final next in rewrites) {
        expect(() => GeneratedDraftWorkspace.requireRetainedPrefix(previous, next),
            throwsArgumentError);
      }
      expect(previous.decisions, [accept, discard]);
    });
  });

  group('strict generated draft codecs and result invariants', () {
    final codecs = <String, (Map<String, Object?>, Object? Function(Object?))>{
      'source': (_textSource().toJson(), GeneratedDraftSource.fromJson),
      'availability': (_availability().toJson(), GeneratedDraftAvailability.fromJson),
      'attempt': (_attempt('one').toJson(), GeneratedDraftAttempt.fromJson),
      'decision': (_decision('one', GeneratedDraftDecisionKind.accept).toJson(),
          GeneratedDraftDecision.fromJson),
      'workspace': (GeneratedDraftWorkspace().toJson(), GeneratedDraftWorkspace.fromJson),
    };
    for (final entry in codecs.entries) {
      test('${entry.key} rejects unknown, missing and nonstring keys', () {
        // Given a valid serialized public value and its exact expected key set.
        final (json, decode) = entry.value;
        final extra = <String, Object?>{...json, 'unknown': true};
        final missing = <String, Object?>{...json}..remove(json.keys.first);
        final wrongKey = <Object?, Object?>{...json, 3: 'invalid'};
        // When a consumer supplies a different object shape or a non-object.
        final invalid = <Object?>[extra, missing, wrongKey, [], null];
        // Then strict decoding rejects every incompatible shape explicitly.
        for (final value in invalid) {
          expect(() => decode(value), throwsFormatException);
        }
      });
    }

    test('rejects unsupported schema, enums, JSON types and invalid nested history', () {
      // Given detached valid values whose individual fields can be corrupted.
      final source = _textSource().toJson();
      final availability = _availability().toJson();
      final attempt = _attempt('one').toJson();
      final decision = _decision('one', GeneratedDraftDecisionKind.accept).toJson();
      final workspace = GeneratedDraftWorkspace(attempts: [_attempt('one')]).toJson();
      // When durable payloads contain unsupported identities, types or references.
      final invalid = <void Function()>[
        () => GeneratedDraftSource.fromJson({...source, 'kind': 'video'}),
        () => GeneratedDraftSource.fromJson({...source, 'revision': 1}),
        () => GeneratedDraftSource.fromJson({...source, 'text': 42}),
        () => GeneratedDraftSource.fromJson({...source, 'regionRevision': 1.0}),
        () => GeneratedDraftSource.fromJson({...source, 'metadata': []}),
        () => GeneratedDraftSource.fromJson({...source, 'metadata': {'x': double.infinity}}),
        () => GeneratedDraftAvailability.fromJson({...availability, 'operation': 'ocr'}),
        () => GeneratedDraftAvailability.fromJson({...availability, 'state': 'ready'}),
        () => GeneratedDraftAvailability.fromJson({...availability, 'modelName': 1}),
        () => GeneratedDraftAttempt.fromJson({...attempt, 'status': 'unknown'}),
        () => GeneratedDraftAttempt.fromJson({...attempt, 'cleanupFailures': [1]}),
        () => GeneratedDraftAttempt.fromJson({...attempt, 'rawText': false}),
        () => GeneratedDraftDecision.fromJson({...decision, 'kind': 'replace'}),
        () => GeneratedDraftDecision.fromJson({...decision, 'editedText': 0}),
        () => GeneratedDraftWorkspace.fromJson({...workspace, 'schemaVersion': 2}),
        () => GeneratedDraftWorkspace.fromJson({...workspace, 'schemaVersion': 1.0}),
        () => GeneratedDraftWorkspace.fromJson({...workspace, 'attempts': {}}),
        () => GeneratedDraftWorkspace.fromJson({...workspace, 'attempts': [attempt, attempt]}),
        () => GeneratedDraftWorkspace.fromJson({...workspace, 'decisions': [
          {...decision, 'attemptId': 'missing'},
        ]}),
      ];
      // Then malformed persisted data cannot silently coerce or migrate.
      for (final decode in invalid) {
        expect(decode, throwsFormatException);
      }
    });

    for (final raw in <Object?>[
      '2026-02-30T10:00:00.000Z',
      '2026-10-30T25:00:00.000Z',
      '2026-10-30T10:00:00Z',
      '2026-10-30T10:00:00.000+00:00',
      '2026-10-30T10:00:00.000',
      'not-a-date',
      42,
    ]) {
      test('rejects noncanonical or invalid UTC timestamp $raw', () {
        // Given canonical attempt and decision JSON generated by the serializers.
        final attempt = _attempt('one').toJson();
        final decision = _decision('one', GeneratedDraftDecisionKind.accept).toJson();
        // When an exact timestamp field is replaced with this incompatible value.
        void readStart() => GeneratedDraftAttempt.fromJson({...attempt, 'startedAt': raw});
        void readEnd() => GeneratedDraftAttempt.fromJson({...attempt, 'completedAt': raw});
        void readDecision() => GeneratedDraftDecision.fromJson({...decision, 'recordedAt': raw});
        // Then rollover dates, local/offset forms, missing precision and types fail.
        expect(readStart, throwsFormatException);
        expect(readEnd, throwsFormatException);
        expect(readDecision, throwsFormatException);
      });
    }

    test('success requires actual matching model, prompt, output and UTC order', () {
      // Given a valid successful attempt with an exact available-model snapshot.
      final json = _attempt('success').toJson();
      // When any success evidence is absent, contradictory or chronologically invalid.
      final invalid = [
        {...json, 'availability': null},
        {...json, 'availability': {..._availability().toJson(), 'providerId': 'other'}},
        {...json, 'availability': {..._availability().toJson(), 'language': 'en'}},
        {...json, 'availability': {..._availability().toJson(), 'operation': 'imageDescription'}},
        {...json, 'availability': {..._availability().toJson(),
          'state': 'unavailable', 'reason': 'モデル未準備'}},
        {...json, 'modelName': 'different-model'},
        {...json, 'prompt': ' '},
        {...json, 'rawText': '\n'},
        {...json, 'errorCode': 'failure'},
        {...json, 'completedAt': _time.subtract(const Duration(seconds: 1)).toIso8601String()},
        {...json, 'source': _imageSource().toJson()},
      ];
      // Then a success claim cannot load without complete consistent evidence.
      for (final value in invalid) {
        expect(() => GeneratedDraftAttempt.fromJson(value), throwsFormatException);
      }
      expect(() => _decision('success', GeneratedDraftDecisionKind.accept,
          recordedAt: DateTime(2026, 10, 30)), throwsArgumentError);
      expect(() => _decision('success', GeneratedDraftDecisionKind.edit),
          throwsArgumentError);
      expect(() => _decision('success', GeneratedDraftDecisionKind.discard,
          editedText: ''), throwsArgumentError);
    });

    test('failure evidence is exact and cleanup diagnostics are defensive', () {
      // Given an actual failed provider response with blank raw output and cleanup.
      final cleanup = ['release failed'];
      final output = GeneratedDraftProviderOutput(
        status: GeneratedDraftStatus.failed, text: ' \n', modelName: null,
        errorCode: 'nativeFailure', errorMessage: '元の説明',
        cleanupFailures: cleanup,
      );
      // When caller-owned diagnostics change and the failure is persisted/reloaded.
      cleanup.clear();
      final attempt = GeneratedDraftAttempt(
        id: 'failed', operation: GeneratedDraftOperation.textSummary,
        source: _textSource(), language: 'ja', providerId: 'fixture',
        promptTemplate: 'template-v1', startedAt: _time, completedAt: _completed,
        status: output.status, rawText: output.text, modelName: output.modelName,
        errorCode: output.errorCode, errorMessage: output.errorMessage,
        cleanupFailures: output.cleanupFailures,
      );
      final reloaded = GeneratedDraftAttempt.fromJson(_detached(attempt.toJson()));
      // Then partial evidence survives without inventing success/model/prompt.
      expect(reloaded.rawText, ' \n');
      expect(reloaded.modelName, isNull);
      expect(reloaded.prompt, isNull);
      expect(reloaded.availability, isNull);
      expect(reloaded.errorCode, 'nativeFailure');
      expect(reloaded.errorMessage, '元の説明');
      expect(reloaded.cleanupFailures, ['release failed']);
      expect(() => output.cleanupFailures.clear(), throwsUnsupportedError);
      expect(() => reloaded.cleanupFailures.clear(), throwsUnsupportedError);
      expect(() => GeneratedDraftProviderOutput(status: GeneratedDraftStatus.success,
          text: ' ', modelName: 'model'), throwsArgumentError);
      expect(() => GeneratedDraftProviderOutput(status: GeneratedDraftStatus.failed,
          errorCode: 'failure', errorMessage: ' '), throwsArgumentError);
      expect(() => GeneratedDraftProviderOutput(status: GeneratedDraftStatus.canceled,
          errorCode: 'canceled', errorMessage: '中止', cleanupFailures: [' ']),
          throwsArgumentError);
    });

    test('availability distinguishes unknown models from actual available models', () {
      // Given an unavailable operation with an explicit reason and no model claim.
      final unavailable = GeneratedDraftAvailability(providerId: 'fixture',
        operation: GeneratedDraftOperation.textSummary, language: 'ja',
        state: GeneratedDraftAvailabilityState.unavailable, reason: '未対応端末');
      // When that truthful snapshot is serialized and independently reloaded.
      final reloaded = GeneratedDraftAvailability.fromJson(
        _detached(unavailable.toJson()));
      // Then the unknown model stays null and missing required evidence is rejected.
      expect(reloaded.modelName, isNull);
      expect(reloaded.reason, '未対応端末');
      expect(() => GeneratedDraftAvailability(providerId: 'fixture',
          operation: GeneratedDraftOperation.textSummary, language: 'ja',
          state: GeneratedDraftAvailabilityState.available), throwsArgumentError);
      expect(() => GeneratedDraftAvailability(providerId: 'fixture',
          operation: GeneratedDraftOperation.textSummary, language: 'ja',
          state: GeneratedDraftAvailabilityState.preparing), throwsArgumentError);
    });
  });
}

final _time = DateTime.utc(2026, 10, 30, 1);
final _completed = _time.add(const Duration(seconds: 1));

Object? _detached(Object? value) => jsonDecode(jsonEncode(value));

GeneratedDraftSource _textSource({
  String id = 'source',
  String text = '原文を保持する。',
  Map<String, Object?> metadata = const {},
}) => GeneratedDraftSource(id: id, materialId: '原資料', revision: 'revision-1',
  kind: GeneratedDraftSourceKind.text, text: text, metadata: metadata);

GeneratedDraftSource _imageSource() => GeneratedDraftSource(id: 'image-source',
  materialId: '画像原資料', revision: 'revision-1', kind: GeneratedDraftSourceKind.image);

GeneratedDraftAvailability _availability() => GeneratedDraftAvailability(
  providerId: 'fixture', operation: GeneratedDraftOperation.textSummary,
  language: 'ja', state: GeneratedDraftAvailabilityState.available,
  modelName: 'actual-model');

GeneratedDraftAttempt _attempt(String id, {
  GeneratedDraftSource? source,
  String rawText = '生成された要約。',
  GeneratedDraftStatus status = GeneratedDraftStatus.success,
}) => GeneratedDraftAttempt(id: id, operation: GeneratedDraftOperation.textSummary,
  source: source ?? _textSource(), language: 'ja', providerId: 'fixture',
  promptTemplate: 'template-v1', startedAt: _time, completedAt: _completed,
  status: status, availability: _availability(), prompt: ' 正確なプロンプト\n',
  modelName: 'actual-model', rawText: rawText,
  errorCode: status == GeneratedDraftStatus.success ? null : status.name,
  errorMessage: status == GeneratedDraftStatus.success ? null : '実際の失敗または中止');

GeneratedDraftDecision _decision(String attemptId, GeneratedDraftDecisionKind kind, {
  String? editedText,
  DateTime? recordedAt,
}) => GeneratedDraftDecision(attemptId: attemptId, kind: kind,
  recordedAt: recordedAt ?? _completed, editedText: editedText);
