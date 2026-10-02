# Common Display session v1 — provisional client prototype

Date: 2026-10-02
Current status: S02 authored; parent validation and independent review pending
Owner: Core under app PHASE-4 / ESA4-03 / S02-common-display-session
Update rule: Record actual parent checks/review; retain Step and Phase OPEN until their independent acceptance and recorded commits.
Closure basis: S01 source acceptance plus S02 session and S03 TFAF realization, public consumer evidence, independent Step acceptance and commit. This document supplies no closure receipt.

This additive development-only API is exported by
[the public Core library](../../lib/textus_flutter_core.dart). It consumes the
[accepted candidate codecs and ports](display-prototype-contract-v1.md) and
[semantic fixture source](display-fixture-source-v1.md) without a dependency on
fixture types, app domain mappings or TFAF. CNCF/server owns production wire,
ExecutionContext projection and admission. Real-server integration is app Phase 5.

## Public API and snapshots

[DisplaySession](../../lib/src/display/display_session.dart) extends Flutter
`ChangeNotifier`. Its required named constructor configuration is `resourceType`,
`sourceId`, `componentId`, `listScreenId`, `detailScreenId`, `initialContext`,
`contextPolicy`, `displayTransport`, `operationTransport` and `nowUtc`. The five
configured IDs are nonblank and byte preserving. `flowId` binds to the initial
context. Configuration, `state` and `isDisposed` are read-only. Construction
performs no admission, clock invocation, eager query, port call or persistence.
An explicit framework discard disposes this instance and constructs another
from a supplied context; there is no setter, reset, rebind or inherited flow.

The methods return `Future<void>`: `query()`, `read(String resourceId)`,
`retryList()`, `retryDetail()`, `reload()`,
`update({required int observedRevision, required List<DisplayFieldInput> fields})`,
`create({required List<DisplayFieldInput> fields})`,
`delete({required int observedRevision})` and
`executeOperation({required String operationId, required int observedRevision})`.
Resource commands infer the accepted active resource. Input lists are copied at
invocation, retaining order, repeated scoped locators and exact typed text bytes.
Caller positive revision is never silently replaced with the current projection.

Snapshots have library-private constructors and final members:

| Type | Observable contract |
| --- | --- |
| `DisplaySessionReadPhase` | `idle`, `loading`, `ready`, `failed` |
| `DisplaySessionCommandPhase` | `idle`, `running`, `settled`, `failed` |
| `DisplaySessionCommandKind` | `update`, `create`, `delete`, `operation` |
| `DisplaySessionFailureKind` | `context`, `codec`, `unavailable`, `ambiguous`, `unexpected` |
| `DisplaySessionFailure` | `kind`, original `message`, optional exact policy `contextCode` |
| `DisplaySessionReadState<T>` | `phase`, last accepted `data`, current read `failure` |
| `DisplaySessionCommandState` | `sequence` starting zero, `kind`, `phase`, one of `mutation`/`operation`, `failure` |
| `DisplaySessionState` | `context`, immutable unique `diagnostics`, `list`, `detail`, `selectedResourceId`, `command`, `busy`, `projectionPending`, `commandUncertain`, `contextFailure`, immutable `minimumRevisions`/`committedRevisions`, derived `canMutate`/`canCreate` |

Read failures retain accepted data, focus, command history and floors. A requested
resource becomes selected only after full reply admission; query never selects
or eagerly reads Detail. Each eligible explicit command attempt increments
sequence once, clears old command result/error and publishes running. Safe reads
and reload never erase or reinterpret the latest command. Snapshot collections
and nested accepted contract values are immutable. TFAF owns drafts, navigation
and definitions; no draft is part of the common state.

## Admission and lifecycle

Busy is reserved synchronously before notification or port crossing and remains
reserved through bounded update refresh. Busy/disposed methods, absent active
Detail, blank method IDs, nonpositive revisions and ineligible command projection
produce failed Futures with `StateError`/`ArgumentError` and no state/port effect.
Pending or uncertain focus cannot switch resources. `retryList` is one query;
`retryDetail` is one accepted-focus read. Reload performs one active-resource
read then one query, or query only without focus. There is no queue or replay.

Before every raw request, the injected explicit UTC clock and existing policy
admit the current context against fixed source/component/flow. Optional omissions
are adopted with unique `(namespace, code)` diagnostics retained within the
initial family set. Request revision is null for query/read/create and exactly
the caller's revision for update/delete/Operation. A pre-port context/clock failure
preserves preceding context/data/focus and produces visible failure without
command uncertainty. A later explicit safe call can re-admit a corrected clock.

Each raw reply uses its exact existing decoder. List collection/screen/Detail
screen, requested Detail resource/screen and command resource identity are checked
before adoption. Context/provenance source equality remains a codec invariant.
Response admission samples the UTC clock and checks existing producer replacement
policy against that call's admitted request. Only then are context, data or receipt
adopted. Producer attempt replacement continues on later requests; assignment,
locale, flow, source, component, family identity/lifetime are fixed. Optional
expiry/extension rules use the existing policy; allowed opaque replacement is
whole payload replacement, never deep merge. Optional expiry diagnostics also
remain visible when the producer omits the expired family from its reply.

