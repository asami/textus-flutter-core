# TKL-managed Material delivery in Flutter Core

Current disposition, 2026-10-27: the bounded TKL follow-on is accepted and closed
with App Phase 6.3's ordinary completion. The source is locally committed;
original phases remain closed. Earlier dated authoring/pending statements below
retain their historical scopes. Current requirements and selected evidence are
indexed by the owning delivery plan; no execution report, new grant, public
release or main integration is added by this management update.

Decision: 2026-10-24; clarified 2026-10-25. Status: implementation in progress;
live acceptance pending.

ESA63-01 now publishes the additive public values and borrowed
`TklMaterialDeliveryClient` in `lib/src/submission/tkl_material_delivery.dart`.
The exported TklMaterialDeliveryHttpClient now implements all six operations
over an explicitly supplied authenticated HTTPS service root. It reuses Core's
HTTP lifetime/credentials, preserves structured JSON and multipart bytes/MIME,
and identifies uncertain mutation outcomes without automatic replay. Ten
controlled HTTP scenarios pass; they do not establish deployed TKL access.
The existing durable runtime now persists TKL delivery progress and safe direct
upload receipts in the same queue, using additive JSON versions while retaining
legacy requests. Default Android background composition supplies the TKL client.
Direct upload uses ephemeral provider instructions without the application bearer;
Core checkpoints completion before notifying TKL for independent confirmation.
Loss of an upload reply reacquires the retained session's actual status from TKL;
loss of finalization response queries the same delivery instead of replaying it.
The 334 related submission specifications pass, including direct/mediated routes,
reopening, uncertainty, partial bytes and legacy queue behavior. These controlled
observations do not prove deployed TKL/Google authorization or device acceptance.
The final focused direct/HTTP/queue suite passes 23 cases after native projection
and session handling refinements; this overlaps the 334-case scope. Final scoped
App/Core/TFAF static analysis reports no issues.
Authority: [TKL delivery contract](../../../textus-knowledge-lake/docs/spec/tkl-managed-mobile-material-delivery.md).

Core supplies a domain-independent TKL client and transfer runtime. It obtains
logical destination and delivery instructions from TKL; it does not ask users
for Google drive/folder IDs or define Lake layout. Support Workspace Shared Drive
folders and My Drive shared folders, with Workspace as the first live route.

## Runtime behavior

- Accept committed metadata and resource references from the consumer through
  public contracts. Keep Book-specific fields and editing decisions outside Core.
- Resolve TKL's permitted destination, prepare delivery, transfer originals and
  finalize registration using the returned delivery reference.
- A provider adapter can consume concrete upload instructions, including opaque
  provider references, without elevating them to editable application settings.
- Follow TKL's retained `googleDriveResumable` or `tklMultipart` choice. TKL
  selects the mediated route when the provider lacks direct capability and
  supplies a reason. Never infer capability absence from a permission refusal,
  connection failure or unknown result, and never resend through the other route.
- Keep session URIs ephemeral. Persist only safe per-original transfer receipts;
  display upload completion separately from independent TKL confirmation.
- Persist only the execution information required for queued/background work,
  recovery and progress. TKL remains the configuration authority.
- Preserve offline capture, originals, completed uploads and targeted retry.
  Reconcile uncertain outcomes with TKL before repeating remote effects.
- Keep resource upload, TKL registration and Editing Studio submission outcomes
  distinct. Publish registration success only from TKL's receipt.
- Resolve current configuration for new deliveries; resume existing ones through
  their TKL reference. Configuration changes cannot silently retarget pending work.
- Sign-in/consent and provider token renewal use platform facilities. Do not
  accept server service-account keys, invent fixed expiry gates or add integrity
  ledgers. Respect actual provider authorization and transfer-session outcomes.

## Test configuration and production discovery

Explicit test configuration/injection is permitted by the user (2026-10-24).
A test composition may supply the service connection or a configured test
implementation of the public client port. Keep that selection explicit in the
test composition; do not add an automatic fallback to a test client/destination
when the production TKL call fails. Fixture results are not remote receipts.

Production Core uses TKL destination discovery and preparation for integration
information, including the permitted destination and transfer instructions.
Bootstrap/secure application authentication and persisted recovery instructions
remain distinct from that authority. No Google key or physical destination
policy is copied to Android. Existing deliveries retain their TKL binding.

## Migration

The existing Drive connection/HTTP adapters and durable queue are reusable
implementation inputs, not evidence that this TKL route already works. Replace
client-owned destination provisioning for this route. Do not re-create the queue
or copy TKL's account/folder/placement configuration to Android.

Existing queued direct-Drive requests are not silently converted or moved.
Preserve their state and local originals; define explicit reconciliation/adoption
with TKL for prior uploads before retiring their setup path. No destructive queue
reset or app uninstall is a migration step.

