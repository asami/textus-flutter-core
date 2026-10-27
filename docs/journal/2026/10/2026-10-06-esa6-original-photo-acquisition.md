# ESA6 original-only photo acquisition — 2026-10-06

Status: Authored for PHASE-6 / ESA6-03 / ESA6-03-A; pending parent focused
validation, independent complete-Step review and acceptance. No validation was
executed by the implementation worker. Physical acceptance and full release
suites remain due. Owner: Textus Flutter Core, reusable acquisition/runtime/store.

The additive `PhotoCaptureService.captureOriginal()` and `recoverOriginal()`
import one actual camera result into the same caller-owned LocalCaptureStore and
return its durable CaptureMaterialReference, or null for cancellation/empty
recovery. A private shared import helper also serves existing capture/recover;
desired configuration validation remains before camera work, durable import
before inference, stored-original reading before inference, and durable report
before existing recognition return.

Original-only operations preserve bytes, media type, UTC capture time and name.
They perform no settings/configuration selection, saved-original read, provider
probe/preparation/inference or report write. Actual permission/camera/import
exceptions and CameraService UnsupportedError propagate without retry. The same
service guard holds through import and releases on success, failure or cancellation.
No new runtime/store, transaction, rollback or deletion is introduced. Previously
accepted originals retain their ownership even when a later operation fails.

## Authored public executable scenarios

All scenarios use flutter_test public behavior in
`test/capture/photo_capture_service_test.dart`, with adjacent Given/When/Then
comments next to actual setup, action and assertions. Real FileCaptureStore
fixtures and finite injected camera/provider gates are software evidence only.

| Scenario | Authored behavior |
| --- | --- |
| A1 | Exact bytes/UTC/media/name and actual saved reference; fresh real-store reader; one import; zero probe/prepare/inference/read/report work and empty report collection. |
| A2 | One-shot recovered image, separate capture/recovery counts, empty capture/recovery without new storage work, subsequent explicit capture and retained original. |
| A3 | Capture/recovery matrix for exact permission, camera and import errors plus actual unsupported camera; no fabricated reference/report/provider result; subsequent explicit same API and retained original bytes. |
| A4 | Finite held capture/recovery/import excludes both originals, existing capture/recover/recognize/compare and readiness/preparation; held cancellation releases; existing N8 held readiness and photo boundaries also reject both originals. |
| A5 | Later explicit recognize/compare on the original-only saved reference; camera/import remain once; fresh durable reports preserve raw OCR, desired/actual fallback and shared attempt lineage. |

Existing cancellation, invalid-selection-before-camera, report failure,
recognition and native-registration cases remain retained without weakened
expectations. Same-file camera/store/provider fixture extensions supply the
finite gates, one-shot recovery and unavailable-provider reason required by
these public scenarios. No unrelated same-file debt or Scala program is admitted.

## Consumption and pending evidence

TFAF forwards the two APIs exactly. App ESA6-03-B will compose page-specific Add
page photo with this capability; direct annotation text, page attachment,
incomplete Draft and reentry are still due. ESA6-05 real local List/Detail and
the exact requested physical P1–P8 remain pending. Core/TFAF release full suites
and App aggregate validation in Phase6.1 remain due; Phase6.1 is unstarted.

The parent selected Core/TFAF analysis, the Core photo service representative and
existing camera/registry/repository/store plus TFAF facade/controller/panel/storage
accumulators. No pass, Step/Phase closure, review, commit, publication or device
evidence is claimed here. Earlier S/A/E/B1/B2/B3 receipts and failures retain
their exact recorded scope. See the
[usage note](../../../notes/mobile-photo-acquisition-and-recognition.md).

## Actual parent preflight and platform stop — 2026-10-06

Parent exact10paths preflight and all three repository `git diff --check` results
passed. All owned-file whitespace/final-newline checks and48 relative-link checks
also passed. These are static preflight receipts, with no compiler/specification
execution implied.

The first selected Core `flutter analyze` request was submitted with
`require_escalated`. CreateProcess rejected it before execution: automatic
approval review failed because the selected review model was at capacity. The
platform stated that the action was not executed, classified this as a review
failure rather than an unsafe-action determination, and instructed that the
approval check must not be bypassed. The actual raw request/result is retained
under the App root at
`.codex-workflow/phases/PHASE-6/platform-review-failure-esa6-03-a-core-analyze-20261006.json`.

No selected analyze/test process started; no exit status, pass, test count or
session exists. The remaining four selected jobs were not submitted. No
automatic retry, alternate route or repair was consumed. The pre-existing private
constructor parameter spelling observation remains unverified because selected
compiler validation did not run; no compatibility pass, constructor repair or
design change is admitted. Prior successful receipts remain limited to their
recorded historical scope. Current focused validation, independent complete-Step
review/acceptance, physical acceptance and full release obligations remain pending.

