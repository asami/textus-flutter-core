import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  late Directory directory;
  late FileCaptureStore files;
  late _ScriptedCorpus corpus;
  late LocalMaterialRetrievalService service;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('core-material-retrieval-');
    files = FileCaptureStore(directory.path);
    corpus = _ScriptedCorpus([_document()]);
    service = LocalMaterialRetrievalService(store: files, corpus: corpus, corpusId: 'books');
  });
  tearDown(() async {
    await service.close();
    await directory.delete(recursive: true);
  });

  group('real durable derived indexes and borrowed original sources', () {
    test('search persists exact available sources and fresh reopen reloads authority', () async {
      // Given retained original bytes/history, a second index and mixed source availability.
      final original = await files.saveMaterial(bytes: Uint8List.fromList([0, 1, 2, 255]),
          mediaType: 'image/png', capturedAt: DateTime.utc(2026, 10, 31));
      await files.saveDocument('source_histories', 'quote', {'text': '過去の引用', 'revision': 0});
      final historyBytes = await _documentFile(directory, 'source_histories', 'quote').readAsBytes();
      final otherCorpus = _ScriptedCorpus([_document(text: '別の資料')], corpusId: 'other');
      final other = LocalMaterialRetrievalService(store: files, corpus: otherCorpus, corpusId: 'other');
      addTearDown(other.close);
      await other.rebuild();
      final otherBytes = await _indexFile(directory, 'other').readAsBytes();
      final current = _document(text: '  「日本語の引用」😀e\u0301\nＡＢ１２　 ');
      corpus.documents = [current,
        _document(sourceId: 'missing', text: '非公開過去本文', availability: MaterialSourceAvailability.missing),
        _document(sourceId: 'denied', text: '秘密の本文', availability: MaterialSourceAvailability.denied),
        _document(sourceId: 'blank', text: ' \n\t　'),
      ];

      // When a real search writes the index and new store/service instances reopen it.
      final result = await service.search(MaterialRetrievalQuery('日本語 ab12'));
      final persisted = await files.readDocument(LocalMaterialRetrievalService.indexCollection, 'books');
      await service.close();
      final reopenedFiles = FileCaptureStore(directory.path);
      final reopenedCorpus = _ScriptedCorpus([current]);
      final reopened = LocalMaterialRetrievalService(
          store: reopenedFiles, corpus: reopenedCorpus, corpusId: 'books');
      addTearDown(reopened.close);
      final reopenedResult = await reopened.search(MaterialRetrievalQuery('日本語 ab12'));

      // Then exact source-only JSON survives reopen while originals and other indexes are untouched.
      expect(result.hits.single.document, current);
      expect(result.indexedSourceCount, 1);
      expect(persisted, _indexJson('books', [current]));
      expect((persisted!['documents']! as List).single, containsPair('reference', {
        'materialSetId': 'book', 'sourceId': 'quote', 'materialId': null, 'regionId': null,
      }));
      expect(jsonEncode(persisted), isNot(contains('秘密の本文')));
      expect(jsonEncode(persisted), isNot(contains('非公開過去本文')));
      expect(reopenedResult, result);
      expect(reopenedCorpus.loads, 1);
      expect(await reopenedFiles.readMaterial(original), [0, 1, 2, 255]);
      expect(await _documentFile(directory, 'source_histories', 'quote').readAsBytes(), historyBytes);
      expect(await _indexFile(directory, 'other').readAsBytes(), otherBytes);
    });

    test('unchanged product snapshot does not rewrite and returned snapshots cannot mutate index', () async {
      // Given a real store observed at its public port and one current source snapshot.
      final observed = _ObservedStore(files);
      final local = LocalMaterialRetrievalService(store: observed, corpus: corpus, corpusId: 'books');
      addTearDown(local.close);
      final input = [_document()];
      final snapshot = MaterialRetrievalCorpusSnapshot(corpusId: 'books', documents: input);
      corpus.onLoad = (_) async => snapshot;

      // When caller inputs/returned JSON mutate between otherwise equal searches and resolves.
      final first = await local.search(MaterialRetrievalQuery('引用'));
      input.clear();
      final detached = (await files.readDocument(LocalMaterialRetrievalService.indexCollection, 'books'))!;
      (detached['documents']! as List).clear();
      final second = await local.search(MaterialRetrievalQuery('引用'));
      final resolution = await local.resolve(first.hits.single);

      // Then every command reloads authority, equal product values avoid writes and results stay immutable.
      expect(observed.saves, 1);
      expect(observed.reads, 3);
      expect(corpus.loads, 3);
      expect(second, first);
      expect(resolution.status, MaterialRetrievalResolutionStatus.available);
      expect(resolution.document, first.hits.single.document);
      expect(() => first.hits.clear(), throwsUnsupportedError);
      expect(() => snapshot.documents.clear(), throwsUnsupportedError);
      expect(await files.readDocument(LocalMaterialRetrievalService.indexCollection, 'books'),
          _indexJson('books', [_document()]));
    });

    test('service constructor retains the public storage corpus and provider labels', () async {
      // Given existing durable storage and an explicit actual lexical provider.
      const provider = LocalLexicalRetrievalProvider();
      final explicit = LocalMaterialRetrievalService(
          store: files, corpus: corpus, corpusId: 'Books_1-a', provider: provider);
      addTearDown(explicit.close);

      // When invalid token inputs reach the service constructor.
      final invalid = ['', '_books', '-books', 'a/b', '本', List<String>.filled(129, 'x').join()];

      // Then capability is lexical and caller token errors never become fallback stores.
      expect(explicit.capability, provider.capability);
      for (final id in invalid) {
        expect(() => LocalMaterialRetrievalService(store: files, corpus: corpus, corpusId: id),
            throwsArgumentError);
      }
      expect(await directory.list().toList(), isEmpty);
    });
  });

  group('fresh authoritative access and exact result guards', () {
    test('changed revision text title label and address stale a selected source without rebinding', () async {
      // Given one selected exact source and another valid searchable source.
      final original = _document();
      final other = _document(sourceId: 'other', text: '別の引用');
      corpus.documents = [original, other];
      final oldHit = (await service.search(MaterialRetrievalQuery('日本語'))).hits.single;
      final changes = [
        _document(revision: 'r2'),
        _document(text: '同じ版の変更された引用'),
        _document(title: '変更された題名'),
        _document(sourceLabel: '変更されたラベル'),
        _document(materialId: 'photo-2', regionId: 'region-2'),
      ];

      // When each changed current value retains only the same logical source key.
      for (final current in changes) {
        corpus.documents = [current, other];
        final resolution = await service.resolve(oldHit);
        final result = await service.search(MaterialRetrievalQuery('引用'));

        // Then opening is explicitly stale, current values persist and old evidence is never relabeled current.
        expect(resolution.status, MaterialRetrievalResolutionStatus.stale);
        expect(resolution.document, current);
        expect(resolution.document, isNot(oldHit.document));
        expect(result.hits.map((hit) => hit.document), containsAll([current, other]));
        expect(await files.readDocument(LocalMaterialRetrievalService.indexCollection, 'books'),
            _indexJson('books', [other, current]));
      }
      // Given the exact original product value becomes current again.
      corpus.documents = [original, other];
      // When the old hit is resolved against that complete current value.
      final restored = await service.resolve(oldHit);
      // Then only exact equality allows available; the old hit itself never mutates.
      expect(restored.status, MaterialRetrievalResolutionStatus.available);
      expect(restored.document, original);
      expect(oldHit.document, original);
    });

    test('deletion missing denied and identity replacement filter search and deny old opening', () async {
      // Given a readable selected hit and a second independent valid source.
      final original = _document(text: '秘密だった日本語の引用');
      final other = _document(sourceId: 'other', text: '公開されている引用');
      corpus.documents = [original, other];
      final oldHit = (await service.search(MaterialRetrievalQuery('秘密だった'))).hits.single;
      final states = <List<MaterialRetrievalDocument>>[
        [other],
        [other, _document(text: original.text, availability: MaterialSourceAvailability.missing)],
        [other, _document(text: original.text, availability: MaterialSourceAvailability.denied)],
        [other, _document(sourceId: 'replacement', text: '別の引用')],
      ];

      // When current authority removes, denies or replaces the selected logical identity.
      for (final state in states) {
        corpus.documents = state;
        final resolution = await service.resolve(oldHit);
        final oldSearch = await service.search(MaterialRetrievalQuery('秘密だった'));
        final validSearch = await service.search(MaterialRetrievalQuery('公開されている'));
        final persisted = await files.readDocument(LocalMaterialRetrievalService.indexCollection, 'books');

        // Then no prior or denied text/target is returned, while other valid sources remain available.
        expect(resolution.status, MaterialRetrievalResolutionStatus.unavailable);
        expect(resolution.document, isNull);
        expect(oldSearch.hits, isEmpty);
        expect(validSearch.hits.single.document, other);
        expect(jsonEncode(persisted), isNot(contains('秘密だった')));
      }
    });

    test('latest empty source suppresses prior text while a same revision update is observed', () async {
      // Given an indexed old source and its selected hit.
      final oldHit = (await service.search(MaterialRetrievalQuery('日本語'))).hits.single;

      // When current text changes without changing its opaque caller revision.
      final updated = _document(text: '新しい本文の引用');
      corpus.documents = [updated];
      final oldSearch = await service.search(MaterialRetrievalQuery('日本語'));
      final newSearch = await service.search(MaterialRetrievalQuery('新しい本文'));
      final updatedResolution = await service.resolve(oldHit);

      // Then no revision-only shortcut keeps stale text searchable or openable.
      expect(oldSearch.hits, isEmpty);
      expect(newSearch.hits.single.document, updated);
      expect(updatedResolution.status, MaterialRetrievalResolutionStatus.stale);
      expect(updatedResolution.document!.revision, oldHit.document.revision);

      // Given the current source now deliberately contains only whitespace.
      corpus.documents = [_document(text: ' \n　')];
      // When search and the previous hit resolve refresh that complete snapshot.
      final empty = await service.search(MaterialRetrievalQuery('引用'));
      final resolution = await service.resolve(newSearch.hits.single);
      // Then historical text stays suppressed and the old nonblank result is explicitly stale.
      expect(empty.hits, isEmpty);
      expect(empty.indexedSourceCount, 0);
      expect(resolution.status, MaterialRetrievalResolutionStatus.stale);
      expect(resolution.document!.text, ' \n　');
      expect(await files.readDocument(LocalMaterialRetrievalService.indexCollection, 'books'),
          _indexJson('books', []));
    });
  });

  group('strict persistence boundaries and explicit derived-cache rebuild', () {
    test('malformed index never auto-resets on search or resolve and explicit rebuild replaces it', () async {
      // Given a real selected hit, preserved source history, another index and malformed cache bytes.
      final hit = (await service.search(MaterialRetrievalQuery('引用'))).hits.single;
      await files.saveDocument('source_histories', 'quote', {'original': '人が保持する過去'});
      await files.saveDocument(LocalMaterialRetrievalService.indexCollection, 'other', {'keep': true});
      final history = await _documentFile(directory, 'source_histories', 'quote').readAsBytes();
      final other = await _indexFile(directory, 'other').readAsBytes();
      await _indexFile(directory, 'books').writeAsString('{broken');
      final loadsBefore = corpus.loads;

      // When ordinary operations encounter corrupt persisted JSON.
      await expectLater(service.search(MaterialRetrievalQuery('引用')), throwsFormatException);
      await expectLater(service.resolve(hit), throwsFormatException);

      // Then corruption is observable before source loading and the cache is not silently repaired.
      expect(corpus.loads, loadsBefore);
      expect(await _indexFile(directory, 'books').readAsString(), '{broken');

      // Given current authority has a successfully loadable changed source.
      final current = _document(revision: 'r2', text: '再構築する引用');
      corpus.documents = [current];
      // When the caller explicitly rebuilds this one derived index and searches it.
      await service.rebuild();
      final rebuilt = await service.search(MaterialRetrievalQuery('再構築'));
      // Then current evidence replaces only this cache; histories and other corpus indexes survive.
      expect(rebuilt.hits.single.document, current);
      expect(await files.readDocument(LocalMaterialRetrievalService.indexCollection, 'books'),
          _indexJson('books', [current]));
      expect(await _documentFile(directory, 'source_histories', 'quote').readAsBytes(), history);
      expect(await _indexFile(directory, 'other').readAsBytes(), other);
    });

    final corruptions = <String, void Function(Map<String, Object?>)>{
      'future version': (json) => json['version'] = 2,
      'noninteger version': (json) => json['version'] = 1.0,
      'wrong corpus': (json) => json['corpusId'] = 'other',
      'missing root key': (json) => json.remove('documents'),
      'extra root key': (json) => json['extra'] = true,
      'wrong document list': (json) => json['documents'] = {},
      'nonobject document': (json) => json['documents'] = ['invalid'],
      'extra source field': (json) => _entry(json)['extra'] = true,
      'missing source field': (json) => _entry(json).remove('revision'),
      'wrong text type': (json) => _entry(json)['text'] = 42,
      'blank revision': (json) => _entry(json)['revision'] = ' ',
      'blank title': (json) => _entry(json)['title'] = '',
      'blank label': (json) => _entry(json)['sourceLabel'] = '\t',
      'empty source': (json) => _entry(json)['text'] = '　',
      'unknown availability': (json) => _entry(json)['availability'] = 'unknown',
      'denied persisted text': (json) => _entry(json)['availability'] = 'denied',
      'missing persisted text': (json) => _entry(json)['availability'] = 'missing',
      'nonobject reference': (json) => _entry(json)['reference'] = [],
      'extra reference field': (json) => _referenceEntry(json)['extra'] = true,
      'missing explicit nullable field': (json) => _referenceEntry(json).remove('regionId'),
      'wrong nullable field type': (json) => _referenceEntry(json)['materialId'] = 3,
      'invalid source identity': (json) => _referenceEntry(json)['sourceId'] = '\u0000',
      'equal duplicate logical key': (json) => (json['documents']! as List).add(_entry(json)),
      'different address duplicate key': (json) {
        final copy = Map<String, Object?>.from(_entry(json));
        copy['reference'] = {..._referenceEntry(json), 'materialId': 'different', 'regionId': 'different'};
        (json['documents']! as List).add(copy);
      },
    };
    for (final corruption in corruptions.entries) {
      test('${corruption.key} is rejected without ordinary-operation repair', () async {
        // Given a selected real hit and a persisted closed-schema violation.
        final hit = (await service.search(MaterialRetrievalQuery('引用'))).hits.single;
        final invalid = _indexJson('books', [_document()]);
        corruption.value(invalid);
        await files.saveDocument(LocalMaterialRetrievalService.indexCollection, 'books', invalid);
        final before = await _indexFile(directory, 'books').readAsBytes();
        final loads = corpus.loads;

        // When search and resolve both cross the strict persistence boundary.
        await expectLater(service.search(MaterialRetrievalQuery('引用')), throwsFormatException);
        await expectLater(service.resolve(hit), throwsFormatException);

        // Then both fail before corpus loading and preserve the exact stored violation.
        expect(corpus.loads, loads);
        expect(await _indexFile(directory, 'books').readAsBytes(), before);

        // Given the caller explicitly authorizes derived-cache recreation from current authority.
        // When rebuild skips the rejected cache and a fresh query runs.
        await service.rebuild();
        final fresh = await service.search(MaterialRetrievalQuery('引用'));
        // Then only a successfully recreated current-source cache allows a result.
        expect(fresh.hits.single.document, _document());
        expect(await files.readDocument(LocalMaterialRetrievalService.indexCollection, 'books'),
            _indexJson('books', [_document()]));
      });
    }

    test('source load failure corpus mismatch and failed rebuild never return cached success', () async {
      // Given an accepted cached source, its hit and observable authority failure.
      final hit = (await service.search(MaterialRetrievalQuery('引用'))).hits.single;
      final before = await _indexFile(directory, 'books').readAsBytes();
      final failure = StateError('Current original cannot be loaded');
      corpus.onLoad = (_) => Future<MaterialRetrievalCorpusSnapshot>.error(failure);

      // When ordinary search/resolve and explicit rebuild cannot load current authority.
      await expectLater(service.search(MaterialRetrievalQuery('引用')), throwsA(same(failure)));
      await expectLater(service.resolve(hit), throwsA(same(failure)));
      await expectLater(service.rebuild(), throwsA(same(failure)));

      // Then no cached source is relabeled successful and no replacement is written.
      expect(await _indexFile(directory, 'books').readAsBytes(), before);

      // Given the borrowed port instead returns a complete snapshot for another corpus.
      corpus.onLoad = (_) async => MaterialRetrievalCorpusSnapshot(corpusId: 'other', documents: [_document()]);
      // When the bound service searches, resolves or rebuilds from the wrong authority.
      await expectLater(service.search(MaterialRetrievalQuery('引用')), throwsFormatException);
      await expectLater(service.resolve(hit), throwsFormatException);
      await expectLater(service.rebuild(), throwsFormatException);
      // Then this cache remains untouched rather than adopting another corpus identity.
      expect(await _indexFile(directory, 'books').readAsBytes(), before);
    });

    test('read and durable save IO failures propagate and later valid operations recover', () async {
      // Given an accepted hit and an observation wrapper over the actual file store.
      final hit = (await service.search(MaterialRetrievalQuery('引用'))).hits.single;
      final before = await _indexFile(directory, 'books').readAsBytes();
      final observed = _ObservedStore(files);
      final local = LocalMaterialRetrievalService(store: observed, corpus: corpus, corpusId: 'books');
      addTearDown(local.close);
      final readFailure = FileSystemException('read denied');
      observed.beforeRead = () async => throw readFailure;
      final loadsBefore = corpus.loads;

      // When reading the required cache fails.
      await expectLater(local.search(MaterialRetrievalQuery('引用')), throwsA(same(readFailure)));
      await expectLater(local.resolve(hit), throwsA(same(readFailure)));
      // Then no cached success or source-load shortcut conceals the failure.
      expect(corpus.loads, loadsBefore);
      expect(await _indexFile(directory, 'books').readAsBytes(), before);

      // Given current source changes and an actual destination directory blocks atomic file replacement.
      observed.beforeRead = null;
      corpus.documents = [_document(revision: 'r2', text: '変更された引用')];
      final blockerRoot = Directory('${directory.path}/blocked');
      final blockedFiles = FileCaptureStore(blockerRoot.path);
      await Directory('${blockerRoot.path}/documents/${LocalMaterialRetrievalService.indexCollection}/books.json')
          .create(recursive: true);
      observed.beforeSave = (json) => blockedFiles.saveDocument(
          LocalMaterialRetrievalService.indexCollection, 'books', json);

      // When changed sources require a durable save that really fails on the filesystem.
      await expectLater(local.search(MaterialRetrievalQuery('変更された')), throwsA(isA<FileSystemException>()));
      await expectLater(local.resolve(hit), throwsA(isA<FileSystemException>()));
      // Then failure is observable and the previous accepted cache remains intact.
      expect(await _indexFile(directory, 'books').readAsBytes(), before);

      // Given the write obstruction is removed from this service's borrowed port.
      observed.beforeSave = null;
      // When a subsequent invocation retries current-source reconciliation.
      final recovered = await local.search(MaterialRetrievalQuery('変更された'));
      // Then recovered queue state permits a genuine durably saved current result.
      expect(recovered.hits.single.document.revision, 'r2');
      expect(await files.readDocument(LocalMaterialRetrievalService.indexCollection, 'books'),
          _indexJson('books', corpus.documents));
    });
  });

  group('single-instance ordering cancellation and retirement', () {
    test('queued searches cannot overtake an older gated refresh', () async {
      // Given an older source load held at an observable gate and a newer source.
      final entered = Completer<void>();
      final release = Completer<MaterialRetrievalCorpusSnapshot>();
      final old = _document(text: '古い引用');
      final newer = _document(revision: 'r2', text: '新しい引用');
      corpus.onLoad = (call) {
        if (call == 1) { entered.complete(); return release.future; }
        return Future.value(_snapshot([newer]));
      };
      final completions = <String>[];

      // When two searches are invoked while the first source IO is still pending.
      final first = service.search(MaterialRetrievalQuery('引用'))
          .then((result) { completions.add('first'); return result; });
      await entered.future;
      final second = service.search(MaterialRetrievalQuery('引用'))
          .then((result) { completions.add('second'); return result; });

      // Then the queued command has not loaded or overwritten the older operation.
      expect(corpus.loads, 1);
      expect(await _indexFile(directory, 'books').exists(), isFalse);

      // Given the older load now completes with its original source snapshot.
      release.complete(_snapshot([old]));
      // When both commands are allowed to finish in their original invocation order.
      final firstResult = await first;
      final secondResult = await second;
      // Then the later fresh source is durably final and each reply describes its own load.
      expect(completions, ['first', 'second']);
      expect(firstResult.hits.single.document, old);
      expect(secondResult.hits.single.document, newer);
      expect(corpus.loads, 2);
      expect(await files.readDocument(LocalMaterialRetrievalService.indexCollection, 'books'),
          _indexJson('books', [newer]));
    });

    test('failure in an earlier queued load does not poison later commands', () async {
      // Given the first queued source load is gated and will fail observably.
      final entered = Completer<void>();
      final release = Completer<MaterialRetrievalCorpusSnapshot>();
      final failure = StateError('first load failed');
      corpus.onLoad = (call) {
        if (call == 1) { entered.complete(); return release.future; }
        return Future.value(_snapshot([_document(revision: 'r2')]));
      };

      // When a failed command precedes an already queued valid command.
      final first = service.search(MaterialRetrievalQuery('引用'));
      final firstExpectation = expectLater(first, throwsA(same(failure)));
      await entered.future;
      final second = service.search(MaterialRetrievalQuery('引用'));
      release.completeError(failure);
      await firstExpectation;
      final recovered = await second;

      // Then failure is preserved and the recovered tail executes the next current-source load.
      expect(recovered.hits.single.document.revision, 'r2');
      expect(corpus.loads, 2);
      expect(await files.readDocument(LocalMaterialRetrievalService.indexCollection, 'books'),
          _indexJson('books', [_document(revision: 'r2')]));
    });

    test('already canceled and canceled queued work never starts borrowed IO', () async {
      // Given a store observer and a token canceled before invocation.
      final observed = _ObservedStore(files);
      final local = LocalMaterialRetrievalService(store: observed, corpus: corpus, corpusId: 'books');
      addTearDown(local.close);
      final canceled = MaterialRetrievalCancellation()..cancel();

      // When search and rebuild are admitted with an already canceled token.
      await expectLater(local.search(MaterialRetrievalQuery('引用'), cancellation: canceled),
          throwsA(isA<MaterialRetrievalCanceled>()));
      await expectLater(local.rebuild(cancellation: canceled), throwsA(isA<MaterialRetrievalCanceled>()));
      // Then no borrowed storage or source operation has started.
      expect(observed.reads, 0);
      expect(observed.saves, 0);
      expect(corpus.loads, 0);

      // Given one active gated source load and a second command waiting behind it.
      final entered = Completer<void>();
      final release = Completer<MaterialRetrievalCorpusSnapshot>();
      corpus.onLoad = (_) { entered.complete(); return release.future; };
      final first = local.search(MaterialRetrievalQuery('引用'));
      await entered.future;
      final queuedCancellation = MaterialRetrievalCancellation();
      final queued = local.search(MaterialRetrievalQuery('引用'), cancellation: queuedCancellation);
      final queuedExpectation = expectLater(queued, throwsA(isA<MaterialRetrievalCanceled>()));

      // When the waiting command is canceled before the older load finishes.
      queuedCancellation.cancel();
      release.complete(_snapshot([_document()]));
      await first;
      await queuedExpectation;
      // Then the canceled queued command never reads, loads or writes after admission.
      expect(observed.reads, 1);
      expect(observed.saves, 1);
      expect(corpus.loads, 1);
    });

    test('cancellation during source load writes nothing and subsequent query is valid', () async {
      // Given a caller token and a gated actual source authority load.
      final cancellation = MaterialRetrievalCancellation();
      final entered = Completer<void>();
      final release = Completer<MaterialRetrievalCorpusSnapshot>();
      corpus.onLoad = (_) { entered.complete(); return release.future; };

      // When the caller cancels while load is pending and that IO later completes.
      final pending = service.search(MaterialRetrievalQuery('引用'), cancellation: cancellation);
      final expectation = expectLater(pending, throwsA(isA<MaterialRetrievalCanceled>()));
      await entered.future;
      cancellation.cancel();
      release.complete(_snapshot([_document()]));
      await expectation;

      // Then the canceled reply publishes no success and no index is written.
      expect(await _indexFile(directory, 'books').exists(), isFalse);
      expect(corpus.loads, 1);

      // Given the next invocation owns a fresh uncanceled command lifetime.
      corpus.onLoad = null;
      // When that subsequent query refreshes the same actual authority.
      final next = await service.search(MaterialRetrievalQuery('引用'));
      // Then cancellation has not changed source availability or poisoned the queue.
      expect(next.hits.single.document, _document());
      expect(corpus.loads, 2);
    });

    test('canceling rebuild during load preserves even a malformed old derived cache', () async {
      // Given a malformed cache and an explicit rebuild held at source loading.
      final file = _indexFile(directory, 'books');
      await file.parent.create(recursive: true);
      await file.writeAsString('{keep-until-success');
      final cancellation = MaterialRetrievalCancellation();
      final entered = Completer<void>();
      final release = Completer<MaterialRetrievalCorpusSnapshot>();
      corpus.onLoad = (_) { entered.complete(); return release.future; };

      // When rebuild is canceled before its source load completes.
      final pending = service.rebuild(cancellation: cancellation);
      final expectation = expectLater(pending, throwsA(isA<MaterialRetrievalCanceled>()));
      await entered.future;
      cancellation.cancel();
      release.complete(_snapshot([_document()]));
      await expectation;

      // Then explicit repair authority never writes from a failing/canceled load.
      expect(await file.readAsString(), '{keep-until-success');
    });

    test('cancellation during durable save may leave the atomic write but never returns success', () async {
      // Given a real file store with its write held before eventual atomic replacement.
      final observed = _ObservedStore(files);
      final entered = Completer<void>();
      final release = Completer<void>();
      observed.beforeSave = (_) { entered.complete(); return release.future; };
      final local = LocalMaterialRetrievalService(store: observed, corpus: corpus, corpusId: 'books');
      addTearDown(local.close);
      final cancellation = MaterialRetrievalCancellation();

      // When the caller cancels during save and borrowed IO then actually commits.
      final pending = local.search(MaterialRetrievalQuery('引用'), cancellation: cancellation);
      final expectation = expectLater(pending, throwsA(isA<MaterialRetrievalCanceled>()));
      await entered.future;
      cancellation.cancel();
      release.complete();
      await expectation;

      // Then the truthful canceled reply coexists with the completed atomic cache write.
      expect(await files.readDocument(LocalMaterialRetrievalService.indexCollection, 'books'),
          _indexJson('books', [_document()]));
      expect(observed.saves, 1);

      // Given a new current source after that canceled write.
      observed.beforeSave = null;
      corpus.documents = [_document(revision: 'r2', text: '次の引用')];
      // When the next command reloads and reconciles current authority.
      final next = await local.search(MaterialRetrievalQuery('次の'));
      // Then the surviving cache never replaces source truth and the queue remains usable.
      expect(next.hits.single.document.revision, 'r2');
      expect(observed.saves, 2);
      expect(corpus.loads, 2);
    });

    test('cancellation after index read prevents corpus load and resolve also honors caller lifetime', () async {
      // Given an actual selected hit and a subsequent index read held at a gate.
      final hit = (await service.search(MaterialRetrievalQuery('引用'))).hits.single;
      final observed = _ObservedStore(files);
      final entered = Completer<void>();
      final release = Completer<void>();
      observed.beforeRead = () { entered.complete(); return release.future; };
      final local = LocalMaterialRetrievalService(store: observed, corpus: corpus, corpusId: 'books');
      addTearDown(local.close);
      final cancellation = MaterialRetrievalCancellation();
      final loadsBefore = corpus.loads;

      // When resolve is canceled during the required persisted-index read.
      final pending = local.resolve(hit, cancellation: cancellation);
      final expectation = expectLater(pending, throwsA(isA<MaterialRetrievalCanceled>()));
      await entered.future;
      cancellation.cancel();
      release.complete();
      await expectation;

      // Then no source load or resolution success follows the canceled read.
      expect(corpus.loads, loadsBefore);
      expect(observed.saves, 0);
    });

    test('close retires synchronously joins the original tail and preserves borrowed resources', () async {
      // Given an active source load and another queued command on the same service.
      final entered = Completer<void>();
      final release = Completer<MaterialRetrievalCorpusSnapshot>();
      corpus.onLoad = (_) { entered.complete(); return release.future; };
      final active = service.search(MaterialRetrievalQuery('引用'));
      final activeExpectation = expectLater(active, throwsA(isA<MaterialRetrievalCanceled>()));
      await entered.future;
      final queued = service.rebuild();
      final queuedExpectation = expectLater(queued, throwsA(isA<MaterialRetrievalCanceled>()));
      var joined = false;

      // When close retires the service while its original borrowed IO is pending.
      final closing = service.close().then((_) { joined = true; });
      await expectLater(service.search(MaterialRetrievalQuery('引用')), throwsStateError);
      await expectLater(service.rebuild(), throwsStateError);

      // Then retirement rejects new work immediately but does not claim IO already ended.
      expect(joined, isFalse);
      expect(corpus.loads, 1);

      // Given the original source operation is now allowed to finish normally.
      release.complete(_snapshot([_document()]));
      // When the captured original tail, canceled active and canceled queued command all settle.
      await Future.wait([closing, activeExpectation, queuedExpectation]);
      await service.close();
      // Then no late result/cache was published and borrowed storage/corpus still work for the owner.
      expect(joined, isTrue);
      expect(corpus.loads, 1);
      expect(await _indexFile(directory, 'books').exists(), isFalse);
      corpus.onLoad = null;
      expect((await corpus.load()).documents.single, _document());
      await files.saveDocument('owner', 'still_open', {'usable': true});
      expect(await files.readDocument('owner', 'still_open'), {'usable': true});
    });

    test('close during save joins completed IO without publishing a late result', () async {
      // Given a pending write over actual durable storage.
      final observed = _ObservedStore(files);
      final entered = Completer<void>();
      final release = Completer<void>();
      observed.beforeSave = (_) { entered.complete(); return release.future; };
      final local = LocalMaterialRetrievalService(store: observed, corpus: corpus, corpusId: 'books');
      final pending = local.search(MaterialRetrievalQuery('引用'));
      final expectation = expectLater(pending, throwsA(isA<MaterialRetrievalCanceled>()));
      await entered.future;
      var joined = false;

      // When service retirement occurs during the borrowed atomic write.
      final closing = local.close().then((_) { joined = true; });
      await expectLater(local.resolve(const LocalLexicalRetrievalProvider()
          .search(MaterialRetrievalQuery('引用'), _snapshot([_document()])).hits.single), throwsStateError);
      // Then close is pending until the original write finishes.
      expect(joined, isFalse);

      // Given the original borrowed write is allowed to reach durable completion.
      release.complete();
      // When retirement and the canceled command finish joining that write.
      await Future.wait([closing, expectation]);
      // Then atomic bytes may remain but no successful result escapes after close.
      expect(joined, isTrue);
      expect(await files.readDocument(LocalMaterialRetrievalService.indexCollection, 'books'),
          _indexJson('books', [_document()]));
      expect((await corpus.load()).documents.single, _document());
    });
  });
}

