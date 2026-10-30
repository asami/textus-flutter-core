/// The actual retrieval algorithm, independently of query presentation.
enum MaterialRetrievalMode { lexical }

/// Current access to a source, supplied by the corpus owner.
enum MaterialSourceAvailability { available, missing, denied }

final class MaterialRetrievalCapability {
  const MaterialRetrievalCapability({
    required this.providerId,
    required this.mode,
    required this.supportsSemanticRetrieval,
    required this.supportsQueryAssistance,
  });

  final String providerId;
  final MaterialRetrievalMode mode;
  final bool supportsSemanticRetrieval;
  final bool supportsQueryAssistance;

  @override
  bool operator ==(Object other) =>
      other is MaterialRetrievalCapability &&
      providerId == other.providerId &&
      mode == other.mode &&
      supportsSemanticRetrieval == other.supportsSemanticRetrieval &&
      supportsQueryAssistance == other.supportsQueryAssistance;

  @override
  int get hashCode => Object.hash(
    providerId, mode, supportsSemanticRetrieval, supportsQueryAssistance,
  );
}

/// Literal logical identities. Core never interprets these as filesystem paths
/// or decodes application-specific Book, material or region semantics.
final class MaterialSourceReference {
  MaterialSourceReference({
    required this.materialSetId,
    required this.sourceId,
    this.materialId,
    this.regionId,
  }) {
    _requireIdentity(materialSetId, 'materialSetId');
    _requireIdentity(sourceId, 'sourceId');
    if (materialId != null) {
      _requireIdentity(materialId!, 'materialId');
    }
    if (regionId != null) {
      _requireIdentity(regionId!, 'regionId');
    }
  }

  final String materialSetId;
  final String sourceId;
  final String? materialId;
  final String? regionId;

  @override
  bool operator ==(Object other) =>
      other is MaterialSourceReference &&
      materialSetId == other.materialSetId && sourceId == other.sourceId &&
      materialId == other.materialId && regionId == other.regionId;

  @override
  int get hashCode => Object.hash(materialSetId, sourceId, materialId, regionId);
}

/// An exact current source value; [revision] is the caller's product revision.
/// Empty source text is representable but is never indexed or returned as a hit.
final class MaterialRetrievalDocument {
  MaterialRetrievalDocument({
    required this.reference,
    required this.revision,
    required this.title,
    required this.sourceLabel,
    required this.text,
    required this.availability,
  }) {
    _requireNonblank(revision, 'revision');
    _requireNonblank(title, 'title');
    _requireNonblank(sourceLabel, 'sourceLabel');
  }

  final MaterialSourceReference reference;
  final String revision;
  final String title;
  final String sourceLabel;
  final String text;
  final MaterialSourceAvailability availability;

  @override
  bool operator ==(Object other) =>
      other is MaterialRetrievalDocument && reference == other.reference &&
      revision == other.revision && title == other.title &&
      sourceLabel == other.sourceLabel && text == other.text &&
      availability == other.availability;

  @override
  int get hashCode => Object.hash(
    reference, revision, title, sourceLabel, text, availability,
  );
}

/// A complete source-authoritative snapshot, including missing/denied sources.
final class MaterialRetrievalCorpusSnapshot {
  MaterialRetrievalCorpusSnapshot({
    required this.corpusId,
    required Iterable<MaterialRetrievalDocument> documents,
  }) : documents = List<MaterialRetrievalDocument>.unmodifiable(documents) {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(corpusId)) {
      throw ArgumentError.value(corpusId, 'corpusId', 'invalid storage token');
    }
    final keys = <(String, String)>{};
    for (final document in this.documents) {
      final reference = document.reference;
      if (!keys.add((reference.materialSetId, reference.sourceId))) {
        throw ArgumentError('Duplicate logical material source');
      }
    }
  }

  final String corpusId;
  final List<MaterialRetrievalDocument> documents;
}

abstract interface class MaterialRetrievalCorpus {
  Future<MaterialRetrievalCorpusSnapshot> load();
}

