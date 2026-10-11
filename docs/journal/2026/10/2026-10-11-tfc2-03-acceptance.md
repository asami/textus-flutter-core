# 2026-10-11 — TFC2-03 public submission handoff entry

Current status: TFC2-01 and TFC2-02 accepted and committed. TFC2-03 documentary
handoff and parent intake complete; independent protected owning Step review
passed. Exact Step commit and whole Core Phase 2 acceptance remain pending.
Owner: textus-flutter-core Phase 2 / TFC2-03; parent owns evidence admission,
validation, independent review, transitions and commits.
Update rule: append actual scoped intake, review and exact commit receipts;
preserve earlier dated failures and pending-at-receipt statements. Record full
Phase closure only after its actual validation/review/release gates pass.

## Frozen scope and predecessor receipts

Implementation manifest `tfc2-03-documentary-handoff-manifest-20261011@1`
selects TFC2-03-D-handoff under `tfc2-connected-20261011-authority@1`,
`tfc2-connected-20261011-goal-binding@1` and epoch
`tfc2-connected-20261011-epoch-1@1`. The
[parent manifest](../../../../../../phases/PHASE-6.1/core2-03-documentary-handoff-manifest-20261011.json)
retains the original App Goal, bases, Core/TFAF authority and review/repair history.
Core total scope remains 80 paths. This is factual documentary adoption of
existing contracts and specifications, with no behavior or assertion change.

TFC2-01 owning review `tfc2-01-owning-step-review-20261011@1` passed; actual
25-path Step commit is `cd9da12f7219c8096762f5c16f3f2f5bb3998a65`.
TFC2-02 owning review `tfc2-02-owning-step-review-20261011@1` passed; actual
49-path Step commit is `95942a5c260adc37608f8b002284097e7b61f905`.
The [Step1 journal](2026-10-11-tfc2-01-acceptance.md) and
[Step2 journal](2026-10-11-tfc2-02-acceptance.md) retain their historical
precommit receipts. These current commit observations supersede only current
progress, without rewriting historical failures or acceptance attribution.
Core Phase 1.3 historical status and TFAF Phase 2.1's accepted handoff remain.

The exact TFC2-03 Step is original six plus two shared progress paths:

| Exact repository-relative path | Role | Four-document author subset |
| --- | --- | --- |
| `lib/textus_flutter_core.dart` | Public library target program | No |
| `test/support/submission_fixture.dart` | Original/SQLite and controlled-port target program | No |
| `test/support/submission_http_fixture.dart` | Controlled HTTP target program | No |
| `test/support/submission_background_fixture.dart` | Background composition target program | No |
| `docs/notes/phase-2-public-submission-handoff.md` | Public handoff | Yes |
| `docs/journal/2026/10/2026-10-11-tfc2-03-acceptance.md` | This owning journal | Yes |
| `docs/phase/phase-2.md` | Shared Phase progress | Yes |
| `docs/phase/phase-2-checklist.md` | Shared checklist | Yes |

The four programs and every code/test/fixture/export/configuration path are
read-only for this author. The complete eight-path parent Step includes their
existing changes; documentary authoring does not independently accept them.

## Existing contracts and public consumers

The [public library](../../../../lib/textus_flutter_core.dart) exposes existing
`SubmissionRequest`, `SubmissionCodec`, `SubmissionService`,
`SubmissionTransferStatus` and `SubmissionBackgroundResources`, with generic
queue/configuration/adapters/background execution. The
[submission fixture](../../../../test/support/submission_fixture.dart) owns
real test-private original files/SQLite and independently controlled storage,
transport, wake, checkpoint-write and original-read barriers. The
[HTTP fixture](../../../../test/support/submission_http_fixture.dart) owns the
captured client and ephemeral credential ports while concrete public Drive/HTTP
adapters borrow them. The
[background fixture](../../../../test/support/submission_background_fixture.dart)
composes real disk/SQLite, controlled configuration/HTTP and borrowed run
lifetimes, with explicit handle cleanup. These are test support, not production
RAM fallback, public production exports or global factory replacement.

