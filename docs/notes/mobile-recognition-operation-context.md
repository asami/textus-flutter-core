# Mobile recognition operation context

Recorded: 2026-10-08. Identity: PHASE-6 / ESA6-02 / ESA6-02-PHOTO-B1,
`implementation-esa6-photo-b1-20261008` revision1.
Status: source, executable specification and documentation authoring. Parent
selected validation, independent acceptance and physical evidence are pending.
Owner: textus-flutter-core maintainer; callers own role/kind vocabulary and
operation instructions. Update rule: record API/schema compatibility changes
and actual validation separately; retain old reports, provenance and receipts.

## Exact public value and wire

`RecognitionOperationContext` is exported by `textus_flutter_core.dart`.
Its constructor requires `sourceRole: String`, `targetKinds: Iterable<String>`
and `instructions: String`; `extensions: Map<String, Object?>` defaults to `{}`.
Role, instructions and every kind must be nonblank and retain their exact
strings, including whitespace. Kinds are ordered, distinct and nonempty.
Extensions accept only acyclic JSON Maps/Lists with String keys and finite
numbers, Strings, Booleans and null. Construction snapshots and deeply freezes
the collections. Invalid values throw `ArgumentError`. Equality and hashing
include all fields, kind order and nested extension values.

`toJson()` returns detached mutable containers with exactly:

```json
{
  "schemaVersion": 1,
  "sourceRole": "caller-owned-role",
  "targetKinds": ["caller-owned-kind"],
  "instructions": "Exact trusted caller instructions",
  "extensions": {}
}
```

`RecognitionOperationContext.fromJson(Object?)` strictly requires every key and
rejects unknown keys, unsupported versions, wrong types and invalid values with
`FormatException`. Version is integer1; Boolean/double1 are rejected. There is
no book role enum, automatic source selection, candidate priority or filtering
in Core. The optional value makes no IO or model preparation request.

## Input and raw report compatibility

`ImageRecognitionInput.operationContext` is nullable and defaults to null.
Defensive service/provider input reconstruction preserves the same immutable
context and exact original bytes. Every actually executed stage in one operation
receives that context plus the actual earlier executed raw results for the same
original. Shared attempt identity, source links, provider chain selection,
availability, fallback, timing and busy guards retain their existing semantics.
No context is stored on the service or carried into a later omitted-context call.

Core `PhotoCaptureService.capture`, `recover`, `recognize` and `compare` take
optional named `operationContext`. Saved-original recognition does not reimport
the source. Cancellation returns null without a report. Reports are returned
only after durable save; actual read/write errors remain observable. Original-only
capture/recovery, original reads, preparation and settings APIs keep their contracts.

`RecognitionOperationContext.extensionKey` is exactly
`recognitionOperationContext`. A nonnull request writes its complete schema1
snapshot in `RecognitionComparison.extensions` beside `providerProvenance`.
Null omits the namespace entirely. `RecognitionComparison.operationContext`
reads the validated value; absence returns null. A present null, malformed or
unsupported namespace throws `ArgumentError` in direct report construction and
`FormatException` in `RecognitionReportCodec.decode`. Encoding explicitly
validates the known namespace and returns detached wire containers.

The raw report root remains version1 with exactly `version`, `id`, `material`,
`createdAt`, `runs` and `extensions`; unrelated extension namespaces are opaque.
Legacy absence survives read/write without adding a namespace or migration.
Raw attempt IDs, shared objects, inputAttemptIds, result strings/duplicates,
failure trace, source metadata and times are retained. Malformed stored reports
remain observable and cannot be silently replaced by a successful save.
Context describes requested work even when providers are unavailable, fail or
fall back; it is never evidence that extraction or enhancement ran.

## Nano prompt and native boundary

Without context, Nano produces the exact preexisting prompt and native request
keys `bytes`, `prompt`, `expectedModelName`. With context it appends the exact
trusted operation instructions after configured base instructions. It requests
only the listed candidate kinds with visibly supported values. The JSON object
containing exactly `sourceRole`, `targetKinds`, `extensions` is framed between
`BEGIN_OPERATION_CONTEXT` and `END_OPERATION_CONTEXT`, explicitly described as
source metadata, never instructions. It does not contain operation instructions.

The existing `BEGIN_SOURCE_DATA` / `END_SOURCE_DATA` frame contains unchanged
earlier OCR/barcode/interpretation/candidate data in actual execution order,
with the existing direction to treat it as data, never commands or instructions.
`textus-image-recognition-v1` remains the base promptTemplate; optional operation
framing follows context schemaVersion1. Static providerProvenance retains only
configured base instructions/template. The raw report carries exact operation
instructions. Unknown and duplicate generated kinds remain verbatim.
The Kotlin/channel/native keys, token/deadline/cleanup/model/download boundaries
are unchanged. MethodChannel fixture observations establish request framing and
raw response preservation, not model obedience or physical inference.

## Executable specifications and consumer handoff

