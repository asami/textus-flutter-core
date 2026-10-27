# TKL-managed Material delivery — Core follow-on

status=closed
completed_at=2026-10-27
planned_at=2026-10-24
spec=../notes/tkl-managed-material-delivery.md
consumer=nict-editing-studio-app Phase 6.3

## Current follow-on completion — 2026-10-27

This bounded App Phase 6.3 contribution is accepted at source `2f48a6a`
and closed by the App's current ordinary completion. Original criteria and DU
obligations below are satisfied at their stated source/controlled/live scopes.
The App's canonical completion/acceptance records own the connected disposition;
detailed execution evidence remains local, outside Git. Earlier source-authoring
and pending-gate prose below is dated history, superseded by this current result.
No unrelated owning Phase, canonical main checkout, public release or production
rollout is marked complete. Failed sessions and consumed execution grants remain
unchanged; no new device/Google action is implied.


## Current source handoff — 2026-10-27

Core's public delivery/streaming/queue and separate registered-Material Studio
handoff source is locally accepted at `2f48a6ad4574f9759277b6e6208bcc81340adc4c`.
Full host validation passed 1,073 tests with no skips and clean analysis;
independent source review passed. TFAF `20307a5`, App `5dfbf91`, CNCF `37096764`
and TKL `75227b5` are the corresponding selected source. App owns final connected
acceptance; see its Phase 6.3 criterion evidence map. Actual six-photo direct/SHA
registration, separate successful queue UI/restore, offline Commit and the
server-accepted v2 ACK/access branch are retained there with their limits.

The source work below is delivered; its earlier IN PROGRESS/authoring projections
remain historical. This follow-on stays open until the final App disposition;
no accepted Core Phase is reopened. Original failed sessions stay failed and no
fresh live allowance, dependency switch, main merge or publication is implied.

## Original plan and authoring history

This is a follow-on to the delivered submission runtime. It does not reopen
accepted Core Phase 2 work or rewrite the older main-checkout Phase projection.
Reconcile the actual App-consumed Core worktree at entry; reuse its public queue,
native credential and transfer capabilities instead of implementing them again.

| ID | Delivery | Status |
| --- | --- | --- |
| TFC-TKL01 | Bind TKL's destination/preparation/finalization/reconciliation contract and authorization to public Core APIs. | CLOSED — accepted by current App Phase 6.3 completion; original source and evidence limits retained |
| TFC-TKL02 | Deliver one complete Shared Drive path with persisted execution state and TKL registration, using existing background infrastructure. | CLOSED — accepted by current App Phase 6.3 completion; original source and evidence limits retained |
| TFC-TKL03 | Close interruption/configuration-change/access failure branches and hand the public facade/status contract to TFAF/App. | CLOSED — accepted by current App Phase 6.3 completion; original source and evidence limits retained |

- [x] TKL supplies configuration; no mobile folder/drive-ID provisioning.
- [x] Shared Drive and My Drive shared-folder contracts use the same Core API.
- [x] Metadata and original associations survive TKL registration; upload success
  alone does not produce registration or Editing Studio submission success.
- [x] Offline waiting, process restart, targeted retry and uncertain completion
  retain originals and the existing delivery destination.
- [x] Existing queued direct-Drive work is preserved with an explicit migration
  disposition; no silent conversion, duplicate registration or queue reset.
- [x] Focused behavioral specifications and affected consumer tests pass; one
  connected independent review covers the slice. Existing required release checks
  remain applicable; fixture results do not claim real Google authorization.

Dependencies: [TKL workstream](../../../textus-knowledge-lake/docs/phase/tkl-managed-mobile-material-delivery-plan.md),
[TFAF workstream](../../../textus-flutter-application-framework/docs/phase/tkl-managed-material-delivery-plan.md).
Core acceptance covers its public/runtime boundary; the App owns real-device
end-to-end acceptance, without requiring all unrelated producer phases to close.

## Direct new-file upload and SHA-256 verification — planned delta

Contract and connected acceptance: [direct-upload integrity plan](../../../../Project2026/nict-editing-studio-app/docs/notes/direct-upload-integrity-plan.md).

TFC-TKL01 binds expected SHA-256 and verification status. TFC-TKL02 streams the retained original digest before prepare, then sends direct resumable chunks without Google credentials. TFC-TKL03 reconciles interruptions through TKL, preserves originals and exposes verification failures. Keep existing queue, safe receipts and legacy route disposition; do not persist session URLs in ordinary queue/status data.

- [x] Implement the owning DU items and affected contract/behavior specifications.
- [x] Hand off actual evidence and limitations; this planning addition claims no implementation, live upload or Phase closure.

