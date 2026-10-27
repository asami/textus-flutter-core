import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

import '../support/submission_http_fixture.dart';

/// Shared canonical original intent; test data describes no live registration.
SubmissionRequest registeredTestRequest({
  String id = 'book1',
  List<String> mediaTypes = const ['image/jpeg', 'audio/wav'],
  Map<String, Object?> opaque = const {
    'future': [null, '  日本語 🐈\n ', [], [null]],
  },
}) {
  final createdAt = DateTime.utc(2026, 10, 26);
  final updatedAt = DateTime.utc(2026, 10, 26, 1, 2, 3, 4, 5);
  final originals = [for (var i = 0; i < mediaTypes.length; i++)
    CaptureMaterialReference(
      id: 'original$i', mediaType: mediaTypes[i], byteLength: i + 1,
      capturedAt: updatedAt,
      originalName: '  原本 $i  ', extensions: opaque,
    )];
  final photos = originals.where((m) => m.mediaType.startsWith('image/')).toList();
  final audio = originals.where((m) => m.mediaType.startsWith('audio/')).toList();
  final document = <String, Object?>{
    'schemaVersion': 2, 'id': id,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'state': 'Draft',
    'evidence': [for (final original in photos)
      {'role': 'cover', 'material': original.toJson(),
        'label': '  表紙  ', 'extensions': opaque}],
    'isbn': [],
    'title': [
      {'value': '  原本の書籍  ', 'provenance': {
        'source': 'manual', 'recordedAt': updatedAt.toIso8601String(),
        'materialIds': [], 'method': null, 'extensions': opaque,
      }},
    ],
    'annotationText': [], 'sectionName': [], 'elements': [],
    'extensions': {
      ...opaque,
      'org.textus.editingStudio.bookAudio': {
        'schemaVersion': 1,
        'annotations': [for (final original in audio)
          {'id': original.id, 'linkedElementId': null, 'review': {
            'version': 1,
            'original': {'version': 1, 'material': original.toJson(),
              'durationMilliseconds': 1000},
            'reports': [], 'revisions': [],
          }}],
      },
    },
  };
  final materials = [
    for (final original in photos)
      SubmissionMaterial(
        key: original.id, original: original,
        provenance: {'kind': 'image', 'role': 'frontCover',
          'label': '  表紙  ', 'extensions': opaque},
      ),
    for (final original in audio)
    SubmissionMaterial(
      key: original.id, original: original,
      provenance: {'kind': 'audio', 'annotationId': original.id,
        'linkedElementId': null},
    ),
  ];
  return SubmissionRequest(
    id: id, kind: 'bookMaterial', subjectId: id,
    createdAt: updatedAt,
    document: document,
    payload: {
      'schemaVersion': 1, 'type': 'bookMaterial',
      'material': document,
      'recognitionReports': {'report1': opaque},
    },
    materials: materials, transportConnectionId: 'lake', extensions: opaque,
    tklDelivery: TklMaterialDeliveryRequest(requestId: id, contribution: {'book': opaque}),
  );
}

HttpSubmissionConnection registeredTestTarget({String id = 'studio', String path = '/rest/v1/editing-studio/book-material/submit'}) =>
    HttpSubmissionConnection(id: id, endpoint: Uri.parse('https://studio.example.test$path'));

RegisteredMaterialSubmissionPacket registeredTestPacket({
  SubmissionRequest? source, HttpSubmissionConnection? target,
  String materialRef = '  urn:tkl:Material:日本語/Exact%20Ref  ',
}) {
  final request = source ?? registeredTestRequest();
  return RegisteredMaterialSubmissionPacket(
    sourceRequest: request, target: target ?? registeredTestTarget(),
    association: RegisteredMaterialAssociation(materialRef: materialRef,
      resources: [for (final m in request.materials)
        RegisteredMaterialResource(key: m.key, resourceId: m.key)]),
  );
}

Map<String, Object?> registeredJsonCopy(Map<String, Object?> value) =>
    Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);

