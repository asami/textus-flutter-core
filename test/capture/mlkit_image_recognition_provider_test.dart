import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('actual ML Kit channels and owned native resources', () {
    late TargetPlatform? previousPlatform;
    late _Channels channels;
    setUp(() {
      previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      channels = _Channels()..install();
    });
    tearDown(() {
      channels.restore();
      debugDefaultTargetPlatformOverride = previousPlatform;
    });

    test('R1 Japanese OCR and all barcode formats share unchanged temp input and close resources', () async {
      // Given actual plugin channel response shapes and raw codes including blank/null entries.
      channels.text = ' 日本語 raw OCR \n';
      channels.codes = [_barcode(' 978 raw '), _barcode(null), _barcode('  ')];
      final input = _input();
      final provider = MlKitImageRecognitionProvider();
      // When the real ML Kit adapter processes one saved original.
      final result = await provider.recognize(input);
      // Then native arguments, raw values, both close calls and owned temp cleanup are observable.
      expect(result.text, ' 日本語 raw OCR \n'); expect(result.barcodeCompleted, isTrue);
      expect(result.barcodes, [RecognizedImageBarcode(value: ' 978 raw ', format: 'ean13')]);
      expect(result.failures, isEmpty); expect(result.hasSuccessfulOutput, isTrue);
      expect(channels.textArguments.single['script'], 3);
      expect(channels.barcodeArguments.single['formats'], [65535]);
      final textImage = channels.textArguments.single['imageData'] as Map;
      final barcodeImage = channels.barcodeArguments.single['imageData'] as Map;
      expect(textImage, barcodeImage); expect(textImage['type'], 'file');
      expect(textImage['path'], endsWith('.jpg'));
      expect(channels.inputBytes, [[1, 2, 3], [1, 2, 3]]);
      expect(channels.textClosed, [channels.textArguments.single['id']]);
      expect(channels.barcodeClosed, [channels.barcodeArguments.single['id']]);
      expect(await File(channels.paths.single).exists(), isFalse);
      expect(await Directory(File(channels.paths.single).parent.path).exists(), isFalse);
      expect(input.bytes, [1, 2, 3]);
    });

    test('R1 empty successful OCR and barcode stages remain successful completed empties', () async {
      // Given published minimal empty channel responses for both successful stages.
      channels.text = ''; channels.codes = [];
      // When the actual provider recognizes an image with no detected output.
      final result = await MlKitImageRecognitionProvider().recognize(_input());
      // Then completion differs from failure and both resources were released.
      expect(result.text, ''); expect(result.barcodes, isEmpty);
      expect(result.barcodeCompleted, isTrue); expect(result.hasSuccessfulOutput, isTrue);
      expect(result.failures, isEmpty); expect(channels.textClosed.length, 1); expect(channels.barcodeClosed.length, 1);
      expect(await Directory(File(channels.paths.single).parent.path).exists(), isFalse);
    });

    test('R2 independent stage failures preserve the other raw stage and native error description', () async {
      // Given native OCR/barcode errors in both partial combinations and together.
      final textError = PlatformException(code: 'ocr_native', message: 'Japanese model unavailable');
      final barcodeError = PlatformException(code: 'barcode_native', message: 'Barcode processing rejected image');
      for (final failures in <List<bool>>[[true, false], [false, true], [true, true]]) {
        channels.textError = failures[0] ? textError : null;
        channels.barcodeError = failures[1] ? barcodeError : null;
        channels.text = 'native text'; channels.codes = [_barcode('978-source')];
        final callsBefore = channels.textArguments.length;
        // When independent native stages process the same original despite a peer failure.
        final result = await MlKitImageRecognitionProvider().recognize(_input());
        // Then no failed stage masquerades as empty success and all cleanup still runs.
        expect(result.text, failures[0] ? null : 'native text');
        expect(result.barcodeCompleted, !failures[1]);
        expect(result.barcodes.length, failures[1] ? 0 : 1);
        expect(result.hasSuccessfulOutput, !failures.every((failed) => failed));
        expect(result.failures.map((item) => item.stage), [
          if (failures[0]) ImageRecognitionStage.text, if (failures[1]) ImageRecognitionStage.barcode,
        ]);
        if (failures[0]) {
          final failure = result.failures.firstWhere((item) => item.stage == ImageRecognitionStage.text);
          expect(failure.code, 'textRecognitionFailed'); expect(failure.message, contains('ocr_native'));
          expect(failure.message, contains('Japanese model unavailable'));
        }
        if (failures[1]) {
          final failure = result.failures.firstWhere((item) => item.stage == ImageRecognitionStage.barcode);
          expect(failure.code, 'barcodeRecognitionFailed'); expect(failure.message, contains('barcode_native'));
        }
        expect(channels.textArguments.length, callsBefore + 1);
        expect(channels.barcodeArguments.length, callsBefore + 1);
        expect(channels.textClosed.length, callsBefore + 1); expect(channels.barcodeClosed.length, callsBefore + 1);
        expect(await Directory(File(channels.paths.last).parent.path).exists(), isFalse);
      }
    });

    test('R3 both close failures remain visible while other close and temp cleanup proceed', () async {
      // Given successful processing and independent native close failures plus a durable original.
      channels.textCloseError = PlatformException(code: 'text_close', message: 'text handle close failed');
      channels.barcodeCloseError = PlatformException(code: 'barcode_close', message: 'barcode handle close failed');
      final directory = await Directory.systemTemp.createTemp('mlkit-original-spec-');
      addTearDown(() async { await directory.delete(recursive: true); });
      final store = FileCaptureStore(directory.path);
      final original = await store.saveMaterial(bytes: Uint8List.fromList([1, 2, 3]),
        mediaType: 'image/jpeg', capturedAt: DateTime.utc(2026, 10, 6));
      // When the real adapter owns temporary resources over bytes read from the store.
      final result = await MlKitImageRecognitionProvider().recognize(ImageRecognitionInput(
        material: original, bytes: await store.readMaterial(original),
      ));
      // Then cleanup failures retain real descriptions without hiding raw success or touching original storage.
      expect(result.text, 'raw text'); expect(result.barcodeCompleted, isTrue);
      expect(result.failures.length, 2);
      expect(result.failures.every((item) => item.stage == ImageRecognitionStage.cleanup && item.code == 'cleanupFailed'), isTrue);
      expect(result.failures.first.message, contains('text_close'));
      expect(result.failures.last.message, contains('barcode_close'));
      expect(channels.textClosed.length, 1); expect(channels.barcodeClosed.length, 1);
      expect(await Directory(File(channels.paths.single).parent.path).exists(), isFalse);
      expect(await store.readMaterial(original), [1, 2, 3]);
    });

    test('R4 unsupported platforms and invalid images fail before native processing', () async {
      // Given a desktop target and malformed image input constructors.
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final provider = MlKitImageRecognitionProvider();
      final invalid = <void Function()>[
        () => ImageRecognitionInput(material: _material(), bytes: Uint8List(0)),
        () => ImageRecognitionInput(material: _material(), bytes: Uint8List(2)),
        () => ImageRecognitionInput(material: _material(type: 'text/plain'), bytes: Uint8List(3)),
      ];
      // When availability, preparation, recognition and invalid input are requested.
      final snapshot = await provider.availability();
      await expectLater(provider.prepare(), throwsUnsupportedError);
      await expectLater(provider.recognize(_input()), throwsUnsupportedError);
      for (final construct in invalid) { expect(construct, throwsArgumentError); }
      // Then platform readiness is truthful and no plugin operation or temp input occurred.
      expect(snapshot.state, RecognitionProviderState.unavailable);
      expect(snapshot.reason, 'unsupportedPlatform'); expect(snapshot.modelName, isNull);
      expect(snapshot.capabilities, {RecognitionCapability.ocr, RecognitionCapability.barcodes});
      expect(channels.textArguments, isEmpty); expect(channels.barcodeArguments, isEmpty);
      expect(channels.textClosed, isEmpty); expect(channels.barcodeClosed, isEmpty); expect(channels.paths, isEmpty);
    });

    test('R4 successive calls own distinct temp directories handles and MIME suffixes', () async {
      // Given one caller-owned provider and every documented image suffix including an opaque subtype.
      final provider = MlKitImageRecognitionProvider();
      final types = <String, String>{
        'image/jpeg': '.jpg', 'image/png': '.png', 'image/heic': '.heic', 'image/heif': '.heif',
        'image/webp': '.webp', 'image/gif': '.gif', 'image/custom': '.img',
      };
      // When successive calls each create and release their own native resources.
      final availability = await provider.availability(); await provider.prepare();
      for (final entry in types.entries) {
        await provider.recognize(_input(type: entry.key));
        expect(channels.paths.last, endsWith(entry.value));
      }
      // Then availability has no invented model, each call owns distinct paths/handles and none persist.
      expect(availability.state, RecognitionProviderState.available); expect(availability.modelName, isNull);
      expect(channels.paths.length, types.length);
      expect(channels.paths.map((path) => File(path).parent.path).toSet().length, types.length);
      expect(channels.textArguments.map((args) => args['id']).toSet().length, types.length);
      expect(channels.barcodeArguments.map((args) => args['id']).toSet().length, types.length);
      expect(channels.textClosed.length, types.length); expect(channels.barcodeClosed.length, types.length);
      for (final path in channels.paths) { expect(await Directory(File(path).parent.path).exists(), isFalse); }
      expect(channels.inputBytes.every((bytes) => listEquals(bytes, [1, 2, 3])), isTrue);
    });
  });
}

