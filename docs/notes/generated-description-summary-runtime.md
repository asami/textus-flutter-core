# Generated image descriptions and text summaries

`GeneratedDraftService` is the common Core boundary for independent image
descriptions and text summaries. A borrowed `GeneratedDraftProvider` reports
operation/language availability, supplies its prompt template and exact prompt,
and returns its actual model and raw response. The generic injectable contract is
accompanied by `GeminiNanoGeneratedDraftProvider`, an optional Android adapter for
the Core GenAI companion. Authored adapter code and controlled specifications do
not establish device support or Japanese generation quality.

## Exact source and ephemeral request

`GeneratedDraftSource` records an exact source ID, material ID, revision and kind.
An image source has no text. A text source carries its original nonblank text,
including all surrounding whitespace. Region identity and positive region
revision occur together; an image region also identifies its parent material.
Every provided identity is nonblank, has no surrounding whitespace, and contains
no NUL. Caller-owned metadata is finite JSON copied into deeply immutable maps
and lists. Core retains such provenance as transcript report/index or annotation
revision without interpreting application histories.

An image-description request requires image bytes, copied into an unmodifiable
buffer. A text-summary request requires a text source and no image bytes. Bytes
are ephemeral and have no durable JSON representation. Requests default to `ja`
and publish limits of 512 output tokens and 2048 output Unicode scalar values.
The service rejects oversized output without truncating its raw response.
Each attempt needs a fresh request ID, including retries after failure or
cancellation; a service rejects reuse for its entire lifetime.

## Explicit readiness and serial completion

Availability is specific to provider, operation and language. `available` carries
the actual model name; every other state carries an explicit reason and can
leave an unknown model name null. A readiness probe performs no preparation or
generation. Explicit `prepare` probes first, invokes provider preparation only
for `downloadable`, and re-probes that same operation/language afterward.
`unsupported`, `unavailable`, `preparing` and `available` return their truthful
snapshot directly. Availability identity mismatches fail explicitly.

One service operation owns the busy guard from entry until all its awaited work
ends. Generation captures the source, provider ID, template, UTC start/end times,
availability, exact prompt computed once, actual model, raw text and cleanup
diagnostics. The available model is passed to the provider as `expectedModelName`.
Success requires that same actual model and nonblank prompt/output. Readiness
states produce distinct `unsupportedOperation`, `providerUnavailable`,
`preparationRequired` or `providerPreparing` failures without inference.
Model changes produce `modelChanged`; excessive output produces `outputTooLarge`.
Provider-returned failures retain their own code, explanation, model, raw output
and cleanup diagnostics. A thrown provider error becomes `providerFailure` with
its original description. Missing prompt or availability remains null when the
corresponding operation never completed.

Cancellation marks the current generation before asking the provider to cancel
that exact request ID. During explicit preparation or an ordinary readiness
probe there is no active generation to cancel. Cancellation during generation's
readiness probe prevents inference. After inference begins, cancellation keeps
the busy guard until both generation and the cancellation operation settle.
Late provider success, refusal to cancel, or a cancellation exception still
produces a canceled attempt. Actual raw output and cleanup diagnostics survive;
a cancellation exception adds its description to cleanup failures. Repeated
cancellation shares the current target. Idle cancellation returns false and
cannot reach a later request. No cancellation result is pending or adoptable.

Clocks must provide actual UTC timestamps with completion no earlier than start.
Invalid or backward clocks fail explicitly and release the busy guard; the
service does not fabricate a timestamp.

## Durable history and explicit adoption

`GeneratedDraftWorkspace` serializes exact attempts and terminal human decisions
under schema version 1. Its strict codecs reject missing/unknown keys,
unsupported enums/schema versions, wrong types and noncanonical UTC dates,
including rolled-over invalid dates. There is no schema migration fallback.
Collections are defensive immutable copies.

Attempt IDs are unique. Every occurrence of a source ID must retain the same
exact source value, comparing nested JSON maps independently of insertion order.
Only successful attempts can receive a decision, at most once and no earlier
than completion. `accept`, `edit` and `discard` remain separate from generation.
An edit carries exact text and permits an intentional empty clear; other decision
kinds carry no edited text. Successful undecided attempts remain pending in their
original order. Appending an attempt or deciding returns a new validated workspace.

`requireRetainedPrefix(previous, next)` rejects deletion, rewrite and reorder of
retained attempts and decisions by semantic product value. This protects
application history integrity. It supplies no workflow or artifact anti-tamper
mechanism.

## Optional Android plain-text draft protocol

`GeminiNanoGeneratedDraftProvider` identifies itself as
`gemini-nano-generated-draft` and uses prompt template
`textus.generated-draft.ja.v2`. Historical attempts retain their original v1
template and exact prompt. Only non-Web Android and language `ja` reach the
native bridge. Other platforms/languages return explicit unsupported snapshots
and generation failures without channel calls. The adapter uses the existing
`org.textus.flutter.core/genai.v1` channel. Its four native probe states map to
generated-draft readiness; available requires an actual nonblank model name and
all other native states require a nonblank reason. Missing registration is
`nativeBridgeUnavailable`; actual native and malformed-probe descriptions remain
unavailable reasons. A probe never qualifies Japanese output quality.