/// Caller-owned command cancellation. It does not interrupt borrowed IO.
final class MaterialRetrievalCancellation {
  bool _isCanceled = false;
  bool get isCanceled => _isCanceled;
  void cancel() => _isCanceled = true;
  void throwIfCanceled() {
    if (_isCanceled) {
      throw const MaterialRetrievalCanceled();
    }
  }
}

final class MaterialRetrievalCanceled implements Exception {
  const MaterialRetrievalCanceled();
  @override
  String toString() => 'Material retrieval canceled';
}

/// Bounded literal input. Only ASCII case and fullwidth ASCII/space normalize.
final class MaterialRetrievalQuery {
  MaterialRetrievalQuery(this.text, {this.limit = 50}) {
    if (text.runes.length > 256) {
      throw ArgumentError.value(text, 'text', 'at most 256 Unicode scalars');
    }
    if (limit < 1 || limit > 100) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 100');
    }
    if (terms.length > 16) {
      throw ArgumentError.value(text, 'text', 'at most 16 unique terms');
    }
  }

  final String text;
  final int limit;
  late final List<String> terms = List<String>.unmodifiable(
    _normalize(text).split(RegExp(r'\s+', unicode: true))
        .where((term) => term.isNotEmpty).toSet(),
  );

  @override
  bool operator ==(Object other) =>
      other is MaterialRetrievalQuery && text == other.text && limit == other.limit;
  @override
  int get hashCode => Object.hash(text, limit);
}

/// A source substring with half-open Unicode scalar offsets, without ellipses.
final class MaterialRetrievalHit {
  MaterialRetrievalHit({
    required this.document,
    required this.snippet,
    required this.snippetStart,
    required this.snippetEnd,
  }) {
    final scalars = document.text.runes.toList();
    if (document.availability != MaterialSourceAvailability.available ||
        document.text.trim().isEmpty || snippetStart < 0 ||
        snippetEnd < snippetStart || snippetEnd > scalars.length ||
        snippetEnd - snippetStart > 160 ||
        snippet != String.fromCharCodes(scalars.sublist(snippetStart, snippetEnd))) {
      throw ArgumentError('Snippet must be an exact eligible source substring');
    }
  }

  final MaterialRetrievalDocument document;
  final String snippet;
  final int snippetStart;
  final int snippetEnd;

  @override
  bool operator ==(Object other) =>
      other is MaterialRetrievalHit && document == other.document &&
      snippet == other.snippet && snippetStart == other.snippetStart &&
      snippetEnd == other.snippetEnd;
  @override
  int get hashCode => Object.hash(document, snippet, snippetStart, snippetEnd);
}

final class MaterialRetrievalResult {
  MaterialRetrievalResult({
    required this.query,
    required this.capability,
    required Iterable<MaterialRetrievalHit> hits,
    required this.totalMatches,
    required this.indexedSourceCount,
  }) : hits = List<MaterialRetrievalHit>.unmodifiable(hits) {
    if (totalMatches < this.hits.length || indexedSourceCount < totalMatches ||
        this.hits.length > query.limit || totalMatches < 0) {
      throw ArgumentError('Inconsistent retrieval counts');
    }
  }

  final MaterialRetrievalQuery query;
  final MaterialRetrievalCapability capability;
  final List<MaterialRetrievalHit> hits;
  final int totalMatches;
  final int indexedSourceCount;
  bool get hasMore => totalMatches > hits.length;

  @override
  bool operator ==(Object other) =>
      other is MaterialRetrievalResult && query == other.query &&
      capability == other.capability && totalMatches == other.totalMatches &&
      indexedSourceCount == other.indexedSourceCount &&
      _sameList(hits, other.hits);
  @override
  int get hashCode => Object.hash(
    query, capability, Object.hashAll(hits), totalMatches, indexedSourceCount,
  );
}

enum MaterialRetrievalResolutionStatus { available, stale, unavailable }

