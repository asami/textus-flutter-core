# Provisional semantic fixture Display source v1

Date: 2026-10-02
Owner: Core; app Phase 4, ESA4-03 / S01-semantic-fixture-source
Status: implementation and executable specifications authored; parent validation and independent review pending
Contract: [accepted candidate codec/context/port v1](display-prototype-contract-v1.md)
Consumer: [app R01–R10 and SC01–SC20](../../../../Project2026/nict-editing-studio-app/docs/notes/display-client-prototype-requirements.md)

## Responsibility and public API

`FixtureDisplaySource` is a development-only, domain-neutral semantic interpreter
of `DisplayPrototypeFixture`. The app supplies ordered semantic seeds, projection
and Operation bindings, labels and named templates. Core contains no app resource,
field, action or arm constants. This is deterministic client simulation; no real
CNCF admission, server delivery, network or persistence is established.

The public barrel exports `fixture_display_source.dart` additively. Its immutable
`FixtureSemanticResource` constructor requires named `resourceId`,
`sourceRevision` and `Map<String, DisplayValue> fields`. IDs and semantic keys are
nonblank and revision is a positive integer. Fields are defensively copied.
Source resource snapshots are newly immutable values; old snapshots never change.

`FixtureDisplaySource implements DisplayTransport` requires named `fixture`,
`listTemplateId`, `detailTemplateId`, `componentId`, `contextPolicy` and injected
`DateTime Function() nowUtc`. Templates select existing decoded List and Detail
envelopes of the right kinds. `fixture.reference.sampleId` identifies the source;
`fixture.resourceType` identifies its collection. Read-only `resources`, `calls`,
`callCount`, `operationCalls` and `operationCallCount` expose immutable semantic
snapshots and exact typed Display/Operation request observations.

`FixtureOrdinaryOperationTransport({required FixtureDisplaySource source})`
implements the separate `OrdinaryOperationTransport.execute` port. It shares the
supplied semantic source and never calls a Display port. Descriptor availability
and enabled flags do not grant execution authority.

`FixtureTransportFault` has `unavailable`, `ambiguousBeforeCommit` and
`ambiguousAfterCommit`. `failNextDisplay(kind, fault)` queues fault tags in an
independent FIFO for each Display method; `failNextOperation(fault)` uses another
FIFO. No queue, resource, projection or observation state is global.

`holdProjection()` captures current immutable resources and List snapshot once;
repeated holds are idempotent. Writes continue to commit live semantic data.
`releaseProjection()` immediately restores live projections.
`omitNextMutationProjection()` queues one omission of included Display on the
next successful changed/noop receipt; rejection/conflict/unsupported does not
consume it. Omission never rolls back semantic state.

## Strict interpreter admission

The generic fixture decoder remains unchanged. The source interprets these
closed mapping shapes, rejecting unsupported objects/types with `FormatException`
before use:

- `semanticSeed` is a nonempty ordered array of exact `resourceId`,
  `sourceRevision`, `fields` objects. Each fields map is nonempty and contains
  typed DisplayValue wire values. Duplicate IDs, invalid identifiers/revisions,
  missing/invalid values and unsupported shapes reject.
- `projectionBindings` contains exactly `screenId`, `sectionId`, `fields`.
  Ordered field bindings contain `fieldId`, `semanticField`, bool `writable`,
  bool `requiredNonBlank`, and optional nonempty string-to-string `lookup`.
  Field IDs are unique within the section and semantic keys exist in every seed.
  Writable values are Text and cannot have lookup. Read-only bindings cannot be
  required-nonblank. Lookup values are semantic Text; every initial and declared
  transition value has a mapping. Required Text constraints apply to seeds and
  declared transitions. There is no string coercion or inverse label lookup.
  After all bindings are validated, any lookup binding whose semantic key is
  writable through another binding rejects with
  `FormatException('Editable semantic field cannot use a lookup projection')`,
  independently of binding order. Direct aliases, read-only direct mirrors and
  multiple read-only lookup aliases remain supported; semantic keys need not
  be unique across bindings.
- Detail screen and its sole section match the binding identities; ordered
  fields match bindings. Title, labels, roles, field order and action descriptors
  come from the template. Template resource ID, values, revision and edit
  bindings are not semantic truth. List targets that Detail screen and has at
  least one row. The first row supplies labels/roles/order; every template row
  field has a unique corresponding binding. Seed order supplies actual rows.
- `operationBindings` is an ID-keyed map of exact `developmentOnly`,
  `inputFields`, `expected`, `transition` objects. Development-only is true;
  inputFields is exactly `[resourceId]`. Expected and transition are nonempty
  string-to-string maps of semantic Text keys in every seed. Transitions satisfy
  projection lookup and required-text constraints. Every template action has
  a binding; unknown references and shape/type mismatches reject admission.
- Fixture contexts have unique flow IDs and the configured source/component.
  Producer payloads and supplied arms are preserved. Constructor admission
  checks structure and identity independently of time, allowing expired
  fixtures to be exercised with an injected clock.

## Request admission, observations and delivery faults