The existing [durable submission](../../../notes/durable-material-submission.md),
[transfer status](../../../notes/background-transfer-status-contract.md),
[reference access](../../../notes/submission-reference-access-contract.md) and
[HTTP/Drive](../../../notes/submission-http-drive-connections.md) contracts are
adopted unchanged. Commit snapshots document/payload, ordered originals,
provenance and opaque presentation/execution context before wake, with no remote
IO. Targeted retry preserves successful reservations/receipts, immutable
idempotency identity and exact packet. Unknown acknowledgement remains observable;
only matching acknowledgement establishes submission success. Storage success
and submission success are separate facts, neither establishing Candidate formation.

Existing constructor/codec errors, null-for-absence queries, equality, close,
cancellation/retirement, original retention and exact manual transcript whitespace
remain. Opaque context, including arm information, retains no Core experiment
interpretation or experiment policy in UI. Reference bindings are local operator
declarations, not remote permission proof; no credential/grant/network fallback
or public sharing is introduced. Device encrypted configuration and actual native
execution retain their separately scoped limits.

| Consumer owner | Public edge | Responsibility and selected evidence |
| --- | --- | --- |
| TFAF Phase 3 | `SubmissionFacade`, `SubmissionConfigurationFacade`, `SubmissionStatusBinding` over public Core imports | Immutable input, fresh queries/actions, common settings/status and borrowed resources; CF1/CF2/CU3 and selected 27-suite/234-case evidence. |
| App Phase 6.1 | `BookSubmissionService`, `BookSubmissionMapper`, `BookSubmissionComposition` over public TFAF/Core | Saved ISBN-or-title eligibility and Book snapshot, originals/transcript/provenance/opaque context, editor/navigation; controlled eight-suite/100-case evidence and BH17 plus mapper/service55. |

Core closure requires consumer evidence. TFAF/App own Phase closure remains
separate and is not a circular prerequisite for Core's public handoff.

## Exact scoped parent evidence

These are supplied actual parent receipts, reused within their stated scopes.
This author executed no product validation, analyzer, runtime, static validation
or self-review. No executable specification, Given/When/Then clause, fixture or
assertion changed in this documentary Slice.