App currently consumes a Core worktree via pubspec_overrides.yaml. Main's older
Phase status is not evidence that delivered Core features are absent. At entry,
integrate the actual accepted producer work before implementing only this delta.

Plan: [delivery workstream](../phase/tkl-managed-material-delivery-plan.md).

## DU-03 bounded retained-original implementation authoring

The selected Core consumer now authors optional `StreamingLocalCaptureStore`,
implemented by native `FileCaptureStore` using half-open ranges and at most 64KiB
per emitted chunk. Each range checks the actual regular retained file's complete
declared length before reading and at successful completion; cancellation closes
its own reader. The non-IO stub exposes the same optional capability and fails
observably. Existing `LocalCaptureStore` implementations remain source compatible.

New TKL Commit admission requires this optional capability. It opens only
`start:0,end:0`: actual full-file existence/length validation consumes no payload
and computes no digest. Missing streaming capability returns the fixed safe
`originalStreamingRequired` before enqueue. Existing queued legacy mediated work
retains its old path; non-TKL Commit behavior is unchanged.

Leased `processNext` first finds the immutable request correlation. A destination
advertising `contentIntegrity:"sha256"` enables hashing actual final retained bytes
with package `crypto`, at most one missing original per claim. The native SQLite
queue stores checked immutable `TklContentDigest` values under the existing valid
lease in `SubmissionRecord.tklContentDigests`. Equal duplicates are idempotent;
replacement, unknown material and non-TKL insertion fail without a write. Record
V5 carries the nonempty digest map and explicit `tklProgress`/`directReceipts`, even
when empty. V1–4 remain readable. No table, scheduler or request schema is added.

Preparation adds only each original's `contentDigest` in detached transport JSON.
The accepted Book/document/contribution, literal strings, nulls, list order and
source/provenance stay exact. Caller expectations must match actual local bytes;
server expectations never substitute for hashing. A lost prepare reply uses the
same persisted expectations and existing correlation reconciliation.

`TklStreamingDirectMaterialDeliveryClient.uploadDirectStream` borrows a reopenable
`TklOriginalRangeReader` and explicit total length. The HTTP implementation opens
only the next half-open range, emits provider PUTs of at most 256KiB, validates
actual counts before dispatch and attaches no application/Google bearer. Every
nonfinal request has a 256KiB body. Only an unambiguous provider-confirmed contiguous
308 prefix advances offset; missing, regressing, excess or ambiguous prefixes
return to existing TKL reconciliation. An early nonfinal 200/201 is incomplete.
A full acknowledged prefix requires an empty status PUT. Completion receipt is
persisted before independent TKL confirmation; session URIs remain ephemeral.
The compatible Uint8List API stays available, but this integrity-aware direct
service path never invokes it or a whole-original reader.

Wire decoding accepts only the closed native camelCase/adapter snake_case aliases
for destination integrity and resource digest/verification fields. Ambiguous,
null, malformed and partial tuples fail. Inner digest JSON is exactly algorithm
and value. Opaque Book JSON is never renamed. Ready/registering/registered with
digests requires placed verified resources bound to complete actual local
expectations. Existing terminal legacy registration remains readable without a
retroactive SHA claim. Unfinished old direct work requires explicit
`integrityUpgradeRequired` disposition; new direct without SHA capability fails
`integrityCapabilityRequired` before preparation.

A `verifying` observation triggers one existing finalize call per eligible claim,
including when a sibling still has pending bytes. The server owns its total-three
independent metadata-check bound. `integrityMismatch`, `verificationUnavailable`
and `integrityUpgradeRequired` retain originals, receipts and verified siblings
and suppress ordinary presentation Retry/RequestRun actions.

### Exact public projection for the TFAF consumer pass

`SubmissionTransferStatus.preparation` and `.verification` are nullable
`SubmissionTransferOperationStatus` values and null outside TKL. Preparation's
`completedCount` is exactly the persisted local digest count, `totalCount` is the
accepted material count, and an active lease may show running without inventing
a byte percentage. Verification counts only actual server verified originals;
legacy absent proof is null/unreported. `upload` remains byte placement,
`registration` is TKL registration, and `submission`/`acknowledgement` remain the
separate Studio outcome. A Material reference appears only for actual server
Registered. New fields participate in status equality/notifications. TFAF widgets
and App production adoption belong to their next owning pass.

All DU-03 source/specification statements here are authoring pending parent
offline resolution, analysis, focused execution and independent review. No
worker validation or live/device operation occurred. Earlier evidence/history
and the consumed 7/7 live allowance remain intact; no SHA/live/Phase acceptance
is claimed.
