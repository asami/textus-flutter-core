import 'capture_material.dart';
import 'photo_capture.dart';
import 'recognition_configuration.dart';
import 'recognition_operation_context.dart';
import 'recognition_report.dart';

/// Exact version1 wire schema. Unknown data belongs only in extensions.
abstract final class RecognitionReportCodec {
  /// Validates the optional known context and returns detached version1 JSON.
  static Map<String, Object?> encode(RecognitionComparison comparison) {
    if (comparison.extensions.containsKey(RecognitionOperationContext.extensionKey)) {
      RecognitionOperationContext.fromJson(
        comparison.extensions[RecognitionOperationContext.extensionKey],
      );
    }
    return {
    'version': 1, 'id': comparison.id,
    'material': _detach(comparison.material.toJson()),
    'createdAt': comparison.createdAt.toIso8601String(),
    'runs': [for (final run in comparison.runs) {
      'desiredConfigurationId': run.desiredConfigurationId,
      'actualConfigurationId': run.actualConfigurationId,
      'actualProviderIds': List<String>.of(run.actualProviderIds),
      'fallbackReason': run.fallbackReason,
      'attempts': [for (final attempt in run.attempts) _encodeAttempt(attempt)],
    }],
    'extensions': _detach(comparison.extensions),
    };
  }

