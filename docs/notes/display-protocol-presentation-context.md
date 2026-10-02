# Display Protocol and Presentation Context proposal

Date: 2026-10-02
Status: non-normative proposal; no implemented or frozen protocol is claimed
Consumer/parent: nict-editing-studio-app Phase 4
History: [responsibility decisions](../journal/2026/10/2026-10-02-display-protocol-context-responsibilities.md)

## Purpose and authority

Extend the [client runtime direction](../journal/2026/09/2026-09-29-display-model-client-runtime.md)
with the UI-driven [app protocol/server-model proposal](../../../../Project2026/nict-editing-studio-app/docs/notes/display-protocol-presentation-context-proposal.md).
The accepted fake UI and development-only server sample supply requirements;
server implementation need not be complete before this proposal is prepared.
CNCF owns the versioned wire protocol and ExecutionContext projection. Core
consumes their reviewed codec and fixtures rather than introducing a local
semantic model or an Editing Studio-specific protocol.

## Core responsibilities

- Decode/validate protocol, model/context families and compatibility metadata;
  expose presentation-neutral runtime models and replaceable sources.
- Execute admitted Display query/read/mutation and ordinary REST Operation
  bindings through common transport/dispatch facilities.
- Receive, retain and propagate Presentation Context within its admitted flow.
- Provide common loading/failure/refresh state, committed revision and Display
  readiness so clients can distinguish conflict from projection pending.
- Enforce context lifetime, declared inheritance, replacement and unsupported
  or expired-context policy; prevent cross-flow context leakage.

Core does not choose screen layout or resolve arm-to-UI definitions. TFAF owns
that presentation behavior. The app supplies declarative UI configuration,
resource/domain bindings and composition through public APIs.

## Generic Presentation Context

Presentation Context is a bounded projection of CNCF ExecutionContext,
including admitted evaluation, scope and correlation information required for
presentation/continuation. It is not the complete runtime object or a new
client-owned execution authority. It excludes runtime service capabilities,
UnitOfWork and internal security objects.

The logical protocol distinguishes data from context. Model the latter with
namespaced, versioned typed families. Each declares producer, readers/updaters,
lifetime, propagation scope, merge/replacement behavior and required/optional
compatibility. Candidate families include locale/presentation, supplied
experiment/arm assignment and permitted correlation references. Exact source
mapping, namespace spelling, JSON/header placement and public API types are
review questions, not APIs introduced by this note.

Known family decoding is strict. Carrying unknown optional content opaquely
requires a bounded, explicit codec/propagation rule. Client context neither
changes permissions nor grants assignment; CNCF validates/rebinds continuation.
Observed resource revision stays on the existing transport contract. Protocol
version, context version, definition version and resource revision stay distinct.

## Continuation and experiment context

Carry the declared context through List query, Detail read, standard update,
direct Business Operation, explicit reload and retry without application-owned
copying. Attempt correlation can change while the admitted flow/assignment
reference remains, according to CNCF policy. A context is scoped to its flow;
restart persistence, expiration, logout, server/component changes and nested
operation inheritance must have explicit rules.

Existing CNCF Operation Evaluation freezes assignment for one logical execution.
Continuity across separate UI Operations requires an explicit admission and
continuation handoff. Core must not assume arbitrary nested calls inherit an
assignment or send serialized ExecutionContext back as execution authority.
Existing [CNCF evaluation design](../../../../dev2025/cloud-native-component-framework/docs/design/operation-evaluation-capture.md)
is the source boundary to reconcile.

A/B and multi-arm information travels as context. Core transports supplied arm
identity; TFAF resolves the corresponding registered presentation definition.
Experiment/server owners allocate arms, own definitions/runs and evaluate
results. App screens do not branch on experiment/arm IDs or manage propagation.
This includes deterministic fixed-arm fixtures supplied by verification.
No UI experiment metric/exposure subsystem is implied by this context support.

## Server-model handoff required by the client

Receive explicit resource identity/revision, typed display and input values,
field locators/constraints/editability, capabilities and separate Business
Operation bindings. Derived fields remain read-only unless server bindings
admit updates. Receive context projection and continuation rules tied to CNCF
ExecutionContext. A committed update with pending Display must preserve its
committed identity/revision; transport/refresh state must not encourage replay
of a committed command. Physical error and pending representations remain open.

