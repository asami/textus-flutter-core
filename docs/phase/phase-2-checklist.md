# Phase 2 Checklist - Background Transfer Runtime and State

status=active
Owner: textus-flutter-core Phase 2.
Plan: [Phase 2](phase-2.md).
Only the explicitly evidenced entry/contract items below are checked. Remaining
Step commit, execution/recovery, handoff and whole-Phase obligations are pending.

## Entry

- [x] Confirm actual predecessor/API handoff and previously implemented connected
      work; identify remaining delta without replaying accepted work.
- [x] Freeze exact worktree, scope, public contract, dependency order and realistic
      execution estimate before implementation.

## TFC2-01: Public state and adapter contract

- [x] Freeze upload/submission identity, dependencies, persisted state and actions.
- [ ] Record focused behavioral evidence, independent acceptance and the owning Step commit.

## TFC2-02: Execution and recovery

- [ ] Implement durable execution, targeted retry, partial failure and restart.
- [ ] Record focused behavioral evidence, independent acceptance and the owning Step commit.

## TFC2-03: Public handoff and consumer verification

- [ ] Provide fixtures, adapter evidence and accepted APIs to TFAF/app.
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
passed as `tfc2-01-owning-step-review-20261011@1`. Its commit and all later
Step/full-validation/release checkboxes remain pending.

TFC2-01 evidence: `tfc2-01-owning-step-review-20261011@1`, PASS; exact
Step commit pending. Later owning Step/full-Phase gates remain required.