Incompatible response context latches for this instance, retains the last admitted
context/projection/focus and prevents later raw continuation and editing. Only
explicit discard/new session starts another flow. Malformed or identity/context
invalid dispatched command replies provide no receipt and remain uncertain.
`PresentationContextException` supplies its exact policy code; `FormatException`
is codec failure; declared transport tags map to unavailable/ambiguous; other
port or clock exceptions are unexpected. Operational failures are visible state
and complete method Futures normally; local programmer preconditions throw.
A refresh exception never reclassifies an accepted command as failed.

Disposal is idempotent. It sets `isDisposed`, detaches listeners and prevents
late publication and further port continuation after every await/notification.
Synchronous listener disposal invalidates the flow immediately and completes
ChangeNotifier teardown after notification unwinds. Listener reentry encounters
already reserved busy. Disposal does not cancel or assert rollback of a started
source mutation. Retained snapshots remain immutable. Independent sessions can
overlap and inherit neither context nor failure.

## Receipts and projection freshness

`minimumRevisions` retains maximum positive resource revisions from List rows,
Detail and accepted command currentRevision. `committedRevisions` retains only
maximum admitted changed-receipt committedRevision. Snapshot labels are opaque;
no numeric revision is extracted from `snapshot-N`. Full coherence requires every
tracked resource represented at/above its floor and exact selected-row/Detail
revision equality, without assuming screen/model equality from revision alone.

Changed/noOp update publishes its settled receipt immediately, retaining changed
commit or noOp current floor. Valid included Detail may be stale evidence; absent
Detail preserves preceding data. A refresh obligation blocks commands and then
attempts one active read and one query, each at most once. Read transport/codec
failure still permits that one query; context rejection/disposal stops continuation.
The Future completes after this bounded refresh; listeners see the receipt first.
Rejected/conflict/unsupported updates never implicitly reload. Conflict preserves
current floor/error and stale projection remains read-only until explicit coherence.

A changed ordinary Operation retains commit and refresh obligation with zero
automatic Display calls. Rejected/conflict/unsupported Operation remains its own
result, with conflict floor applied and no implicit Display. Action availability
is presentation metadata, never admission or authority. Prototype create/delete
accept only rejected/unsupported receipts; changed/noOp/conflict is a visible
codec/prototype contract failure after dispatch, uncertain without a fabricated
successful capability or implicit reload.

Raw command delivery/codec/unexpected failure after dispatch creates uncertainty
and a safe refresh obligation with zero automatic reads, retries or replay.
Unavailable delivery does not assert rollback. A later coherent safe reload can
allow a new explicit command while historical failure stays failed/unknown; it
creates no receipt or commit. TFAF retains observed revision/draft and owns explicit
reconciliation/discard. On new accepted changed/noOp update receipt, TFAF clears
only the submitted draft, including when refresh remains pending.

A command obligation requires one successful fresh active Detail and one successful
fresh List after its event, exact selected-row/Detail equality and all tracked floors
represented. Stale/held/missing/inconsistent replies and failed reload stay pending.
Explicit retry of one failed safe part can complete its obligation; another explicit
read is needed when fresh replies disagree. Safe success never lowers a floor.
Incoherence discovered without a command also marks projection pending.
`canMutate` additionally requires ready List+Detail, active identity, no busy,
context failure, pending or uncertainty. `canCreate` requires ready List, all
floors represented and no busy/context/pending/uncertainty. Neither grants server
or UI-definition authority. Core never clears, merges or rebases a draft.

## Authored evidence and remaining owners

[The Core runtime specification](../../test/display/display_runtime_test.dart)
authors DS01–DS43 with 98 expanded cases. Neutral raw/controllable ports exercise
bad responses, failures, gating and context continuation; semantic-source cases
observe actual source mutations. [The App public consumer specification](../../../../Project2026/nict-editing-studio-app/test/display_session_consumer_test.dart)
authors AS01–AS04 against the unchanged asset without per-request metadata.
These are authored evidence awaiting parent execution/review. No test result,
UI/draft realization, SC01–SC20 closure, package Phase or app Phase closure follows.

[The Slice journal](../journal/2026/10/2026-10-02-display-prototype-esa4-03-slices.md)
retains S01 acceptance and S02 pending scope. TFAF S03 owns definition registry,
editor/draft/navigation/adaptive widgets. App ESA4-04/05 owns composed scenarios,
Web 400/1200, feedback and final validation/review/release; real-server work stays
Phase 5. Existing legacy action APIs, codecs, source, fixture/configuration,
dependencies and accepted capture/package Phase contracts retain their boundaries.
