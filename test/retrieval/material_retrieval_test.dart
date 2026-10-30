import 'package:flutter_test/flutter_test.dart';
import 'package:textus_flutter_core/textus_flutter_core.dart';

void main() {
  const provider = LocalLexicalRetrievalProvider();

  group('exact source values and caller authority', () {
    test('literal identities and every source field define value equality', () {
      // Given exact logical identities, nullable addresses and Unicode source text.
      final first = _document(text: '  「本」😀e\u0301\nＡＢ１２  ');
      final equal = _document(text: '  「本」😀e\u0301\nＡＢ１２  ');
      final addressed = _document(materialId: 'photo', regionId: 'region 1');
      final literal = MaterialSourceReference(materialSetId: ' 本 ', sourceId: '引用');

      // When equal values and individual product changes are compared.
      final variants = <MaterialRetrievalDocument>[
        _document(text: first.text, revision: 'r2'),
        _document(text: first.text, title: '別の本'),
        _document(text: first.text, sourceLabel: '別の引用'),
        _document(text: '別の本文'),
        _document(text: first.text, availability: MaterialSourceAvailability.denied),
        _document(text: first.text, materialId: 'photo'),
        _document(text: first.text, regionId: 'region 1'),
      ];

      // Then equality retains all exact fields, nulls and literal whitespace.
      expect(first, equal);
      expect(first.hashCode, equal.hashCode);
      expect(first.reference, equal.reference);
      expect(first.reference.hashCode, equal.reference.hashCode);
      expect(first.reference.materialId, isNull);
      expect(first.reference.regionId, isNull);
      expect(first.text, '  「本」😀e\u0301\nＡＢ１２  ');
      expect(variants, everyElement(isNot(first)));
      expect(addressed.reference.materialId, 'photo');
      expect(addressed.reference.regionId, 'region 1');
      expect(literal.materialSetId, ' 本 ');
      expect(literal, isNot(MaterialSourceReference(materialSetId: '本', sourceId: '引用')));
    });

    test('invalid source values fail as caller errors without trimming', () {
      // Given blank or control-bearing identities and blank descriptive values.
      final badIds = <String>['', '  ', '\n', 'a\u0000b', 'a\u007fb', 'a\u0085b'];

      // When each invalid value reaches the public value constructor.
      for (final id in badIds) {
        // Then every required and optional identity rejects caller misuse.
        expect(() => MaterialSourceReference(materialSetId: id, sourceId: 's'), throwsArgumentError);
        expect(() => MaterialSourceReference(materialSetId: 'b', sourceId: id), throwsArgumentError);
        expect(() => _document(materialId: id), throwsArgumentError);
        expect(() => _document(regionId: id), throwsArgumentError);
      }
      expect(() => _document(revision: ' '), throwsArgumentError);
      expect(() => _document(title: '\t'), throwsArgumentError);
      expect(() => _document(sourceLabel: ''), throwsArgumentError);
      expect(_document(text: '').text, isEmpty);
    });

    test('snapshot detaches inputs and rejects duplicate logical keys', () {
      // Given a complete snapshot including unavailable source states.
      final input = <MaterialRetrievalDocument>[
        _document(),
        _document(sourceId: 'missing', availability: MaterialSourceAvailability.missing),
        _document(sourceId: 'denied', availability: MaterialSourceAvailability.denied),
      ];
      final snapshot = MaterialRetrievalCorpusSnapshot(corpusId: 'Books_1-a', documents: input);

      // When the caller mutates its input or supplies repeated logical keys.
      input.clear();
      MaterialRetrievalCorpusSnapshot equalDuplicate() => _snapshot([_document(), _document()]);
      MaterialRetrievalCorpusSnapshot changedAddressDuplicate() => _snapshot([
        _document(materialId: 'one'), _document(materialId: 'two', regionId: 'region'),
      ]);

      // Then the snapshot is immutable and optional addresses cannot split a key.
      expect(snapshot.documents, hasLength(3));
      expect(snapshot.documents.map((document) => document.availability), [
        MaterialSourceAvailability.available,
        MaterialSourceAvailability.missing,
        MaterialSourceAvailability.denied,
      ]);
      expect(() => snapshot.documents.clear(), throwsUnsupportedError);
      expect(equalDuplicate, throwsArgumentError);
      expect(changedAddressDuplicate, throwsArgumentError);
    });

    test('corpus tokens match existing durable storage identity bounds', () {
      // Given safe boundary tokens and values that cannot name a store document.
      final longest = List<String>.filled(128, 'a').join();
      final invalid = ['', '_first', '-first', '../books', '本', ' a', '$longest-a'];

      // When snapshots are constructed with these exact corpus identifiers.
      final valid = MaterialRetrievalCorpusSnapshot(corpusId: longest, documents: const []);

      // Then 128 ASCII characters are accepted and invalid values are not rebound.
      expect(valid.corpusId, longest);
      for (final id in invalid) {
        expect(() => MaterialRetrievalCorpusSnapshot(corpusId: id, documents: const []),
            throwsArgumentError);
      }
    });
  });

  group('bounded explicit lexical query semantics', () {
    test('query preserves exact input and bounds scalars unique terms and limit', () {
      // Given astral input, repeated normalized terms and the query boundaries.
      final scalars256 = List<String>.filled(256, '😀').join();
      final terms16 = List<String>.generate(16, (i) => '語$i').join(' ');
      final repeated = List<String>.filled(40, 'Ａ a').join(' ');

      // When valid inputs and their next invalid boundary are constructed.
      final query = MaterialRetrievalQuery(' Ａ\tＡ\u3000a\n本 ', limit: 1);

      // Then exact input survives while normalized unique terms have strict bounds.
      expect(query.text, ' Ａ\tＡ\u3000a\n本 ');
      expect(query.terms, ['a', '本']);
      expect(() => query.terms.clear(), throwsUnsupportedError);
      expect(MaterialRetrievalQuery(scalars256).text.runes.length, 256);
      expect(MaterialRetrievalQuery(terms16, limit: 100).terms, hasLength(16));
      expect(MaterialRetrievalQuery(repeated).terms, ['a']);
      expect(() => MaterialRetrievalQuery('$scalars256😀'), throwsArgumentError);
      expect(() => MaterialRetrievalQuery('$terms16 語16'), throwsArgumentError);
      expect(() => MaterialRetrievalQuery('本', limit: 0), throwsArgumentError);
      expect(() => MaterialRetrievalQuery('本', limit: 101), throwsArgumentError);
      expect(query, MaterialRetrievalQuery(query.text, limit: 1));
      expect(query.hashCode, MaterialRetrievalQuery(query.text, limit: 1).hashCode);
    });

    test('Japanese phrases and AND terms use one title and its own source', () {
      // Given a Japanese phrase, one title/source pair and separated evidence.
      final exact = _document(sourceId: 'exact', title: '読書記録', text: '「猫のいる暮らし」を読む。');
      final splitTitle = _document(sourceId: 'title', title: '海辺の本', text: '山道を歩く');
      final splitText = _document(sourceId: 'text', title: '別の本', text: '夕日の記録');
      final snapshot = _snapshot([exact, splitTitle, splitText]);

      // When a literal phrase, a title/source conjunction and cross-source conjunction run.
      final phrase = provider.search(MaterialRetrievalQuery('猫のいる暮らし'), snapshot);
      final conjunction = provider.search(MaterialRetrievalQuery('海辺 山道'), snapshot);
      final crossSource = provider.search(MaterialRetrievalQuery('山道 夕日'), snapshot);
      final naturalPhrase = provider.search(MaterialRetrievalQuery('猫と暮らす方法'), snapshot);

      // Then only actual literal evidence within one document produces a hit.
      expect(phrase.hits.single.document, exact);
      expect(conjunction.hits.single.document, splitTitle);
      expect(conjunction.hits.single.snippet, '山道を歩く');
      expect(crossSource.hits, isEmpty);
      expect(naturalPhrase.totalMatches, 0);
    });

    test('only fullwidth ASCII space and ASCII case normalize', () {
      // Given exact fullwidth numbers, ASCII text, distinct Kana and combining text.
      final snapshot = _snapshot([
        _document(sourceId: 'width', text: 'ＡＢＣ１２　Quoted'),
        _document(sourceId: 'kana', text: 'カタカナ ｶﾀｶﾅ e\u0301 ①'),
      ]);

      // When explicit width/case equivalents and broader Unicode variants are queried.
      final ascii = provider.search(MaterialRetrievalQuery('abc12\u3000QUOTED'), snapshot);
      final fullwidth = provider.search(MaterialRetrievalQuery('ＡｂＣ１２'), snapshot);

      // Then original snippets survive and Kana/composed characters are not rewritten.
      expect(ascii.hits.single.snippet, 'ＡＢＣ１２　Quoted');
      expect(fullwidth.hits.single.document.reference.sourceId, 'width');
      expect(provider.search(MaterialRetrievalQuery('カタカナ'), snapshot).totalMatches, 1);
      expect(provider.search(MaterialRetrievalQuery('ｶﾀｶﾅ'), _snapshot([
        _document(text: 'カタカナ'),
      ])).hits, isEmpty);
      expect(provider.search(MaterialRetrievalQuery('かたかな'), snapshot).hits, isEmpty);
      expect(provider.search(MaterialRetrievalQuery('é'), snapshot).hits, isEmpty);
      expect(provider.search(MaterialRetrievalQuery('1'), _snapshot([
        _document(text: '①'),
      ])).hits, isEmpty);
    });

    test('whitespace empty and unavailable source text never enumerate sources', () {
      // Given available, blank, denied and missing documents with matching titles.
      final snapshot = _snapshot([
        _document(sourceId: 'valid'), _document(sourceId: 'blank', text: ' \t\n　'),
        _document(sourceId: 'denied', availability: MaterialSourceAvailability.denied),
        _document(sourceId: 'missing', availability: MaterialSourceAvailability.missing),
      ]);

      // When empty/Unicode-whitespace queries and an ordinary title match execute.
      final empty = provider.search(MaterialRetrievalQuery(''), snapshot);
      final whitespace = provider.search(MaterialRetrievalQuery('\t\n\u2003\u3000'), snapshot);
      final titleOnly = provider.search(MaterialRetrievalQuery('本'), snapshot);

      // Then no empty query lists all documents and only eligible sources count.
      expect(empty.hits, isEmpty);
      expect(empty.totalMatches, 0);
      expect(whitespace.hits, isEmpty);
      expect(titleOnly.hits.map((hit) => hit.document.reference.sourceId), ['valid']);
      expect(titleOnly.indexedSourceCount, 1);
      expect(titleOnly.hits.single.snippet, '日本語の引用');
      expect(provider.search(MaterialRetrievalQuery('存在しない'), snapshot).hits, isEmpty);
    });

    test('stable logical ordering limits returned hits but retains total matches', () {
      // Given unsorted matching sources and one unmatched available source.
      final snapshot = _snapshot([
        _document(materialSetId: 'b', sourceId: 'a'),
        _document(materialSetId: 'a', sourceId: 'z'),
        _document(materialSetId: 'a', sourceId: 'a'),
        _document(sourceId: 'unmatched', text: '別資料', title: '別資料'),
      ]);
      final query = MaterialRetrievalQuery('引用', limit: 2);

      // When the pure provider repeats a limited search.
      final first = provider.search(query, snapshot);
      final second = provider.search(query, snapshot);

      // Then the same exact values, counts and deterministic source order return.
      expect(first.hits.map((hit) => (hit.document.reference.materialSetId,
          hit.document.reference.sourceId)), [('a', 'a'), ('a', 'z')]);
      expect(first.totalMatches, 3);
      expect(first.indexedSourceCount, 4);
      expect(first.hasMore, isTrue);
      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first.capability.providerId, 'local-lexical-v1');
      expect(first.capability.mode, MaterialRetrievalMode.lexical);
      expect(first.capability.supportsSemanticRetrieval, isFalse);
      expect(first.capability.supportsQueryAssistance, isFalse);
      expect(provider.search(MaterialRetrievalQuery('引用'), snapshot).hasMore, isFalse);
    });
  });

  group('inspectable original Unicode snippets and immutable results', () {
    test('later source match centers exact scalar substring without splitting codepoints', () {
      // Given a long source containing astral and combining codepoints before a later match.
      final prefix = List<String>.filled(70, '😀e\u0301').join();
      final text = '$prefix「検索語」ＡＢ１２${List<String>.filled(180, '後').join()}';
      final document = _document(text: text);

      // When the later lexical term is retrieved.
      final hit = provider.search(MaterialRetrievalQuery('検索語'), _snapshot([document])).hits.single;
      final scalars = text.runes.toList();
      final expectedStart = prefix.runes.length + 1 - 40;

      // Then offsets address exact original scalars with 40 leading and at most 160 total.
      expect(hit.snippetStart, expectedStart);
      expect(hit.snippetEnd, expectedStart + 160);
      expect(hit.snippet, String.fromCharCodes(scalars.sublist(expectedStart, expectedStart + 160)));
      expect(hit.snippet.runes.length, 160);
      expect(hit.snippet, contains('「検索語」ＡＢ１２'));
      expect(hit.snippet, isNot(contains('\ufffd')));
      expect(hit.document.text, text);
    });

    test('earliest source term wins and title-only match uses the first original scalars', () {
      // Given early/late source terms and a separate title-only source match.
      final text = '${List<String>.filled(80, '前').join()}早い'
          '${List<String>.filled(100, '中').join()}遅い';
      final source = _document(text: text);
      final title = _document(text: '${List<String>.filled(170, '😀').join()}末', title: '題名一致');

      // When query term order differs from source order, and only a title matches.
      final earliest = provider.search(MaterialRetrievalQuery('遅い 早い'), _snapshot([source])).hits.single;
      final titleOnly = provider.search(MaterialRetrievalQuery('題名一致'), _snapshot([title])).hits.single;

      // Then source order controls context and title-only snippets still come from source text.
      expect(earliest.snippetStart, 40);
      expect(earliest.snippet, contains('早い'));
      expect(titleOnly.snippetStart, 0);
      expect(titleOnly.snippetEnd, 160);
      expect(titleOnly.snippet, List<String>.filled(160, '😀').join());
    });

    test('hit constructor enforces exact association bounds and eligibility', () {
      // Given a short original Unicode source and invalid snippet descriptions.
      final document = _document(text: '「本」😀e\u0301');

      // When a precise substring and fabricated/out-of-bounds variants are constructed.
      final hit = MaterialRetrievalHit(document: document, snippet: '😀e\u0301',
          snippetStart: 3, snippetEnd: 6);

      // Then only the original exact scalar interval is accepted.
      expect(hit.snippet, '😀e\u0301');
      expect(() => MaterialRetrievalHit(document: document, snippet: '別の本文',
          snippetStart: 0, snippetEnd: 3), throwsArgumentError);
      expect(() => MaterialRetrievalHit(document: document, snippet: '',
          snippetStart: -1, snippetEnd: 0), throwsArgumentError);
      expect(() => MaterialRetrievalHit(document: document, snippet: '',
          snippetStart: 3, snippetEnd: 2), throwsArgumentError);
      expect(() => MaterialRetrievalHit(document: document, snippet: '',
          snippetStart: 0, snippetEnd: 7), throwsArgumentError);
      expect(() => MaterialRetrievalHit(document: _document(text: '',
          availability: MaterialSourceAvailability.missing), snippet: '',
          snippetStart: 0, snippetEnd: 0), throwsArgumentError);
      final long = List<String>.filled(161, '本').join();
      expect(() => MaterialRetrievalHit(document: _document(text: long), snippet: long,
          snippetStart: 0, snippetEnd: 161), throwsArgumentError);
    });

    test('results detach hit lists and reject inconsistent counts', () {
      // Given a real provider hit and a caller-owned result input list.
      final query = MaterialRetrievalQuery('引用');
      final hits = provider.search(query, _snapshot([_document()])).hits.toList();
      final result = MaterialRetrievalResult(query: query, capability: provider.capability,
          hits: hits, totalMatches: 1, indexedSourceCount: 1);

      // When the input list is changed and invalid counts are supplied.
      hits.clear();

      // Then the accepted result remains immutable with honest pagination counts.
      expect(result.hits, hasLength(1));
      expect(() => result.hits.clear(), throwsUnsupportedError);
      expect(result.hasMore, isFalse);
      expect(() => MaterialRetrievalResult(query: query, capability: provider.capability,
          hits: result.hits, totalMatches: 0, indexedSourceCount: 1), throwsArgumentError);
      expect(() => MaterialRetrievalResult(query: query, capability: provider.capability,
          hits: [], totalMatches: 1, indexedSourceCount: 0), throwsArgumentError);
      expect(() => MaterialRetrievalResult(query: query, capability: provider.capability,
          hits: [], totalMatches: 0, indexedSourceCount: -1), throwsArgumentError);
    });

    test('cancellation is caller lifetime and unavailable resolutions hide documents', () {
      // Given caller cancellation and an available source value.
      final cancellation = MaterialRetrievalCancellation();
      final document = _document();

      // When the caller cancels and explicit resolution values are constructed.
      cancellation.throwIfCanceled();
      cancellation.cancel();
      cancellation.cancel();
      final available = MaterialRetrievalResolution(
          status: MaterialRetrievalResolutionStatus.available, document: document);
      final stale = MaterialRetrievalResolution(
          status: MaterialRetrievalResolutionStatus.stale, document: _document(revision: 'r2'));
      final unavailable = MaterialRetrievalResolution(status: MaterialRetrievalResolutionStatus.unavailable);

      // Then cancellation is typed and resolution status cannot leak denied text.
      expect(cancellation.isCanceled, isTrue);
      expect(cancellation.throwIfCanceled, throwsA(isA<MaterialRetrievalCanceled>()));
      expect(available.document, document);
      expect(stale.document!.revision, 'r2');
      expect(unavailable.document, isNull);
      expect(() => MaterialRetrievalResolution(status: MaterialRetrievalResolutionStatus.available),
          throwsArgumentError);
      expect(() => MaterialRetrievalResolution(status: MaterialRetrievalResolutionStatus.unavailable,
          document: document), throwsArgumentError);
      expect(() => MaterialRetrievalResolution(status: MaterialRetrievalResolutionStatus.stale,
          document: _document(availability: MaterialSourceAvailability.denied)), throwsArgumentError);
    });
  });
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
