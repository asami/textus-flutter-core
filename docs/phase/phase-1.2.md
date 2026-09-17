# Phase 1.2 - Flutter Capture Providers / Reference Application Vertical Slice

status=planned
depends_on=docs/phase/phase-1.1.md
split_from=PHASE-1.1
external_consumer=KnowledgeHubProject/nict-editing-studio-app Phase 1

## Purpose

Consume the Phase 1.1 device-runtime foundation to deliver the first concrete,
domain-independent capture vertical slice through the Textus Flutter Core
Reference Application.

This Phase implements capability-sized camera and audio providers, text-note
input, and the Reference Application screens needed to exercise them on
admitted devices. It does not add review/submit workflow behavior or mutate
the external consumer application.

## Required Release Handoff

- `from_child`: `PHASE-1.1`
- `to_child`: `PHASE-1.2`
- `kind`: `release`
- `input`: accepted Service / Provider architecture, capability/availability
  contract, and Reference Application skeleton
- `action_or_decision`: close and release Phase 1.1 before Phase 1.2 entry
- `output`: immutable Phase 1.1 release commit and documented device-runtime
  foundation
- `owner`: `PHASE-1.1`
- `invalidation_reason`: a required change to Service/Provider ownership,
  capability/availability semantics, or the Reference Application boundary
  returns to Phase 1.1

## Work Stack

| ID | Stage | Outcome | Status |
| --- | --- | --- | --- |
| TFC-05 | Capture providers | Camera/image and audio capabilities plus text-note input work through capability-sized Providers on admitted devices. | planned |
| TFC-06 | Reference application vertical slice | The Reference Application captures image, audio, and text items and presents device/provider diagnostics independently of Editing Studio. | planned |

## Acceptance

- Camera, audio, and text are implemented through the Phase 1.1 Service /
  Provider boundary, without a monolithic DeviceProvider.
- The Reference Application can create image, audio, and text capture items
  and report each admitted capability's availability.
- Focused tests cover provider selection, unavailable-capability behavior, and
  public runtime integration.
- The Reference Application vertical slice has iPhone and Android smoke
  evidence for the capabilities explicitly admitted to this Phase.
- No Book, Editing Studio, or other consumer-domain types enter Textus Flutter
  Core.

## Phase Plan Gate

Phase Plan Gate: PROCEED

- target: calibrated expected duration centered on 6h; allowed ceiling 8h
- estimate_calibration: concrete provider work and a single Reference
  Application capture slice are bounded by the frozen Phase 1.1 SPI
- planning_demand: bounded-settled
- recommended_parent_profile: gpt-5.6-terra / high
- profile_cost_role: implementation integration
- expensive_reasoning_kernel: native/provider lifecycle integration while
  preserving the released Service / Provider boundary
- frozen_profile_transition_handoff: Phase 1.1 device-runtime foundation
- parent_reasoning_mode_policy: standard
- estimated_at_recommended_profile: 360 minutes, uncertainty range 300–420
  minutes; at the 6h target and within the 8h ceiling
- incoming_semantic_handoffs: Phase 1.1 release handoff recorded above
- merge_attempts_for_every_sub_4h_child: none; this Phase is estimated at 6h
- rebalance_attempts_for_every_sub_5h_child: none; this Phase is not below 5h
- adjacent_merge_structural_rejection_evidence: merging with Phase 1.3 would
  combine native capture integration with workflow/external-consumer
  acceptance for an estimated 780-minute unit, exceeding the 480-minute ceiling
- profile_cost_only_rejection_forbidden: true
- short_child_basis: none
- overhead_tradeoff: a release handoff lets workflow and consumer acceptance
  proceed against a tested capture surface
- agent_reasoning_mode_policy: default standard; consider pro only at an
  eligible agent launch when frozen quality-first evidence justifies it
- runtime_suitability: re-evaluate in the Phase execution task
- source: 2026-09-17 successor re-split and re-estimation

## Flutter Validation Boundary

This Flutter package has no SBT repository-full suite. Phase 1.2 requires
`flutter analyze`, `flutter test`, focused provider/reference-application
behavior tests, and iPhone/Android smoke evidence for admitted capabilities.

## Non-Goals

- Reopening Phase 1 public contracts or Phase 1.1 Service / Provider decisions.
- Review, correction, removal, reorder, submit, or sync-state workflow.
- Editing Studio source mutation or BookCaptureProfile acceptance.
- Concrete on-device AI workflows, offline queueing, or background sync.

## Planning References

- `docs/phase/phase-1.1.md`
- `docs/phase/phase-1.3.md`
- `docs/journal/2026/09/2026-09-17-device-service-provider-reference-application.md`
