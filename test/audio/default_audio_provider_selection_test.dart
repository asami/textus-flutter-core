import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ios = MethodChannel('org.textus.flutter.core/ios_audio');
  const android = MethodChannel('org.textus.flutter.core/audio');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <String>[];
  final capturedAt = DateTime.utc(2026, 11, 5);
  final wave = PcmWaveAudio.encode(
    Uint8List.fromList(List.generate(320, (i) => i % 256)),
  );

  setUp(() {
    calls.clear();
    for (final entry in {
      ios: 'ios-on-device-speech',
      android: 'android-basic-speech',
    }.entries) {
      messenger.setMockMethodCallHandler(entry.key, (call) async {
        calls.add('${entry.value}/${call.method}');
        final args = call.arguments as Map;
        if (call.method == 'availability') {
          return {
            'providerId': entry.value,
            'locale': args['locale'],
            'state': 'available',
            'reason': null,
          };
        }
        if (call.method == 'stopRecording') {
          return {
            'bytes': wave,
            'capturedAt': capturedAt.toIso8601String(),
            'originalName': 'recording.wav',
          };
        }
        if (call.method == 'play') expect(args['bytes'], orderedEquals(wave));
        return null;
      });
    }
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(ios, null);
    messenger.setMockMethodCallHandler(android, null);
  });

  for (final entry in {
    TargetPlatform.iOS: 'ios-on-device-speech',
    TargetPlatform.android: 'android-basic-speech',
  }.entries) {
    test(
      'default factory selects ${entry.key.name} and owns one shared adapter',
      () async {
        // Given a platform override and the existing in-memory store fixture pattern.
        debugDefaultTargetPlatformOverride = entry.key;
        final store = _MemoryStore();
        await store.saveDocument('kept', 'document', {'exact': '保存'});
        // When the default factory probes, captures and replays through its selected adapter.
        final service = await openDefaultAudioCaptureService(store: store);
        expect(calls, isEmpty);
        expect(service.ownsProviders, isTrue);
        expect(service.isSupported, isTrue);
        expect((await service.availability()).providerId, entry.value);
        await service.startRecording();
        final original = await service.stopRecording();
        await service.playOriginal(original);
        await service.dispose();
        await service.dispose();
        // Then one provider is disposed once and the borrowed store retains exact originals/documents.
        expect(calls, [
          '${entry.value}/availability',
          '${entry.value}/startRecording',
          '${entry.value}/stopRecording',
          '${entry.value}/play',
          '${entry.value}/dispose',
        ]);
        expect(
          await store.readMaterial(original.material),
          orderedEquals(wave),
        );
        expect(original.material.capturedAt, capturedAt);
        expect(await store.readDocument('kept', 'document'), {'exact': '保存'});
      },
      skip: kIsWeb,
    );
  }

  test(
    'unsupported platform keeps honest Android fallback without native calls',
    () async {
      // Given a non-iOS/non-Android host and a caller-owned memory store.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final store = _MemoryStore();
      // When the default factory checks readiness and is disposed.
      final service = await openDefaultAudioCaptureService(store: store);
      final readiness = await service.availability();
      await service.dispose();
      // Then fallback semantics remain unavailable and no native provider work occurs.
      expect(service.isSupported, isFalse);
      expect(readiness.providerId, 'android-basic-speech');
      expect(readiness.state, AudioProviderState.unavailable);
      expect(calls, isEmpty);
    },
  );
}

// Adapted from the private in-memory LocalCaptureStore in
// test/capture/image_region_processing_test.dart; no disk/plugin store opens.
final class _MemoryStore implements LocalCaptureStore {
  final materials = <String, Uint8List>{};
  final documents = <String, Map<String, Object?>>{};
  int serial = 0;

  @override
  Future<CaptureMaterialReference> saveMaterial({
    required Uint8List bytes,
    required String mediaType,
    required DateTime capturedAt,
    String? originalName,
  }) async {
    final id = 'material${serial++}';
    materials[id] = Uint8List.fromList(bytes);
    return CaptureMaterialReference(
      id: id,
      mediaType: mediaType,
      byteLength: bytes.length,
      capturedAt: capturedAt,
      originalName: originalName,
    );
  }

  @override
  Future<Uint8List> readMaterial(CaptureMaterialReference reference) async =>
      Uint8List.fromList(materials[reference.id]!);

  @override
  Future<void> saveDocument(
    String collection,
    String id,
    Map<String, Object?> document,
  ) async {
    documents['$collection/$id'] = Map<String, Object?>.from(
      jsonDecode(jsonEncode(document)) as Map,
    );
  }

  @override
  Future<Map<String, Object?>?> readDocument(
    String collection,
    String id,
  ) async {
    final value = documents['$collection/$id'];
    return value == null
        ? null
        : Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);
  }

  @override
  Future<List<String>> listDocumentIds(String collection) async =>
      documents.keys
          .where((key) => key.startsWith('$collection/'))
          .map((key) => key.substring(collection.length + 1))
          .toList()
        ..sort();
}