final class _ScriptedCorpus implements MaterialRetrievalCorpus {
  _ScriptedCorpus(this.documents, {this.corpusId = 'books'});
  final String corpusId;
  List<MaterialRetrievalDocument> documents;
  int loads = 0;
  Future<MaterialRetrievalCorpusSnapshot> Function(int call)? onLoad;

  @override
  Future<MaterialRetrievalCorpusSnapshot> load() {
    loads++;
    return onLoad?.call(loads) ?? Future.value(
      MaterialRetrievalCorpusSnapshot(corpusId: corpusId, documents: documents),
    );
  }
}

/// Gates observe the public borrowed port; all accepted index IO still goes to
/// the actual FileCaptureStore rather than to an in-memory index substitute.
final class _ObservedStore implements LocalCaptureStore {
  _ObservedStore(this.delegate);
  final LocalCaptureStore delegate;
  int reads = 0;
  int saves = 0;
  Future<void> Function()? beforeRead;
  Future<void> Function(Map<String, Object?> json)? beforeSave;

  @override
  Future<Map<String, Object?>?> readDocument(String collection, String id) async {
    reads++;
    await beforeRead?.call();
    return delegate.readDocument(collection, id);
  }
  @override
  Future<void> saveDocument(String collection, String id, Map<String, Object?> document) async {
    saves++;
    await beforeSave?.call(document);
    await delegate.saveDocument(collection, id, document);
  }
  @override
  Future<List<String>> listDocumentIds(String collection) => delegate.listDocumentIds(collection);
  @override
  Future<Uint8List> readMaterial(CaptureMaterialReference reference) => delegate.readMaterial(reference);
  @override
  Future<CaptureMaterialReference> saveMaterial({required Uint8List bytes,
    required String mediaType, required DateTime capturedAt, String? originalName}) =>
      delegate.saveMaterial(bytes: bytes, mediaType: mediaType, capturedAt: capturedAt,
          originalName: originalName);
}