## Proposed verification and dependencies

- Matching server/CNCF/Cozy codec and context fixtures with versions/provenance.
- Lossless admitted context round-trip, strict incompatible-version rejection
  and policy-defined optional/required handling.
- Isolated flows, lifecycle/expiration, retries and Operation/reload continuity.
- Strong revision transport, field errors/conflict and committed/pending state.
- Public runtime APIs allow TFAF presentation selection while the app composes
  configuration without direct JSON parsing or context management.

The [TFAF proposal](../../../textus-flutter-application-framework/docs/notes/display-protocol-context-realization.md)
owns selection/visual verification. Core does not depend on TFAF. The app
Phase 4 owns client prototype feasibility; Phase 5 owns real-server
aggregate/E2E acceptance. Dependency handoffs retain focused
verification. Owning Core Phase bindings are resolved with the frozen minimum
protocol; this note creates no new Phase or acceptance and reopens no release.

## Client prototype scope update — 2026-10-02

The user clarified that app Phase 4 ends at provisional client implementation
and feasibility exploration. It uses development-only sample models and
controllable fake transport/Operations to prove the Core/TFAF/app boundary,
context continuation and supplied-arm UI. Findings revise protocol/server-model
proposals. Completed server implementation and frozen wire contracts are not
prototype closure prerequisites; simulation does not prove real CNCF admission.
App Phase 5 consumes this prototype and owns real-server integration and final
aggregate/E2E acceptance. Dependency contracts/Phases retain separate acceptance.

## ESA4-02 acceptance and semantic source Slice — 2026-10-02

The proposal above records its historical scope. ESA4-02 is now accepted and
locally committed: Core `7a38c67e165cceb25f85a310ed5582491553d64f`, TFAF
`0b3ebaab0f33762c371c21cd2aabbecf716e4810`, app
`739d4694811a46f21ee80cb92fe67a4461e2adc2`; see the
[shared review/M0 lineage](../journal/2026/10/2026-10-02-display-prototype-esa4-02-acceptance.md).
Candidate codecs/context/ports/fixture data are accepted within app prototype
scope; real CNCF wire/admission and separate package Phases remain independent.

ESA4-03 is in_progress/OPEN. Its S01
[semantic source contract](../design/display-fixture-source-v1.md) adds a generic
seed-backed source, atomic revision-aware update, separate Operation transition,
context admission and controllable held/omitted/fault projection evidence.
Executable specifications are authored; parent validation/review remains pending.
S02 common session/context/loading/freshness and S03 TFAF realization remain
required. This Slice supplies no runtime UI, SC01–SC20 or Phase closure claim.

## ESA4-03 / S02 common session handoff — 2026-10-02

Current status: S01 accepted; S02 authored awaiting parent checks/review; Step OPEN
Owner: Core under app Phase 4
Update rule: Append actual evidence; retain historical proposals and acceptance lineage.
Closure basis: Source/session plus TFAF S03, public consumers, independent Step acceptance and commit; full Phase gates remain required.

The preceding pending-source sentences describe their authoring point. S01 now
has 139 actual targeted successes, clean selected analyzers, independent review
`esa4-03-s01-review-20261002-root-01` and eligible authoring M0 amendment
`esa4-03-s01-gwt-parent-m0-amendment-20261002-root-01`, retained at ledger9.
[The Slice journal](../journal/2026/10/2026-10-02-display-prototype-esa4-03-slices.md)
records this boundary without closing ESA4-03.

[DisplaySession v1](../design/display-session-v1.md) is an additive public
ChangeNotifier API with immutable state, fixed flow/configured identities, common
typed request construction and existing producer-policy admission before effects
and reply adoption. Consumers invoke query/read/update/create/delete/Operation,
explicit Reload and safe retries without copying context or constructing request
metadata. Command history/commit floors remain distinct from stale or failed
projection. Update publishes an admitted changed/noOp receipt before bounded
read-then-query refresh; ordinary Operation has zero implicit Display calls.
Uncertain delivery has no automatic read/replay; safe explicit coherence permits
a later new command while historical failure stays failed. Disposal prevents late
publication/continuation and synchronous listener reentry encounters busy.

