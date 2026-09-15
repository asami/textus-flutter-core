# Phase 1.1 - Flutter Device Capture / Consumer Vertical Slice

status=planned
depends_on=docs/phase/phase-1.md
split_from=PHASE-1
consumer=KnowledgeHubProject/nict-editing-studio-app Phase 1

## Purpose

Close the reusable device-to-consumer capture vertical slice against Phase 1's
released public package, capture-model, CaptureProfile, and repository
contracts. This Phase owns the remaining runtime behavior and the documented
Phase 2 handoff; it does not reopen the predecessor's public contracts.

Split from Phase 1. This is the final member of the `PHASE-1 -> PHASE-1.1`
serial delivery sequence and the lower-cost bounded integration child.

## Required Release Handoff

Phase 1.1 has one incoming semantic handoff, recorded on this receiving Phase:

- `from_child`: `PHASE-1`
- `to_child`: `PHASE-1.1`
- `kind`: `release`
- `input`: Phase 1's accepted public package, CaptureSession/CaptureItem,
  CaptureProfile, and repository-boundary contract
- `action_or_decision`: close and release Phase 1 before Phase 1.1 entry
- `output`: immutable Phase 1 release commit and documented public runtime
  contract
- `owner`: `PHASE-1`
- `invalidation_reason`: a required change to exported models, lifecycle,
  profile extension semantics, or repository abstractions returns to the
  predecessor public-contract boundary

Any source mutation in `nict-editing-studio-app` requires that repository to
be explicitly added to the Phase execution scope. This planning document does
not grant mutation authority outside this repository.

## Work Stack

| ID | Stage | Outcome | Status |
| --- | --- | --- | --- |
| TFC-04 | Device capture | Camera/image acquisition and text-note input work through a consumer on iPhone and Android. | planned |
| TFC-05 | Review/correction | Reusable capture review, correction, removal, and reorder behavior is available. | planned |
| TFC-07 | Submit/sync baseline | CaptureSession can be submitted and exposes success/failure/sync state through application-provided integration. | planned |
| TFC-08 | External app acceptance | NICT Editing Studio BookCaptureProfile consumes the runtime end-to-end on iPhone and Android. | planned |
| TFC-09 | Phase 2 handoff | Local Commit / Deferred Sync and AI extension points are documented without premature implementation. | planned |

## Acceptance

- image and text items can be captured, reviewed, corrected, removed, and
  reordered through the reusable runtime.
- submit crosses the Phase 1 abstract repository/API boundary and exposes
  success, failure, and sync state.
- the external application defines BookCaptureProfile semantics without
  introducing Book-specific core types.
- the end-to-end consumer path is exercised on iPhone and Android within the
  explicitly admitted consumer scope.
- Local Commit / Deferred Sync and AI extension points are documented without
  prematurely implementing them.

## Phase Plan Gate

Phase Plan Gate: PROCEED

- target: calibrated expected duration centered on 6h; allowed ceiling 8h
- estimate_calibration: no comparable completed Phase is recorded; the split
  uses the original ten planned stages and their stated device/consumer
  acceptance obligations
- planning_demand: bounded-settled
- recommended_parent_profile: gpt-5.6-terra / high
- profile_cost_role: lower-cost execution
- expensive_reasoning_kernel: none; this Phase consumes Phase 1's frozen
  public runtime-contract handoff
- frozen_profile_transition_handoff: Phase 1 immutable release commit and
  documented public package/model/profile/repository contract
- parent_reasoning_mode_policy: standard
- estimated_at_recommended_profile: 420 minutes, uncertainty range 360–540
  minutes; above the 6h target but within the 8h ceiling
- incoming_semantic_handoffs: the complete Phase 1 release handoff recorded
  in `Required Release Handoff`
- merge_attempts_for_every_sub_4h_child: none; this Phase is not a short child
- rebalance_attempts_for_every_sub_5h_child: none; this Phase is estimated at
  7h
- adjacent_merge_structural_rejection_evidence: merging with Phase 1 would be
  780 minutes and exceed the 480-minute ceiling; profile cost was not used as
  the rejection reason
- profile_cost_only_rejection_forbidden: true
- short_child_basis: none
- overhead_tradeoff: the preceding contract-release overhead is retained so
  bounded device/consumer execution can proceed against a stable API; the
  benefit exceeds the added Phase review, closure, and commit overhead
- agent_reasoning_mode_policy: default standard; consider pro only at an
  eligible agent launch when the active interface supports it and frozen
  quality-first evidence justifies it
- runtime_suitability: re-evaluate in the Phase execution task
- source: applied split from Phase 1

## Flutter Validation Boundary

This Flutter package has no SBT repository-full suite, so no aggregate SBT
validation policy applies. Phase 1.1 independently requires `flutter analyze`,
`flutter test`, and its focused behavior/consumer acceptance evidence. Its
iPhone/Android consumer smoke requires `nict-editing-studio-app` to be in the
explicitly admitted execution scope. Focused validation, independent review,
Step acceptance, closure ledger, and release commit remain required for both
Phases.

## Non-Goals

- Reopening Phase 1 public package, model, profile, or repository contracts.
- Book-specific domain types in Textus Flutter Core.
- Complete offline-first queueing, production background synchronization, or
  complex conflict resolution.
- Advanced native/on-device AI or voice-recognition workflows.
- Server-side Semantic Grounding or Knowledge Formation.

## Planning references

- `docs/phase/phase-1.md`
- `docs/notes/mobile-capture-runtime-provisional-specification.md`
- `docs/journal/2026/09/2026-09-15-textus-mobile-editing-studio-boundary.md`