void main() {
  for (final types in <List<String>>[
    [], ['image/jpeg'], ['audio/wav'], ['image/jpeg', 'image/png', 'audio/wav'],
  ]) {
    test('should retain exact nine-field v2 for ${types.length} ordered originals $types', () {
      // Given the original saved-intent shape, all references and literal MaterialRef.
      final packet = registeredTestPacket(source: registeredTestRequest(mediaTypes: types));
      // When the separate v2 codec serializes and decodes that packet.
      final wire = RegisteredMaterialSubmissionCodec.packetToJson(packet);
      final restored = RegisteredMaterialSubmissionCodec.packetFromJson(wire,
        sourceRequest: packet.sourceRequest, target: packet.target);
      // Then there are exactly nine fields, exact originals, and no physical receipt or timestamp.
      expect(wire.keys.toSet(), {'version', 'requestId', 'kind', 'subjectId', 'createdAt',
        'payload', 'extensions', 'materials', 'registeredMaterial'});
      expect(wire['version'], 2);
      expect(restored, packet);
      expect(restored.association.materialRef, '  urn:tkl:Material:日本語/Exact%20Ref  ');
      expect((wire['materials'] as List).length, types.length);
      for (final item in wire['materials'] as List) {
        expect((item as Map).keys.toSet(), {'key', 'original', 'provenance'});
      }
      expect((wire['registeredMaterial'] as Map).keys.toSet(), {'schema', 'materialRef', 'resources'});
      expect(wire.containsKey('storedAt'), isFalse);
      expect(wire.containsKey('document'), isFalse);
      expect(wire.containsKey('target'), isFalse);
      expect(() => packet.association.resources.clear(), throwsUnsupportedError);
    });
  }

  test('should preserve seeded opaque null Unicode lists and histories in both wire versions', () {
    // Given deterministic nested JSON with null, empty/singleton lists and literal text.
    final random = Random(632026);
    final legacy = SubmissionHttpFixture();
    addTearDown(legacy.dispose);
    for (var i = 0; i < 80; i++) {
      final opaque = <String, Object?>{'seed': i, 'future': _generated(random, 4),
        'literal': '  日本語 🐈\n\t ', 'singleton': [null]};
      final source = registeredTestRequest(opaque: opaque);
      final packet = registeredTestPacket(source: source);
      // When each seeded packet and a legacy packet pass their actual codecs.
      final wire = registeredJsonCopy(RegisteredMaterialSubmissionCodec.packetToJson(packet));
      final decoded = RegisteredMaterialSubmissionCodec.packetFromJson(wire,
        sourceRequest: source, target: packet.target);
      final oldRequest = SubmissionRequest(id: 'old$i', kind: 'bookMaterial', subjectId: 'old$i',
        createdAt: source.createdAt, document: opaque, payload: source.payload,
        materials: const [], transportConnectionId: 'server', extensions: opaque);
      final v1 = SubmissionCodec.packetToJson(SubmissionPacket(request: oldRequest, receipts: const {}));
      // Then opaque values and complete payloads survive unchanged, with eight legacy keys.
      expect(decoded.sourceRequest.payload, source.payload);
      expect(decoded.sourceRequest.extensions, opaque);
      expect(decoded.sourceRequest.materials, source.materials);
      expect(v1.length, 8);
      expect(v1['version'], 1);
      expect(v1['extensions'], opaque);
      expect(v1['payload'], source.payload);
      expect(v1.containsKey('registeredMaterial'), isFalse);
    }
  });

  final mutations = <String, void Function(Map<String, Object?>)>{
    'missing association': (v) => v.remove('registeredMaterial'),
    'null association': (v) => v['registeredMaterial'] = null,
    'null materials': (v) => v['materials'] = null,
    'string version': (v) => v['version'] = '2',
    'legacy version': (v) => v['version'] = 1,
    'unsupported version': (v) => v['version'] = 3,
    'double version': (v) => v['version'] = 2.0,
    'unknown outer null': (v) => v['future'] = null,
    'wrong identity': (v) => v['subjectId'] = 'other',
    'invalid time': (v) => v['createdAt'] = '2026-02-30T00:00:00Z',
    'wrong schema': (v) => (v['registeredMaterial'] as Map)['schema'] = 'other',
    'blank reference': (v) => (v['registeredMaterial'] as Map)['materialRef'] = '  ',
    'association unknown null': (v) => (v['registeredMaterial'] as Map)['deliveryRef'] = null,
    'map unknown null': (v) => (((v['registeredMaterial'] as Map)['resources'] as List).first as Map)['extra'] = null,
    'invalid selector': (v) => (((v['registeredMaterial'] as Map)['resources'] as List).first as Map)['resourceId'] = '../unsafe',
    'null resource': (v) => ((v['registeredMaterial'] as Map)['resources'] as List)[0] = null,
    'duplicate key': (v) {
      final maps = (v['registeredMaterial'] as Map)['resources'] as List;
      (maps[1] as Map)['key'] = (maps[0] as Map)['key'];
    },
    'duplicate resourceId': (v) {
      final maps = (v['registeredMaterial'] as Map)['resources'] as List;
      (maps[1] as Map)['resourceId'] = (maps[0] as Map)['resourceId'];
    },
    'missing mapping': (v) => ((v['registeredMaterial'] as Map)['resources'] as List).removeLast(),
    'extra mapping': (v) => ((v['registeredMaterial'] as Map)['resources'] as List)
      .add({'key': 'extra', 'resourceId': 'extraResource'}),
    'reordered mapping': (v) {
      final maps = (v['registeredMaterial'] as Map)['resources'] as List;
      (v['registeredMaterial'] as Map)['resources'] = maps.reversed.toList();
    },
    'reordered originals': (v) => v['materials'] = (v['materials'] as List).reversed.toList(),
    'receipt even null': (v) => ((v['materials'] as List).first as Map)['receipt'] = null,
    'nonpositive bytes': (v) => (((v['materials'] as List).first as Map)['original'] as Map)['byteLength'] = 0,
    'changed provenance': (v) => ((v['materials'] as List).first as Map)['provenance'] = {},
    'List recognition reports': (v) => (v['payload'] as Map)['recognitionReports'] = [],
    'scalar recognition reports': (v) => (v['payload'] as Map)['recognitionReports'] = 1,
    'null recognition reports': (v) => (v['payload'] as Map)['recognitionReports'] = null,
    'changed payload': (v) => (v['payload'] as Map)['recognitionReports'] = {'otherReport': {}},
  };
  for (final entry in mutations.entries) {
    test('should reject ${entry.key} without repairing v2', () {
      // Given a complete canonical v2 packet with one deliberately invalid field.
      final packet = registeredTestPacket();
      final wire = registeredJsonCopy(RegisteredMaterialSubmissionCodec.packetToJson(packet));
      entry.value(wire);
      // When the strict decoder is given that altered packet and original intent.
      RegisteredMaterialSubmissionPacket decode() => RegisteredMaterialSubmissionCodec.packetFromJson(wire,
        sourceRequest: packet.sourceRequest, target: packet.target);
      // Then absence, null, unknown keys and changed source facts are all rejected.
      expect(decode, throwsFormatException);
    });
  }

  test('should require TKL intent and complete ordered mapping before DTO construction', () {
    // Given an ordinary legacy intent with no TKL delivery authority.
    final f = SubmissionHttpFixture();
    addTearDown(f.dispose);
    final legacy = f.request(withMaterial: false);
    // When a registered packet or duplicate association is constructed directly.
    RegisteredMaterialSubmissionPacket build() => registeredTestPacket(source: legacy);
    // Then invalid intent and duplicate selectors fail without any IO.
    expect(build, throwsArgumentError);
    expect(() => RegisteredMaterialAssociation(materialRef: 'ref', resources: [
      RegisteredMaterialResource(key: 'a', resourceId: 'r'),
      RegisteredMaterialResource(key: 'b', resourceId: 'r'),
    ]), throwsArgumentError);
    expect(f.client.requests, isEmpty);
  });

  for (final entry in <String, Object?>{
    'List': <Object?>[], 'scalar': 1, 'null': null,
  }.entries) {
    test('should require Map recognition reports for a direct TKL DTO instead of ${entry.key}', () {
      // Given a TKL source with complete Book intent but non-Map reports.
      final valid = registeredTestRequest();
      final source = SubmissionRequest(
        id: valid.id, kind: valid.kind, subjectId: valid.subjectId,
        createdAt: valid.createdAt, document: valid.document,
        payload: {...valid.payload, 'recognitionReports': entry.value},
        materials: valid.materials,
        transportConnectionId: valid.transportConnectionId,
        tklDelivery: valid.tklDelivery, extensions: valid.extensions,
      );
      // When the DTO is constructed directly, without the wire decoder.
      RegisteredMaterialSubmissionPacket build() => registeredTestPacket(source: source);
      // Then malformed report containers fail while the original Map remains valid.
      expect(build, throwsArgumentError);
      expect(registeredTestPacket(source: valid).sourceRequest.payload, valid.payload);
      expect(valid.payload['recognitionReports'], isA<Map>());
    });
  }
}

Object? _generated(Random random, int depth) {
  if (depth == 0) return [null, true, false, random.nextInt(100), '  日本語\n '][random.nextInt(5)];
  return switch (random.nextInt(4)) {
    0 => null,
    1 => [for (var i = 0; i < random.nextInt(4); i++) _generated(random, depth - 1)],
    2 => {'opaque/key': _generated(random, depth - 1), 'null': null},
    _ => '  🐈 ${random.nextInt(100)}  ',
  };
}
