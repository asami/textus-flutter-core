# Core background transfer status design note

Recorded: 2026-10-10. Planning note; public types and implementation are not frozen.

## Configuration amendment — 2026-10-24

For the planned TKL route, [TKL-managed Material delivery](tkl-managed-material-delivery.md)
supersedes any assumption below that mobile consumers provision physical
destinations. TKL supplies configuration and registration; Core executes transfer
and recovery. Storage upload, TKL registration and Studio acknowledgement remain
distinct. Existing delivery history is unchanged.

## Selected responsibility

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

## Interface decisions before implementation

Reuse existing public contracts first. Settle work-item/operation association,
durable state observation, optional progress and per-file outcomes, and action
availability with the counterpart owner. Stable consumer identity links the two
operations; do not introduce a content hash to identify work. Successful results
must correspond to the same committed content; changed content or inaccessible
references use the existing queue/material contract rather than silent reuse.

For unknown acknowledgement after interruption, distinguish uncertain completion
from definitive failure. Select supported reconciliation/retry behavior with the
transport owner; do not manufacture idempotency or implement a UI-only resend rule.
The app decides Book eligibility and presentation terminology. The two runtime
operations remain separately observable regardless of their display labels.

The common screen's first consumer displays:

```text
Book Material
  TKL material upload: complete (photos/audio)
  Editing Studio data submission: failed (connection unavailable)
  Retry submission
```

This illustrates state separation, not an actual execution result. The app's
existing plan spells material storage KTL/Google Drive; the user's TKL label does
not select a new backend. Actual endpoint, access and acknowledgement contracts
must be taken from the selected configuration and adapter handoff.

See the [development plan](../phase/phase-2.md),
[consumer note](../../../../Project2026/nict-editing-studio-app/docs/notes/background-material-transfer-status.md) and
[decision journal](../journal/2026/10/2026-10-10-background-material-transfer-status.md).

Execution owner: repository Phase 2; its checklist and release own upstream
acceptance. App Phase 6.1 remains the consumer/integration owner.
