import '../audio/audio_transcript.dart';
import 'capture_material.dart';
import 'image_region.dart';
import 'recognition_configuration.dart';

/// Explicit origin of human-retained text, separate from raw provider output.
enum RegionTextOrigin { manual, ocr, ai, transcript }

/// One exact immutable text revision, including an intentional empty clear.
final class RegionTextRevision {
  /// Validates the source-field shape; entries resolve source identities.
  RegionTextRevision({required String id, required this.regionRevision,
    required this.text, required DateTime recordedAt, required this.origin,
    String? sourceReportId, String? audioMaterialId, this.transcriptRevisionIndex,
    this.sourceConfirmed = false}) : id = _token(id), recordedAt = recordedAt.toUtc(),
      sourceReportId = sourceReportId == null ? null : _token(sourceReportId),
      audioMaterialId = audioMaterialId == null ? null : _token(audioMaterialId) {
    if (regionRevision <= 0 || (transcriptRevisionIndex != null && transcriptRevisionIndex! < 0)) {
      throw ArgumentError('Invalid region text revision');
    }
    final valid = switch (origin) {
      RegionTextOrigin.manual => sourceReportId == null && audioMaterialId == null && transcriptRevisionIndex == null,
      RegionTextOrigin.ocr || RegionTextOrigin.ai => sourceReportId != null && audioMaterialId == null && transcriptRevisionIndex == null,
      RegionTextOrigin.transcript => audioMaterialId != null && ((sourceReportId != null) != (transcriptRevisionIndex != null)),
    };
    if (!valid) throw ArgumentError('Text source fields do not match origin');
  }
  /// Safe identity unique across both text histories in an entry.
  final String id;
  /// Exact selected region revision.
  final int regionRevision;
  /// Exact caller text; never trimmed or generated implicitly.
  final String text;
  /// UTC revision time.
  final DateTime recordedAt;
  /// Explicit manual, image report, or audio transcript origin.
  final RegionTextOrigin origin;
  /// Extraction comparison id, or successful audio report id for transcript.
  final String? sourceReportId;
  /// Exact linked original audio id for transcript sources.
  final String? audioMaterialId;
  /// Stable retained index into the caller-owned audio correction history.
  final int? transcriptRevisionIndex;
  /// Human source-inspection intent; required for quotation adoption.
  final bool sourceConfirmed;
  /// Detached exact wire representation, including nullable source fields.
  Map<String, Object?> toJson() => {'id': id, 'regionRevision': regionRevision,
    'text': text, 'recordedAt': recordedAt.toIso8601String(), 'origin': origin.name,
    'sourceReportId': sourceReportId, 'audioMaterialId': audioMaterialId,
    'transcriptRevisionIndex': transcriptRevisionIndex, 'sourceConfirmed': sourceConfirmed};
  /// Strict exact-key decoder.
  factory RegionTextRevision.fromJson(Map<String, Object?> json) => _decode(() {
    _keys(json, {'id', 'regionRevision', 'text', 'recordedAt', 'origin', 'sourceReportId',
      'audioMaterialId', 'transcriptRevisionIndex', 'sourceConfirmed'});
    final origin = RegionTextOrigin.values.where((v) => v.name == json['origin']);
    if (origin.isEmpty || json['sourceConfirmed'] is! bool) throw const FormatException('Invalid text origin or confirmation');
    return RegionTextRevision(id: _string(json['id']), regionRevision: _integer(json['regionRevision']),
      text: _string(json['text']), recordedAt: _time(json['recordedAt']), origin: origin.single,
      sourceReportId: _nullableString(json['sourceReportId']), audioMaterialId: _nullableString(json['audioMaterialId']),
      transcriptRevisionIndex: json['transcriptRevisionIndex'] == null ? null : _integer(json['transcriptRevisionIndex']),
      sourceConfirmed: json['sourceConfirmed'] as bool);
  });
}