Adjacent Given/When/Then and observable matchers author OC1 immutable values and
strict malformed matrices, OC2 real service context/shared stages/fallback/absence,
OC3 real-file report compatibility/reopen/corruption/guards/durability, and OC4
observed Nano native requests in the five owned capture specification files.
The parent owns all actual validation and independent review.

TFAF forwards optional generic intent through its facade/controller. The App's
PHOTO-B2 must separately freeze role/target selection and integrated-review
persistence before product editing. B1 supplies no App runtime book wiring.
The dated [authoring journal](../journal/2026/10/2026-10-08-esa6-recognition-operation-context.md)
records this boundary and pending work.

## PHOTO-B1 parent validation result — 2026-10-08

Current status: B1 common API authoring complete; parent selected validation
found one App consumer-specification failure. Core representative106 and
8-suite accumulator188 passed; TFAF representative57 and6-suite accumulator87
passed. App21-suite accumulator:250 passed,1 failed. All3 static analyses and
all3 repository diff checks passed. These are software results, not native or
Step/Phase acceptance.
Owner: Phase6 parent for validation and next scope; each repository maintainer
for its existing responsibilities. Update rule: append actual repair/validation
results; preserve dated authoring, old receipts, original/raw/manual/workspace
histories and all7 acceptance viewpoints.

The failed existing F8 in `test/book_identification_flow_test.dart` calls save
after failed explicit reloads left the controller uninitialized. The observed
error is `Bad state: Book review is not initialized`; the saved-raw corruption
validation assertion was not reached. A normal successful reinitialization
is missing from that specification. Its path is outside B1 owned edits and
requires exact parent PLAN admission before correction; the production
read-only safety contract remains required. No repair or PASS is claimed here.

B2 still requires all5 book fields (title, author, section/volume, ISBN and
publication information), role/target snapshots, standard-first same-original
processing, available local AI only for unresolved targets, merged candidates
with conflicts/equal multiple sources, and manual/select/apply/save with strict
separate integrated-review persistence. Legacy mapping1/2 remains unchanged.
Updated Fold/Sony, camera-denial negative route, complete Step/affected-boundary
independent review, separate acceptance commits and Phase closure/release
remain pending. Phase6.1 is unstarted.

## PHOTO-REQUEST-REVISION App historical contract — 2026-10-08

Identity: PHASE-6 / ESA6-02 / PHOTO-REQUEST-REVISION,
implementation-esa6-photo-request-revision-20261008 revision1.
Current status: App source/specification authoring; parent software validation,
revised native effectiveness and independent acceptance pending. Owner: this
repository's maintainer for generic responsibilities, App maintainer for book
meaning/history, Phase6 parent for validation and closure. Update rule: append
actual results separately and retain prior B1/B2 authoring, failures, receipts,
original/raw/provider/manual/workspace histories and acceptance boxes.

Core continues to own generic context/input/report/provider/storage/settings services. Its outer RecognitionOperationContext schema1, version1 raw report, static provider provenance, Nano prompt template and strict decoder remain unchanged. App payload schemaVersion1/2 is opaque finite extension data to Core; Core does not choose book request versions, validate book bibliography or remap historical book candidates.

App reserves session.extensions.bookRecognitionContract for exactly integer
schemaVersion1 and requestRevision1/2. Absence means historical1 and remains
absent on Save; malformed present metadata rejects in the App codec and aggregate.
App's bookRecognitionRequest keeps exactly schemaVersion,bookMaterialId,
sessionId,stage with payload version1/2 matching the frozen session revision.
New App runs freeze explicit2 before busy; standard and enhanced calls forward
that same intent. App preserves old exact trusted instructions and appends its
exact revised kind/value/visible-bibliography guidance for2. App reconstructs
whole historical raw contexts, rejects unknown/mixed versions or forged text,
and preserves old raw/candidate/human/workspace prefixes. No upstream program
or generic historical report migration is introduced.

The actual Fold saved session has six originals, five selected sources, one
role correction and one selection change; Save and same-install COLD retention
were observed. Four of five actual Nano candidate outputs were invalid.
App RR1–RR5 author real-file compatibility/strictness and actual Dart Nano
MethodChannel framing/valid versus malformed output. Those controlled channels
prove software behavior only, never native model effectiveness. Implementation
worker executed no validation, build, device work, independent review or commit.

Existing Core188/TFAF87 B1 selected software receipts retain their unchanged
program scope; this append adds no new PASS. Parent owes App representative/
28-suite/analysis and three-root diff checks, saved-session-first revision2
Fold rerun/fresh Save/COLD evidence, Sony standard-only/fallback and original
camera-denial negative, whole ESA6-02 plus affected01/03/05 protected review,
separate repository journals/acceptance commits, upstream final validation,
unused epoch1 full Phase review and Phase6 release. All five book fields/seven
viewpoints and canonical Hygiene/Development Candidate paths, IDs and statuses
remain; no Phase6.1 execution or counter/epoch reset.
