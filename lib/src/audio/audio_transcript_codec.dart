import '../capture/capture_material.dart';
import 'audio_capture.dart';
import 'audio_transcript.dart';

/// Strict version 1 JSON for audio originals, reports and editable histories.
abstract final class AudioTranscriptCodec {
  /// Returns detached original JSON, including its top-level schema version.
  static Map<String, Object?> encodeOriginal(OriginalAudio original) => {
    'version': 1,
    'material': _detach(original.material.toJson()),
    'durationMilliseconds': original.durationMilliseconds,
  };

  /// Decodes exactly the original schema without migration or automatic writes.
  static OriginalAudio decodeOriginal(Map<String, Object?> json) => _decode(() {
    final map = _object(json, {'version', 'material', 'durationMilliseconds'});
    _version(map);
    final material = _map(map['material']);
    _time(material['capturedAt']);
    return OriginalAudio(
      material: CaptureMaterialReference.fromJson(material),
      durationMilliseconds: _int(map['durationMilliseconds']),
    );
  });

  /// Returns detached report JSON, preserving exact text and extension values.
  static Map<String, Object?> encodeReport(AudioTranscriptReport report) => {
    'version': 1,
    'id': report.id,
    'original': encodeOriginal(report.original),
    'providerId': report.providerId,
    'locale': report.locale,
    'startedAt': report.startedAt.toIso8601String(),
    'completedAt': report.completedAt.toIso8601String(),
    'elapsedMilliseconds': report.elapsedMilliseconds,
    'status': report.status.name,
    'text': report.text,
    'errorCode': report.errorCode,
    'errorMessage': report.errorMessage,
    'extensions': _detach(report.extensions),
  };

  /// Decodes the exact report keys, types, enums, times and provenance.
  static AudioTranscriptReport decodeReport(Map<String, Object?> json) =>
      _decode(() {
        final map = _object(json, {
          'version',
          'id',
          'original',
          'providerId',
          'locale',
          'startedAt',
          'completedAt',
          'elapsedMilliseconds',
          'status',
          'text',
          'errorCode',
          'errorMessage',
          'extensions',
        });
        _version(map);
        return AudioTranscriptReport(
          id: _string(map['id']),
          original: decodeOriginal(_map(map['original'])),
          providerId: _string(map['providerId']),
          locale: _string(map['locale']),
          startedAt: _time(map['startedAt']),
          completedAt: _time(map['completedAt']),
          elapsedMilliseconds: _int(map['elapsedMilliseconds']),
          status: _enum(map['status'], AudioTranscriptStatus.values),
          text: _nullableString(map['text']),
          errorCode: _nullableString(map['errorCode']),
          errorMessage: _nullableString(map['errorMessage']),
          extensions: _map(map['extensions']),
        );
      });

  /// Returns detached review JSON with all retained reports and revisions.
  static Map<String, Object?> encode(AudioTranscriptReview review) => {
    'version': 1,
    'original': encodeOriginal(review.original),
    'reports': review.reports.map(encodeReport).toList(),
    'revisions': [
      for (final revision in review.revisions)
        {
          'text': revision.text,
          'recordedAt': revision.recordedAt.toIso8601String(),
          'source': revision.source.name,
          'reportId': revision.reportId,
        },
    ],
  };

  /// Decodes exactly version 1 and rejects malformed or contradictory history.
  static AudioTranscriptReview decode(Map<String, Object?> json) => _decode(() {
    final map = _object(json, {'version', 'original', 'reports', 'revisions'});
    _version(map);
    return AudioTranscriptReview(
      original: decodeOriginal(_map(map['original'])),
      reports: _list(map['reports']).map((value) => decodeReport(_map(value))),
      revisions: _list(map['revisions']).map((value) {
        final revision = _object(value, {
          'text',
          'recordedAt',
          'source',
          'reportId',
        });
        return TranscriptRevision(
          text: _string(revision['text']),
          recordedAt: _time(revision['recordedAt']),
          source: _enum(revision['source'], TranscriptRevisionSource.values),
          reportId: _nullableString(revision['reportId']),
        );
      }),
    );
  });
}

T _decode<T>(T Function() action) {
  try {
    return action();
  } on ArgumentError catch (error) {
    throw FormatException('Invalid audio value: $error');
  }
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Expected a string-keyed object');
  }
  return Map<String, Object?>.from(value);
}

Map<String, Object?> _object(Object? value, Set<String> keys) {
  final map = _map(value);
  if (map.length != keys.length || !map.keys.every(keys.contains)) {
    throw const FormatException('Missing or unknown audio keys');
  }
  return map;
}

void _version(Map<String, Object?> map) {
  if (map['version'] is! int || map['version'] != 1) {
    throw const FormatException('Unsupported audio version');
  }
}

String _string(Object? value) {
  if (value is! String) throw const FormatException('Expected a string');
  return value;
}

String? _nullableString(Object? value) => value == null ? null : _string(value);
int _int(Object? value) {
  if (value is! int) throw const FormatException('Expected an integer');
  return value;
}

List<Object?> _list(Object? value) {
  if (value is! List) throw const FormatException('Expected a list');
  return List<Object?>.of(value);
}

T _enum<T extends Enum>(Object? value, List<T> values) {
  final name = _string(value);
  for (final item in values) {
    if (item.name == name) return item;
  }
  throw FormatException('Unknown audio enum $name');
}

DateTime _time(Object? value) {
  final text = _string(value);
  final parsed = DateTime.tryParse(text);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != text) {
    throw const FormatException('Expected a canonical UTC timestamp');
  }
  return parsed;
}

Object? _detach(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key as String: _detach(entry.value),
    };
  }
  if (value is List) return value.map(_detach).toList();
  return value;
}