Every request validates the explicitly UTC injected clock, resourceType when
present, and exact declared context flow before recording a call or consuming a
fault. Unknown flow throws `PresentationContextException` code `unknown-flow`.
Existing `PresentationContextPolicy.admit` checks source/component/flow;
`admitResponse` checks compatibility against that flow's initially supplied
context at the same instant. Responses echo admitted context, including permitted
optional omission. Producer attempt replacement follows existing policy. There
is no client arm allocation, payload merge, replacement or implicit default.
Invalid, expired or required unsupported context leaves call counts, semantic
state and queued faults untouched. S02 must separately prove common-session
pre-transport admission against raw ports.

After admission, the exact immutable request is recorded and one matching fault
is consumed. Unavailable throws unavailable before source changes. Before-commit
ambiguity throws ambiguous before changes. After-commit ambiguity throws
ambiguous only after a successful changed commit; noop/rejected/conflict/
unsupported outcomes return their actual decoded receipts. Query/read ambiguity
has no semantic effect and always throws ambiguous. This ordering simulates
specified delivery outcomes and does not infer real server delivery.

Async methods make each decision and commit synchronously before returning their
Future, without an await between revision comparison and mutation. There is no
retry, timer, callback or automatic reload. No command is automatically replayed.

## Projection and atomic update

Query projects ordered summaries from held/live resources. Each row has its own
source revision. Global List snapshot starts `snapshot-1`, advances once per
changed update/Operation, and equals provenance revision. List producer comes
from its selected template and source from the fixture. Read projects exact
resource revision provenance; missing identity throws unavailable without mutation.

Detail preserves template presentation structure. It projects typed semantic
values directly or through explicit Text lookup. Writable edit inputs retain
unprojected semantic Text; read-only input is Missing. Actions remain only while
all their Operation expected conditions match the projected resource, preserving
original descriptor enabled flags.

Update admission/fault ordering is followed by live resource lookup, revision
comparison, complete input validation, then atomic copy/equality/commit. Unknown
resource returns rejected with global `unknown-resource`, currentRevision null.
Stale observed revision conflicts with current live revision before equal values
can qualify as noop. Scoped errors are `duplicate-field`, `unknown-field` for
unknown/wrong-screen/wrong-section targets, `read-only`, `invalid-type` for
non-Text/Missing input, and `required-nonblank` for required empty or
Unicode-whitespace-only text. Null cannot enter the typed request codec.
Whitespace uses Dart trim including full-width space and explicitly U+0085;
stored valid text is never trimmed or normalized. Any required binding makes
that semantic key required for every writable direct alias; an optional alias
cannot bypass the constraint. Rejection uses `required-nonblank` at the submitted
locator, while emitted binding metadata keeps its original required flag.

Duplicate exact locators retain their existing rejection. Validated values from
distinct writable locators are also tracked by semantic key: equal typed Text
coalesces into one candidate value, and unequal values reject with
`duplicate-field` at the actual later conflicting locator in either input order.
Unknown, read-only, invalid-type and required-blank inputs retain their precedence
and never register a valid alias value. Revision comparison precedes this work.

All fields validate before mutation. One invalid field rejects the whole update
with immutable errors and unchanged source/snapshot. Empty or all-equal current
input yields noop: committedRevision null, currentRevision unchanged and included
held/live Detail unless omitted. Changed input preserves all unrelated fields and
resources, increments resource revision and snapshot exactly once, and returns
currentRevision=committedRevision=new revision with held/live Detail or null.
Failure receipts have no included Display, no committed revision and no mutation.
Create returns unsupported identity `unsupported:create`. Delete returns
unsupported with supplied identity and its known current revision, if any.

## Separate ordinary Operation

Execute records only the exact Operation request after context admission. Unknown
resource/operation reject globally with `unknown-resource`/`unknown-operation`.
Revision comparison precedes expected state: stale requests conflict; unmet state
rejects with `operation-precondition`. An admitted transition applies all declared
Text fields atomically, preserves unrelated fields/resources and advances resource
revision/snapshot once. An admitted equal transition still returns changed under
the existing Operation receipt contract. Its separate result has no Display body
and no implicit Display call. Only explicit later read/query projects the state.

## Specifications and remaining work

[Neutral public-API specification](../../test/display/fixture_display_source_test.dart)
covers initial ordering/provenance, atomic text preservation, noop/conflict/scoped
errors, unsupported/missing resources, separate Operations, held/omitted
projection, delivery faults/no replay, immutable observations/isolated instances,
strict interpreter admission and context/clock ordering. AL01–AL08 additionally
author both binding orders for editable lookup rejection, accepted direct and
read-only lookup aliases, shared required constraints, equal alias changed/noop
receipts and atomic conflicting alias rejection in both input orders. The
[actual asset consumer](../../../../Project2026/nict-editing-studio-app/test/display_fixture_source_test.dart)
authors app revision 1→2→3, coherent explicit reload, rejection/pending and
ambiguity evidence. Parent owns execution and fresh independent review; this
record claims no new successful test run.

S01 does not close ESA4-03. S02 must implement Core common session dispatch,
context propagation, loading/failure and freshness state. S03 must implement
TFAF registry, Editor/draft/navigation and adaptive presentation. ESA4-04 owns
complete composed SC01–SC20 acceptance; ESA4-05 owns Web 400/1200 observations,
feasibility feedback, final validation and distinct Phase review/release.
App Phase 5 retains real-server integration. Capture and legacy Resource/Settings
contracts retain their accepted behavior and independent package acceptance.