MaterialRetrievalCorpusSnapshot _snapshot(List<MaterialRetrievalDocument> documents) =>
    MaterialRetrievalCorpusSnapshot(corpusId: 'books', documents: documents);

MaterialRetrievalDocument _document({
  String materialSetId = 'book', String sourceId = 'quote',
  String? materialId, String? regionId, String revision = 'r1',
  String title = '本の題名', String sourceLabel = '引用', String text = '日本語の引用',
  MaterialSourceAvailability availability = MaterialSourceAvailability.available,
}) => MaterialRetrievalDocument(
  reference: MaterialSourceReference(materialSetId: materialSetId, sourceId: sourceId,
      materialId: materialId, regionId: regionId),
  revision: revision, title: title, sourceLabel: sourceLabel, text: text, availability: availability,
);

Map<String, Object?> _indexJson(String corpusId, List<MaterialRetrievalDocument> documents) => {
  'version': 1, 'corpusId': corpusId,
  'documents': documents.map((document) => <String, Object?>{
    'reference': <String, Object?>{
      'materialSetId': document.reference.materialSetId, 'sourceId': document.reference.sourceId,
      'materialId': document.reference.materialId, 'regionId': document.reference.regionId,
    },
    'revision': document.revision, 'title': document.title, 'sourceLabel': document.sourceLabel,
    'text': document.text, 'availability': document.availability.name,
  }).toList(),
};

Map<String, Object?> _entry(Map<String, Object?> json) =>
    (json['documents']! as List).first as Map<String, Object?>;
Map<String, Object?> _referenceEntry(Map<String, Object?> json) =>
    _entry(json)['reference']! as Map<String, Object?>;
File _documentFile(Directory directory, String collection, String id) =>
    File('${directory.path}/documents/$collection/$id.json');
File _indexFile(Directory directory, String corpusId) =>
    _documentFile(directory, LocalMaterialRetrievalService.indexCollection, corpusId);
