# 2026-10-10 ESA6-06-S1 transfer status producer

Current status: Manifest `esa61-submission-status-producer-manifest-20261010@1`
source/specification/document authoring complete. Parent DR1 passed (1 test), and
the selected 20-suite software accumulator passed (339 tests, 0 failures).
Parent analysis reported `No issues found!`; dry format reported 13 files with
0 changed. Independent S1 acceptance remains pending. No Step or Phase completion
is recorded here.

Owner: Core owns immutable transfer status, exact persistence compatibility and
fenced dispatch uncertainty. Parent `/root` owns validation, review, acceptance,
workflow records and commits. TFAF/App presentation follows later admitted work.

Update rule: Append exact parent validation/review evidence for this tree when
available. Keep authored source, software execution, native runtime, real Drive,
fake server and actual server acceptance distinct; retain prior phase histories.

The [public contract note](../../../notes/background-transfer-status-contract.md)
records both operation mapping tables, actual progress/deadlines/actions, safe
network/reference observations and immutable navigation identity. The
[public library](../../../../lib/textus_flutter_core.dart) exports the pure
projection and additive checkpoint/outcome values. No projection performs IO,
scheduling or authorization.

Record persistence alone upgrades to exact v2. Exact deployed v1 rows remain
readable without rewrite; complete-reference positive-claim non-submitted rows,
including zero-upload rows, retain legacy ambiguity with null dispatch time/count.
Request/packet/original/audio/transcript schemas, opaque provenance/context and
edited whitespace remain exact. SQL schema/user_version/index/root remain 1.

Earliest uncertainty is durable before submit. Fenced checkpoint return is
followed by current-owner recheck and lease renewal. Matching acknowledgement
clears uncertainty. Trusted current-claim no-send/refusal can clear only that
nonlegacy checkpoint; a later refusal cannot erase earlier/legacy possible
acceptance. Timeout/raw/mismatch/cancellation/local acknowledgement write loss
preserve uncertainty. HTTP safe errors before potential send are notSent; only
explicit sent 401/403 authorization refusals are rejected. Other sent outcomes
remain unknown without exposing credentials/raw response text.

Existing intent recovers through the same idempotent POST/key/packet, preserving
successful uploads. `requestRun(id)` is fresh serialized read plus existing wake;
it creates no queue intent/claim/remote effect. Submitted never wakes. Failed
presentation supports retry, ready or expired claim supports requestRun, and a
current lease supports no presentation action.

[TS1/TS2](../../../../test/submission/submission_transfer_status_test.dart)
author actual two-operation/reference/action/network/immutability matrices.
[DR1–DR5](../../../../test/submission/submission_dispatch_recovery_test.dart)
author real photo/audio originals plus actual SQLite acceptance-write loss and
restart, bounded checkpoint/remote barriers and competing handles, safe refusal
clearing versus earliest/legacy retention, literal old rows and first v2
transitions, and concrete HTTP transport over controlled streams. Adjacent
Given/When/Then clauses attach setup/action/observable expectations to scenarios,
helpers, callbacks and cleanup. The worker executed no validation/self-review.

S2 execution reference-access guard and query integration are pending mandatory
follow-up. Unknown/unavailable reference presentation cannot authorize dispatch.
Host specifications do not accept Android isolate/WorkManager lifecycle, actual
Google Drive upload/access or actual EditingStudio server execution. Fake server
acknowledgement is controlled evidence only. Existing A/B1/B2/audio acceptance
histories remain intact; previous Kotlin/APK compilation remains historical native
evidence. No old B2/App status receipt is rewritten by this manifest.

Core Phase 2 and TFAF Phase 3 retain their separate planned startup/review/closure;
this slice starts/closes neither. App Phase6.1 review cannot replace upstream
package/Phase acceptance. Parent still owns selected representative/accumulator
validation, final aggregate validation, exact Step commits and distinct release.
No publication, deployment, real-server acceptance, Step or Phase closure is
claimed by authored code/specifications.
