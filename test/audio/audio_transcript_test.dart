import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  group('audio values and append-only review', () {
    test('snapshots original/input bytes and rejects invalid configuration or provenance', () {
      // Given one canonical WAV, a durable reference and mutable input.
      final bytes = PcmWaveAudio.encode(Uint8List(32000));
      final expected = Uint8List.fromList(bytes);
      final original = _original();
      // When captured and recognition snapshots are created and inputs mutate.
      final captured = CapturedAudio(bytes: bytes, capturedAt: _time.toLocal());
      final input = AudioTranscriptionInput(
        bytes: bytes,
        original: original,
        locale: 'ja-JP',
      );
      bytes[44] = 1;
      captured.bytes[44] = 2;
      input.bytes[44] = 3;
      // Then UTC and exact bytes are independent; invalid boundaries reject.
      expect(captured.bytes, orderedEquals(expected));
      expect(input.bytes, orderedEquals(expected));
      expect(captured.capturedAt.isUtc, isTrue);
      expect(input.original, same(original));
      expect(AudioRecordingConfiguration().maxDurationSeconds, 120);
      for (final limit in [0, -1, 121]) {
        expect(
          () => AudioRecordingConfiguration(maxDurationSeconds: limit),
          throwsArgumentError,
        );
      }
      expect(
        () => AudioTranscriptionInput(
          bytes: Uint8List(1),
          original: original,
          locale: 'ja-JP',
        ),
        throwsArgumentError,
      );
      expect(
        () => AudioTranscriptionInput(
          bytes: expected,
          original: original,
          locale: '../ja',
        ),
        throwsArgumentError,
      );
      expect(
        () => OriginalAudio(
          material: CaptureMaterialReference(
            id: 'image',
            mediaType: 'image/png',
            byteLength: 1,
            capturedAt: _time,
          ),
          durationMilliseconds: 1,
        ),
        throwsArgumentError,
      );
      for (final duration in [0, 120001]) {
        expect(
          () => OriginalAudio(
            material: original.material,
            durationMilliseconds: duration,
          ),
          throwsArgumentError,
        );
      }
    });

    test('first success prefills exact text and later success retains manual clear', () {
      // Given a review with no selected text and two successful exact transcripts.
      final first = _report('first', text: ' 日本語 \n');
      final second = _report('second', text: ' second ', second: 4);
      final empty = AudioTranscriptReview(original: first.original);
      // When first success prefills, correction and clear append, then recognition repeats.
      final prefilled = empty.appendReport(first);
      final corrected = prefilled.correct(' corrected ', recordedAt: _at(2));
      final cleared = corrected.correct('', recordedAt: _at(3));
      final repeated = cleared.appendReport(second);
      // Then exact user intent and all provenance survive later provider success.
      expect(prefilled.currentText, ' 日本語 \n');
      expect(
        prefilled.revisions.single.source,
        TranscriptRevisionSource.generated,
      );
      expect(corrected.currentText, ' corrected ');
      expect(repeated.currentText, '');
      expect(repeated.reports, [first, second]);
      expect(repeated.revisions.length, 3);
      expect(repeated.revisions.last.reportId, 'first');
      expect(repeated.revisions.last.source, TranscriptRevisionSource.manual);
      AudioTranscriptReview.requireRetainedPrefix(cleared, repeated);
    });

    test('explicit report selection appends exact generated text without replacing history', () {
      // Given retained generated, manual and second-success histories.
      final first = _report('first');
      final second = _report('second', text: ' 新しい \n', second: 3);
      final prior = AudioTranscriptReview(original: first.original)
          .appendReport(first)
          .correct('mine', recordedAt: _at(2))
          .appendReport(second);
      // When the caller explicitly selects the second report.
      final selected = prior.useReport('second', recordedAt: _at(5));
      // Then only a new linked revision changes current text and all prior entries remain.
      expect(prior.currentText, 'mine');
      expect(selected.currentText, ' 新しい \n');
      expect(selected.revisions.last.reportId, 'second');
      expect(selected.revisions.length, prior.revisions.length + 1);
      expect(selected.reports, prior.reports);
      AudioTranscriptReview.requireRetainedPrefix(prior, selected);
    });

    test('failed unavailable and cancelled attempts preserve text and allow manual-only entry', () {
      // Given three actual nonsuccess outcomes and a manually entered review.
      final manual = AudioTranscriptReview(original: _original())
          .correct('manual only', recordedAt: _at(0));
      // When reports append without any successful provider text.
      var next = manual;
      for (final status in [
        AudioTranscriptStatus.failed,
        AudioTranscriptStatus.unavailable,
        AudioTranscriptStatus.cancelled,
      ]) {
        next = next.appendReport(
          _report(status.name, status: status, second: next.reports.length + 1),
        );
      }
      // Then manual entry remains usable and no failure changes current or original.
      expect(next.currentText, 'manual only');
      expect(next.original, manual.original);
      expect(next.revisions, manual.revisions);
      expect(next.reports.map((report) => report.status), [
        AudioTranscriptStatus.failed,
        AudioTranscriptStatus.unavailable,
        AudioTranscriptStatus.cancelled,
      ]);
      expect(
        () => next.useReport('failed', recordedAt: _at(5)),
        throwsArgumentError,
      );
    });

    test(
      'reports extensions histories and equality are immutable exact values',
      () {
        // Given mutable nested extension input and mutable history collections.
        final extension = <String, Object?>{
          'list': <Object?>[' 日本語 ', null, true, 2],
        };
        final report = _report('one', extensions: extension);
        final reports = [report];
        final revisions = [
          TranscriptRevision(
            text: '',
            recordedAt: _at(2),
            source: TranscriptRevisionSource.manual,
            reportId: report.id,
          ),
        ];
        // When caller inputs mutate after construction and equal values are compared.
        final review = AudioTranscriptReview(
          original: _original(),
          reports: reports,
          revisions: revisions,
        );
        (extension['list'] as List).clear();
        reports.clear();
        revisions.clear();
        final equal = AudioTranscriptReview(
          original: _original(),
          reports: [
            _report(
              'one',
              extensions: {
                'list': <Object?>[' 日本語 ', null, true, 2],
              },
            ),
          ],
          revisions: review.revisions,
        );
        // Then snapshots are deeply immutable and exact equal values hash equally.
        expect(review, equal);
        expect(review.hashCode, equal.hashCode);
        expect(review.reports.single.extensions['list'], [
          ' 日本語 ',
          null,
          true,
          2,
        ]);
        expect(() => review.reports.clear(), throwsUnsupportedError);
        expect(() => review.revisions.clear(), throwsUnsupportedError);
        expect(() => report.extensions['new'] = true, throwsUnsupportedError);
        expect(
          () => (report.extensions['list'] as List).clear(),
          throwsUnsupportedError,
        );
        expect(_report('different'), isNot(report));
      },
    );

    test(
      'rejects invalid report status identity locale and clock combinations',
      () {
        // Given a valid original and constructors violating report invariants.
        final original = _original();
        AudioTranscriptReport construct({
          String id = 'id',
          String provider = 'provider',
          String locale = 'ja-JP',
          AudioTranscriptStatus status = AudioTranscriptStatus.success,
          String? text = 'ok',
          String? code,
          String? message,
          int elapsed = 0,
          DateTime? start,
          DateTime? end,
        }) => AudioTranscriptReport(
          id: id,
          original: original,
          providerId: provider,
          locale: locale,
          startedAt: start ?? _at(0),
          completedAt: end ?? _at(1),
          elapsedMilliseconds: elapsed,
          status: status,
          text: text,
          errorCode: code,
          errorMessage: message,
        );
        // When each invalid public value is supplied without silent normalization.
        final invalid = <AudioTranscriptReport Function()>[
          () => construct(id: '../id'),
          () => construct(provider: 'a/b'),
          () => construct(locale: ''),
          () => construct(text: ' \n'),
          () => construct(text: null),
          () => construct(code: 'error'),
          () => construct(message: 'error'),
          () => construct(elapsed: -1),
          () => construct(start: _time.subtract(const Duration(seconds: 1))),
          () => construct(start: _at(2), end: _at(1)),
          () => construct(status: AudioTranscriptStatus.failed, text: null),
          () => construct(status: AudioTranscriptStatus.failed, code: 'error'),
          () => construct(
            status: AudioTranscriptStatus.failed,
            text: null,
            code: ' ',
          ),
        ];
        // Then each violation is an observable constructor error.
        for (final action in invalid) {
          expect(action, throwsArgumentError);
        }
        expect(
          () => TranscriptRevision(
            text: 'generated',
            recordedAt: _at(1),
            source: TranscriptRevisionSource.generated,
          ),
          throwsArgumentError,
        );
      },
    );

    test('rejects duplicate foreign unordered and contradictory report/revision links', () {
      // Given valid reports plus attempts and revisions with wrong provenance.
      final first = _report('first');
      final failed = _report(
        'failed',
        status: AudioTranscriptStatus.failed,
        second: 2,
      );
      final foreign = _report('foreign', original: _original('other'));
      // When histories contain duplicate IDs, another original, clocks or mismatched text.
      final invalid = <AudioTranscriptReview Function()>[
        () => AudioTranscriptReview(
          original: _original(),
          reports: [first, first],
        ),
        () => AudioTranscriptReview(original: _original(), reports: [foreign]),
        () => AudioTranscriptReview(
          original: _original(),
          reports: [failed, first],
        ),
        () => AudioTranscriptReview(
          original: _original(),
          reports: [first],
          revisions: [
            TranscriptRevision(
              text: 'wrong',
              recordedAt: _at(2),
              source: TranscriptRevisionSource.generated,
              reportId: 'first',
            ),
          ],
        ),
        () => AudioTranscriptReview(
          original: _original(),
          reports: [failed],
          revisions: [
            TranscriptRevision(
              text: '',
              recordedAt: _at(4),
              source: TranscriptRevisionSource.manual,
              reportId: 'failed',
            ),
          ],
        ),
        () => AudioTranscriptReview(
          original: _original(),
          revisions: [
            TranscriptRevision(
              text: '',
              recordedAt: _at(1),
              source: TranscriptRevisionSource.manual,
              reportId: 'missing',
            ),
          ],
        ),
        () => AudioTranscriptReview(
          original: _original(),
          revisions: [
            TranscriptRevision(
              text: 'a',
              recordedAt: _at(2),
              source: TranscriptRevisionSource.manual,
            ),
            TranscriptRevision(
              text: 'b',
              recordedAt: _at(1),
              source: TranscriptRevisionSource.manual,
            ),
          ],
        ),
      ];
      // Then no broken source link or reordered clock is accepted.
      for (final action in invalid) {
        expect(action, throwsArgumentError);
      }
    });

    test('rejects dropped rewritten or foreign retained prefixes', () {
      // Given a successful report with an exact retained manual revision.
      final prior = AudioTranscriptReview(original: _original())
          .appendReport(_report('one'))
          .correct('kept', recordedAt: _at(2));
      // When a replacement drops history, rewrites a report/revision or changes original.
      final replacements = [
        AudioTranscriptReview(original: _original()),
        AudioTranscriptReview(
          original: _original(),
          reports: prior.reports,
          revisions: prior.revisions.take(1),
        ),
        AudioTranscriptReview(original: _original())
            .appendReport(_report('one', text: 'rewrite')),
        AudioTranscriptReview(original: _original('other')),
      ];
      // Then retained provenance cannot be truncated or silently rewritten.
      for (final next in replacements) {
        expect(
          () => AudioTranscriptReview.requireRetainedPrefix(prior, next),
          throwsArgumentError,
        );
      }
      AudioTranscriptReview.requireRetainedPrefix(prior, prior);
      expect(prior.currentText, 'kept');
    });
  });
}

final _time = DateTime.utc(2026, 10, 9);
DateTime _at(int second) => _time.add(Duration(seconds: second));
OriginalAudio _original([String id = 'original']) => OriginalAudio(
  material: CaptureMaterialReference(
    id: id,
    mediaType: 'audio/wav',
    byteLength: 32044,
    capturedAt: _time,
  ),
  durationMilliseconds: 1000,
);
AudioTranscriptReport _report(
  String id, {
  String text = ' exact ',
  AudioTranscriptStatus status = AudioTranscriptStatus.success,
  int second = 0,
  OriginalAudio? original,
  Map<String, Object?> extensions = const {},
}) => AudioTranscriptReport(
  id: id,
  original: original ?? _original(),
  providerId: 'provider',
  locale: 'ja-JP',
  startedAt: _at(second),
  completedAt: _at(second + 1),
  elapsedMilliseconds: 1,
  status: status,
  text: status == AudioTranscriptStatus.success ? text : null,
  errorCode: status == AudioTranscriptStatus.success ? null : 'actualCode',
  errorMessage: status == AudioTranscriptStatus.success
      ? null
      : 'actual diagnostic',
  extensions: extensions,
);
