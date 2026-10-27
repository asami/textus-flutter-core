import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  group('strict audio version 1 codec', () {
    test('roundtrips exact Unicode whitespace empty revisions extensions and values', () {
      // Given a review with exact generated Unicode, an intentional clear and opaque JSON.
      final report = _report();
      final review = AudioTranscriptReview(original: report.original)
          .appendReport(report)
          .correct('', recordedAt: _time.add(const Duration(seconds: 2)));
      // When JSON crosses a real encode/decode boundary for each top-level value.
      final encoded = AudioTranscriptCodec.encode(review);
      final decoded = AudioTranscriptCodec.decode(_wire(encoded));
      final decodedReport = AudioTranscriptCodec.decodeReport(
        _wire(AudioTranscriptCodec.encodeReport(report)),
      );
      final decodedOriginal = AudioTranscriptCodec.decodeOriginal(
        _wire(AudioTranscriptCodec.encodeOriginal(report.original)),
      );
      // Then exact values, nulls and version fields survive with value semantics.
      expect(decoded, review);
      expect(decoded.hashCode, review.hashCode);
      expect(decodedReport, report);
      expect(decodedOriginal, report.original);
      expect(decoded.currentText, '');
      expect(decoded.reports.single.text, ' 日本語\n café 😀 ');
      expect(decoded.reports.single.extensions, {
        'nested': <Object?>[null, true, 1, 1.5, ' ', <String, Object?>{}],
      });
      expect(encoded['version'], 1);
      expect((encoded['original'] as Map)['version'], 1);
      expect(((encoded['reports'] as List).single as Map)['version'], 1);
    });

    test('encoded nested maps and lists detach from immutable source data', () {
      // Given immutable original/report/review values with nested extensions.
      final report = _report();
      final review = AudioTranscriptReview(original: report.original)
          .appendReport(report);
      // When returned JSON is edited at every nested mutable layer.
      final output = AudioTranscriptCodec.encode(review);
      ((output['original'] as Map)['material'] as Map)['id'] = 'changed';
      (((output['reports'] as List).single as Map)['extensions']
              as Map)['nested'] =
          'changed';
      (output['revisions'] as List).clear();
      // Then independent subsequent encodings and exact source values remain intact.
      expect(report.original.material.id, 'original');
      expect(report.extensions['nested'], isA<List>());
      expect(review.revisions.length, 1);
      expect(
        AudioTranscriptCodec.decode(AudioTranscriptCodec.encode(review)),
        review,
      );
    });

    test('rejects unknown missing version enum and exact-type violations', () {
      // Given valid original, report and review JSON plus unsupported wire values.
      final report = _report();
      final reviewJson = AudioTranscriptCodec.encode(
        AudioTranscriptReview(original: report.original).appendReport(report),
      );
      final reportJson = AudioTranscriptCodec.encodeReport(report);
      final originalJson = AudioTranscriptCodec.encodeOriginal(report.original);
      // When every required key is removed, an extra key added, or a scalar changes type.
      for (final key in reviewJson.keys) {
        final invalid = _wire(reviewJson)..remove(key);
        expect(
          () => AudioTranscriptCodec.decode(invalid),
          throwsFormatException,
        );
      }
      for (final key in reportJson.keys) {
        final invalid = _wire(reportJson)..remove(key);
        expect(
          () => AudioTranscriptCodec.decodeReport(invalid),
          throwsFormatException,
        );
      }
      for (final key in originalJson.keys) {
        final invalid = _wire(originalJson)..remove(key);
        expect(
          () => AudioTranscriptCodec.decodeOriginal(invalid),
          throwsFormatException,
        );
      }
      final invalidReports = [
        {...reportJson, 'unknown': null},
        {...reportJson, 'version': 2},
        {...reportJson, 'version': 1.0},
        {...reportJson, 'status': 'partial'},
        {...reportJson, 'elapsedMilliseconds': 0.0},
        {...reportJson, 'id': true},
        {...reportJson, 'text': <Object?>[]},
        {...reportJson, 'errorCode': 1},
        {
          ...reportJson,
          'extensions': <int, Object?>{1: true},
        },
      ];
      // Then each malformed schema fails with FormatException instead of repair.
      for (final invalid in invalidReports) {
        expect(
          () => AudioTranscriptCodec.decodeReport(invalid),
          throwsFormatException,
        );
      }
      for (final invalid in [
        {...originalJson, 'durationMilliseconds': 1.0},
        {...originalJson, 'durationMilliseconds': 0},
        {...originalJson, 'extra': 0},
        {...originalJson, 'version': '1'},
      ]) {
        expect(
          () => AudioTranscriptCodec.decodeOriginal(invalid),
          throwsFormatException,
        );
      }
      expect(
        () => AudioTranscriptCodec.decode({...reviewJson, 'reports': null}),
        throwsFormatException,
      );
      expect(
        () => AudioTranscriptCodec.decode({...reviewJson, 'unknown': 1}),
        throwsFormatException,
      );
    });

    test('rejects noncanonical time identity provenance and revision source corruption', () {
      // Given a valid success and generated revision tied to the exact original.
      final report = _report();
      final encoded = AudioTranscriptCodec.encode(
        AudioTranscriptReview(original: report.original).appendReport(report),
      );
      // When reports/timestamps or their generated selection links are corrupted.
      final corruptions = <void Function(Map<String, Object?>)>[
        (map) => map['version'] = 0,
        (map) => (map['original'] as Map)['durationMilliseconds'] = 120001,
        (map) => ((map['original'] as Map)['material'] as Map)['capturedAt'] =
            '2026-10-09T09:00:00+09:00',
        (map) => _reportMap(map)['startedAt'] = '2026-10-09T00:00:00Z',
        (map) => _reportMap(map)['completedAt'] = '2026-02-31T00:00:00.000Z',
        (map) => _reportMap(map)['startedAt'] = '2026-10-08T00:00:00.000Z',
        (map) => _reportMap(map)['id'] = '../escape',
        (map) => _reportMap(map)['providerId'] = '/provider',
        (map) => _reportMap(map)['locale'] = 'bad locale',
        (map) => _reportMap(map)['text'] = '',
        (map) => _reportMap(map)['errorCode'] = 'error',
        (map) =>
            ((_reportMap(map)['original'] as Map)['material'] as Map)['id'] =
                'foreign',
        (map) => (map['reports'] as List).add(_wire(_reportMap(map))),
        (map) => _revisionMap(map)['source'] = 'automatic',
        (map) => _revisionMap(map)['reportId'] = null,
        (map) => _revisionMap(map)['reportId'] = 'missing',
        (map) => _revisionMap(map)['text'] = 'silently changed',
        (map) => _revisionMap(map)['recordedAt'] = '2026-10-08T00:00:00.000Z',
        (map) => _revisionMap(map)['unknown'] = 1,
      ];
      // Then exact schema and provenance errors remain observable and source JSON stays intact.
      for (final corrupt in corruptions) {
        final invalid = _wire(encoded);
        corrupt(invalid);
        expect(
          () => AudioTranscriptCodec.decode(invalid),
          throwsFormatException,
        );
      }
      expect(AudioTranscriptCodec.decode(encoded).reports.single, report);
    });

    test(
      'roundtrips nonsuccess diagnostics without selecting generated text',
      () {
        // Given every nonsuccess outcome with exact diagnostics and no selected text.
        final original = _report().original;
        // When each failed/unavailable/cancelled report is encoded and decoded.
        for (final status in [
          AudioTranscriptStatus.failed,
          AudioTranscriptStatus.unavailable,
          AudioTranscriptStatus.cancelled,
        ]) {
          final report = AudioTranscriptReport(
            id: status.name,
            original: original,
            providerId: 'provider',
            locale: 'ja-JP',
            startedAt: _time,
            completedAt: _time,
            elapsedMilliseconds: 0,
            status: status,
            errorCode: 'real-code',
            errorMessage: ' 実際の診断\n',
          );
          final review = AudioTranscriptReview(original: original)
              .appendReport(report);
          final decoded = AudioTranscriptCodec.decode(
            _wire(AudioTranscriptCodec.encode(review)),
          );
          // Then typed diagnostics survive and failure cannot create current text.
          expect(decoded.reports.single, report);
          expect(decoded.revisions, isEmpty);
          expect(decoded.currentText, isNull);
        }
      },
    );
  });
}

final _time = DateTime.utc(2026, 10, 9);
AudioTranscriptReport _report() => AudioTranscriptReport(
  id: 'report',
  original: OriginalAudio(
    material: CaptureMaterialReference(
      id: 'original',
      mediaType: 'audio/wav',
      byteLength: 32044,
      capturedAt: _time,
    ),
    durationMilliseconds: 1000,
  ),
  providerId: 'provider',
  locale: 'ja-JP',
  startedAt: _time,
  completedAt: _time.add(const Duration(seconds: 1)),
  elapsedMilliseconds: 1,
  status: AudioTranscriptStatus.success,
  text: ' 日本語\n café 😀 ',
  extensions: {
    'nested': <Object?>[null, true, 1, 1.5, ' ', <String, Object?>{}],
  },
);
Map<String, Object?> _wire(Map<String, Object?> value) =>
    Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);
Map<String, Object?> _reportMap(Map<String, Object?> value) =>
    (value['reports'] as List).single as Map<String, Object?>;
Map<String, Object?> _revisionMap(Map<String, Object?> value) =>
    (value['revisions'] as List).single as Map<String, Object?>;
