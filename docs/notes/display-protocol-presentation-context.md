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