/// Immutable link to an existing original audio; no review or bytes duplicated.
final class RegionAudioLink {
  /// Creates a safe link to one positive region revision.
  RegionAudioLink({required String audioMaterialId, required this.regionRevision,
    required DateTime recordedAt}) : audioMaterialId = _token(audioMaterialId), recordedAt = recordedAt.toUtc() {
    if (regionRevision <= 0) throw ArgumentError('Invalid audio region revision');
  }
  /// Original audio identity owned by the caller's audio workspace.
  final String audioMaterialId;
  /// Exact region revision.
  final int regionRevision;
  /// UTC link time.
  final DateTime recordedAt;
  /// Detached exact wire representation.
  Map<String, Object?> toJson() => {'audioMaterialId': audioMaterialId,
    'regionRevision': regionRevision, 'recordedAt': recordedAt.toIso8601String()};
  /// Strict exact-key decoder.
  factory RegionAudioLink.fromJson(Map<String, Object?> json) => _decode(() {
    _keys(json, {'audioMaterialId', 'regionRevision', 'recordedAt'});
    return RegionAudioLink(audioMaterialId: _string(json['audioMaterialId']),
      regionRevision: _integer(json['regionRevision']), recordedAt: _time(json['recordedAt']));
  });
}

/// Append-only histories bound to one exact original and canonical frame.
final class ImageRegionEntry {
  /// Snapshots all lists and validates source, revision, timing and adoption links.
  ImageRegionEntry({required Iterable<ImageRegionSnapshot> snapshots,
    Iterable<ImageRegionExtraction> extractions = const [],
    Iterable<RegionTextRevision> quotations = const [],
    Iterable<RegionTextRevision> comments = const [],
    Iterable<RegionAudioLink> audioLinks = const []})
    : snapshots = List.unmodifiable(snapshots), extractions = List.unmodifiable(extractions),
      quotations = List.unmodifiable(quotations), comments = List.unmodifiable(comments),
      audioLinks = List.unmodifiable(audioLinks) {
    if (this.snapshots.isEmpty) throw ArgumentError('Region entry requires snapshots');
    final first = this.snapshots.first;
    var previous = first.source.capturedAt;
    for (var i = 0; i < this.snapshots.length; i++) {
      final s = this.snapshots[i];
      if (s.revision != i + 1 || s.regionId != first.regionId || s.source != first.source ||
          s.pixelWidth != first.pixelWidth || s.pixelHeight != first.pixelHeight ||
          s.frameVersion != first.frameVersion || s.recordedAt.isBefore(previous)) {
        throw ArgumentError('Snapshots must retain exact source and contiguous ordered revisions');
      }
      previous = s.recordedAt;
    }
    final reports = <String, ImageRegionExtraction>{};
    for (final extraction in this.extractions) {
      final region = extraction.derivation.region;
      if (reports.containsKey(extraction.id) || !_same(region.toJson(), _snapshot(region.revision).toJson())) {
        throw ArgumentError('Extraction must resolve an exact unique region revision');
      }
      reports[extraction.id] = extraction;
    }
    final audio = <String, RegionAudioLink>{};
    for (final link in this.audioLinks) {
      if (audio.containsKey(link.audioMaterialId) || link.recordedAt.isBefore(_snapshot(link.regionRevision).recordedAt)) {
        throw ArgumentError('Audio links must be unique and follow their region revision');
      }
      audio[link.audioMaterialId] = link;
    }
    final textIds = <String>{};
    void validateText(List<RegionTextRevision> history, {required bool quotation}) {
      DateTime? last;
      for (final text in history) {
        final snapshot = _snapshot(text.regionRevision);
        if (!textIds.add(text.id) || text.recordedAt.isBefore(snapshot.recordedAt) ||
            (last != null && text.recordedAt.isBefore(last)) || (quotation && !text.sourceConfirmed)) {
          throw ArgumentError('Text histories require unique ordered source-confirmed quotation revisions');
        }
        last = text.recordedAt;
        switch (text.origin) {
          case RegionTextOrigin.manual: break;
          case RegionTextOrigin.ocr:
          case RegionTextOrigin.ai:
            final extraction = reports[text.sourceReportId];
            if (extraction == null || extraction.derivation.region.revision != text.regionRevision ||
                text.recordedAt.isBefore(extraction.comparison.createdAt)) {
              throw ArgumentError('Text must resolve an earlier matching-region extraction');
            }
            final matching = extraction.comparison.runs.expand((r) => r.attempts).where((a) =>
              a.executed && (text.origin == RegionTextOrigin.ocr
                ? a.availability.capabilities.contains(RecognitionCapability.ocr) && a.result.text != null
                : (a.availability.capabilities.contains(RecognitionCapability.imageInterpretation) && a.result.interpretation != null) ||
                  (a.availability.capabilities.contains(RecognitionCapability.candidateOrganization) && a.result.candidateOrganizationCompleted)));
            if (matching.isEmpty) throw ArgumentError('Text requires executed output of its declared origin');
          case RegionTextOrigin.transcript:
            final link = audio[text.audioMaterialId];
            if (link == null || link.regionRevision != text.regionRevision || text.recordedAt.isBefore(link.recordedAt)) {
              throw ArgumentError('Transcript text must resolve the same-region audio link');
            }
        }
      }
    }
    validateText(this.quotations, quotation: true);
    validateText(this.comments, quotation: false);
  }
  /// Ordered source-bound geometry revisions.
  final List<ImageRegionSnapshot> snapshots;
  /// Unmodified raw image extraction history.
  final List<ImageRegionExtraction> extractions;
  /// Independently retained confirmed verbatim quotation revisions.
  final List<RegionTextRevision> quotations;
  /// Independently retained human comment revisions.
  final List<RegionTextRevision> comments;
  /// Existing original audio links, with no duplicated review serialization.
  final List<RegionAudioLink> audioLinks;
  /// Stable identity from the first snapshot.
  String get regionId => snapshots.first.regionId;
  ImageRegionSnapshot _snapshot(int revision) {
    if (revision <= 0 || revision > snapshots.length) throw ArgumentError('Unknown region revision');
    return snapshots[revision - 1];
  }
  /// Detached exact wire representation.
  Map<String, Object?> toJson() => {'snapshots': snapshots.map((s) => s.toJson()).toList(),
    'extractions': extractions.map((s) => s.toJson()).toList(),
    'quotations': quotations.map((s) => s.toJson()).toList(),
    'comments': comments.map((s) => s.toJson()).toList(),
    'audioLinks': audioLinks.map((s) => s.toJson()).toList()};
  /// Strict exact-key decoder and source-link validation.
  factory ImageRegionEntry.fromJson(Map<String, Object?> json) => _decode(() {
    _keys(json, {'snapshots', 'extractions', 'quotations', 'comments', 'audioLinks'});
    return ImageRegionEntry(snapshots: _list(json['snapshots']).map((v) => ImageRegionSnapshot.fromJson(_map(v))),
      extractions: _list(json['extractions']).map((v) => ImageRegionExtraction.fromJson(_map(v))),
      quotations: _list(json['quotations']).map((v) => RegionTextRevision.fromJson(_map(v))),
      comments: _list(json['comments']).map((v) => RegionTextRevision.fromJson(_map(v))),
      audioLinks: _list(json['audioLinks']).map((v) => RegionAudioLink.fromJson(_map(v))));
  });
}

