# 2026-10-11 — TFC2-02 execution and recovery evidence entry

Current status: TFC2-02 parent intake and independent protected owning Step
review passed; exact Step commit pending. TFC2-01 is accepted and committed
at `cd9da12f7219c8096762f5c16f3f2f5bb3998a65`. TFC2-03 and whole Core Phase 2
acceptance remain pending.
Owner: textus-flutter-core Phase 2 / TFC2-02; parent owns evidence admission,
validation, review, transitions and commits.
Update rule: append actual scoped parent intake, independent owning review and
exact commit receipts. Retain historical failures, authors and pending-at-receipt
statements; record Phase closure only after its actual gates pass.

## Frozen scope and predecessor

Implementation manifest `tfc2-02-documentary-evidence-manifest-20261011@4`
selects TFC2-02-D-evidence under `tfc2-connected-20261011-authority@1`, the
live original App Phase 6.1 Goal and connected Core Phase 2 authority. The
[parent manifest](../../../../../../phases/PHASE-6.1/core2-02-documentary-evidence-manifest-20261011.json)
and [implementation entry](../../../../../../phases/PHASE-6.1/core2-02-implementation-entry-20261011.json)
retain the original bases, epoch and history. Core total scope remains 80 paths.
The exact TFC2-02 Step accumulator is 49 paths: original 47 plus the two already
admitted shared Phase progress documents. Executable/source ownership remains
partitioned; these same progress documents can be selected by each owning Step
with exact paths. This author owns only this six-document subset:

- [Durable material submission](../../../notes/durable-material-submission.md):
  `docs/notes/durable-material-submission.md`.
- [HTTP/Drive connections](../../../notes/submission-http-drive-connections.md):
  `docs/notes/submission-http-drive-connections.md`.
- [Android runtime](../../../notes/android-submission-runtime.md):
  `docs/notes/android-submission-runtime.md`.
- This journal: `docs/journal/2026/10/2026-10-11-tfc2-02-acceptance.md`.
- [Phase plan](../../../phase/phase-2.md): `docs/phase/phase-2.md`.
- [Phase checklist](../../../phase/phase-2-checklist.md):
  `docs/phase/phase-2-checklist.md`.

`tfc2-01-owning-step-review-20261011@1` returned PASS over 25 owning paths,
50 selected owning/borrowed paths and 16 target programs, with empty CPB/Hygiene/
Development Candidate lists. Its exact Step commit is recorded above; the
[predecessor journal](2026-10-11-tfc2-01-acceptance.md) retains historical
precommit statements. This current projection does not rewrite that journal.
Core Phase 1.3 historical limits and TFAF Phase 2.1's accepted handoff remain.

## Adopted contracts and executable evidence

Existing source and specifications are adopted unchanged. The
[service](../../../../lib/src/submission/submission_service.dart) validates
originals and atomically persists immutable intent before wake without remote IO.
The [SQLite queue](../../../../lib/src/submission/sqlite_submission_queue_store.dart)
owns durable state, strict corruption visibility and matching unexpired claims.
The [runner](../../../../lib/src/submission/submission_background_runner.dart)
and [run lifetime](../../../../lib/src/submission/submission_run_lifetime.dart)
retain current-owner dispatch/checkpoint fencing, bounded lifecycle and borrowed
resource ownership. Targeted retry preserves successful reservations/receipts,
originals, provenance, opaque context and manual whitespace. Earliest unknown
transport dispatch survives no-send/configuration/retry/reopen; only matching
acknowledgement establishes submission success. Local fencing promises no network
exactly-once guarantee; storage success establishes no Candidate formation.

