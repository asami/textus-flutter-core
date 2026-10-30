# Shared text revision proposals

ESA68-S1-A@1 adds `GeneratedDraftOperation.textProofreading` and
`GeneratedDraftOperation.textReadability` to the existing generated-draft contract.
They are proposals for explicit human review. A request, a provider result or a
comparison never mutates the selected source or adopts text.

## Operations and source

Both operations require `GeneratedDraftSourceKind.text`, exact nonblank source
text and `imageBytes == null`. Empty or whitespace-only source text, image
sources, and any image bytes (including an empty buffer) fail at construction.
The caller selects the source and retains its exact identity, revision and
provenance. Whitespace, line breaks and Unicode spelling are not normalized.

`textProofreading` asks for minimal Japanese typo and punctuation correction.
Meaning, facts, names, numbers, quote characters and quoted content are preserved;
the prompt forbids summary, paraphrase and inferred bibliography.
`textReadability` is restricted to caller-selected personal annotations/comments.
It asks for more readable Japanese with the same meaning and no additional facts.
The shared library does not infer Book quotation versus comment roles; the
consumer must enforce this selection boundary. Both return proposal text only.

The existing image-description and text-summary operation names and substantive
instructions remain. `GeminiNanoGeneratedDraftProvider.promptTemplate` and every
current prompt header are `textus.generated-draft.ja.v3`. Text is JSON-encoded
exactly once between `BEGIN_SOURCE_JSON` and `END_SOURCE_JSON`; embedded newlines,
quotes, delimiters and instructions remain source-string data. Prompt constraints
describe requested behavior, not demonstrated model quality.

## Native and durable compatibility

The provider uses the existing `org.textus.flutter.core/genai.v1` `generateDraft`
method with exactly `requestId`, `operation`, `language`, `bytes`, `prompt` and
`expectedModelName`. Language remains exactly `ja`. All three text operations pass
null bytes through the genuine existing SDK text-only generation branch.
`imageDescription` requires a nonempty `ByteArray`. Unknown operation strings,
unsupported language, non-null text bytes, pseudo-image values, and extra or
missing fields fail parsing before model creation.

Model identity checks, explicit preparation, serialized service/provider ownership,
cancellation, deadlines and cleanup keep their existing behavior. No model,
dependency, download policy or network fallback is added.

Workspace schema version remains 1; source, availability, attempt and decision
key sets remain unchanged. New operation names round-trip in the existing enum
field. Historical image/summary attempts, including v2 prompt templates and exact
prompts, continue to decode without being rewritten. Loading neither generates
nor adopts. Retained history and source-identity checks still apply. Human
accept/edit/discard decisions remain separate from generation; an existing
explicit edit can carry an empty string as an intentional clear.

## Inspectable comparison

The public pure factory is
`TextRevisionComparison.between({required String original, required String proposed})`.
It exposes `original`, `proposed`, `unchangedPrefix`, `removedText`, `insertedText`,
`unchangedSuffix` and `hasChanges`. It first takes the longest common prefix in
Unicode scalar values, then the longest suffix that does not overlap that prefix
in either string. Both reconstruction identities hold exactly:

```
original = unchangedPrefix + removedText + unchangedSuffix
proposed = unchangedPrefix + insertedText + unchangedSuffix
```

Equal text has no changes, the entire string as its prefix, and empty removed,
inserted and suffix strings. Empty strings are accepted by the comparison even
though generation requires nonblank input. Astral characters are never split at
a UTF-16 surrogate boundary. Combining characters remain exact scalars without
normalization; a window may separate a base character from a combining mark.

This is one inspectable replacement window, not a minimal diff or selectable
hunks. Multiple interior edits remain in the same window. The whole selected text
is the adoption unit. The helper has no provider, persistence, I/O or adoption
logic. TFAF comparison/current-edit interaction and App Book adoption are later
consumer work; this slice does not deliver them or establish native qualification.