/// Immutable generic region histories, independent of Book or UI semantics.
final class ImageRegionWorkspace {
  /// Creates an explicitly empty workspace or snapshots unique region histories.
  ImageRegionWorkspace({Iterable<ImageRegionEntry> regions = const []}) : regions = List.unmodifiable(regions) {
    final ids = <String>{};
    final audioIds = <String>{};
    for (final entry in this.regions) {
      if (!ids.add(entry.regionId)) throw ArgumentError('Duplicate region identity');
      for (final link in entry.audioLinks) {
        if (!audioIds.add(link.audioMaterialId)) throw ArgumentError('Audio original belongs to another region');
      }
    }
  }
  /// Immutable ordered region entries.
  final List<ImageRegionEntry> regions;

  /// Rejects deletion, reorder, source rebinding and mutation of retained history.
  static void requireRetainedPrefix(ImageRegionWorkspace old, ImageRegionWorkspace next) {
    if (old.regions.length > next.regions.length) throw ArgumentError('Cannot delete retained regions');
    for (var i = 0; i < old.regions.length; i++) {
      final a = old.regions[i];
      final b = next.regions[i];
      if (a.regionId != b.regionId ||
          !_prefix(a.snapshots.map((v) => v.toJson()).toList(), b.snapshots.map((v) => v.toJson()).toList()) ||
          !_prefix(a.extractions.map((v) => v.toJson()).toList(), b.extractions.map((v) => v.toJson()).toList()) ||
          !_prefix(a.quotations.map((v) => v.toJson()).toList(), b.quotations.map((v) => v.toJson()).toList()) ||
          !_prefix(a.comments.map((v) => v.toJson()).toList(), b.comments.map((v) => v.toJson()).toList()) ||
          !_prefix(a.audioLinks.map((v) => v.toJson()).toList(), b.audioLinks.map((v) => v.toJson()).toList())) {
        throw ArgumentError('Replacement must retain exact region history prefixes');
      }
    }
  }

