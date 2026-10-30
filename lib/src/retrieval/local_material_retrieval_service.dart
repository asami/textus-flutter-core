import '../repository/local_capture_store.dart';
import 'material_retrieval.dart';

/// A durable, derived local index over a freshly loaded authoritative corpus.
/// Operations serialize on this instance only. Storage and corpus are borrowed;
/// neither cancellation nor close interrupts their IO or closes their resources.
final class LocalMaterialRetrievalService implements MaterialRetrievalService {
  LocalMaterialRetrievalService({
    required this._store,
    required this._corpus,
    required String corpusId,
    LocalLexicalRetrievalProvider? provider,
  }) : _corpusId = corpusId,
       _provider = provider ?? const LocalLexicalRetrievalProvider() {
    // Share the public corpus token validation with persistence inputs.
    MaterialRetrievalCorpusSnapshot(corpusId: corpusId, documents: const []);
  }

  static const String indexCollection = 'material_retrieval_indexes_v1';
  final LocalCaptureStore _store;
  final MaterialRetrievalCorpus _corpus;
  final String _corpusId;
  final LocalLexicalRetrievalProvider _provider;
  Future<void> _tail = Future<void>.value();
  Future<void>? _closeFuture;
  bool _retired = false;

  @override
  MaterialRetrievalCapability get capability => _provider.capability;

  @override
  Future<MaterialRetrievalResult> search(
    MaterialRetrievalQuery query, {MaterialRetrievalCancellation? cancellation}
  ) => _enqueue(cancellation, () async {
    final snapshot = await _refresh(cancellation);
    _check(cancellation);
    final result = _provider.search(query, snapshot);
    _check(cancellation);
    return result;
  });

  @override
  Future<MaterialRetrievalResolution> resolve(
    MaterialRetrievalHit hit, {MaterialRetrievalCancellation? cancellation}
  ) => _enqueue(cancellation, () async {
    final snapshot = await _refresh(cancellation);
    _check(cancellation);
    MaterialRetrievalDocument? current;
    for (final document in snapshot.documents) {
      if (document.reference.materialSetId == hit.document.reference.materialSetId &&
          document.reference.sourceId == hit.document.reference.sourceId) {
        current = document;
        break;
      }
    }
    if (current == null ||
        current.availability != MaterialSourceAvailability.available ||
        hit.document.availability != MaterialSourceAvailability.available) {
      return MaterialRetrievalResolution(
        status: MaterialRetrievalResolutionStatus.unavailable,
      );
    }
    return MaterialRetrievalResolution(
      status: current == hit.document ? MaterialRetrievalResolutionStatus.available :
          MaterialRetrievalResolutionStatus.stale,
      document: current,
    );
  });

  @override
  Future<void> rebuild({MaterialRetrievalCancellation? cancellation}) =>
      _enqueue(cancellation, () async {
        // Explicit rebuild does not decode an old derived cache. A failed load
        // still leaves that cache, all source histories and other indexes alone.
        final current = await _load(cancellation);
        final documents = _eligible(current);
        _check(cancellation);
        await _store.saveDocument(indexCollection, _corpusId, _encode(documents));
        _check(cancellation);
      });

  @override
  Future<void> close() {
    _retired = true;
    // Capture the original recovered tail, including every already queued task.
    return _closeFuture ??= _tail;
  }

  Future<T> _enqueue<T>(
    MaterialRetrievalCancellation? cancellation,
    Future<T> Function() operation,
  ) {
    if (_retired) {
      return Future<T>.error(StateError('Retrieval service is closed'));
    }
    final result = _tail.then((_) async {
      _check(cancellation);
      final value = await operation();
      _check(cancellation);
      return value;
    });
    _tail = result.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return result;
  }

  void _check(MaterialRetrievalCancellation? cancellation) {
    if (_retired) {
      throw const MaterialRetrievalCanceled();
    }
    cancellation?.throwIfCanceled();
  }

  Future<MaterialRetrievalCorpusSnapshot> _load(
    MaterialRetrievalCancellation? cancellation,
  ) async {
    _check(cancellation);
    final snapshot = await _corpus.load();
    _check(cancellation);
    if (snapshot.corpusId != _corpusId) {
      throw const FormatException('Current retrieval corpus identity mismatch');
    }
    return snapshot;
  }

