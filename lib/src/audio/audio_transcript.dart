import '../capture/capture_material.dart';
import 'audio_capture.dart';

/// Outcome of one saved-original recognition attempt.
enum AudioTranscriptStatus {
  /// Final nonblank provider text was returned.
  success,

  /// A provider failure occurred.
  failed,

  /// The exact provider/locale was not ready.
  unavailable,

  /// The operation was explicitly cancelled.
  cancelled,
}

/// Immutable provenance and diagnostics for one transcription attempt.
final class AudioTranscriptReport {
  /// Validates exact success/error rules and original/time provenance.
  AudioTranscriptReport({
    required String id,
    required this.original,
    required String providerId,
    required String locale,
    required DateTime startedAt,
    required DateTime completedAt,
    required this.elapsedMilliseconds,
    required this.status,
    this.text,
    this.errorCode,
    this.errorMessage,
    Map<String, Object?> extensions = const {},
  }) : id = _token(id),
       providerId = _token(providerId),
       locale = _locale(locale),
       startedAt = startedAt.toUtc(),
       completedAt = completedAt.toUtc(),
       extensions = CaptureMaterialReference(
         id: 'extensions',
         mediaType: 'application/json',
         byteLength: 1,
         capturedAt: startedAt,
         extensions: extensions,
       ).extensions {
    if (this.startedAt.isBefore(original.material.capturedAt) ||
        this.completedAt.isBefore(this.startedAt) ||
        elapsedMilliseconds < 0) {
      throw ArgumentError('Invalid transcript time or original provenance');
    }
    if (status == AudioTranscriptStatus.success) {
      if (text == null ||
          text!.trim().isEmpty ||
          errorCode != null ||
          errorMessage != null) {
        throw ArgumentError(
          'Success requires exact nonblank text and no errors',
        );
      }
    } else if (text != null || errorCode == null || errorCode!.trim().isEmpty) {
      throw ArgumentError('Nonsuccess requires a failure code and no text');
    }
  }

  /// Safe unique report identity.
  final String id;

  /// Exact unchanged saved original.
  final OriginalAudio original;

  /// Safe actual provider identity.
  final String providerId;

  /// Exact requested locale.
  final String locale;

  /// UTC recognition start, at or after original capture.
  final DateTime startedAt;

  /// UTC completion, at or after start.
  final DateTime completedAt;

  /// Nonnegative monotonic elapsed time.
  final int elapsedMilliseconds;

  /// Actual attempt outcome.
  final AudioTranscriptStatus status;

  /// Exact final provider text, only for success.
  final String? text;

  /// Actual nonblank failure code, only for nonsuccess.
  final String? errorCode;

  /// Optional actual failure diagnostic.
  final String? errorMessage;

  /// Deeply immutable opaque JSON metadata.
  final Map<String, Object?> extensions;

  @override
  bool operator ==(Object other) =>
      other is AudioTranscriptReport &&
      id == other.id &&
      original == other.original &&
      providerId == other.providerId &&
      locale == other.locale &&
      startedAt == other.startedAt &&
      completedAt == other.completedAt &&
      elapsedMilliseconds == other.elapsedMilliseconds &&
      status == other.status &&
      text == other.text &&
      errorCode == other.errorCode &&
      errorMessage == other.errorMessage &&
      _sameJson(extensions, other.extensions);

  @override
  int get hashCode => Object.hash(
    id,
    original,
    providerId,
    locale,
    startedAt,
    completedAt,
    elapsedMilliseconds,
    status,
    text,
    errorCode,
    errorMessage,
    _jsonHash(extensions),
  );
}

/// Origin of one append-only editable text revision.
enum TranscriptRevisionSource {
  /// Explicit caller text, including an intentional empty clear.
  manual,

  /// Exact text selected from a successful provider report.
  generated,
}

/// Immutable exact current-text history entry.
final class TranscriptRevision {
  /// Generated revisions require a safe linked report identity.
  TranscriptRevision({
    required this.text,
    required DateTime recordedAt,
    required this.source,
    String? reportId,
  }) : recordedAt = recordedAt.toUtc(),
       reportId = reportId == null ? null : _token(reportId) {
    if (source == TranscriptRevisionSource.generated && this.reportId == null) {
      throw ArgumentError('Generated text requires a report identity');
    }
  }

  /// Exact selected or manual text; empty is an intentional clear.
  final String text;

  /// UTC revision time.
  final DateTime recordedAt;

  /// Whether the caller entered text or selected provider text.
  final TranscriptRevisionSource source;

  /// Optional successful source report retained through manual edits.
  final String? reportId;

  @override
  bool operator ==(Object other) =>
      other is TranscriptRevision &&
      text == other.text &&
      recordedAt == other.recordedAt &&
      source == other.source &&
      reportId == other.reportId;

  @override
  int get hashCode => Object.hash(text, recordedAt, source, reportId);
}