  /// Resolves links against caller-owned reviews of those exact original ids.
  /// Transcript adoption must follow its actual report completion or revision.
  void validateAudioReviews(Map<String, AudioTranscriptReview> reviews) {
    for (final entry in regions) {
      for (final link in entry.audioLinks) {
        final review = reviews[link.audioMaterialId];
        if (review == null || review.original.material.id != link.audioMaterialId ||
            link.recordedAt.isBefore(review.original.material.capturedAt)) {
          throw ArgumentError('Audio link requires its exact retained original review');
        }
      }
      for (final text in [...entry.quotations, ...entry.comments]) {
        if (text.origin != RegionTextOrigin.transcript) continue;
        final review = reviews[text.audioMaterialId]!;
        if (text.sourceReportId != null) {
          final reports = review.reports.where((r) => r.id == text.sourceReportId && r.text != null);
          if (reports.isEmpty || text.recordedAt.isBefore(reports.single.completedAt)) {
            throw ArgumentError('Transcript source must resolve an earlier successful report for this original');
          }
        } else {
          final index = text.transcriptRevisionIndex!;
          if (index >= review.revisions.length || text.recordedAt.isBefore(review.revisions[index].recordedAt)) {
            throw ArgumentError('Transcript source must resolve an earlier retained correction index');
          }
        }
      }
    }
  }
}

T _decode<T>(T Function() operation) {
  try { return operation(); } on ArgumentError catch (error) { throw FormatException('Invalid region workspace: $error'); }
}
String _token(String value) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(value)) throw ArgumentError('Unsafe region workspace identity');
  return value;
}
void _keys(Map<String, Object?> json, Set<String> keys) {
  if (json.length != keys.length || !json.keys.every(keys.contains)) throw const FormatException('Invalid region workspace keys');
}
Map<String, Object?> _map(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) throw const FormatException('Expected workspace object');
  return Map<String, Object?>.from(value);
}
List<Object?> _list(Object? value) {
  if (value is! List) throw const FormatException('Expected workspace list');
  return List<Object?>.of(value);
}
String _string(Object? value) {
  if (value is! String) throw const FormatException('Expected string');
  return value;
}
String? _nullableString(Object? value) => value == null ? null : _string(value);
int _integer(Object? value) {
  if (value is! int) throw const FormatException('Expected integer');
  return value;
}
DateTime _time(Object? value) => CaptureMaterialReference.fromJson({'id': 'time',
  'mediaType': 'application/json', 'byteLength': 1, 'capturedAt': _string(value),
  'originalName': null, 'extensions': <String, Object?>{}}).capturedAt;
bool _prefix(List<Object?> old, List<Object?> next) {
  if (old.length > next.length) return false;
  for (var i = 0; i < old.length; i++) { if (!_same(old[i], next[i])) return false; }
  return true;
}
bool _same(Object? a, Object? b) {
  if (a is Map && b is Map) return a.length == b.length && a.keys.every((k) => b.containsKey(k) && _same(a[k], b[k]));
  if (a is List && b is List) return a.length == b.length && _prefix(a, b);
  return a == b && (a is! num || (a is int) == (b is int));
}