The [Drive adapter](../../../../lib/src/submission/drive_submission_storage_adapter.dart)
and [HTTP transport](../../../../lib/src/submission/http_submission_transport.dart)
retain immutable remote identity and safe errors. The
[configuration facade](../../../../lib/src/submission/android_submission_configuration.dart)
and [native worker](../../../../packages/textus_flutter_core_android_submission/android/src/main/kotlin/org/textus/flutter/core/submission/SubmissionWorker.kt)
retain encrypted exact targets, foreground/headless acquisition and accepted
default queue/original roots. Captured ownership, cancellation and close retain
durable data. Configured reference access is a fail-closed local operator
declaration, not remote readability/permission proof. Closed schemas, key/AAD,
no-reset/no-plaintext-fallback and operation-time ENOENT rules remain unchanged.
Book fields/gating/current-edit flush/mapping/navigation remain App-owned;
TFAF consumes public configured connections and status/retry/wake actions.

Directly selected specifications include
[RA3 recovery](../../../../test/submission/submission_reference_guard_recovery_test.dart),
[queue Q4](../../../../test/submission/submission_queue_store_test.dart),
[service](../../../../test/submission/submission_service_test.dart),
[runner/NB1](../../../../test/submission/submission_background_runner_test.dart),
[HTTP integration/HB1](../../../../test/submission/submission_http_integration_test.dart),
[dispatch recovery](../../../../test/submission/submission_dispatch_recovery_test.dart),
[channel](../../../../test/submission/android_submission_channel_test.dart),
[authorization timing](../../../../packages/textus_flutter_core_android_submission/android/src/test/kotlin/org/textus/flutter/core/submission/SubmissionAuthorizationTimingTest.kt),
and App [native configuration/nonempty queue](../../../../../../../integration_test/book_submission_native_test.dart)
and [Drive](../../../../../../../integration_test/book_submission_drive_native_test.dart)
fixtures. No source, assertion, Given/When/Then, fixture, configuration or executable
specification is created or modified by this documentary Slice.

## Exact scoped parent evidence

All results below are actual supplied parent receipts reused within their selected
scope. The documentary author ran no command validation or self-review.

| Receipt | Actual outcome | Scope and limits |
| --- | --- | --- |
| [esa61-submission-reference-guard-software-validation-20261010@1](../../../../../../phases/PHASE-6.1/submission-reference-guard-software-validation-20261010.json) | RA3 representative: exit 0, one pass. Accumulator: exit 0, 23 suites, 375 passes, zero failures. Source analysis: exit 0, no issues. Dry format: 13 files, zero changes; diff check exit 0. | Real originals/SQLite and immutable exact packet on guard-deny/configure/same-id retry/reopen; controlled remote ports. Native pure policy 20 passes and consumer APK compile were scoped compiler observations, not device/server acceptance. |
| [esa61-fix34-validation-20261011@1](../../../../../../phases/PHASE-6.1/submission-fix34-validation-20261011.json) | Q4: exit 0, one pass. Later accumulator: exit 0, ten suites, 115 passes, zero failures/skips. Queue analysis: exit 0, no issues. Dry format: one file, zero changes. NC1/NC2: each exit 0, one pass, zero failures, one other-stage skip. | Later production awaited timeout `rawQuery` correction, actual FULL=2/5000ms and record retention; native encrypted configuration/default-factory observations with empty `queueCount=0`. No nonempty dispatch or hardware certification. |
| [esa61-drive-native-entry-validation-20261011@2](../../../../../../phases/PHASE-6.1/drive-native-entry-validation-20261011.json) | Successful main/test compilation; exit 0, 37 policy passes (14 timing, 10 connection, 9 lifecycle, 4 work), zero failures/errors/skips. Post-entry ND1: exit 0, one pass, zero failures, two other-stage skips. | Shared entry AT9 succeeds at virtual 53 seconds; actual public authorization/retained folder over an existing grant. No new human consent or actual greater-than-20-second wait. ND2/ND3 not rerun here. |
| [esa61-native-book-validation-final-20261011@1](../../../../../../phases/PHASE-6.1/submission-native-book-validation-final-20261011.json) | NQ1–NQ4: each exit 0, one pass, zero failures, five other-stage skips. | NQ1/NQ2 nonempty ready original/immutable intent/newer Draft persistence; NQ3 actual WorkManager two authRequired claims with one explicit retry; NQ4 fresh-process failed original/context/status restore. Held wake/supplied offline prove no physical radio toggle, OS-stop or lease-recovery experiment. |
| [esa61-native-drive-post-timing-actual-20261011@3](../../../../../../phases/PHASE-6.1/native-drive-post-timing-actual-20261011.json) | ND1/ND2/ND3: each exit 0, one pass, zero failures, two other-stage skips. | Historical actual exact-account consent/folder verification; ND2 synthetic 68-byte original upload/idempotence/independent metadata and binary readback; ND3 fresh-process silent restore/readback with unchanged identity and no grant UI/create/upload. No complete Book-media/server or headless Drive-upload acceptance. |
| [esa61-drive-native-entry-focused-admission-20261011@1](../../../../../../phases/PHASE-6.1/drive-native-entry-focused-admission-20261011.json) | Actual `esa61-drive-native-entry-focused-review-20261011@1`: PASS; CPB-ESA61-DRIVE-TIMING-001 resolved. Current-blocker/Hygiene/Development Candidate lists empty in the narrow scope. | App-owned protected entry review, borrowed by Core; whole Step and producer Phases expressly unaccepted. SDK20s/consent120s/total160s and silent20s/cancellation/late-result contracts retained. |

