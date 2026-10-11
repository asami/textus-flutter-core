# Phase 2 Checklist - Background Transfer Runtime and State

status=active
Owner: textus-flutter-core Phase 2.
Plan: [Phase 2](phase-2.md).
Only the explicitly evidenced entry/contract and accepted TFC2-01 item below
are checked, along with independently accepted and committed TFC2-02.
TFC2-03 independent owning review passed; its exact commit, whole behavioral
acceptance, full-package validation, full review and Phase release remain pending.

## Entry

- [x] Confirm actual predecessor/API handoff and previously implemented connected
      work; identify remaining delta without replaying accepted work.
- [x] Freeze exact worktree, scope, public contract, dependency order and realistic
      execution estimate before implementation.

## TFC2-01: Public state and adapter contract

- [x] Freeze upload/submission identity, dependencies, persisted state and actions.
- [x] Record focused behavioral evidence, independent acceptance and the owning Step commit.

## TFC2-02: Execution and recovery

- [x] Implement durable execution, targeted retry, partial failure and restart.
- [x] Record focused behavioral evidence, independent acceptance and the owning Step commit.

## TFC2-03: Public handoff and consumer verification

- [x] Provide fixtures, adapter evidence and accepted APIs to TFAF/app.
- [ ] Record focused behavioral evidence, independent acceptance and the owning Step commit.

## Behavioral acceptance

- [ ] Inventory existing public storage/queue APIs and persisted state; freeze
      only missing bounded additions and the selected adapter/consumer contract.
- [ ] Implement separate upload/submission state, dependency and result delivery
      through the public entry point; preserve existing consumers and saved data.
- [ ] Implement targeted retry, partial failure and restart behavior, including
      handling of unknown acknowledgement without assuming exactly-once delivery.
- [ ] Supply controllable upload/submission fixtures through those same APIs.
- [ ] Validate TFAF and the app against the accepted public handoff; record actual
      Google Drive/storage adapter results separately from fake lifecycle evidence.

- [ ] Cover both success paths, offline waiting, upload failure/dependent wait,
      upload success/submission failure and targeted retry, partial upload,
      queued/running restart, no-upload content and indeterminate progress.
- [ ] Prove that UI rebuild/navigation and submission retry do not repeat an
      already successful upload for the same committed content.
- [ ] Keep fake acceptance distinct from actual remote upload/submission; retain
      local originals and do not claim Candidate formation from either result.
- [ ] Run proportionate package analysis/tests and affected-consumer checks;
      coordinate release validation with Phase 6.1 without declaring upstream
      obligations satisfied by app-only tests.

## Phase closure

- [ ] All owned Steps and required consumer/adapter evidence accepted.
- [ ] Complete package analysis and tests pass; app-only tests are insufficient.
- [ ] One comprehensive Phase review closes all current blockers.
- [ ] Publish the public API/UI handoff and separate actual from fake results.
- [ ] Record closure in Phase, checklist, journal and index; create the distinct
      Phase release commit through the normal execution workflow.

## Connected acceptance evidence — 2026-10-11

Parent-selected checkout and original contracts have been inspected. Existing
App reviews/tests are borrowed evidence only. TFC2-01 owning independent review
passed as `tfc2-01-owning-step-review-20261011@1`; its exact Step commit is
`cd9da12f7219c8096762f5c16f3f2f5bb3998a65`. TFC2-02 documentary evidence is
authored and its parent intake/owning independent protected review passed;
its exact commit is `95942a5c260adc37608f8b002284097e7b61f905`. TFC2-03,
whole behavioral, full-package/full-review and release items remain unchecked
pending their actual owning evidence.

TFC2-01 evidence: `tfc2-01-owning-step-review-20261011@1`, PASS; exact
Step commit `cd9da12f7219c8096762f5c16f3f2f5bb3998a65`. This dated current
projection supersedes precommit status snippets in the unchanged
[predecessor journal](../journal/2026/10/2026-10-11-tfc2-01-acceptance.md); they
remain historical. See [TFC2-02 evidence](../journal/2026/10/2026-10-11-tfc2-02-acceptance.md)
for the six-document authoring subset within its exact 49-path boundary. Core
total scope remains 80 paths. Later owning Step/full-Phase gates remain required;
no scoped App entry-review PASS substitutes for them.

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

## 2026-10-11 — TFC2-02 commit and TFC2-03 scope receipt

Actual TFC2-02 commit `95942a5c260adc37608f8b002284097e7b61f905` contains the
selected 49 paths after `tfc2-02-owning-step-review-20261011@1` PASS. Its
composite evidence/review/commit item is now checked. TFC2-01 remains accepted
and committed at `cd9da12f7219c8096762f5c16f3f2f5bb3998a65`. The dated
precommit snapshot above and historical journals retain their original outcomes.

TFC2-03 documentary handoff is authored within exactly eight paths: the original
six public library, three test-owned support fixtures, public handoff note and
owning TFC2-03 journal, plus the two shared Phase progress documents. See the
[exact path inventory and evidence](../journal/2026/10/2026-10-11-tfc2-03-acceptance.md).
This author owns only the four documents. Core total scope remains 80 paths.
Existing programs, contracts and executable specifications are adopted unchanged.

Both TFC2-03 boxes remain unchecked pending independent Step review and exact
commit. All whole behavioral, full-package, comprehensive review and release
boxes remain unchecked. Scoped RA3/375, later115/native37/NC/NQ/ND and public
TFAF234/App100/BH72 evidence retain their actual limits; separate TFAF/App Phase
and App aggregate/release gates remain required.

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