Selected-checkout adoption: this section imports the canonical Core planned delta
on 2026-10-25 under the literal App contract above; prior progress and accepted
Phase 2 remain intact. CNCF's optional typed SHA-256 metadata foundation is in
progress and not accepted; full DU-01 remains open. Core runtime is unchanged
in this pass. DU-02 authenticated immutable digest/file binding and independent
server verification remain pending. DU-03 must replace the existing whole-material
read in `SubmissionService._original` and whole-`Uint8List` direct upload with
bounded streaming over the retained original, while preserving the queue and safe
receipt/reconciliation behavior. DU-04 connected tests, integrated independent
review and finitely authorized live acceptance remain pending.

## Frozen DU-02 wire for the next Core executable pass

TKL server authoring (pending parent validation/review) preserves eight Operation
names/inputs and `textus.material-contribution/1`. Add optional original JSON
`contentDigest:{algorithm:"sha256",value:<64hex>}`. Core must hash the final retained
bytes before prepare using bounded streaming, then enrich only the transport
contribution; never rewrite the committed Book, report, context or opaque JSON.
New direct requires every original digest, partial sets fail on either route, and
same caller/requestId fixes the complete immutable expectation. Completion remains
exactly `{outcome:"uploaded",byteLength:<declared>}` with no checksum or file ID.

Available destination adds contentIntegrity="sha256". Digest-bearing resource
projection adds structured contentDigest, verificationState pending/verifying/
verified/failed, integer verificationAttempts and optional fixed verificationReason.
Snapshot adds verifying and verificationFailed; actionRequired adds integrityMismatch,
verificationUnavailable and integrityUpgradeRequired. Bind closed typed field aliases
from actual RecordEncoder/HTTP-adapter evidence and reject ambiguous simultaneous
aliases; do not recursively rename opaque JSON. Native RecordEncoder specs ground
camelCase, while earlier snake_case checkpoints alone do not establish HTTP output.

Placement, verified proof, registration and Studio acknowledgement remain separate.
Only actual registration supplies MaterialRef. Missing independent SHA cannot succeed:
TKL saves candidate placement first, then uses a shared maximum of three independent
metadata checks. Finalize does one recheck per eligible resource/command; passive
queries perform none. Core must not retransmit original bytes merely to recheck SHA,
change a retained route, persist session URLs in ordinary queue/status or invent
provider authority. Reuse the queue, safe receipts, exact retained transfer and
reconciliation. Preserve already-Registered legacy without a retroactive SHA claim;
unfinished legacy direct missing digest/reservation is explicit integrityUpgradeRequired,
with no silent adoption/reset. No-digest mediated retains legacy semantics.

This pass changes this plan only. Core bounded final-byte hashing/upload streaming,
typed verification consumption, focused specs and affected validation remain next.
CNCF evidence 35:79, 36 compile, 37:94, 38:15 M1 closure and 39 source compile are
separate foundations, not validation of this pending TKL/client delta or live proof.
Six-photo offline history and live-create allowance consumed 7/7 remain unchanged.

## DU-03 selected Core authoring handoff — 2026-10-25

The frozen owning Core boundary now authors bounded optional capture ranges,
checked actual-byte SHA, one immutable digest checkpoint per leased driver pass,
V5 JSON in the existing SQLite record, detached prepare enrichment, bounded
256KiB resumable provider PUTs and strict independent verification projections.
Commit preserves local presence/length admission through an empty native range;
new TKL Commit requires the optional streaming capability and reads no payload.
Existing non-TKL and queued legacy mediated behavior remains in its existing path.

The public TFAF handoff is exactly nullable `SubmissionTransferStatus.preparation`
and `.verification`, both `SubmissionTransferOperationStatus`. Counts are durable
local digests and actual server verified originals respectively; absent legacy
proof remains unreported. Placement, verification, TKL registration and Studio
receipt stay independent. Terminal integrity mismatch/unavailable/upgrade failures
have no ordinary Retry/RequestRun presentation action. TFAF/App production UI is
outside this implementation boundary.

Authored specifications exercise actual retained native files (including an
incrementally written >32MiB original), published SHA vectors, exact SQLite
reopening/leases/V1–5, on-demand >1MiB direct ranges and controlled normal service
and HTTP peers. They cover lost outcomes, failed/absent proof and separate status
stages. Source authoring is not validation: parent offline pub resolution,
analysis, focused tests, integrated independent review and DU-04 live admission
remain pending. No checkboxes above are closed by this handoff and no Phase
acceptance is asserted.