[The runtime specification](../../test/display/display_runtime_test.dart) authors
DS01–DS43 with 98 expanded cases. Four public App actual-asset cases supplement
the source proof. S02 validation and complete-Step independent conformance review
are pending. TFAF S03 owns definition selection, editor/draft/navigation/adaptive
UI; Core does not allocate/select supplied arms or inherit persisted context.
All SC01–SC20, Web400/1200, feedback/final validation/Phase review/release remain
required. Production wire/admission remains CNCF/server and app Phase 5 work.

## Current S02 acceptance / S03 authoring projection — 2026-10-03

Current status: S01 and S02 accepted; S03 authored pending parent validation and independent review; ESA4-03 and SC01–SC20 OPEN.
Owner: Core session/source, TFAF presentation and app public consumers under the original app Phase 4 authority.
Update rule: Retain historical authoring/pending statements and native failure/review/M0 lineage; this dated projection supersedes their current-status wording.
Closure basis: Actual selected SDK evidence, complete-Step independent review and separate Step commit; ESA4-04/05 and all final Phase gates remain mandatory.

S02 has 237 actual selected successes with clean selected analyzers/format and
independent protected review `esa4-03-s02-review-20261003-root-01` revision 1
PASS at review ledger revision 10. The closed constructor batch and exact 41
captured accepted inputs are preserved. Earlier S02 pending/check/review sentences
record the historical authoring point and no longer describe the current boundary.

S03 authors public `DisplayDefinitionRegistry`, immutable `DisplayDraft` and
`DisplayPresentationState`, owned `DisplayPresentationController` and borrowed
`DisplaySessionView`. Full namespace/set/arm/version lookup has explicit neutral
policy and visible incompatibility. Typed scoped input retains the observed
revision; matching changed/noOp receipt clears submitted input before refresh.
Failure/conflict retains input until explicit reconciliation. Reset adopts only
an explicit pristine new fixed-flow session; late UI/dialog actions retain their
captured session identity. Owned Core disposal is immediate; notifier release
uses one microtask. Ordinary Operation has no implicit Display reload.

The new authored matrix contains RG01–RG12 (23 expanded cases), ED01–ED25
(48), VW01–VW20 (32), plus AF01–AF04 (four actual unchanged-asset public widget
consumers). Standard/cards/sections, locale, Common Settings and400/1200 adaptive
choices use generic public composition. Authored specifications provide no SDK
result or composed SC/Web acceptance. Parent validation and independent review
are pending. No Core source/specification, fixture/configuration, legacy framework
Settings/action/adaptive implementation or app product screen change is included.

ESA4-03 remains OPEN. Product screen composition and complete SC01–SC20 belong
to ESA4-04; Web400/1200, protocol/model feedback, final full validation, one
comprehensive Phase review and distinct release remain ESA4-05/Phase obligations.
Real-server admission remains Phase 5 work. Step repairs 3/3 stay consumed and
closed; Phase repairs 0/3 stay separate, without a new S03 repair allowance.
Accepted findings are empty; no Hygiene/Development Candidate or design promotion
record is introduced by this authoring projection.

## ESA4-03 independent acceptance / commit preparation — 2026-10-03

Current status: S01–S03 implementation and complete ESA4-03 independent review accepted; local Step commits prepared, not yet recorded; Phase 4 and SC01–SC20 OPEN.
Owner: app Phase 4 with Core/TFAF and app public consumers.
Update rule: This dated evidence supersedes earlier current-status wording; retain historical failures and authoring projections. Record actual native Step revisions only after commit success.
Closure basis: Complete-Step independent review PASS and selected validation; the separate local Step commit remains required. ESA4-04/05 and final Phase gates remain required.

