# Phase 1.3 - Flutter Capture Workflow / Consumer Acceptance / Phase 2 Handoff

status=planned
depends_on=docs/phase/phase-1.2.md
split_from=PHASE-1.1
external_consumer=KnowledgeHubProject/nict-editing-studio-app Phase 1

## Purpose

Consume the Phase 1.2 capture-provider vertical slice to close the reusable
capture workflow, prove that it is consumable by the first external application,
and document the bounded Phase 2 handoff.

Phase 1.3 owns review/correction and submit/sync behavior in the Reference
Application, iPhone/Android acceptance for the complete admitted slice, and
the `nict-editing-studio-app` BookCaptureProfile consumer acceptance once that
repository is explicitly admitted. It does not reopen prior public contracts
or implement the deferred production sync/AI systems.

## Required Release Handoff

- `from_child`: `PHASE-1.2`
- `to_child`: `PHASE-1.3`
- `kind`: `release`
- `input`: accepted camera/audio/text capture providers and Reference
  Application vertical slice
- `action_or_decision`: close and release Phase 1.2 before Phase 1.3 entry
- `output`: immutable Phase 1.2 release commit and documented capture surface
- `owner`: `PHASE-1.2`
- `invalidation_reason`: a required change to capture-provider behavior,
  Reference Application capture flow, or provider diagnostics returns to
  Phase 1.2

## Work Stack

| ID | Stage | Outcome | Status |
| --- | --- | --- | --- |
| TFC-07 | Review / submit | CaptureSession review, correction, removal, reorder, submit, and success/failure/sync state work through the Reference Application. | planned |
| TFC-08 | Device and external acceptance | The Reference Application is accepted on iPhone/Android; Editing Studio consumes the runtime through BookCaptureProfile without core domain leakage. | planned |
| TFC-09 | AI boundary / Phase 2 handoff | AiService / AiProvider follow-up, Local Commit / Deferred Sync, and concrete on-device-AI work are documented for the next Phase. | planned |

## Acceptance

- Image, audio, and text capture items can be reviewed, corrected, removed,
  and reordered through the reusable runtime.
- Submit crosses Phase 1's abstract repository/API boundary and exposes
  success, failure, and sync state to the Reference Application.
- The Reference Application full slice has iPhone and Android acceptance
  evidence within the explicitly admitted execution scope.
- `nict-editing-studio-app` defines BookCaptureProfile semantics externally;
  any source mutation or consumer smoke requires that repository to be
  explicitly admitted before work begins.
- `AiService -> AiProvider`, Local Commit / Deferred Sync, and concrete
  on-device AI are documented as next-Phase extension points rather than
  prematurely implemented.

## Phase Plan Gate

Phase Plan Gate: PROCEED

- target: calibrated expected duration centered on 6h; allowed ceiling 8h
- estimate_calibration: workflow and consumer acceptance now consume a tested
  capture surface rather than establishing device architecture or providers
- planning_demand: bounded-settled
- recommended_parent_profile: gpt-5.6-terra / high
- profile_cost_role: integration and acceptance closure
- expensive_reasoning_kernel: preserve consumer-domain separation while
  reconciling runtime workflow state with external-app acceptance evidence
- frozen_profile_transition_handoff: Phase 1.2 capture-provider and Reference
  Application vertical-slice release
- parent_reasoning_mode_policy: standard
- estimated_at_recommended_profile: 420 minutes, uncertainty range 360–480
  minutes; above the 6h target but within the 8h ceiling
- incoming_semantic_handoffs: Phase 1.2 release handoff recorded above
- merge_attempts_for_every_sub_4h_child: none; this Phase is estimated at 7h
- rebalance_attempts_for_every_sub_5h_child: none; this Phase is not below 5h
- adjacent_merge_structural_rejection_evidence: merging with Phase 1.2 would
  combine provider implementation, workflow state, and external consumer
  acceptance for an estimated 780-minute unit, exceeding the 480-minute ceiling
- profile_cost_only_rejection_forbidden: true
- short_child_basis: none
- overhead_tradeoff: the final successor handoff narrows the Phase 2 boundary
  to explicit deferred-sync and on-device-AI decisions
- agent_reasoning_mode_policy: default standard; consider pro only at an
  eligible agent launch when frozen quality-first evidence justifies it
- runtime_suitability: re-evaluate in the Phase execution task
- source: 2026-09-17 successor re-split and re-estimation

## Flutter Validation Boundary

This Flutter package has no SBT repository-full suite. Phase 1.3 requires
`flutter analyze`, `flutter test`, focused workflow tests, Reference
Application iPhone/Android acceptance evidence, and explicitly admitted
external-consumer smoke evidence where applicable.

## Non-Goals

- Reopening Phase 1 contracts, Phase 1.1 architecture, or Phase 1.2 provider behavior.
- Book-specific types in Textus Flutter Core.
- Complete offline-first queueing, production background synchronization, or
  complex conflict resolution.
- Concrete advanced/on-device AI capture workflows or server-side Knowledge
  Formation.

## Planning References

- `docs/phase/phase-1.2.md`
- `docs/notes/mobile-capture-runtime-provisional-specification.md`
- `docs/journal/2026/09/2026-09-17-device-service-provider-reference-application.md`