  static RecognitionComparison decode(Map<String, Object?> json) {
    try {
      final root = _object(json, {'version', 'id', 'material', 'createdAt', 'runs', 'extensions'});
      if (root['version'] is! int || root['version'] != 1) {
        throw const FormatException('Unsupported recognition report version');
      }
      final cache = <String, RecognitionProviderAttempt>{};
      final serialized = <String, Map<String, Object?>>{};
      final runs = <RecognitionRun>[];
      for (final value in _list(root['runs'])) {
        final row = _object(value, {
          'desiredConfigurationId', 'actualConfigurationId', 'actualProviderIds',
          'fallbackReason', 'attempts',
        });
        final attempts = <RecognitionProviderAttempt>[];
        for (final value in _list(row['attempts'])) {
          final map = _object(value, {
            'id', 'providerId', 'materialId', 'availability', 'startedAt',
            'elapsedMicroseconds', 'executed', 'result', 'inputAttemptIds',
          });
          final id = _string(map['id']);
          final previous = cache[id];
          if (previous != null) {
            if (!_sameJson(serialized[id], map)) {
              throw FormatException('Contradictory shared attempt $id');
            }
            attempts.add(previous);
            continue;
          }
          final micros = map['elapsedMicroseconds'];
          if (micros is! int || micros < 0) throw const FormatException('Invalid elapsed duration');
          final attempt = RecognitionProviderAttempt(
            id: id, providerId: _string(map['providerId']), materialId: _string(map['materialId']),
            availability: _availability(map['availability']), startedAt: _time(map['startedAt']),
            elapsed: Duration(microseconds: micros), executed: _bool(map['executed']),
            result: _result(map['result']),
            inputAttemptIds: _list(map['inputAttemptIds']).map(_string),
          );
          cache[id] = attempt;
          serialized[id] = map;
          attempts.add(attempt);
        }
        runs.add(RecognitionRun(
          desiredConfigurationId: _string(row['desiredConfigurationId']),
          actualConfigurationId: _nullableString(row['actualConfigurationId']),
          actualProviderIds: _list(row['actualProviderIds']).map(_string),
          fallbackReason: _nullableString(row['fallbackReason']), attempts: attempts,
        ));
      }
      return RecognitionComparison(
        id: _string(root['id']),
        material: CaptureMaterialReference.fromJson(_map(root['material'])),
        createdAt: _time(root['createdAt']), runs: runs, extensions: _map(root['extensions']),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid recognition report: $error');
    }
  }
}

Map<String, Object?> _encodeAttempt(RecognitionProviderAttempt attempt) => {
  'id': attempt.id, 'providerId': attempt.providerId, 'materialId': attempt.materialId,
  'availability': {
    'providerId': attempt.availability.providerId, 'state': attempt.availability.state.name,
    'capabilities': attempt.availability.capabilities.map((item) => item.name).toList(),
    'reason': attempt.availability.reason, 'modelName': attempt.availability.modelName,
  },
  'startedAt': attempt.startedAt.toIso8601String(),
  'elapsedMicroseconds': attempt.elapsed.inMicroseconds, 'executed': attempt.executed,
  'result': {
    'text': attempt.result.text,
    'barcodes': [for (final item in attempt.result.barcodes) {'value': item.value, 'format': item.format}],
    'barcodeCompleted': attempt.result.barcodeCompleted,
    'interpretation': attempt.result.interpretation,
    'candidates': [for (final item in attempt.result.candidates) {'kind': item.kind, 'value': item.value}],
    'candidateOrganizationCompleted': attempt.result.candidateOrganizationCompleted,
    'failures': [for (final item in attempt.result.failures) {
      'stage': item.stage.name, 'code': item.code, 'message': item.message,
    }],
  },
  'inputAttemptIds': List<String>.of(attempt.inputAttemptIds),
};

RecognitionProviderAvailability _availability(Object? value) {
  final map = _object(value, {'providerId', 'state', 'capabilities', 'reason', 'modelName'});
  final capabilities = _list(map['capabilities']).map(
    (value) => _enum(value, RecognitionCapability.values),
  ).toList();
  if (capabilities.toSet().length != capabilities.length) {
    throw const FormatException('Duplicate capability');
  }
  return RecognitionProviderAvailability(
    providerId: _string(map['providerId']), state: _enum(map['state'], RecognitionProviderState.values),
    capabilities: capabilities, reason: _nullableString(map['reason']),
    modelName: _nullableString(map['modelName']),
  );
}

ImageRecognitionResult _result(Object? value) {
  final map = _object(value, {
    'text', 'barcodes', 'barcodeCompleted', 'interpretation', 'candidates',
    'candidateOrganizationCompleted', 'failures',
  });
  return ImageRecognitionResult(
    text: _nullableString(map['text']), barcodeCompleted: _bool(map['barcodeCompleted']),
    barcodes: _list(map['barcodes']).map((value) {
      final item = _object(value, {'value', 'format'});
      return RecognizedImageBarcode(value: _string(item['value']), format: _string(item['format']));
    }),
    interpretation: _nullableString(map['interpretation']),
    candidateOrganizationCompleted: _bool(map['candidateOrganizationCompleted']),
    candidates: _list(map['candidates']).map((value) {
      final item = _object(value, {'kind', 'value'});
      return RecognitionCandidate(kind: _string(item['kind']), value: _string(item['value']));
    }),
    failures: _list(map['failures']).map((value) {
      final item = _object(value, {'stage', 'code', 'message'});
      return ImageRecognitionFailure(
        stage: _enum(item['stage'], ImageRecognitionStage.values),
        code: _string(item['code']), message: _string(item['message']),
      );
    }),
  );
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
    throw const FormatException('Missing or unknown recognition report keys');
  }
  return map;
}
List<Object?> _list(Object? value) {
  if (value is! List) throw const FormatException('Expected a list');
  return List<Object?>.of(value);
}
String _string(Object? value) {
  if (value is! String) throw const FormatException('Expected a string');
  return value;
}
String? _nullableString(Object? value) => value == null ? null : _string(value);
bool _bool(Object? value) {
  if (value is! bool) throw const FormatException('Expected a boolean');
  return value;
}
T _enum<T extends Enum>(Object? value, List<T> values) {
  final name = _string(value);
  for (final item in values) { if (item.name == name) return item; }
  throw FormatException('Unknown enum value $name');
}

DateTime _time(Object? value) => CaptureMaterialReference.fromJson({
  'id': 'time', 'mediaType': 'application/json', 'byteLength': 1,
  'capturedAt': _string(value), 'originalName': null, 'extensions': <String, Object?>{},
}).capturedAt;

Object? _detach(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries) entry.key as String: _detach(entry.value),
    };
  }
  if (value is List) {
    return value.map(_detach).toList();
  }
  return value;
}
bool _sameJson(Object? first, Object? second) {
  if (first is num && second is num && (first is int) != (second is int)) {
    return false;
  }
  if (first is Map && second is Map) {
    return first.length == second.length &&
      first.keys.every((key) => second.containsKey(key) && _sameJson(first[key], second[key]));
  }
  if (first is List && second is List) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (!_sameJson(first[index], second[index])) return false;
    }
    return true;
  }
  return first == second;
}