Review `esa4-03-review-20261003-root-01` revision 1 is PASS at review ledger
revision 11, covering all 30 Step paths with zero CPB/HYG/DEV findings.
S03's six selected checks passed: 102 framework, four App public-consumer and
55 existing framework tests (161 actual executions), both targeted analyzers
clean and nine-file formatting unchanged. Retained S02 evidence is 237 successes.
The separate approved S03 four-file batch closed at one of three attempts;
original Step repairs 3/3 and Phase repairs 0/3 remain unchanged.
These results do not establish composed SC01–SC20, Web400/1200, a package Phase,
final full validation, comprehensive Phase review/release or real-server E2E.

## Current ESA4-03 commits / App composition authoring — 2026-10-03

Current status: ESA4-03 accepted-and-committed; App ESA4-04 AUTHORED_ONLY pending parent checks/review; SC01–SC20 OPEN; app Phase 4 in_progress.
Owner: Core source/session/context under app Phase 4; app owns configuration/composition.
Update rule: Retain historical proposal, authoring/precommit, independent review/M0 and failure lineage; update acceptance only from native parent evidence.
Closure basis: App composed evidence plus unchanged package specification scopes, selected focused checks, independent Step review and separate commit; Web/final drivers/sole Phase review/release remain required.

Actual ESA4-03 commits are Core `33f99d4e2a86ba4827092876d56e53bb6307f34d`,
TFAF `b4d23403f3a82033d4c392b5e174218b976ec9ea`, App
`da5cf4e3ef26221788314b190edb5d27b7624d3f`. Retain independent review
`esa4-03-review-20261003-root-01` revision1 PASS, selected S02 successes237
and S03 executions161. Original repairs3/3 and closed approved S03 batch1/3
remain unchanged; ESA4-04 repairs0/3 and Phase repairs0/3 are separate.

[App composition v1](../../../../Project2026/nict-editing-studio-app/docs/notes/display-client-composition-v1.md)
consumes the unchanged public FixtureDisplaySource, DisplaySession and policy
APIs. Core retains request construction, received-context continuation,
fixed-flow admission, separate Operation, safe reload/retry and receipt/freshness
ownership. The App builds one pristine session/context per explicit fixed case
and transfers it to TFAF; no per-request copying, context merge or arm decision.
CP01–CP20 and the combined SC/package map are authored/pending. Strict typed/
scoped/context bounds and producer replacement still require actual protocol,
context and DS evidence; CP alone supplies no closure. This Slice changes no
Core product/spec/config and creates no package Phase or server/CNCF acceptance.
See the [documentary handoff journal](../journal/2026/10/2026-10-03-display-prototype-esa4-04-composition.md).

## ESA4-04 independent acceptance / commit preparation — 2026-10-03

Current status: Complete ESA4-04 implementation and independent Step review accepted; local Step commits prepared, not yet recorded; Phase 4 and SC01–SC20 OPEN.
Owner: app Phase 4, consuming unchanged public Core/TFAF prototype APIs.
Update rule: This dated evidence supersedes earlier current-status and repair0 wording; retain historical authoring and failure records. Record native Step revisions after actual commit success.
Closure basis: Complete-Step independent review PASS and selected execution evidence; separate local Step commit remains required. ESA4-05 Web400/1200, protocol/model feedback, final full validation, sole Phase review and distinct release remain required.

Review `esa4-04-review-20261003-root-01` revision 1 is PASS at review ledger
revision 13, covering all 15 owned Step paths and 98 captured inputs, with
zero CPB/HYG/DEV findings. Actual final App execution passed 35 representative
CP01–CP20 cases and 45 regression tests. Six-target fatal-info analysis had
zero issues and the nonwriting six-target formatter reported zero changes.
Historical package evidence was reused after proving 49 package inputs unchanged:
Core runtime98 and five-suite accumulator135 (including protocol/context),
TFAF representative102 and regression55. These are retained executions, not new tests.
The combined SC map uses typed/scoped/context package proof as well as App cases;
actual Web observations for SC02/04/11/12/20 and final Phase gates remain pending.

ESA4-04 repairs3/3 are independently accepted and closed. Original ESA4-03
repairs3/3 and its separately approved S03 batch1/3 remain closed, without
budget transfer; Phase repairs0/3 and PLAN epoch1 remain unchanged.
This is Step evidence, not Phase completion, a package Phase closure,
real-server E2E, CNCF admission, experiment allocation or evaluation.