  Future<MaterialRetrievalCorpusSnapshot> _refresh(
    MaterialRetrievalCancellation? cancellation,
  ) async {
    _check(cancellation);
    final saved = await _store.readDocument(indexCollection, _corpusId);
    _check(cancellation);
    final previous = saved == null ? null : _decode(saved);
    final current = await _load(cancellation);
    _check(cancellation);
    final documents = _eligible(current);
    if (previous == null || !_equalDocuments(previous, documents)) {
      _check(cancellation);
      await _store.saveDocument(indexCollection, _corpusId, _encode(documents));
      _check(cancellation);
    }
    return current;
  }

  List<MaterialRetrievalDocument> _eligible(MaterialRetrievalCorpusSnapshot snapshot) =>
      snapshot.documents.where((document) =>
        document.availability == MaterialSourceAvailability.available &&
        document.text.trim().isNotEmpty,
      ).toList()..sort((a, b) {
        final bySet = a.reference.materialSetId.compareTo(b.reference.materialSetId);
        return bySet != 0 ? bySet : a.reference.sourceId.compareTo(b.reference.sourceId);
      });

  Map<String, Object?> _encode(List<MaterialRetrievalDocument> documents) => {
    'version': 1,
    'corpusId': _corpusId,
    'documents': documents.map((document) => <String, Object?>{
      'reference': <String, Object?>{
        'materialSetId': document.reference.materialSetId,
        'sourceId': document.reference.sourceId,
        'materialId': document.reference.materialId,
        'regionId': document.reference.regionId,
      },
      'revision': document.revision,
      'title': document.title,
      'sourceLabel': document.sourceLabel,
      'text': document.text,
      'availability': document.availability.name,
    }).toList(),
  };

  List<MaterialRetrievalDocument> _decode(Map<String, Object?> json) {
    try {
      final root = _object(json, const {'version', 'corpusId', 'documents'});
      if (root['version'] is! int || root['version'] != 1 ||
          root['corpusId'] != _corpusId || root['documents'] is! List) {
        throw const FormatException('Invalid retrieval index header');
      }
      final documents = <MaterialRetrievalDocument>[];
      for (final value in root['documents']! as List) {
        final entry = _object(value, const {
          'reference', 'revision', 'title', 'sourceLabel', 'text', 'availability',
        });
        final reference = _object(entry['reference'], const {
          'materialSetId', 'sourceId', 'materialId', 'regionId',
        });
        final document = MaterialRetrievalDocument(
          reference: MaterialSourceReference(
            materialSetId: reference['materialSetId'] as String,
            sourceId: reference['sourceId'] as String,
            materialId: reference['materialId'] as String?,
            regionId: reference['regionId'] as String?,
          ),
          revision: entry['revision'] as String,
          title: entry['title'] as String,
          sourceLabel: entry['sourceLabel'] as String,
          text: entry['text'] as String,
          availability: MaterialSourceAvailability.values.byName(
            entry['availability'] as String,
          ),
        );
        if (document.availability != MaterialSourceAvailability.available ||
            document.text.trim().isEmpty) {
          throw const FormatException('Index may contain only available source text');
        }
        documents.add(document);
      }
      // This validates logical key uniqueness even when all other fields agree.
      return _eligible(MaterialRetrievalCorpusSnapshot(
        corpusId: _corpusId, documents: documents,
      ));
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Invalid retrieval index source value');
    }
  }
}

Map<String, Object?> _object(Object? value, Set<String> keys) {
  if (value is! Map || value.length != keys.length ||
      value.keys.any((key) => key is! String || !keys.contains(key))) {
    throw const FormatException('Invalid retrieval index object keys');
  }
  return Map<String, Object?>.from(value);
}

bool _equalDocuments(
  List<MaterialRetrievalDocument> first,
  List<MaterialRetrievalDocument> second,
) {
  if (first.length != second.length) {
    return false;
  }
  for (var i = 0; i < first.length; i++) {
    if (first[i] != second[i]) {
      return false;
    }
  }
  return true;
}
