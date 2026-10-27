# Phase 2 public submission handoff

Current status (2026-10-11): TFC2-01 and TFC2-02 accepted and committed.
TFC2-03 parent intake and independent protected owning Step review passed.
Its exact commit, full-package validation and whole Core Phase 2 acceptance remain pending.
Owner: textus-flutter-core Phase 2 owns this public handoff and durable submission
contracts. TFAF owns shared presentation; App owns Book mapping and navigation.
Update rule: append actual owning Step acceptance and exact commit receipts,
full-package validation, comprehensive Phase review and release receipts as they
occur. Retain each earlier receipt's date and scope. Contract changes require
their admitted source and executable-specification changes together.

This note summarizes the existing settled contracts in
[durable material submission](durable-material-submission.md),
[background transfer status](background-transfer-status-contract.md),
[reference access](submission-reference-access-contract.md) and
[HTTP/Drive connections](submission-http-drive-connections.md). Those contracts
and the current existing code are adopted unchanged for owning validation. This
entry introduces no new normative semantics, API or owner.

## Public values and ports

Consumers import `package:textus_flutter_core/textus_flutter_core.dart` through
the [public library](../../lib/textus_flutter_core.dart). Existing public
`SubmissionRequest` and `SubmissionMaterial` constructors freeze request id,
kind/subject identity, UTC creation time, ordered original references, provenance,
local document, server payload and opaque extensions. Later consumer edits cannot
change committed intent. One Commit per `(kind, subjectId)` remains the contract;
equal ids are idempotent and conflicting intent is rejected. Original photo/audio
references, descriptive names and edited transcript whitespace retain their
existing values. Commit validates originals and publishes durable intent before
wake; it performs no upload or submission.

Use the existing `SubmissionService`, `SubmissionQueueStore`,
`SubmissionStorageAdapter`, `SubmissionTransport` and `SubmissionWakeScheduler`
public ports. The queue is the durable state authority. TFAF/App compose public
constructors and ports; they use no private imports or replacement queue. Storage
and transport connections are explicit immutable targets. Borrowed resources keep
their established lifetimes. Originals stay with their original store and are
retained after failures; this handoff authorizes no deletion or public sharing.

## Independent operations and actual outputs

`SubmissionTransferStatus` and the service's fresh `findTransferStatus`,
`findTransferStatusForSubject` and `listTransferStatuses` queries expose upload
and submission separately. Upload reports `notRequired`, `queued`, `waiting`,
`running`, `succeeded` or `failed` from actual required files, receipts, lease,
failure and observations. Submission reports `queued`, `waiting`, `running`,
`outcomeUnknown`, `succeeded` or `failed` under the existing precedence rules.
Missing receipts mean `materialUpload` waiting; unknown/unavailable configured
reference access can keep complete uploads waiting before dispatch. A pending
or legacy dispatch checkpoint retains acknowledgement uncertainty.

Progress is actual receipt count, with actual persisted times, deadlines, safe
failures and acknowledgement values where available. No percentage, active file,
remote result or retry deadline is inferred. `running` establishes an unexpired
durable claim, without proving live network activity. Network observations default
independently to unknown; observations do not grant execution permission.

Supported presentation actions remain `retry` for Failed, `requestRun` for Ready
or expired Submitting, and none for Submitted or an unexpired Submitting lease.
Execution freshly reads state. Retry retains immutable identity, successful
reservations/receipts and history, so partial upload success is reused and a
failed submission does not repeat successful uploads. Recovery uses the same
idempotent request and packet; local fencing promises no exactly-once remote effect.

Actual output includes original references, storage reservations/receipts,
matching server acknowledgement, safe failures and durable status/history.
The transport packet retains ordered materials, provenance, payload and opaque
presentation/execution context; it excludes the local document and original
bytes. Credentials and raw errors are excluded. Storage completion is upload
evidence; only a matching server acknowledgement establishes submission success.
Neither fact establishes Candidate formation.

## Configured reference access