/// Stale is an explicit current value, never permission to navigate to it.
/// Unavailable carries no document, including no formerly readable denied text.
final class MaterialRetrievalResolution {
  MaterialRetrievalResolution({required this.status, this.document}) {
    if ((status == MaterialRetrievalResolutionStatus.unavailable) !=
        (document == null) ||
        (document != null &&
            document!.availability != MaterialSourceAvailability.available)) {
      throw ArgumentError('Resolution document does not match its status');
    }
  }

  final MaterialRetrievalResolutionStatus status;
  final MaterialRetrievalDocument? document;
}

abstract interface class MaterialRetrievalService {
  MaterialRetrievalCapability get capability;
  Future<MaterialRetrievalResult> search(
    MaterialRetrievalQuery query, {MaterialRetrievalCancellation? cancellation}
  );
  Future<MaterialRetrievalResolution> resolve(
    MaterialRetrievalHit hit, {MaterialRetrievalCancellation? cancellation}
  );
  Future<void> rebuild({MaterialRetrievalCancellation? cancellation});
  Future<void> close();
}

/// Pure lexical matching; all terms must occur within one document's title/text.
final class LocalLexicalRetrievalProvider {
  const LocalLexicalRetrievalProvider();

  MaterialRetrievalCapability get capability => const MaterialRetrievalCapability(
    providerId: 'local-lexical-v1',
    mode: MaterialRetrievalMode.lexical,
    supportsSemanticRetrieval: false,
    supportsQueryAssistance: false,
  );

  MaterialRetrievalResult search(
    MaterialRetrievalQuery query,
    MaterialRetrievalCorpusSnapshot snapshot,
  ) {
    final eligible = snapshot.documents.where((document) =>
      document.availability == MaterialSourceAvailability.available &&
      document.text.trim().isNotEmpty,
    ).toList()..sort((a, b) {
      final bySet = a.reference.materialSetId.compareTo(b.reference.materialSetId);
      return bySet != 0 ? bySet :
          a.reference.sourceId.compareTo(b.reference.sourceId);
    });
    final hits = <MaterialRetrievalHit>[];
    var totalMatches = 0;
    if (query.terms.isNotEmpty) {
      for (final document in eligible) {
        final title = _normalize(document.title);
        final source = _normalize(document.text);
        if (!query.terms.every((term) => title.contains(term) || source.contains(term))) {
          continue;
        }
        totalMatches++;
        if (hits.length == query.limit) {
          continue;
        }
        int? earliest;
        for (final term in query.terms) {
          final offset = source.indexOf(term);
          if (offset >= 0) {
            final scalarOffset = source.substring(0, offset).runes.length;
            if (earliest == null || scalarOffset < earliest) {
              earliest = scalarOffset;
            }
          }
        }
        final scalars = document.text.runes.toList();
        final start = earliest == null || earliest < 40 ? 0 : earliest - 40;
        final end = start + 160 < scalars.length ? start + 160 : scalars.length;
        hits.add(MaterialRetrievalHit(
          document: document,
          snippet: String.fromCharCodes(scalars.sublist(start, end)),
          snippetStart: start,
          snippetEnd: end,
        ));
      }
    }
    return MaterialRetrievalResult(
      query: query, capability: capability, hits: hits,
      totalMatches: totalMatches, indexedSourceCount: eligible.length,
    );
  }
}

String _normalize(String text) => String.fromCharCodes(text.runes.map((scalar) {
  if (scalar == 0x3000) {
    return 0x20;
  }
  var value = scalar >= 0xff01 && scalar <= 0xff5e ? scalar - 0xfee0 : scalar;
  if (value >= 0x41 && value <= 0x5a) {
    value += 0x20;
  }
  return value;
}));

void _requireNonblank(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must be nonblank');
  }
}

void _requireIdentity(String value, String name) {
  _requireNonblank(value, name);
  if (value.runes.any((scalar) => scalar < 0x20 ||
      (scalar >= 0x7f && scalar <= 0x9f))) {
    throw ArgumentError.value(value, name, 'must be control-free');
  }
}

bool _sameList<T>(List<T> first, List<T> second) {
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
