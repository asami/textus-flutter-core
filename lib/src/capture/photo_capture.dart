import 'dart:typed_data';

import 'capture_material.dart';
import 'recognition_operation_context.dart';

/// An unchanged acquisition snapshot without a plugin cache path.
final class CapturedPhoto {
  CapturedPhoto({
    required Uint8List bytes,
    required String mediaType,
    required DateTime capturedAt,
    this.originalName,
  }) : _bytes = _imageBytes(bytes, mediaType),
       mediaType = mediaType,
       capturedAt = capturedAt.toUtc();

  final Uint8List _bytes;
  final String mediaType;
  final DateTime capturedAt;
  final String? originalName;

  /// A fresh caller-owned copy on each access.
  Uint8List get bytes => Uint8List.fromList(_bytes);

  @override
  bool operator ==(Object other) {
    if (other is! CapturedPhoto || mediaType != other.mediaType ||
        capturedAt != other.capturedAt || originalName != other.originalName ||
        _bytes.length != other._bytes.length) {
      return false;
    }
    for (var index = 0; index < _bytes.length; index++) {
      if (_bytes[index] != other._bytes[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    mediaType, capturedAt, originalName, Object.hashAll(_bytes),
  );
}

/// Verbatim provider barcode output; no domain validation is implied.
final class RecognizedImageBarcode {
  RecognizedImageBarcode({required String value, required String format})
    : value = _nonblank(value, 'value'), format = _nonblank(format, 'format');

  final String value;
  final String format;

  @override
  bool operator ==(Object other) => other is RecognizedImageBarcode &&
      value == other.value && format == other.format;
  @override
  int get hashCode => Object.hash(value, format);
}

/// A generated suggestion with an opaque provider-defined classification.
final class RecognitionCandidate {
  RecognitionCandidate({required String kind, required String value})
    : kind = _nonblank(kind, 'kind'), value = _nonblank(value, 'value');

  final String kind;
  final String value;

  @override
  bool operator ==(Object other) => other is RecognitionCandidate &&
      kind == other.kind && value == other.value;
  @override
  int get hashCode => Object.hash(kind, value);
}

enum ImageRecognitionStage {
  text, barcode, interpretation, provider, availability, cleanup,
}

/// Serializable descriptive failure, without an arbitrary exception object.
final class ImageRecognitionFailure {
  ImageRecognitionFailure({
    required this.stage, required String code, required String message,
  }) : code = _nonblank(code, 'code'), message = _nonblank(message, 'message');

  final ImageRecognitionStage stage;
  final String code;
  final String message;

  @override
  bool operator ==(Object other) => other is ImageRecognitionFailure &&
      stage == other.stage && code == other.code && message == other.message;
  @override
  int get hashCode => Object.hash(stage, code, message);
}

/// Immutable raw stages. Empty completed output differs from no output.
final class ImageRecognitionResult {
  ImageRecognitionResult({
    this.text,
    Iterable<RecognizedImageBarcode> barcodes = const [],
    this.barcodeCompleted = false,
    this.interpretation,
    Iterable<RecognitionCandidate> candidates = const [],
    this.candidateOrganizationCompleted = false,
    Iterable<ImageRecognitionFailure> failures = const [],
  }) : barcodes = List.unmodifiable(barcodes),
       candidates = List.unmodifiable(candidates),
       failures = List.unmodifiable(failures) {
    if (this.barcodes.isNotEmpty && !barcodeCompleted) {
      throw ArgumentError('Barcode values require a completed barcode stage');
    }
    if (this.candidates.isNotEmpty && !candidateOrganizationCompleted) {
      throw ArgumentError('Candidates require a completed organization stage');
    }
  }

  final String? text;
  final List<RecognizedImageBarcode> barcodes;
  final bool barcodeCompleted;
  final String? interpretation;
  final List<RecognitionCandidate> candidates;
  final bool candidateOrganizationCompleted;
  final List<ImageRecognitionFailure> failures;

  bool get hasSuccessfulOutput => text != null || barcodeCompleted ||
      interpretation != null || candidateOrganizationCompleted;
}

/// Defensive original bytes and earlier executed raw stages for that original.
final class ImageRecognitionInput {
  ImageRecognitionInput({
    required this.material,
    required Uint8List bytes,
    Iterable<ImageRecognitionResult> previousResults = const [],
    this.operationContext,
  }) : _bytes = _imageBytes(bytes, material.mediaType),
       previousResults = List.unmodifiable(previousResults) {
    if (_bytes.length != material.byteLength) {
      throw ArgumentError('Image length does not match original reference');
    }
  }

  final CaptureMaterialReference material;
  final Uint8List _bytes;
  final List<ImageRecognitionResult> previousResults;
  /// Immutable caller intent for this operation; null preserves legacy input.
  final RecognitionOperationContext? operationContext;
  Uint8List get bytes => Uint8List.fromList(_bytes);
}

Uint8List _imageBytes(Uint8List bytes, String mediaType) {
  if (bytes.isEmpty || !mediaType.toLowerCase().startsWith('image/') ||
      !RegExp(r"^[A-Za-z0-9!#$%&'*+.^_`|~-]+/[A-Za-z0-9!#$%&'*+.^_`|~-]+$")
          .hasMatch(mediaType)) {
    throw ArgumentError('Positive bytes and an image MIME token are required');
  }
  return Uint8List.fromList(bytes);
}

String _nonblank(String value, String name) {
  if (value.trim().isEmpty) throw ArgumentError.value(value, name, 'blank');
  return value;
}