`SubmissionConfigurationSnapshot.referenceAccessBindings` and
`SubmissionConfigurationStore.setReferenceAccess` retain the existing explicit
transport-to-access-identity mapping. `ConfiguredSubmissionReferenceAccessPolicy`
reads fresh configuration and checks actual receipt access ids. An absent binding
is unknown, an empty binding revokes access, and insufficient access denies.
A sufficient binding is an operator declaration of resolver provisioning, not
remote permission proof. Selected connections, upload receipts and tokens alone
do not establish access. Nonempty materials require the existing fresh guarded
dispatch checks; no-upload intent bypasses them. Core creates no sharing grant
and implements no server resolver here.

## Owning Steps and evidence scope

The [owning Phase plan](../phase/phase-2.md) and
[parent connected plan](../../../../phases/PHASE-6.1/connected-own-phase-plan-20261011.json)
select the current Core checkout on `codex/esa6-local-capture`, with exactly 70
existing Core submission/capture-guard paths adopted for validation. Existing
source and specifications are preserved; documentary entry is no source acceptance.

| Step | Required owning outcome | Acceptance / commit |
| --- | --- | --- |
| TFC2-01 | Public state and adapter contract | Accepted / `cd9da12f7219c8096762f5c16f3f2f5bb3998a65` |
| TFC2-02 | Execution and recovery | Accepted / `95942a5c260adc37608f8b002284097e7b61f905` |
| TFC2-03 | Public handoff and consumer verification, including public exports and fixtures | Independent protected owning review passed / exact commit pending |

Earlier App A/B/S2 and timing source reviews through
`esa6-1-review-ledger-20261009@29` remain borrowed evidence. They are not owning
Core Step reviews. Historical host results keep their controlled file/SQLite,
adapter, HTTP and policy scopes; fake acknowledgement proves no actual server
acceptance. Applicable prior evidence is reused only after parent relevance checks.

`esa61-drive-native-entry-validation-20261011@2` records 37 native policy cases
and post-entry ND1 public authorization smoke over an existing grant. It proves
no actual long human consent wait. Its ND2/ND3 were not rerun.
`esa61-drive-native-entry-focused-review-20261011@1` is the earlier App timing
review. `esa61-native-drive-post-timing-actual-20261011@3` retains historical ND2
actual adapter upload/idempotence and binary readback, and ND3 fresh-process silent
authorization/readback for the same 68-byte synthetic fixture. These prove no
real Book/server acceptance or headless Drive upload.
`esa61-native-book-validation-final-20261011@1` retains the recorded NQ1–NQ4
persistence/WorkManager scopes; supplied offline input proves no physical radio
toggle or OS-stop experiment. Earlier failed attempts remain historical.

TFC2-03 owning review and exact commit, full-package `scripts/validate-full.sh`,
comprehensive Core Phase review, canonical dispositions and distinct release are
pending. Core Phase 1.3's historical status is retained. Core Phase 2, TFAF Phase 3
and App Phase 6.1 are not complete. Consumer evidence is required for Core closure;
TFAF/App Phase closure is not a circular prerequisite. No server implementation,
AI follow-up, Phase 5 or successor work is admitted by this entry.

## 2026-10-11 — TFC2-03 public consumer handoff

TFC2-01 owning review `tfc2-01-owning-step-review-20261011@1` passed and its
exact Step commit is `cd9da12f7219c8096762f5c16f3f2f5bb3998a65`.
TFC2-02 owning review `tfc2-02-owning-step-review-20261011@1` passed and its
exact Step commit is `95942a5c260adc37608f8b002284097e7b61f905`.
Earlier precommit journals and failed validation attempts retain their dated
outcomes; these receipts supersede only current progress. The
[TFC2-03 journal](../journal/2026/10/2026-10-11-tfc2-03-acceptance.md) records the
exact eight-path Step, four-document author subset and selected parent evidence.
Core total scope remains 80 paths.

The four target programs are the public library and three test-owned helpers:

| Program | Handoff role |
| --- | --- |
| [Public Core library](../../lib/textus_flutter_core.dart) | Exports existing immutable request/codec/status, service, queue, adapters, configuration and background resources; production consumers import this library. |
| [Submission fixture](../../test/support/submission_fixture.dart) | Owns test-private real originals/SQLite and independent controlled storage, transport, wake, local-write and read barriers. |
| [HTTP fixture](../../test/support/submission_http_fixture.dart) | Captures requests from public concrete Drive/HTTP adapters with controlled responses and ephemeral credential ports; owns its HTTP client. |
| [Background fixture](../../test/support/submission_background_fixture.dart) | Composes real files/SQLite, concrete adapters, controlled HTTP/configuration and borrowed run lifetimes; explicit owners close their handles. |

