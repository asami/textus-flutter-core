# Generated description and summary common runtime

- Phase / Step / Slice: PHASE-6.7 / ESA67-S1 / S1-A.
- Authority: `esa67-phase-authority-001`, revision 1.
- Plan: `esa67-plan-001`, revision 1.
- Scope: Core reusable generated-draft contracts and serial service.

The implementation introduces independently retained image descriptions and text
summaries with exact source provenance. Sources preserve Japanese text and
caller-owned origin metadata. Image request bytes are immutable ephemeral input;
durable attempts retain provenance and provider evidence without embedding media.
The workspace records explicit accept/edit/discard decisions, including an empty
edit as a human clear, without changing the original source.

The new serialized contract uses strict schema version 1 and canonical UTC
timestamps. Source identity cannot be reused for changed content or metadata.
Retained attempt and decision prefixes compare semantic JSON product values so
map insertion order does not imply a rewrite. Deletion, reorder and actual
rewrites remain invalid. Decisions reference only successful completed attempts
and are terminal once recorded.

The service probes operation/language readiness before generation and captures
the available actual model and one exact prompt. Provider output must match that
model and stay within 2048 Unicode scalar values for success. Failures retain raw
responses and cleanup evidence; they do not truncate or infer success. Explicit
preparation invokes provider preparation only after a downloadable snapshot and
then re-probes. No probe or generation implicitly prepares a model.

Cancellation owns its exact active request until generation and cancellation
cleanup both settle. A canceled probe cannot begin inference; late output remains
canceled even if native cancellation is unsupported or throws. Raw output and
cleanup diagnostics survive while canceled attempts remain ineligible for human
adoption. Fresh IDs can start later requests after actual terminal completion.

Behavioral Flutter specifications were authored with adjacent semantic
Given/When/Then clauses. They cover immutable image/text input, Japanese raw-text
roundtrips and decisions, malformed durable data and history changes, serial
readiness/preparation, cancellation races, model mismatch, output size, native
failure evidence and invalid clocks. The provider fixture is a controlled generic
boundary, not a native implementation or Japanese quality claim.

The next boundaries are the native provider, TFAF controller/panel with stale
source and owner guards, and App source resolution plus additive persistence and
independent draft presentation. No existing recognition/source contract or
persistence version changes in this slice. Analyzer/test execution, independent
review and Phase/Step acceptance remain parent-owned work; this record makes no
passed-validation or completion claim.

## S1-B: optional Gemini Nano plain-text adapter

- Phase / Step / Slice: PHASE-6.7 / ESA67-S1 / S1-B.
- Authority: `esa67-phase-authority-001`, revision 1.
- Plan: `esa67-plan-001`, revision 1.
- Scope: optional Core Dart provider and additive Android draft protocol.

`GeminiNanoGeneratedDraftProvider` implements the existing S1-A provider boundary
without changing source, request, attempt, workspace or service signatures. Its
Japanese template `textus.generated-draft.ja.v1` produces an image-description
prompt from real image input or a text-summary prompt retaining exact original
text as a JSON string. Unsupported platform/language requests make no native
calls. Readiness is strict, explicit preparation uses the existing null envelope,
and generation sends the supplied prompt and expected model without recomputing
either. It never implicitly prepares, retries or falls back.

The existing `genai.v1` channel gains `generateDraft` and `cancelDraft`.
Generation has an exact six-key envelope carrying request ID, operation,
language, original image bytes or null, prompt and expected model. Native parsing
snapshots image input before suspension. One model rechecks readiness and actual
identity before invoking real image-plus-text or text-only SDK input under the
unchanged beta4 stable client and token/output configuration. Its exact four-key
response preserves request ID, raw plain text, actual model and cleanup after
model close. Blank draft responses remain available to Dart failure evidence;
old recognition retains its separate three-key input, JSON interpretation and
nonblank behavior.

Cancellation is a separate strict one-key control parsed before ordinary
foreground/busy admission. It acknowledges only an exact current draft; idle,
detached, mismatched and old operation owners return false without model creation.
Acknowledgement records intent while the owned coroutine completes cleanup and
delivers one terminal generation callback. Both provider and native session keep
busy ownership until actual terminal completion. Callback-started newer requests
remain protected against stale owner clearing. Lifecycle cancellation and
deadlines remain in the existing session. Native/cancel errors retain actual
diagnostics; the real service prevents adopting any late canceled output.

Authored Flutter scenarios connect the actual provider and service to a mock
channel for exact image/text arguments, prompts, expected/actual model, plain
Japanese raw-text persistence, strict readiness, malformed/error evidence and
pending cancellation. Authored native JUnit scenarios cover strict new argument
parsing and old recognition compatibility, defensive image ownership, true
nullable text-only model input, unavailable/model-changed no-infer behavior,
primary/cleanup failures, control acknowledgement before dispatch and during
awaited cleanup, stale IDs, lifecycle deadlines and callback-started new owners.
New and modified behaviors have adjacent semantic Given/When/Then clauses.

These are authored implementation/specification changes. No analyzer, Flutter,
Gradle, native compile or device execution result is asserted here. Actual
Japanese quality remains unqualified until real-device evidence exists; an
available probe alone cannot establish that quality. Independent review,
validation and Phase/Step acceptance remain parent-owned.

## Connected Book qualification and prompt correction

The subsequent Book integration exercised the real `nano-v4-full` model with
saved original/crop images, a retained Japanese transcript and a longer Japanese
annotation. Native generation, explicit decisions, cancellation and durable
reopen succeeded. The original v1 prompt leaked explanatory instructions into
the short summary. The v2 prompt removes that wording, restricts summaries to
source content and discourages guessed image details. Existing focused provider,
service and representation checks pass (132 cases); Core analysis reports no
issues. Old v1 attempts retain their original provenance without migration.

The v2 device run completed the same route and removed the observed short-summary
instruction leakage. Image descriptions still misread book titles, so this is
an editable, source-compared drafting capability, without bibliographic or OCR
accuracy assurance. App records own the complete integrated acceptance and
preservation correction; final owning validation and independent review remain
separate gates.

The connected Book Step independently accepted the v2 correction together with
source/decision persistence and real supported Android operation. The factual
image-description limits remain a separately recorded provider-quality task.
Phase-wide review and final owning full validation are still required.
