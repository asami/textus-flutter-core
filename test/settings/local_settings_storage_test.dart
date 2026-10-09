import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';
import 'package:textus_flutter_core/settings_io.dart';

void main() {
  group('Installation-local whole-record storage', () {
    late Directory directory;
    setUp(
      () async =>
          directory = await Directory.systemTemp.createTemp('core-settings-'),
    );
    tearDown(() async => directory.delete(recursive: true));
    FileSettingsStorage storage(String namespace) => FileSettingsStorage(
      namespace: namespace,
      directory: () async => directory,
    );

    test(
      'missing record reads as absent without creating directories',
      () async {
        // Given a fresh application-support directory.
        final adapter = storage('app');
        // When restoration asks for its record.
        final record = await adapter.read();
        // Then absence is distinct from failure and construction/read does not write.
        expect(record, isNull);
        expect(directory.listSync(), isEmpty);
      },
    );

    test(
      'acknowledged replacement survives a new adapter and isolates namespaces',
      () async {
        // Given an acknowledged record including unknown future keys.
        const first = '{"version":1,"values":{"unknown":{"nested":true}}}';
        await storage('app').write(first);
        await storage('other').write('other-record');
        // When the original namespace atomically replaces its complete record.
        const latest = '{"version":9,"opaque":[1,2,3]}';
        await storage('app').write(latest);
        // Then a new instance restores the exact bytes without decoding or rewriting.
        expect(await storage('app').read(), latest);
        expect(await storage('other').read(), 'other-record');
        expect(directory.listSync(recursive: true).whereType<File>().length, 2);
      },
    );

    test(
      'failed replacement propagates and cleans only its owned temporary',
      () async {
        // Given a directory occupying the destination and an unrelated file.
        final destination = Directory(
          '${directory.path}/textus-settings/app.json',
        );
        await destination.create(recursive: true);
        final unrelated = File('${destination.parent.path}/keep.pending');
        await unrelated.writeAsString('keep');
        // When replacement cannot rename over that directory.
        await expectLater(
          storage('app').write('new'),
          throwsA(isA<FileSystemException>()),
        );
        // Then failure is not acknowledged and unrelated content remains untouched.
        expect(destination.existsSync(), isTrue);
        expect(await unrelated.readAsString(), 'keep');
        expect(destination.parent.listSync().length, 2);
      },
    );

    test(
      'directory and read failures propagate rather than returning absence',
      () async {
        // Given an unavailable platform directory and a non-file record.
        final unavailable = FileSettingsStorage(
          namespace: 'app',
          directory: () async => throw StateError('unavailable'),
        );
        await Directory('${directory.path}/textus-settings/app.json')
            .create(recursive: true);
        // When read/write request storage.
        await expectLater(unavailable.read(), throwsStateError);
        await expectLater(unavailable.write('record'), throwsStateError);
        // Then a present but unreadable record is an error, not default restoration.
        await expectLater(
          storage('app').read(),
          throwsA(isA<FileSystemException>()),
        );
      },
    );

    test('public composition rejects empty or path-like namespaces', () {
      // Given identifiers that could escape the app-specific record directory.
      for (final namespace in ['', '../app', '/app', 'app/other', 'a b']) {
        // When constructing the portable adapter.
        // Then invalid identity is rejected before any I/O.
        expect(
          () => createLocalSettingsStorage(namespace: namespace),
          throwsArgumentError,
        );
      }
      expect(
        createLocalSettingsStorage(namespace: 'app.example-1'),
        isA<SettingsStorage>(),
      );
    });
  });
}
