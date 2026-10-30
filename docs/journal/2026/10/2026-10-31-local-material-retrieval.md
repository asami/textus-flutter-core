# 2026-10-31 — Reusable local material retrieval authored

ESA69-S1-A authors Core's immutable material/source references, exact source
documents, bounded lexical queries, inspectable Unicode snippets, explicit
freshness results and caller-owned cancellation. `local-lexical-v1` is actual
literal retrieval; semantic retrieval and query assistance are unsupported.

`LocalMaterialRetrievalService` uses the existing borrowed capture store to
maintain one strict version 1 derived index per corpus. Every search/resolution
validates saved data, reloads current authority, filters access and reconciles
changed product values before returning. Explicit rebuild alone can replace a
malformed/future derived cache. Original bytes, source histories and other corpus
indexes stay outside that operation. Commands serialize on one service instance;
cancellation/retirement suppress success without pretending to interrupt IO.

Public value/provider and real file-store executable specifications are authored
with semantic Given/When/Then scenarios. The file scenarios include reopen,
source preservation, update/deletion/access guards, strict decoding, rebuild,
observable IO failures, queued failure recovery and controlled cancellation/close.
See [the retrieval contract](../../../notes/material-retrieval.md) for semantics.

Status: authored; parent analysis and focused execution, independent review,
full-validation gates and native/device qualification remain pending. This entry
does not record a passing run, Step acceptance, Phase completion or publication.
TFAF's common consumer follows in S1-B; Book/Annotation corpus composition and
pending-editor-preserving source navigation follow in S2 under App ownership.

## Parent qualification — 2026-10-31 JST

Core analyzer0 and80 focused checks passed. App analyzer0 and69 existing consumer checks also passed against actual Phase6.9 Core/TFAF composition. Fixture scheduling and callback assertion corrections retain their original matching expectations and all initial failures are local execution history. Independent protected-focused S1 acceptance and local commits remain pending, followed by App S2, native qualification and final Phase gates.

## ESA69-S1 accepted — 2026-10-31 JST

The complete Core/TFAF/App common boundary received independent protected-focused review. Its one original-command Cancel race was fixed within TFAF and independently closed by focused review. Core80, TFAF253 and App69 focused checks and all three analyzers passed. The Step is accepted for three dependency-ordered local commits. App S2 integration, Android qualification and final Phase gates remain pending; no publication or Phase completion is claimed.
