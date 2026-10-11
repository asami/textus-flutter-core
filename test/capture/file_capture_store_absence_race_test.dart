import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  late Directory root;

  setUp(() async {
    // Given a scenario requiring native file operations without shared artifacts.
    // When a new real temporary root is allocated before installing overrides.
    root = await Directory.systemTemp.createTemp('capture-absence-spec-');
    // Then every scenario owns the files it will observe and later remove.
  });

  tearDown(() async {
    // Given scoped overrides have ended and only this scenario owns its root.
    // When the real temporary tree is removed after all awaited operations.
    await root.delete(recursive: true);
    // Then production originals and other scenarios' files remain untouched.
  });

  test('F1 missing listing remains empty when the collection is then created', () async {
    // Given real absent collection entities obtained outside the override zone.
    final collection = Directory('${root.path}/documents/comparisons');
    final document = File('${collection.path}/created.json');
    final value = <String, Object?>{
      'source': 'retained',
      'nested': [null, true],
    };
    var missingObserved = false;
    final overrides = _SelectedIoOverrides(
      directoryPath: collection.path,
      list: (real, recursive, followLinks) async* {
        // Given the selected real directory has not yet been created.
        // When its native listing reports absence and a writer creates it.
        try {
          await for (final entry in real.list(
            recursive: recursive,
            followLinks: followLinks,
          )) {
            yield entry;
          }
        } on FileSystemException catch (error) {
          expect(error.osError?.errorCode, 2);
          missingObserved = true;
          await collection.create(recursive: true);
          await document.writeAsString(jsonEncode(value), flush: true);
          // Then Core receives that same real ENOENT after the final file exists.
          rethrow;
        }
      },
    );
    await IOOverrides.runWithIOOverrides(() async {
      // Given the public store and a scoped override for only this collection.
      final store = FileCaptureStore(root.path);
      // When the first listing observes native absence before concurrent creation.
      final first = await store.listDocumentIds('comparisons');
      // Then absence stays empty and a fresh listing sees the retained final id.
      expect(missingObserved, isTrue);
      expect(first, isEmpty);
      expect(await store.listDocumentIds('comparisons'), ['created']);
      expect(jsonDecode(await document.readAsString()), value);
    }, overrides);
    expect(await document.exists(), isTrue);
  });

  test('F2 missing read remains null when the document is then created', () async {
    // Given a real absent document and parent obtained before scoped overrides.
    final collection = Directory('${root.path}/documents/transcripts');
    final document = File('${collection.path}/created.json');
    final value = <String, Object?>{'text': '  retained\n原文  ', 'context': {}};
    var missingObserved = false;
    final overrides = _SelectedIoOverrides(
      filePath: document.path,
      read: (real, encoding) async {
        // Given this selected real file is absent at the actual read operation.
        // When native read fails, create the parent and a valid final object.
        try {
          return await real.readAsString(encoding: encoding);
        } on FileSystemException catch (error) {
          expect(error.osError?.errorCode, 2);
          missingObserved = true;
          await collection.create(recursive: true);
          await document.writeAsString(jsonEncode(value), flush: true);
          // Then the same ENOENT reaches Core after creation without a fake read.
          rethrow;
        }
      },
    );
    await IOOverrides.runWithIOOverrides(() async {
      // Given the public store and an override limited to the selected read.
      final store = FileCaptureStore(root.path);
      // When the first read observes absence and the next read starts afresh.
      final first = await store.readDocument('transcripts', 'created');
      final second = await store.readDocument('transcripts', 'created');
      // Then null belongs to the failed operation and the exact new object survives.
      expect(missingObserved, isTrue);
      expect(first, isNull);
      expect(second, value);
      expect(jsonDecode(await document.readAsString()), value);
    }, overrides);
    expect(await document.exists(), isTrue);
  });

  test('F3 nonmissing read and listing failures preserve documents and originals', () async {
    // Given an accepted real document and original material in the owned root.
    final store = FileCaptureStore(root.path);
    final value = <String, Object?>{
      'accepted': true,
      'context': [null, 'opaque'],
    };
    await store.saveDocument('retained', 'accepted', value);
    final bytes = Uint8List.fromList([255, 216, 20, 255, 217]);
    final original = await store.saveMaterial(
      bytes: bytes,
      mediaType: 'image/jpeg',
      capturedAt: DateTime.utc(2026, 10, 10),
    );
    final collection = Directory('${root.path}/documents/retained');
    final document = File('${collection.path}/accepted.json');
    final acceptedContents = await document.readAsString();
    final readError = FileSystemException(
      'controlled read denial',
      document.path,
      const OSError('denied', 13),
    );
    final listError = FileSystemException(
      'controlled listing denial',
      collection.path,
      const OSError('denied', 13),
    );
    final overrides = _SelectedIoOverrides(
      filePath: document.path,
      directoryPath: collection.path,
      read: (real, encoding) async {
        // Given a selected read of an existing accepted document.
        // When a nonmissing permission error is injected at that operation.
        throw readError;
        // Then Core must expose the same error without replacing source bytes.
      },
      list: (real, recursive, followLinks) async* {
        // Given a selected listing of an existing accepted collection.
        // When a nonmissing permission error is injected at that operation.
        throw listError;
        // Then Core must expose the same error without deleting final files.
      },
    );
    await IOOverrides.runWithIOOverrides(() async {
      // Given only read/list operations for accepted paths are intercepted.
      // When the public store encounters those two nonmissing failures.
      await expectLater(
        store.readDocument('retained', 'accepted'),
        throwsA(same(readError)),
      );
      await expectLater(
        store.listDocumentIds('retained'),
        throwsA(same(listError)),
      );
      // Then original-material reads remain real and preserve the exact bytes.
      expect(await store.readMaterial(original), bytes);
    }, overrides);
    // Given the narrow override zone has ended after both observed failures.
    // When fresh real reads/listing inspect the accepted files again.
    expect(await document.readAsString(), acceptedContents);
    expect(await store.readDocument('retained', 'accepted'), value);
    expect(await store.listDocumentIds('retained'), ['accepted']);
    // Then the accepted document and original remain unchanged and available.
    expect(await store.readMaterial(original), bytes);
  });
}

