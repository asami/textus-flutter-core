# Phase 2 - Background Transfer Runtime and State

status=planned
planned_at=2026-10-10
execution_owner=textus-flutter-core
phase_owner=textus-flutter-core
consumer_phase=nict-editing-studio-app Phase 6.1
validation_ownership=standalone-full-owner
predecessor=Phase 1.3 public workflow handoff
execution_started=false
related_steps=ESA6-06, ESA6-07, ESA6-08

## Boundary

Connected upstream delivery for [app Phase 6.1](../../../../Project2026/nict-editing-studio-app/docs/phase/phase-6.1.md).
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
| TFC2-01 | Public state and adapter contract | Freeze upload/submission identity, dependencies, persisted state and actions. | planned |
| TFC2-02 | Execution and recovery | Implement durable execution, targeted retry, partial failure and restart. | planned |
| TFC2-03 | Public handoff and consumer verification | Provide fixtures, adapter evidence and accepted APIs to TFAF/app. | planned |

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
- [Design discussion](../notes/background-material-transfer-status.md)
- [Decision journal](../journal/2026/10/2026-10-10-background-material-transfer-status.md)

## Predecessor and deferred scope

Phase 1.3 already identifies Local Commit / Deferred Sync as a Phase 2 handoff.
This Phase concretizes its bounded transfer-runtime portion. AiService/AiProvider
and other on-device-AI follow-ups remain separate planned work; this Phase neither
accepts nor silently deletes them. Inspect the actual public workflow handoff at
entry without rewriting historical Phase status. Core closure requires bounded
public-API/fixture and adapter evidence, not TFAF Phase 3 or app Phase 6.1 closure;
TFAF can therefore consume the accepted handoff without a circular dependency.