These selected accumulators are not full-package validation. Original initial
failures and authored-only receipts retain their outcome and author; newer passes
supersede only current status within their proven scope. Explicit other-stage
skips prove nothing about skipped scenarios. Controlled HTTP acknowledgements,
supplied offline and synthetic binary results retain their stated limits. No
account/client/token/grant-secret contents are recorded.

## Remaining owning gates and dispositions

Parent six-document truth/link/whitespace intake and complete 49-path selected
boundary verification passed, with 118 resolved local links. Complete mechanical
intake covered 34 target programs, five configuration inputs and 149 behavioral
scenarios; affected-consumer/error/cancellation assessment was recorded. Fresh
independent protected TFC2-02 review passed over all 49 owning and 84 selected
paths. The exact Step commit remains pending; authoring alone was not acceptance. New admitted findings for this Slice
are empty; no Hygiene, Development Candidate or current blocker is invented.
Canonical [Hygiene](2026-10-11-phase-2-hygiene-follow-up.md) and
[Development Candidate](2026-10-11-phase-2-development-candidate-follow-up.md)
records retain their chronology and parent admission rules. No target-program
same-file debt applies to this documentary subset, and no separate debt is newly
admitted.

TFC2-03 must close public exports/fixture handoff and required consumer evidence.
All original three Steps, full-package `scripts/validate-full.sh`, one comprehensive
Core Phase review, canonical dispositions and distinct Phase release remain
required. App 153-path Step review/commit, TFAF Phase 3, comprehensive App review,
aggregate validation and release remain separately owned. Consumer evidence is
required for Core closure; TFAF/App Phase closure is not a circular prerequisite.
Core Phase 1.3, saved photo/text compatibility, original audio/editable transcript
and existing authorities retain their original limits. No server implementation,
Phase 5, successor Phase, migration, publication or deployment is admitted here.

## 2026-10-11 — Owning TFC2-02 acceptance before commit

The parent completed the six-document intake and selected 49-path whitespace/link
checks. Independent protected review `tfc2-02-owning-step-review-20261011@1`
returned PASS over 49 owning and 84 selected paths, including all 34 target
programs and five configuration inputs. Current blockers, Hygiene and Development
Candidate findings were explicitly empty. The review inspected actual scoped
RA3/375, later SQLite Q4/115, clean analysis, native 37-case and NC/NQ/ND results;
it executed no product validation. Their controlled/native/synthetic limits remain.

This dated receipt supersedes only earlier current-status implications; historical
failures, authored-only receipts and their outcomes remain unchanged. The parent
prepares the exact 49-path local Step commit. Its native outcome is still pending.
This is no standalone package or whole-Phase release. TFC2-03, Core full-package
validation/comprehensive Phase review/distinct release, TFAF Phase 3 and App
Step/Phase/aggregate/release closure remain required. Existing contracts and source
are unchanged by this factual bookkeeping; no new remote/server result is inferred.