The helpers are test support, not exported production implementations or a RAM
fallback for the durable queue. They import the public Core library and replace
no global factory. Controlled credentials, grants, acknowledgements and reference
bindings establish no remote permission or actual server result.

TFAF Phase 3 consumes public `SubmissionFacade`,
`SubmissionConfigurationFacade` and `SubmissionStatusBinding` over Core's
immutable input, fresh query/actions and borrowed resources. App Phase 6.1's
`BookSubmissionService`, `BookSubmissionMapper` and `BookSubmissionComposition`
compose public TFAF/Core boundaries. App owns saved ISBN-or-title eligibility,
Book snapshots, original references, edited transcript/provenance, opaque context
including arm information, editor and navigation. Core interprets no experiment
policy; TFAF owns common settings/status/actions.

Selected parent evidence retains RA3 one pass and 23 suites/375 passes with clean
analysis, using real originals/SQLite and controlled remote ports for denied
reference access, configuration, same-id retry and exact packet reopen. Later
Q4 and ten suites/115 passes cover production awaited `rawQuery`, FULL=2 and
5000ms busy timeout. Native NC1/NC2 cover retained encrypted configuration and
empty default-factory acquisition, not nonempty dispatch. Later native compilation
and 37 policy cases passed; post-entry ND1 exercised public channel authorization
and retained folder over an existing grant. Virtual 53-second timing proves no
actual greater-than-20-second human wait. The narrow App entry-review PASS resolving
CPB-ESA61-DRIVE-TIMING-001 is borrowed context, not Core Step acceptance.

NQ1/NQ2 record nonempty ready original/intent/newer Draft persistence; NQ3 records
two actual WorkManager `authRequired` claims and one explicit retry; NQ4 records
fresh-process failed original/context/status restore. Supplied offline and held
wake prove no physical radio toggle, OS stop or successful headless upload.
Historical ND2 records actual synthetic 68-byte upload/idempotence/independent
binary readback; ND3 records fresh-process silent restore without UI/create/upload.
They prove no whole Book-media or server acceptance.

Public consumer software receipts are TFAF CF1/CF2/CU3 representative one pass,
27 suites/234 passes and clean analysis; App controlled eight suites/100 passes;
and server handoff 17 BH plus 55 mapper/service cases, 72 passes. These exercise
real local files/SQLite and public codec/concrete HTTP adapter with injected HTTP;
success/failure/retry/offline/reopen and server acknowledgement remain controlled.
Storage success and matching server acknowledgement stay separate; neither
establishes Candidate formation. No product command was run by this author.

TFC2-03 independent review and exact commit remain pending. Core full-package
`scripts/validate-full.sh`, comprehensive Phase review, canonical dispositions
and distinct release remain required, as do separate TFAF/App own Phase and App
aggregate gates. Consumer evidence is required for Core handoff; consumer Phase
closure is not a circular prerequisite. Existing contracts, executable
specifications, errors, cancellation/retirement, retention, manual whitespace and
opaque context are adopted unchanged.

## 2026-10-11 — Owning TFC2-03 acceptance before commit

Parent intake covered all eight owning paths and four target programs, with 48
local links and 62 export targets resolved. Independent protected review
`tfc2-03-owning-step-review-20261011@1` returned PASS over eight owning and 42
selected paths. Current blockers, Hygiene and Development Candidate findings
were explicitly empty. The review assessed Core, TFAF and App consumers with
actual scoped software/native evidence; it executed no validation commands.

This receipt supersedes only current progress. Earlier dated authored-only and
precommit receipts retain their original outcomes. Only the TFC2-03 fixture/API
handoff implementation item is now checked; its composite evidence/review/commit
item remains open until the native commit is verified. The exact eight-path Step
commit is pending. Core full-package validation, comprehensive Phase review and
distinct release, TFAF Phase 3 and App Step/Phase/aggregate closure remain required.
Controlled remote results and native synthetic 68-byte transfer do not establish
whole Book-media transfer, successful headless upload or actual server acceptance.
No normative contract, executable, configuration or fixture meaning changes here.