/// Given exact selected paths and read/list callbacks, when a scoped zone uses
/// these overrides, then all unselected entities come from real IO constructors.
final class _SelectedIoOverrides extends IOOverrides {
  _SelectedIoOverrides({
    this.filePath,
    this.directoryPath,
    this.read,
    this.list,
  });

  final String? filePath;
  final String? directoryPath;
  final Future<String> Function(File, Encoding)? read;
  final Stream<FileSystemEntity> Function(Directory, bool, bool)? list;

  @override
  File createFile(String path) {
    // Given any path requested within the scoped zone.
    final real = super.createFile(path);
    // When only the selected read path requires a forwarding wrapper.
    final selected = read;
    // Then real construction avoids recursion and unrelated file IO is untouched.
    return path == filePath && selected != null
        ? _SelectedReadFile(real, selected)
        : real;
  }

  @override
  Directory createDirectory(String path) {
    // Given any directory path requested within the scoped zone.
    final real = super.createDirectory(path);
    // When only the selected collection listing needs a forwarding wrapper.
    final selected = list;
    // Then native directory creation avoids recursion and other paths stay real.
    return path == directoryPath && selected != null
        ? _SelectedListDirectory(real, selected)
        : real;
  }
}

/// Given a real selected file, when Core reads it, then only readAsString is
/// intercepted and its real path is retained for normal store resolution.
final class _SelectedReadFile implements File {
  _SelectedReadFile(this.real, this.read);

  final File real;
  final Future<String> Function(File, Encoding) read;

  @override
  String get path {
    // Given the wrapper retains the actual native file.
    // When Core requests its path, then the exact real path is forwarded.
    return real.path;
  }

  @override
  Future<String> readAsString({Encoding encoding = utf8}) {
    // Given the real selected file and Core's requested encoding.
    // When its read callback runs, then the scenario delegates real absence or
    // exposes the selected nonmissing error, never a synthetic successful read.
    return read(real, encoding);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    // Given this helper owns only selected string reads and real path forwarding.
    // When another File member is requested.
    throw UnsupportedError('Unsupported file member: ${invocation.memberName}');
    // Then accidental interception fails explicitly instead of fabricating IO.
  }
}

/// Given a real selected collection, when Core lists it, then only list is
/// intercepted and the path used by normal document resolution remains real.
final class _SelectedListDirectory implements Directory {
  _SelectedListDirectory(this.real, this.listEntries);

  final Directory real;
  final Stream<FileSystemEntity> Function(Directory, bool, bool) listEntries;

  @override
  String get path {
    // Given the wrapper retains the actual native directory.
    // When Core requests its path, then the exact real path is forwarded.
    return real.path;
  }

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) {
    // Given the real selected collection and Core's requested listing flags.
    // When its callback runs, then real listing drives absence/created entries
    // or the selected nonmissing failure without synthetic successful disk data.
    return listEntries(real, recursive, followLinks);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    // Given this helper owns only selected listing and real path forwarding.
    // When another Directory member is requested.
    throw UnsupportedError(
      'Unsupported directory member: ${invocation.memberName}',
    );
    // Then accidental interception fails explicitly instead of fabricating IO.
  }
}
