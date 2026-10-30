# Source-linked structured candidates

Phase 6.6 of Editing Studio App consumes the additive public types exported from
`textus_flutter_core.dart`. Existing capture, transcript and region schemas stay
unchanged. `StructuredTextSource` identifies an original Material plus an OCR
report/attempt or an exact transcript revision/report; optional region identity
and revision retain geometry correspondence. Text spans use half-open UTF-16
offsets and must not split a surrogate pair.

`StructuredCandidateWorkspace` owns immutable sources, derived field proposals
and ordered human decisions. Generate/display does not confirm a value. Accept,
edit (including an empty clear) and discard are distinct decisions. An already
decided proposal cannot be applied again. Codecs reject malformed versions,
keys, spans and links. Prefix validation prevents history deletion/replacement.
Applications resolve retained source identities and apply domain values atomically
with decisions; the Core model does not own Book fields or repositories.

`StructuredCandidateService` preserves deterministic results and asks an optional
registered local provider only about unresolved fields. It probes capability
before invocation, rejects a remote provider, validates source/field/provider
ownership, and retains the baseline on unavailable or failed supplementation.
When deterministic results already cover every field, it reports `notRequested`
and does not probe; this is distinct from a provider lacking capability.
This interface does not claim that the existing image-only Gemini Nano provider
supports transcript structuring. No native structuring adapter is registered by
this change.