| Receipt | Actual outcome | Scope and limits |
| --- | --- | --- |
| [esa61-submission-reference-guard-software-validation-20261010@1](../../../../../../phases/PHASE-6.1/submission-reference-guard-software-validation-20261010.json) | RA3 representative: exit 0, one pass. Accumulator: exit 0, 23 suites, 375 passes, zero failures. Source analysis: no issues. | Real originals/SQLite, guard denial/configuration/same-id retry/reopen and immutable exact packet through public exports/fixtures; controlled remote ports. Native20 and consumer APK compile remain scoped compiler observations. |
| [esa61-fix34-validation-20261011@1](../../../../../../phases/PHASE-6.1/submission-fix34-validation-20261011.json) | Q4: exit 0, one pass. Ten suites: 115 passes, zero failures/skips. Scoped analysis no issues; dry format zero changes. NC1/NC2: each one pass, zero failures, one other-stage skip. | Later production awaited `rawQuery` correction, FULL=2/5000ms and retained records. Native retained encrypted configuration/default factories with `queueCount=0`, not nonempty queue dispatch or hardware security certification. |
| [esa61-drive-native-entry-validation-20261011@2](../../../../../../phases/PHASE-6.1/drive-native-entry-validation-20261011.json) | Main/test compilation successful; 37 policy passes (14 timing, 10 connection, 9 lifecycle, 4 work), zero failures/errors/skips. Post-entry ND1 one pass, zero failures, two other-stage skips. | Public channel authorization/retained folder over an existing grant. AT9 virtual 53 seconds proves no actual greater-than-20-second human wait. ND2/ND3 not rerun here. |
| [esa61-native-book-validation-final-20261011@1](../../../../../../phases/PHASE-6.1/submission-native-book-validation-final-20261011.json) | NQ1–NQ4 each exit 0, one pass, zero failures, five other-stage skips. | NQ1/NQ2 nonempty ready original/immutable intent/newer Draft persistence; NQ3 actual WorkManager two `authRequired` claims and one explicit retry; NQ4 fresh-process failed original/context/status restoration. Held wake/supplied offline prove no physical radio toggle, OS stop, lease-recovery experiment or successful headless upload. |
| [esa61-native-drive-post-timing-actual-20261011@3](../../../../../../phases/PHASE-6.1/native-drive-post-timing-actual-20261011.json) | Historical ND1/ND2/ND3 each exit 0, one pass, zero failures, two other-stage skips. | Actual ND1 consent/folder; ND2 synthetic 68-byte original upload/idempotence/independent metadata and binary readback; ND3 fresh-process silent restore with unchanged identity and no UI/create/upload. No whole Book-media, server or headless Drive-upload acceptance. |
| [esa61-drive-native-entry-focused-admission-20261011@1](../../../../../../phases/PHASE-6.1/drive-native-entry-focused-admission-20261011.json) | Narrow protected App entry review PASS; CPB-ESA61-DRIVE-TIMING-001 resolved. | Borrowed context, not Core Step acceptance. Existing SDK20s/consent120s/total160s, silent20s/cancellation/late-result contracts retained; whole Step/producer Phases unaccepted at this receipt. |
| [esa61-submission-tfaf-c2-software-validation-20261010@1](../../../../../../phases/PHASE-6.1/submission-tfaf-c2-software-validation-20261010.json) | CU3 representative one pass; 27 suites/234 passes, zero failures; clean analysis. | CF1/CF2/CU3 public Core facade/fixtures with controlled ports and real local files/SQLite; no remote/native result or TFAF own Phase acceptance. |
| [esa61-controlled-software-validation-20261011@1](../../../../../../phases/PHASE-6.1/controlled-software-validation-20261011.json) | Representative one pass; eight suites/100 passes, zero failures/skips; analysis zero issues. | Public Book-Core-TFAF success/failure/retry/offline/reopen, actual original files/SQLite with controlled remote outcomes/network policy/software reopen; no device/cloud/server acceptance. |
| [esa61-server-handoff-software-validation-20261011@1](../../../../../../phases/PHASE-6.1/server-handoff-software-validation-20261011.json) | Representative one pass; 17 BH plus 55 mapper/service cases, 72 passes, zero failures/skips; analysis zero issues. | Public codec/concrete HTTP adapter with injected HTTP, actual private originals/SQLite, provenance/context/packet; no actual server receiver/durable remote idempotency acceptance. |

These accumulators are not complete package/Phase validation. Initial failures,
authored-only statements and earlier pending gates retain their date and outcome.
Newer results supersede only current status in the proven scope. Other-stage skips
prove nothing about skipped scenarios. Account, client, token and grant contents
and private machine paths are excluded from this journal.

## Remaining gates and dispositions

Parent complete eight-path intake and four-program preflight passed. Protected
independent TFC2-03 review passed; exact Step commit remains pending. This author reports no new
findings. Canonical [Hygiene](2026-10-11-phase-2-hygiene-follow-up.md) and
[Development Candidate](2026-10-11-phase-2-development-candidate-follow-up.md)
records retain their parent-owned admission and chronology. No target-program
same-file debt applies to this four-document subset; no separate debt is newly
admitted.

All original three Steps remain required. Core full-package
`scripts/validate-full.sh`, one comprehensive owning Phase review, canonical
dispositions, checklist/index/journal closure and distinct Phase release remain
pending. Separate TFAF Phase 3 and App Step/Phase/aggregate validation/release
remain required. Saved photo/text compatibility and original audio/editable
transcript retain their accepted limits. No server implementation, Candidate or
AI follow-up, Phase 5, successor Phase, publication or deployment is admitted.

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