## F-ESA6-03-B-01 shared original-read repair authoring — 2026-10-06

PHASE-6 / ESA6-03 / ESA6-03-B-R parent freezes the correction of the observed
App attachment-read exclusion gap. `PhotoCaptureService.readOriginal` now
forwards the exact saved reference once through `_operate` to its borrowed
LocalCaptureStore. Shared Core ownership lasts through actual read settlement,
including error, and releases in the existing finally. No new lock, continuous
capture/read lease, runtime, cache, schema or disposal authority is authored.
The internal recognition read remains private store IO under its already-owned
guard. Independent low-level storage reads retain their contract.

| Scenario | Authored regression evidence in the existing service spec |
| --- | --- |
| R1 | Original-only saved reference, exact metadata and single reference forwarding; unsupported camera/unavailable models; caller byte mutation, repeated read and fresh same-store service reopen with unchanged source and zero new acquisition/provider/report work. |
| R2 | Observed finite store read excludes all public photo/readiness/read APIs before effects; explicit gate release settles unchanged bytes and admits subsequent read. Injected exact error, actual missing original and inconsistent byte length preserve saved original/report history and release ownership. |
| R3 | A4 acquisition/import and N8 probe/preparation/read/inference/report gates reject public readOriginal before competing store work, while admitted operations settle and existing recognition durability remains. |

Each changed/new behavior uses adjacent Given/When/Then at actual setup, action
and assertions. Same-file fixture debt completed: lastReadReference observation
and existing finite gate/error adapters retained without changing old defaults.
No unrelated debt or finding is admitted. TFAF exact forwarding and App helper
consumption are authored in their dedicated admitted roots.

Status: repair authoring complete, actual parent-selected compiler/behavior
validation and fresh M2 complete-Step03 protected focused conformance pending.
No execution, pass, review, acceptance, commit or physical claim is made. The
pre-start capacity failure and constructor spelling observation remain unchanged.
Previous receipts, physical P1–P8, ESA6-05, upstream full release and App deferred
Phase6.1 obligations retain their stated scope.

## ESA6-03 independent acceptance and commit preparation — 2026-10-07

Current status: Complete ESA6-03 A+B+F software acceptance is PASS; its
Step03-only commit is deferred pending prerequisite Step02/05 acceptance.

Owner: Textus Flutter Core maintainer, coordinated by PHASE-6.

Update rule: Append actual admitted evidence and dated supersession; retain all
earlier raw failures, dates and held/pending records with their original scope.

Independent reviewer /root/esa6_03_acceptance_review_20261007 returned PASS for
complete A+B+F over 18 owned and 32 affected paths, with zero CPB/HYG/DEV.
Review reference esa6-03-acceptance-20261007@1 was admitted to typed ledger
esa6-review-ledger-20261006@6; parent append/save/read/require_review succeeded.
F-ESA6-03-B-01 is independently RESOLVED. This supersedes the earlier pending
Step03 independent-review and original repair18 conformance statuses. It grants
Step03 software acceptance only; Step02, Step05 and Phase acceptance remain due.

All 14 parent-selected validation obligations passed in the actual recovery.
Core analyze passed exit0; the service representative passed 44 cases and the
selected accumulator passed 57, for 101 distinct selected Core cases.

Commit preparation found 16 direct import edges to files absent from committed
HEAD outside the 18-file Step03 target, 15 dirty consumed-input edges and shared
Step05 path content. The actual index was empty in all three roots. A Step03-only
commit is deferred until prerequisite Step02/05 acceptance permits coherent,
dependency-ordered exact per-root commits. No intake, runner, staging or commit
occurred. This changes sequencing only; acceptance criteria, feature/protocol,
ownership, public API and original bases retain their existing authority.

Plain evidence records: review-admission-esa6-03-20261007.json,
sealed-source-esa6-03-20261007.json, validation-recovery-execution-20261007.json
and step-commit-preparation-esa6-03-20261007.json.

Prereview33 remains consumed; original repair18 is explicitly accepted by the
independent F closure, with no blanket acceptance of later harness repairs.
Step/Phase review repairs remain 0; nonconverging remains 0/limit3. The original
Goal remains active under the existing authority, binding, start and epoch.

Remaining gates: independent complete Step05 A+B review; complete Step02
S+A+E+B protected-focused review after exact Pixel11Pro and separate
standard-only Android P1–P8, including P7 actual saved-ID Candidates List/Detail
restart; per-root Step commits; upstream full release validation; and one
independent full Phase review/release. App aggregate validation remains deferred
to unstarted Phase6.1. Selected software evidence establishes no full-suite or
physical-device acceptance.