/// Append-only report and user revision history for one exact original.
final class AudioTranscriptReview {
  /// Snapshots histories and rejects duplicate identities or invalid source links.
  AudioTranscriptReview({
    required this.original,
    Iterable<AudioTranscriptReport> reports = const [],
    Iterable<TranscriptRevision> revisions = const [],
  }) : reports = List.unmodifiable(reports),
       revisions = List.unmodifiable(revisions) {
    final known = <String, AudioTranscriptReport>{};
    DateTime? previousReportTime;
    for (final report in this.reports) {
      if (report.original != original ||
          known.containsKey(report.id) ||
          (previousReportTime != null &&
              report.startedAt.isBefore(previousReportTime))) {
        throw ArgumentError(
          'Reports must be unique, ordered and use this original',
        );
      }
      known[report.id] = report;
      previousReportTime = report.completedAt;
    }
    var previousTime = original.material.capturedAt;
    for (final revision in this.revisions) {
      if (revision.recordedAt.isBefore(previousTime)) {
        throw ArgumentError('Revision clock moved backwards');
      }
      previousTime = revision.recordedAt;
      final source = known[revision.reportId];
      if (revision.reportId != null &&
          (source == null ||
              source.status != AudioTranscriptStatus.success ||
              revision.recordedAt.isBefore(source.completedAt))) {
        throw ArgumentError(
          'Revision source must be an earlier successful report',
        );
      }
      if (revision.source == TranscriptRevisionSource.generated &&
          revision.text != source?.text) {
        throw ArgumentError(
          'Generated text must exactly match its source report',
        );
      }
    }
  }

  /// Unchanged original shared by all entries.
  final OriginalAudio original;

  /// Immutable ordered recognition attempt history.
  final List<AudioTranscriptReport> reports;

  /// Immutable ordered editable text history.
  final List<TranscriptRevision> revisions;

  /// Last text revision, or null when no text has ever been selected/entered.
  String? get currentText => revisions.isEmpty ? null : revisions.last.text;

  /// Adds an attempt and prefills exact first success only before any revision.
  AudioTranscriptReview appendReport(AudioTranscriptReport report) =>
      AudioTranscriptReview(
        original: original,
        reports: [...reports, report],
        revisions: [
          ...revisions,
          if (revisions.isEmpty &&
              report.status == AudioTranscriptStatus.success)
            TranscriptRevision(
              text: report.text!,
              recordedAt: report.completedAt,
              source: TranscriptRevisionSource.generated,
              reportId: report.id,
            ),
        ],
      );

  /// Appends exact caller text, preserving any selected source report identity.
  AudioTranscriptReview correct(String text, {required DateTime recordedAt}) =>
      AudioTranscriptReview(
        original: original,
        reports: reports,
        revisions: [
          ...revisions,
          TranscriptRevision(
            text: text,
            recordedAt: recordedAt,
            source: TranscriptRevisionSource.manual,
            reportId: revisions.isEmpty ? null : revisions.last.reportId,
          ),
        ],
      );

  /// Explicitly appends the exact text of one successful report.
  AudioTranscriptReview useReport(String id, {required DateTime recordedAt}) {
    final matching = reports.where((report) => report.id == id);
    if (matching.isEmpty ||
        matching.single.status != AudioTranscriptStatus.success) {
      throw ArgumentError('Select a known successful report');
    }
    return AudioTranscriptReview(
      original: original,
      reports: reports,
      revisions: [
        ...revisions,
        TranscriptRevision(
          text: matching.single.text!,
          recordedAt: recordedAt,
          source: TranscriptRevisionSource.generated,
          reportId: id,
        ),
      ],
    );
  }

  /// Rejects a replacement which changes or drops any retained history entry.
  static void requireRetainedPrefix(
    AudioTranscriptReview old,
    AudioTranscriptReview next,
  ) {
    if (old.original != next.original ||
        !_prefix(old.reports, next.reports) ||
        !_prefix(old.revisions, next.revisions)) {
      throw ArgumentError(
        'Replacement must retain exact original and history prefixes',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AudioTranscriptReview &&
      original == other.original &&
      _listEqual(reports, other.reports) &&
      _listEqual(revisions, other.revisions);

  @override
  int get hashCode =>
      Object.hash(original, Object.hashAll(reports), Object.hashAll(revisions));
}

bool _prefix(List<Object?> first, List<Object?> second) {
  if (first.length > second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

bool _listEqual(List<Object?> first, List<Object?> second) =>
    first.length == second.length && _prefix(first, second);
bool _sameJson(Object? first, Object? second) {
  if (first is Map && second is Map) {
    return first.length == second.length &&
        first.keys.every(
          (key) =>
              second.containsKey(key) && _sameJson(first[key], second[key]),
        );
  }
  if (first is List && second is List) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (!_sameJson(first[index], second[index])) return false;
    }
    return true;
  }
  return first == second &&
      (first is! num || (first is int) == (second is int));
}

int _jsonHash(Object? value) {
  if (value is Map) {
    return Object.hashAllUnordered(
      value.entries.map(
        (entry) => Object.hash(entry.key, _jsonHash(entry.value)),
      ),
    );
  }
  if (value is List) return Object.hashAll(value.map(_jsonHash));
  return value.hashCode;
}

String _token(String value) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(value)) {
    throw ArgumentError.value(value, 'id', 'unsafe identity');
  }
  return value;
}

String _locale(String value) {
  if (!RegExp(r'^[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$').hasMatch(value)) {
    throw ArgumentError.value(value, 'locale', 'invalid language tag');
  }
  return value;
}