CaptureMaterialReference _material({String type = 'image/jpeg'}) => CaptureMaterialReference(
  id: 'original', mediaType: type, byteLength: 3, capturedAt: DateTime.utc(2026, 10, 6),
);
ImageRecognitionInput _input({String type = 'image/jpeg'}) => ImageRecognitionInput(
  material: _material(type: type), bytes: Uint8List.fromList([1, 2, 3]),
);
Map<String, Object?> _barcode(String? raw) => {
  'type': 3, 'format': 32, 'displayValue': null, 'rawValue': raw, 'rawBytes': null,
  'rect': {'left': 0.0, 'top': 0.0, 'right': 1.0, 'bottom': 1.0}, 'points': <Object?>[],
};
final class _Channels {
  static const _text = MethodChannel('google_mlkit_text_recognizer');
  static const _barcode = MethodChannel('google_mlkit_barcode_scanning');
  String text = 'raw text';
  List<Map<String, Object?>> codes = [];
  Object? textError; Object? barcodeError; Object? textCloseError; Object? barcodeCloseError;
  final textArguments = <Map<String, Object?>>[];
  final barcodeArguments = <Map<String, Object?>>[];
  final textClosed = <Object?>[];
  final barcodeClosed = <Object?>[];
  final paths = <String>[];
  final inputBytes = <List<int>>[];
  void install() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_text, (call) async {
      final args = Map<String, Object?>.from(call.arguments as Map);
      if (call.method == 'vision#startTextRecognizer') {
        textArguments.add(args); await _recordImage(args);
        if (textError != null) throw textError!;
        return {'text': text, 'blocks': <Object?>[]};
      }
      if (call.method == 'vision#closeTextRecognizer') {
        textClosed.add(args['id']);
        if (textCloseError != null) throw textCloseError!;
        return null;
      }
      throw StateError('Unexpected text method ${call.method}');
    });
    messenger.setMockMethodCallHandler(_barcode, (call) async {
      final args = Map<String, Object?>.from(call.arguments as Map);
      if (call.method == 'vision#startBarcodeScanner') {
        barcodeArguments.add(args); await _recordImage(args);
        if (barcodeError != null) throw barcodeError!;
        return codes;
      }
      if (call.method == 'vision#closeBarcodeScanner') {
        barcodeClosed.add(args['id']);
        if (barcodeCloseError != null) throw barcodeCloseError!;
        return null;
      }
      throw StateError('Unexpected barcode method ${call.method}');
    });
  }
  Future<void> _recordImage(Map<String, Object?> args) async {
    final image = args['imageData'] as Map;
    final path = image['path'] as String;
    if (!paths.contains(path)) paths.add(path);
    inputBytes.add(await File(path).readAsBytes());
  }
  void restore() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_text, null); messenger.setMockMethodCallHandler(_barcode, null);
  }
}