The image-description prompt asks for visible features and excludes guessed
unreadable text, titles, languages and document types. The text-summary prompt
asks for source content only, permits a single bullet for a short source,
excludes instructions and explanatory additions, and treats source instructions
as data. These are prompt requests, not factual-accuracy guarantees. Actual
device qualification found incorrect book-title readings even with v2; source
comparison and human review remain necessary. The exact original source text
is encoded with `jsonEncode` as one JSON
string between `BEGIN_SOURCE_JSON` and `END_SOURCE_JSON`. Prompt construction
preserves linefeeds and never trims or truncates source text. Prompt construction
does not probe, prepare or generate.

The additive `generateDraft` method accepts exactly six keys:

| Key | Meaning |
| --- | --- |
| `requestId` | Exact nonblank identity, without edge whitespace or NUL |
| `operation` | `imageDescription` or `textSummary` |
| `language` | Exactly `ja` |
| `bytes` | Nonempty original image bytes for description; exactly null for summary |
| `prompt` | Exact nonblank invocation prompt supplied to the adapter |
| `expectedModelName` | Exact supplied nonblank model name, or null |

Native parsing rejects unknown, missing, extra and incorrectly typed fields
before a model factory can run. Parsed image bytes are snapshotted before any
suspension and remain protected from caller mutation. A draft keeps the existing
90-second inference deadline, foreground requirement and single-request session
ownership. The runner creates one model, rechecks actual readiness and actual
model identity, rejects unavailable/changed models before inference, and never
downloads implicitly.

The production model uses the existing beta4 default stable client. Images use
an actual decoded `ImagePart` plus `TextPart`; summaries use only `TextPart` with
no image allocation. Both keep temperature 0, one candidate, 512 output tokens,
and the requirement that counted input tokens plus 512 fit the actual token
limit. Exactly one candidate is required. Draft text can be blank so Dart can
retain it truthfully in an `emptyResponse` failure. Existing recognition retains
its nonblank requirement and its separate recognition JSON parser/envelope.
Bitmap ownership stays within the same coroutine's finally; the runner closes
its model once after inference or failure.

The draft reply has exactly `requestId`, `text`, `modelName` and
`cleanupFailures`, delivered after cleanup. Dart requires the matching request
ID, a String raw response, an actual nonblank model and a list of nonblank
cleanup descriptions. Output is plain text, including surrounding whitespace;
there is no recognition JSON decoding or truncation. Blank output, model drift
and malformed envelopes fail explicitly while retaining independently valid
raw/model/cleanup evidence. A successful generation can retain image/model
cleanup failures. A primary native failure keeps its original code/description
with cleanup as additional evidence; a native `canceled` code maps to canceled
status. Service limits and cancellation adoption guards apply afterward.

The separate `cancelDraft` control method accepts exactly one key, `requestId`.
It is parsed before the regular foreground/busy admission gate, creates no model,
and immediately returns a boolean. True means cancellation intent was sent to
the exact current draft's owned job with code `canceled`; it does not mean native
terminal completion or cleanup has finished. An idle, detached, mismatched or
old recognition/preparation/probe owner returns false. Invalid arguments fail
with `invalidArguments`.

The Dart provider sends this control only for its exact active draft ID. Stale
and idle IDs cause no native call. Cancel bypasses its regular busy guard but
never clears that guard or active identity on acknowledgement. Native finish
delivers the generation terminal callback once after owned cleanup and clears
only the matching owner before invoking its callback. A callback may start a new
request without stale completion clearing it. Missing, native-error and malformed
cancel replies propagate to the service's cancellation diagnostics. Pause,
Activity detach, engine detach and deadlines retain the existing lifecycle
ownership behavior. Explicit preparation remains a null-argument, null-reply
`prepare`; no generation path hides preparation, retry or fallback.

## Consumer boundaries and executable specifications

The optional native provider implements this interface and its explicit readiness,
model identity and cancellation obligations. Existing image recognition APIs and
`StructuredTextSource` remain separate contracts. Core does not select a remote
backend, invoke OCR/ASR, own Book, change original media, or publish into a
replacement controller.

TFAF can consume the common service and immutable workspace/decisions while
keeping stale source and owner guards in its controller/panel. The App resolves
source metadata against its Book, image, region, transcript and annotation
histories; it presents independently labeled derived drafts and persists this
workspace through an additive extension. Human adoption and any representative
text change remain consumer responsibilities.

The authored Flutter specifications exercise immutable image/text inputs,
detached Japanese JSON roundtrips, exact human intent, strict malformed-data
rejection, semantic retained prefixes, ready generation, explicit preparation,
busy guards, duplicate IDs, cancellation races, model drift, scalar output limits,
provider diagnostics and clock failures. Their controlled provider exercises the
real Core service. The adapter specifications additionally author exact image/text
channel envelopes, plain Japanese raw-text roundtrips through the real provider
and service, malformed/native error retention, serial readiness/preparation and
exact pending cancellation. Native JUnit scenarios author strict protocol
admission, immutable image snapshots, nullable text-only input, readiness/model
rechecks, cleanup/primary failures, cancellation before dispatch and during
awaited cleanup, lifecycle deadlines, and callback ownership across newer drafts.
Each new or changed behavior has adjacent semantic Given/When/Then clauses.
Execution, analyzer results and native/device behavior require separate
parent-owned validation. Actual Japanese description/summary quality remains
unqualified until observed on the actual device; probe success is insufficient.
