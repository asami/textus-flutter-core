# Local material retrieval

Core owns the reusable source-reference, query, result and freshness contracts in
`material_retrieval.dart`, the actual `LocalLexicalRetrievalProvider`, and the
derived durable index in `LocalMaterialRetrievalService`. Both files are exported
through `textus_flutter_core.dart`. Applications supply a complete current
`MaterialRetrievalCorpus`; Core does not interpret application identities or
invent source access, network endpoints or generated evidence.

## Source and query contract

`MaterialSourceReference` retains exact logical Material Set/source identities
and nullable material/region addresses. Identities are nonblank and control-free,
are never trimmed, and are never used as file paths. A snapshot rejects repeated
Material Set/source keys even when material/region addresses differ. The caller's
opaque product revision, title, human source label, original text and availability
remain part of each exact immutable document. Missing and denied states remain
visible in the current corpus snapshot. Blank source text cannot produce a hit.

The actual provider is `local-lexical-v1`, mode `lexical`, with semantic retrieval
and query assistance both false. Queries preserve their input and allow at most
256 Unicode scalars, 16 distinct normalized whitespace-delimited terms, and a
result limit from 1 to 100 (default 50). Only fullwidth ASCII and fullwidth space
map to ASCII, and ASCII uppercase maps to lowercase. Japanese/Kana and other
Unicode retain their literal meanings; there is no general Unicode compatibility
normalization, segmentation, stopword removal, fuzzy matching or query rewriting.

All query terms must appear literally in one document's title or its source text.
Evidence never joins across documents. A Japanese natural-language phrase can be
entered directly, but receives the same literal lexical treatment. Empty or
whitespace input returns no hits. Results sort by exact Material Set ID then
source ID; the total counts all matches before the requested limit. The indexed
source count includes only available nonblank sources. No relevance or semantic
ranking is claimed.

Snippets always use the selected hit's original source text, including when only
its title matched. Half-open start/end offsets count Unicode scalars. The earliest
matching source term receives 40 scalars of leading context when possible, within
a maximum 160-scalar substring; title-only matches use the first 160 scalars.
Astral and combining codepoints remain intact, with no ellipsis inserted into
the stored substring. Presentation may use offsets to indicate omissions.

## Persistence and freshness

`LocalMaterialRetrievalService` borrows `LocalCaptureStore` and a current corpus.
Its public constructor accepts `store`, `corpus`, `corpusId`, and an optional
actual local lexical `provider`. Corpus IDs exactly match existing file-store
tokens: `^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$`. They are never trimmed or remapped.
No new storage schema, plugin or dependency is introduced.

The collection is `material_retrieval_indexes_v1`, with one document per corpus
ID. Version 1 JSON has exactly `version`, `corpusId`, and `documents`. Each source
has exactly `reference`, `revision`, `title`, `sourceLabel`, `text`, and
`availability`; references have exactly `materialSetId`, `sourceId`, `materialId`,
and `regionId`, with nullable addresses explicitly encoded. Only available,
nonblank original sources are persisted. Denied/missing plaintext is excluded.
All persisted types, keys, versions, identities, availability and duplicate keys
are validated strictly; persistence decoding failures surface as `FormatException`.
Caller constructor misuse is an `ArgumentError`.

Every search and resolution first reads and validates any saved index, then loads
the complete current corpus and verifies its bound identity. Available source
values reconcile the cache; unchanged product values avoid a write. The reply
waits for any needed durable save. Read, source-load or save failure remains an
observable failure, with no earlier snippet or cache substituted for source truth.
Equality here expresses ordinary business freshness, without checksums or
management certificates. The source may still change after an operation; there
is no transaction spanning external authority and cache IO.

Resolving a hit checks the same logical key against fresh authority. Only full
reference, revision, title, label, text and availability equality returns
`available` with the exact current document. Changed values return `stale` with
an explicit current value; that status grants no navigation to a replacement.
Absent, missing or denied sources return `unavailable` with no document. An old
identity is never rebound to another source. Applications must recheck their
actual domain/media/region links immediately before opening a resolved result.

Ordinary search and resolution never repair corrupt or future-version caches.
An explicit `rebuild` recreates only this derived corpus index from a successfully
loaded current snapshot, including when its old cache is malformed or newer.
Failed or canceled loading cannot write a replacement. Source histories,
original media, other collections and other corpus indexes are outside rebuild.
A reopened service/store reads the durable cache and still reloads current
source authority before answering.

## Operation lifetime

One service sequences commands in invocation order and recovers its queue after
failure. This prevents an older refresh from overwriting a later command on that
instance; it supplies no cross-instance/process lock or transaction. Caller-owned
`MaterialRetrievalCancellation` is checked before and after borrowed IO and before
save/publication. Canceled queued work is skipped before loading when possible.
Cancellation returns `MaterialRetrievalCanceled` and does not interrupt underlying
IO. An atomic save completed while cancellation was requested may remain; the
reply still reports cancellation and the next operation refreshes normally.

`close` retires the service synchronously, prevents active/queued success
publication, rejects new operations, and joins the originally queued cleanup.
It does not close the borrowed storage or corpus. There are no provider processes
or other unmanaged lifecycle resources.

## Authored evidence and downstream work

The two retrieval test files author public value/provider scenarios and actual
`FileCaptureStore` scenarios in test-owned directories. They include Japanese,
quotation, whitespace, fullwidth ASCII, astral and combining source text; durable
reopen and preservation of originals/histories/independent indexes; freshness and
availability; strict corrupted-cache cases; explicit rebuild; IO failures; and
gated ordering, cancellation and close. Every scenario records semantic
Given/When/Then comments at its setup, action and assertions.

This is ESA69-S1-A authored implementation, with parent execution, analysis,
independent review and acceptance still pending. The common TFAF consumer is
S1-B; application corpus/navigation integration is S2. Existing capture-store
consumers remain unchanged. Repository-full and native/device qualification
remain owning Phase gates. This note claims no passing execution, accepted Step,
completed Phase or publication.
