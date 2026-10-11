# Phase 2 - Background Transfer Runtime and State

status=active
planned_at=2026-10-10
execution_owner=textus-flutter-core
phase_owner=textus-flutter-core
consumer_phase=nict-editing-studio-app Phase 6.1
validation_ownership=standalone-full-owner
predecessor=Phase 1.3 public workflow handoff
execution_started=true
related_steps=ESA6-06, ESA6-07, ESA6-08

## Boundary

Connected upstream delivery for [app Phase 6.1](../../../../../docs/phase/phase-6.1.md).
This is the repository-owned Phase 2, with its own Steps, checklist,
validation, review and release closure. App Phase 6.1 ESA6-06/07/08 is the
consumer/integration owner, not a substitute for upstream acceptance. Existing
accepted work and app aggregate-validation ownership remain unchanged. Entry
selects the actual repository/worktree, available predecessor APIs and missing
bounded capabilities; this document does not start implementation or redirect
an already-running checkout. See [the completion checklist](phase-2-checklist.md).


Core owns the durable operation state and execution used by the common TFAF
screen. Keep storage upload and data submission independently observable and
associate them with the same consumer-selected work item. The package remains
domain-independent: Book fields, Material Commit eligibility, destination labels
and navigation belong to the consumer. TKL is the logical material destination;
the existing app plan's KTL/Google Drive adapter is not a separate third stage.

- Expose durable queued/waiting/running/succeeded/failed outcomes, waiting reason,
  timestamps, available progress, failure details, supported actions and results.
- Gate submission on required accessible storage references; expose dependency
  waiting explicitly. A work item requiring no upload can proceed without one.
- Preserve successful uploads for the same committed content when submission
  fails; retry the failed submission only. Handle partial file failure without
  automatically repeating successful transfers.
- Restore actual state after restart. Define interrupted/unknown acknowledgement
  handling through the selected transport contract before permitting a resend.
- Keep original local material on failure. Storage completion and submission
  acknowledgement are different facts; neither implies Candidate formation.
- Return only supported progress/retry information. Do not fabricate percentages,
  retry deadlines or successful remote results.

## Work Stack

| ID | Step | Outcome | Status |
| --- | --- | --- | --- |
| TFC2-01 | Public state and adapter contract | Freeze upload/submission identity, dependencies, persisted state and actions. | accepted; committed cd9da12 |
| TFC2-02 | Execution and recovery | Implement durable execution, targeted retry, partial failure and restart. | accepted; committed 95942a5 |
| TFC2-03 | Public handoff and consumer verification | Provide fixtures, adapter evidence and accepted APIs to TFAF/app. | owning review passed; exact commit pending |

## Entry and validation

Before execution, identify the current accepted predecessor/public APIs and the
exact remaining delta. Preserve already implemented connected app work and reuse
its relevant evidence; do not reimplement or claim it accepted merely by creating
this Phase. Freeze repository scope, dependencies and a calibrated execution
estimate at entry; no unsupported PROCEED/time estimate is asserted here.

Each Step receives focused behavioral validation and independent acceptance under
the execution workflow. Phase closure requires the complete package analysis/test
suite, affected-consumer evidence, one comprehensive Phase review, resolved current
blockers and a distinct release commit with the checklist/journal handoff. App-only
validation does not replace this package's full checks. Fake results do not prove
real adapter or server execution. No full-validation deferral is selected here.

## Coordination

Delivery order: Core public state/action contract -> TFAF common screen -> app
composition -> ESA6-07 integration acceptance -> ESA6-08 handoff documentation.
Missing cross-owner capabilities are addressed by their owner before dependent
integration; do not add temporary app implementations for later extraction.
No hash ledger, generic revision framework, public-sharing default or unrelated
storage migration is introduced by this request.

- [Other upstream plan](../../../textus-flutter-application-framework/docs/phase/phase-3.md)
- [Design discussion](../notes/background-transfer-status-contract.md)
- [Decision journal](../journal/2026/10/2026-10-10-esa6-06-transfer-status-contract.md)

## Predecessor and deferred scope

Phase 1.3 already identifies Local Commit / Deferred Sync as a Phase 2 handoff.
This Phase concretizes its bounded transfer-runtime portion. AiService/AiProvider
and other on-device-AI follow-ups remain separate planned work; this Phase neither
accepts nor silently deletes them. Inspect the actual public workflow handoff at
entry without rewriting historical Phase status. Core closure requires bounded
public-API/fixture and adapter evidence, not TFAF Phase 3 or app Phase 6.1 closure;
TFAF can therefore consume the accepted handoff without a circular dependency.

## Connected execution plan — 2026-10-11

Current status (2026-10-11): TFC2-01 independent protected Step review passed
and its exact commit is `cd9da12f7219c8096762f5c16f3f2f5bb3998a65`. TFC2-02
parent intake and protected owning review passed; its exact commit is
`95942a5c260adc37608f8b002284097e7b61f905`. TFC2-03 documentary handoff
and parent intake are complete; independent protected Step review passed.
Exact Step commit and whole-Phase acceptance remain pending.
Owner: textus-flutter-core Phase 2, coordinated by the existing App Phase 6.1 task.
Update rule: retain historical App source reviews as borrowed evidence and record
this Phase's independent Step reviews, exact commits, full checks and release separately.

