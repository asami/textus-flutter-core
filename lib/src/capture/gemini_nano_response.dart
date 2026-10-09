part of 'gemini_nano_image_recognition_provider.dart';

/// Strict whole-response decoding, with independent generated stage truth.
ImageRecognitionResult _decodeNanoResponse(String generated) {
  Object? root;
  try {
    var json = generated.trim();
    if (json.startsWith('```')) {
      final fence = RegExp(r'^```(?:json)?\r?\n([\s\S]*)\r?\n```$').firstMatch(json);
      if (fence == null) {
        throw const FormatException('Incomplete or unsupported JSON fence');
      }
      json = fence.group(1)!;
    }
    root = jsonDecode(json);
    if (root is! Map || root.length != 2 ||
        !root.containsKey('interpretation') || !root.containsKey('candidates')) {
      throw const FormatException('Expected exactly interpretation and candidates');
    }
  } catch (error) {
    return _failed('invalidGeneratedResponse',
      'Invalid generated response: ${_nanoDescription(error)}; generated text: $generated');
  }
  final object = root;
  final interpretation = object['interpretation'];
  final rawCandidates = object['candidates'];
  final validInterpretation = interpretation is String && interpretation.trim().isNotEmpty;
  final validCandidates = rawCandidates is List && rawCandidates.every((item) =>
    item is Map && item.length == 2 && item.containsKey('kind') && item.containsKey('value') &&
    item['kind'] is String && (item['kind'] as String).trim().isNotEmpty &&
    item['value'] is String && (item['value'] as String).trim().isNotEmpty,
  );
  return ImageRecognitionResult(
    interpretation: validInterpretation ? interpretation : null,
    candidateOrganizationCompleted: validCandidates,
    candidates: validCandidates ? [
      for (final item in rawCandidates)
        RecognitionCandidate(kind: (item as Map)['kind'] as String, value: item['value'] as String),
    ] : const [],
    failures: [
      if (!validInterpretation) ImageRecognitionFailure(
        stage: ImageRecognitionStage.interpretation, code: 'invalidInterpretation',
        message: 'Generated interpretation must be a nonblank String; generated text: $generated',
      ),
      if (!validCandidates) ImageRecognitionFailure(
        stage: ImageRecognitionStage.provider, code: 'invalidGeneratedCandidates',
        message: 'Generated candidates must be a complete valid kind/value array; generated text: $generated',
      ),
    ],
  );
}
