import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  group('material reference values', () {
    test('deep extensions are immutable values with exact JSON roundtrip', () {
      // Given mutable nested JSON containing empty collections and nulls.
      final nested = <String, Object?>{
        'items': <Object?>[null, <String, Object?>{'empty': <Object?>[]}],
        'object': <String, Object?>{},
      };
      final reference = _reference(extensions: nested);
      final equivalent = _reference(extensions: <String, Object?>{
        'object': <String, Object?>{},
        'items': <Object?>[null, <String, Object?>{'empty': <Object?>[]}],
      });

      // When the inputs mutate and the public JSON is decoded independently.
      (nested['items']! as List<Object?>).add('changed');
      nested['new'] = true;
      final decoded = CaptureMaterialReference.fromJson(
        Map<String, Object?>.from(jsonDecode(jsonEncode(reference.toJson()))
            as Map),
      );
      final offsetTime = CaptureMaterialReference.fromJson(<String, Object?>{
        ...reference.toJson(), 'capturedAt': '2026-10-06T10:02:03+09:00',
      });

      // Then all fields participate in value semantics and nested data is frozen.
      expect(reference, equivalent);
      expect(reference.hashCode, equivalent.hashCode);
      expect(decoded, reference);
      expect(offsetTime, reference);
      expect(reference.capturedAt.isUtc, isTrue);
      expect(reference.toJson().keys.toSet(), <String>{
        'id', 'mediaType', 'byteLength', 'capturedAt', 'originalName', 'extensions',
      });
      expect(reference.toJson()['capturedAt'], '2026-10-06T01:02:03.000Z');
      expect(reference.extensions.containsKey('new'), isFalse);
      expect((reference.extensions['items']! as List).length, 2);
      expect(() => reference.extensions['x'] = 1, throwsUnsupportedError);
      expect(() => (reference.extensions['items']! as List).add(1),
          throwsUnsupportedError);
      final child = (reference.extensions['items']! as List)[1] as Map;
      expect(() => child['x'] = 1, throwsUnsupportedError);
      expect(() => (child['empty'] as List).add(1), throwsUnsupportedError);
      for (final field in <String>[
        'id', 'mediaType', 'byteLength', 'capturedAt', 'originalName', 'extensions',
      ]) {
        final changed = reference.toJson();
        changed[field] = <String, Object?>{
          'id': 'different',
          'mediaType': 'image/png',
          'byteLength': 4,
          'capturedAt': '2026-10-07T01:02:03.000Z',
          'originalName': 'different.jpg',
          'extensions': <String, Object?>{},
        }[field];
        expect(CaptureMaterialReference.fromJson(changed), isNot(reference));
      }
    });

    test('invalid reference tokens types lengths and JSON are rejected', () {
      // Given valid public JSON and invalid constructor or schema inputs.
      final valid = _reference().toJson();
      final cyclic = <String, Object?>{};
      cyclic['self'] = cyclic;
      final invalidExtensions = <Map<String, Object?>>[
        <String, Object?>{'value': Object()},
        <String, Object?>{'value': double.nan},
        <String, Object?>{'value': double.infinity},
        <String, Object?>{'value': <int, String>{1: 'bad key'}},
        cyclic,
      ];

      // When constructors and decoders receive unsafe or malformed values.
      final constructors = <void Function()>[
        for (final id in <String>['', ' ', '../x', '/tmp/x', 'a/b', 'a.b',
          List<String>.filled(129, 'a').join()])
          () => _reference(id: id),
        for (final type in <String>['', ' ', 'image', 'image/ jpeg'])
          () => _reference(mediaType: type),
        () => _reference(byteLength: 0),
        () => _reference(byteLength: -1),
        for (final extensions in invalidExtensions)
          () => _reference(extensions: extensions),
      ];
      final malformed = <Map<String, Object?>>[
        <String, Object?>{...valid, 'unknown': 1},
        <String, Object?>{...valid}..remove('originalName'),
        <String, Object?>{...valid, 'id': 1},
        <String, Object?>{...valid, 'id': '../x'},
        <String, Object?>{...valid, 'mediaType': null},
        <String, Object?>{...valid, 'mediaType': 'broken'},
        <String, Object?>{...valid, 'byteLength': 3.0},
        <String, Object?>{...valid, 'byteLength': 0},
        <String, Object?>{...valid, 'capturedAt': true},
        <String, Object?>{...valid, 'capturedAt': 'not-a-date'},
        <String, Object?>{...valid, 'capturedAt': '2026-02-31T01:02:03.000Z'},
        <String, Object?>{...valid, 'originalName': 5},
        <String, Object?>{...valid, 'extensions': null},
        <String, Object?>{...valid, 'extensions': <int, String>{1: 'x'}},
        for (final extensions in invalidExtensions)
          <String, Object?>{...valid, 'extensions': extensions},
      ];

      // Then constructor errors and observable JSON format errors reject them.
      for (final construct in constructors) {
        expect(construct, throwsArgumentError);
      }
      for (final json in malformed) {
        expect(() => CaptureMaterialReference.fromJson(json),
            throwsFormatException);
      }
      expect(_reference().extensions, isEmpty);
      expect(_reference(originalName: null).originalName, isNull);
    });
  });

  group('durable material and opaque document storage', () {
    late Directory directory;
    late LocalCaptureStore store;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('core-capture-store-');
      store = FileCaptureStore(directory.path);
    });
    tearDown(() async {
      await directory.delete(recursive: true);
    });

    test('original bytes and descriptive reference survive a new instance', () async {
      // Given original bytes, descriptive metadata and a configured local root.
      final bytes = Uint8List.fromList(<int>[0, 255, 1, 127, 42]);
      final capturedAt = DateTime.utc(2026, 10, 6, 1, 2, 3);

      // When material is saved and read from a new store at the same root.
      final reference = await store.saveMaterial(
        bytes: bytes,
        mediaType: 'image/jpeg',
        capturedAt: capturedAt,
        originalName: '/descriptive/cover.jpg',
      );
      final restarted = FileCaptureStore(directory.path);
      final restored = CaptureMaterialReference.fromJson(reference.toJson());
      final read = await restarted.readMaterial(restored);

      // Then complete originals, length/type/time/name and logical identity persist.
      expect(read, orderedEquals(bytes));
      expect(reference.id, matches(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$'));
      expect(reference.byteLength, bytes.length);
      expect(reference.mediaType, 'image/jpeg');
      expect(reference.capturedAt, capturedAt);
      expect(reference.originalName, '/descriptive/cover.jpg');
      expect(restored, reference);
      expect(await _materialFile(directory, reference.id).readAsBytes(),
          orderedEquals(bytes));
    });

    test('distinct imports retain both originals and snapshot input bytes', () async {
      // Given mutable input that will be changed before awaiting the first save.
      final bytes = Uint8List.fromList(<int>[1, 2, 3]);

      // When equal originals are imported twice and caller bytes mutate immediately.
      final firstSave = store.saveMaterial(
        bytes: bytes, mediaType: 'image/png', capturedAt: _time,
      );
      bytes.fillRange(0, bytes.length, 9);
      final secondSave = store.saveMaterial(
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
        mediaType: 'image/png', capturedAt: _time,
      );
      final first = await firstSave;
      final second = await secondSave;

      // Then identities are independent and both unchanged originals remain.
      expect(first.id, isNot(second.id));
      expect(await store.readMaterial(first), orderedEquals(<int>[1, 2, 3]));
      expect(await store.readMaterial(second), orderedEquals(<int>[1, 2, 3]));
      expect(await _materialFile(directory, first.id).exists(), isTrue);
      expect(await _materialFile(directory, second.id).exists(), isTrue);
      expect(await Directory('${directory.path}/materials').list().length, 2);
    });

    test('missing or length-inconsistent materials fail observably', () async {
      // Given an absent reference and an existing original with expected length.
      final absent = _reference(id: 'absent');
      final reference = await _saveOriginal(store);

      // When an original is truncated externally and both references are read.
      await _materialFile(directory, reference.id).writeAsBytes(<int>[7]);
      final absentRead = store.readMaterial(absent);
      final inconsistentRead = store.readMaterial(reference);

      // Then absence propagates IO failure and inconsistent length is explicit.
      await expectLater(absentRead, throwsA(isA<FileSystemException>()));
      await expectLater(inconsistentRead, throwsFormatException);
      expect(await _materialFile(directory, reference.id).readAsBytes(), <int>[7]);
      await expectLater(store.saveMaterial(
        bytes: Uint8List(0), mediaType: 'image/png', capturedAt: _time,
      ), throwsArgumentError);
      await expectLater(store.saveMaterial(
        bytes: Uint8List(1), mediaType: 'invalid', capturedAt: _time,
      ), throwsArgumentError);
    });

    test('nested opaque documents survive restart and absent lookup is null', () async {
      // Given opaque draft data with nested fields, extensions, empties and nulls.
      final draft = <String, Object?>{
        'applicationState': 'draft',
        'nested': <String, Object?>{'entries': <Object?>[1, true, null, 'text']},
        'extensions': <String, Object?>{'unknown': <String, Object?>{}},
        'empty': <Object?>[],
        'nullable': null,
      };
      final expected = jsonDecode(jsonEncode(draft));

      // When save is invoked, input mutates and a new instance reads the document.
      final save = store.saveDocument('drafts', 'one', draft);
      (draft['nested']! as Map<String, Object?>)['entries'] = 'changed';
      draft['injectedAfterSave'] = true;
      await save;
      final restarted = FileCaptureStore(directory.path);
      final restored = await restarted.readDocument('drafts', 'one');
      final absent = await restarted.readDocument('drafts', 'absent');

      // Then the opaque invocation snapshot is exact with no injected schema keys.
      expect(restored, expected);
      expect(absent, isNull);
      expect(jsonDecode(await _documentFile(directory, 'drafts', 'one')
          .readAsString()), expected);
    });

    test('corrections overwrite durably reads detach and empty documents persist', () async {
      // Given an accepted document and original material.
      final reference = await _saveOriginal(store);
      await store.saveDocument('drafts', 'one', <String, Object?>{'text': 'old'});

      // When a correction replaces it, returned JSON mutates and an empty object saves.
      await store.saveDocument('drafts', 'one', <String, Object?>{
        'text': 'corrected', 'nested': <Object?>[<String, Object?>{'v': 1}],
      });
      final read = (await store.readDocument('drafts', 'one'))!;
      read['text'] = 'caller change';
      ((read['nested']! as List)[0] as Map)['v'] = 9;
      await store.saveDocument('drafts', 'empty', <String, Object?>{});
      final restarted = FileCaptureStore(directory.path);

      // Then subsequent/restarted reads detach and accepted originals remain intact.
      final expected = <String, Object?>{
        'text': 'corrected', 'nested': <Object?>[<String, Object?>{'v': 1}],
      };
      expect(await store.readDocument('drafts', 'one'), expected);
      expect(await restarted.readDocument('drafts', 'one'), expected);
      expect(await restarted.readDocument('drafts', 'empty'), <String, Object?>{});
      expect(await store.readMaterial(reference), orderedEquals(<int>[1, 2, 3]));
    });

    test('ids sort deterministically and ignore temporary and nonfile entries', () async {
      // Given final documents plus temporary, invalid, corrupt and nonfile entries.
      await store.saveDocument('drafts', 'z-last', <String, Object?>{});
      await store.saveDocument('drafts', 'a-first', <String, Object?>{});
      final collection = Directory('${directory.path}/documents/drafts');
      await File('${collection.path}/pending.json.token.tmp').writeAsString('temp');
      await File('${collection.path}/bad.id.json').writeAsString('{}');
      await File('${collection.path}/notes.txt').writeAsString('text');
      final corrupt = File('${collection.path}/m-corrupt.json');
      await corrupt.writeAsString('{broken');
      await Directory('${collection.path}/folder.json').create();

      // When ids are listed repeatedly and an absent collection is queried.
      final first = await store.listDocumentIds('drafts');
      final second = await store.listDocumentIds('drafts');
      final absent = await store.listDocumentIds('missing');

      // Then only valid final file ids sort and listing never parses/deletes candidates.
      expect(first, <String>['a-first', 'm-corrupt', 'z-last']);
      expect(second, first);
      expect(absent, isEmpty);
      expect(await corrupt.readAsString(), '{broken');
      expect(await File('${collection.path}/pending.json.token.tmp').exists(), isTrue);
    });

    test('unsafe collection and id tokens cannot write outside the root', () async {
      // Given a store below a test-owned parent and unsafe tokens in both positions.
      final isolatedRoot = Directory('${directory.path}/isolated');
      final isolated = FileCaptureStore(isolatedRoot.path);
      final invalid = <String>['', ' ', '../escape', '/escape', 'a/b', r'a\b',
        'a.b', List<String>.filled(129, 'x').join()];

      // When save, read and list are called with unsafe logical identities.
      for (final token in invalid) {
        await expectLater(isolated.saveDocument(token, 'id', <String, Object?>{}),
            throwsArgumentError);
        await expectLater(isolated.saveDocument('drafts', token, <String, Object?>{}),
            throwsArgumentError);
        await expectLater(isolated.readDocument(token, 'id'), throwsArgumentError);
        await expectLater(isolated.readDocument('drafts', token), throwsArgumentError);
        await expectLater(isolated.listDocumentIds(token), throwsArgumentError);
      }

      // Then validation creates neither in-root nor escaped files.
      expect(await isolatedRoot.exists(), isFalse);
      expect(await directory.list().toList(), isEmpty);
    });

    test('malformed and nonobject existing JSON fail without silent replacement', () async {
      // Given malformed and nonobject final JSON files in a test-owned collection.
      final collection = Directory('${directory.path}/documents/drafts');
      await collection.create(recursive: true);
      final contents = <String, String>{
        'malformed': '{broken', 'array': '[]', 'null': 'null', 'number': '42',
      };
      for (final entry in contents.entries) {
        await _documentFile(directory, 'drafts', entry.key).writeAsString(entry.value);
      }

      // When each corrupted candidate is read through the public boundary.
      for (final entry in contents.entries) {
        await expectLater(store.readDocument('drafts', entry.key), throwsFormatException);

        // Then corruption is observable and the exact existing file remains.
        expect(await _documentFile(directory, 'drafts', entry.key).readAsString(),
            entry.value);
      }
    });

    test('invalid JSON replacement preserves valid documents and originals', () async {
      // Given an accepted document, an original and unsupported/cyclic JSON values.
      final reference = await _saveOriginal(store);
      final accepted = <String, Object?>{'accepted': true};
      await store.saveDocument('drafts', 'one', accepted);
      final existing = await _documentFile(directory, 'drafts', 'one').readAsBytes();
      final cyclic = <Object?>[];
      cyclic.add(cyclic);
      final invalid = <Object?>[
        Object(), DateTime.utc(2026), double.nan, double.infinity,
        <int, String>{1: 'invalid'}, cyclic,
      ];

      // When invalid nested JSON tries to replace the accepted document.
      for (final value in invalid) {
        await expectLater(store.saveDocument('drafts', 'one', <String, Object?>{
          'replacement': value,
        }), throwsArgumentError);
      }

      // Then accepted bytes and original material survive every failed replacement.
      expect(await _documentFile(directory, 'drafts', 'one').readAsBytes(), existing);
      expect(await store.readDocument('drafts', 'one'), accepted);
      expect(await store.readMaterial(reference), orderedEquals(<int>[1, 2, 3]));
      expect(await Directory('${directory.path}/documents/drafts').list().length, 1);
    });

    test('queued writes commit in invocation order and recover after failure', () async {
      // Given one instance and a path that blocks one collection's IO.
      await Directory('${directory.path}/documents').create();
      await File('${directory.path}/documents/blocked').writeAsString('blocker');

      // When multiple writes queue with a failing operation between valid saves.
      final observedOrder = <int>[];
      final first = store.saveDocument('drafts', 'one', <String, Object?>{'v': 1})
          .then((_) => observedOrder.add(1));
      final failed = store.saveDocument('blocked', 'one', <String, Object?>{'v': 2});
      final failedExpectation = expectLater(failed, throwsA(isA<FileSystemException>()));
      final third = store.saveDocument('drafts', 'one', <String, Object?>{'v': 3})
          .then((_) => observedOrder.add(3));
      final fourth = store.saveDocument('drafts', 'one', <String, Object?>{'v': 4})
          .then((_) => observedOrder.add(4));
      await Future.wait(<Future<void>>[
        first.then((_) {}), failedExpectation, third.then((_) {}), fourth.then((_) {}),
      ]);

      // Then completion order matches invocation and the final successful save persists.
      expect(observedOrder, <int>[1, 3, 4]);
      expect(await store.readDocument('drafts', 'one'), <String, Object?>{'v': 4});
      expect(await File('${directory.path}/documents/blocked').readAsString(), 'blocker');
    });
  });

  group('observable IO failures', () {
    late Directory directory;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('core-capture-failure-');
    });
    tearDown(() async {
      await directory.delete(recursive: true);
    });

    test('path and rename failures preserve accepted data and foreign temps', () async {
      // Given durable accepted data and a directory blocking one final-file rename.
      final store = FileCaptureStore(directory.path);
      final reference = await _saveOriginal(store);
      await store.saveDocument('drafts', 'accepted', <String, Object?>{'v': 'safe'});
      final blockedDestination = Directory('${directory.path}/documents/drafts/blocked.json');
      await blockedDestination.create();
      await File('${blockedDestination.path}/keep').writeAsString('keep');
      final foreignTemp = File('${directory.path}/documents/drafts/foreign.tmp');
      await foreignTemp.writeAsString('foreign');
      final invalidRoot = File('${directory.path}/root-file');
      await invalidRoot.writeAsString('root-blocker');
      final badStore = FileCaptureStore(invalidRoot.path);

      // When rename, directory creation, read and listing encounter blocked paths.
      await expectLater(store.saveDocument('drafts', 'blocked', <String, Object?>{'v': 2}),
          throwsA(isA<FileSystemException>()));
      await expectLater(badStore.saveDocument('drafts', 'one', <String, Object?>{}),
          throwsA(isA<FileSystemException>()));
      await expectLater(_saveOriginal(badStore), throwsA(isA<FileSystemException>()));
      await expectLater(store.readDocument('drafts', 'blocked'),
          throwsA(isA<FileSystemException>()));
      await File('${directory.path}/documents/blocked-collection').writeAsString('file');
      await expectLater(store.listDocumentIds('blocked-collection'),
          throwsA(isA<FileSystemException>()));

      // Then failures propagate, accepted data survives and only owned temps disappear.
      expect(await store.readDocument('drafts', 'accepted'), <String, Object?>{'v': 'safe'});
      expect(await store.readMaterial(reference), orderedEquals(<int>[1, 2, 3]));
      expect(await foreignTemp.readAsString(), 'foreign');
      expect(await File('${blockedDestination.path}/keep').readAsString(), 'keep');
      expect(await invalidRoot.readAsString(), 'root-blocker');
      final names = await Directory('${directory.path}/documents/drafts').list()
          .map((entry) => entry.uri.pathSegments.where((part) => part.isNotEmpty).last)
          .toList();
      expect(names.toSet(), <String>{'accepted.json', 'blocked.json', 'foreign.tmp'});
    });
  });
}

final DateTime _time = DateTime.utc(2026, 10, 6, 1, 2, 3);

CaptureMaterialReference _reference({
  String id = 'material-1',
  String mediaType = 'image/jpeg',
  int byteLength = 3,
  String? originalName = 'cover.jpg',
  Map<String, Object?> extensions = const <String, Object?>{},
}) => CaptureMaterialReference(
  id: id,
  mediaType: mediaType,
  byteLength: byteLength,
  capturedAt: _time,
  originalName: originalName,
  extensions: extensions,
);

Future<CaptureMaterialReference> _saveOriginal(LocalCaptureStore store) =>
    store.saveMaterial(
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
      mediaType: 'image/png', capturedAt: _time,
    );

File _materialFile(Directory directory, String id) =>
    File('${directory.path}/materials/$id.bin');

File _documentFile(Directory directory, String collection, String id) =>
    File('${directory.path}/documents/$collection/$id.json');