The human explicitly authorized Core Phase 2 and TFAF Phase 3 completion in this
chat. Use the [selected Core checkout](../..) on `codex/esa6-local-capture`; the original main checkout is
read-only. The original App Goal, bases, epoch and review/repair history remain.
This is adoption of existing connected implementation for owning-Phase acceptance,
not acceptance inferred from the App's source reviews. No successor starts here.

Core has 70 existing submission/capture-guard paths; TFAF has 39 common UI paths.
Preserve existing code, saved data, public APIs and executable specifications.
The accepted audio/capture APIs are available, but this record does not close
Core Phase 1.3 or reinterpret its historical planned status. TFAF Phase 2.1's
accepted handoff is retained. TFAF runtime acceptance waits for Core Phase 2's
public handoff; Core closure needs consumer evidence, not TFAF/App Phase closure.

All three original Steps remain required. The private parent-owned plan selects
exact partitioned executable/source commit paths and borrowed inputs for each Step.
The same two shared Phase progress documents, `docs/phase/phase-2.md` and
`docs/phase/phase-2-checklist.md`, may be selected for staging in each owning Step
to record truthful progress; the parent must retain the exact selected paths.
TFC2-02 therefore has exactly 49 paths (original 47 plus these two), including
its six-document authoring subset. The overall Core scope remains 80 paths. Public export and
fixture handoff closes in the third Step. Intermediate local Step commits are
not standalone package releases. Require all owning Steps before the distinct
Phase release; do not move unreviewed dependency changes into an accepted handoff.

Reuse applicable observed host/native results after checking their relevance;
do not rerun them merely for new record formatting. Core policy tests currently
pass 37 cases; post-entry Fold authorization passed. Earlier real Drive upload
and fresh-process readback retain their 68-byte synthetic-fixture scope. Long
consent success is controlled virtual-time evidence, not a real long human wait.
NQ1–NQ4 supply their recorded native persistence/WorkManager scopes; supplied
offline inputs do not prove a physical radio toggle or an OS-stop experiment.
Unknown acknowledgement handling retains the configured idempotent transport
contract; no exactly-once remote guarantee or real server acceptance is claimed.

Required owning closure: focused behavioral evidence and one independent Step
acceptance per Step, exact Step commits, one comprehensive owning Phase review,
complete `scripts/validate-full.sh`, applicable native policy and consumer evidence,
canonical Hygiene/Development Candidate disposition, checklist/index/journal
handoff, and a distinct local Phase release commit. Full-package checks are
reserved for this Phase's release tree; App-only checks cannot substitute.
No server implementation, Phase 5, AI follow-up or automatic public sharing is included.

TFC2-01 evidence: `tfc2-01-owning-step-review-20261011@1`, PASS; exact
Step commit `cd9da12f7219c8096762f5c16f3f2f5bb3998a65`. The
[predecessor journal](../journal/2026/10/2026-10-11-tfc2-01-acceptance.md) retains
its historical precommit receipt; this current projection supersedes only its
commit-pending status. The [TFC2-02 journal](../journal/2026/10/2026-10-11-tfc2-02-acceptance.md)
records scoped execution evidence and protected owning review PASS; its historical
precommit statements are retained. The actual TFC2-02 commit is recorded above.
TFC2-03, full-package validation, comprehensive Core Phase review and distinct
release remain required. Original bases, predecessor limits and all three Steps
retain their admitted authority and contracts.

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

## 2026-10-11 — TFC2-02 commit and TFC2-03 documentary handoff

The actual local TFC2-02 Step commit is
`95942a5c260adc37608f8b002284097e7b61f905` (49 paths), after owning independent
review `tfc2-02-owning-step-review-20261011@1` PASS. TFC2-01 remains accepted
at `cd9da12f7219c8096762f5c16f3f2f5bb3998a65`. These receipts supersede only
current progress; the dated acceptance-before-commit snapshot above and both
predecessor journals preserve their original precommit/failure scopes.

TFC2-03 now has its documentary handoff authored. Its exact Step scope is eight
paths: original six (`lib/textus_flutter_core.dart`, the three
`test/support/submission_fixture.dart`, `submission_http_fixture.dart` and
`submission_background_fixture.dart` helpers, `docs/notes/phase-2-public-submission-handoff.md`
and `docs/journal/2026/10/2026-10-11-tfc2-03-acceptance.md`) plus shared
`docs/phase/phase-2.md` and `docs/phase/phase-2-checklist.md`. The four-document
author subset is the handoff, new journal and two shared Phase documents; no
program or specification change is selected. Core total scope remains 80 paths.

The [handoff](../notes/phase-2-public-submission-handoff.md) and
[owning journal](../journal/2026/10/2026-10-11-tfc2-03-acceptance.md) identify the
four programs, public TFAF/App consumers and actual selected scoped evidence:
RA3/375, later Q4/115, native 37/NC/NQ/ND, TFAF 234, App 100 and BH/mapper/service
72. Their controlled, empty-queue, authRequired and 68-byte synthetic limits
remain. These are reused parent observations, not new validation or acceptance.

TFC2-03 independent protected Step review and exact commit remain pending. Core
full-package validation, one comprehensive Phase review and distinct release,
TFAF Phase 3 closure, App Step/Phase/aggregate validation and release remain
required. No whole-Phase or real server acceptance is inferred.

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
