# Phase 1.1 - Flutter Device Runtime Foundation

status=planned
depends_on=docs/phase/phase-1.md
split_from=PHASE-1
external_consumer=KnowledgeHubProject/nict-editing-studio-app Phase 1

## Purpose

Establish the reusable Flutter device-runtime foundation against Phase 1's released public package, capture model, CaptureProfile, and repository contracts.

Phase 1.1 freezes the common Service / Provider architecture for device-dependent capabilities and establishes the dedicated Textus Flutter Core Reference Application skeleton. Phase 1.2 consumes that release to implement the camera/audio/text capture vertical slice; Phase 1.3 then owns workflow, external-consumer acceptance, and the Phase 2 handoff.

It does not reopen the predecessor's public capture contracts. `nict-editing-studio-app` remains the first practical external consumer rather than serving as the Textus Flutter Core reference application.

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

Any source mutation in `nict-editing-studio-app` requires that repository to be explicitly added to the Phase execution scope. This planning document does not grant mutation authority outside this repository.

## Device Service / Provider Architecture

Device-dependent functions use a common two-level boundary:

- **Service**: stable Textus-facing API and runtime semantics.
- **Provider**: replaceable SPI for platform, device, Flutter-plugin, or external-provider differences.

Provider interfaces remain capability-sized rather than being combined into a monolithic DeviceProvider.

Initial architecture:

```text
Capture Runtime / Application
        |
        +-- CameraService -- CameraProvider
        +-- AudioService  -- AudioProvider
        +-- AiService     -- AiProvider
```

Providers expose capability/availability information where needed. Services may use that information to choose an implementation without exposing platform details to consumers.

AI follows the same architecture as other device capabilities. `AiService` is the stable AI service boundary; `AiProvider` represents concrete routes such as Android on-device AI, future iOS on-device AI, cloud AI, or test implementations.

## Reference Application

Phase 1.1 owns the Reference Application's package/app boundary, startup skeleton, and provider-capability diagnostics surface. It is an executable example and device acceptance harness, not a domain application and not a disposable sample.

Phase 1.2 adds camera/image capture, audio recording, text-note input, and live device-capability diagnostics to that skeleton. Phase 1.3 adds review, correction, removal, reorder, submit, and consumer acceptance. Editing Studio-specific BookCaptureProfile and domain semantics stay in `nict-editing-studio-app`.

## Work Stack

| ID | Stage | Outcome | Status |
| --- | --- | --- | --- |
| TFC-04 | Device runtime foundation | Service / Provider architecture, capability/availability boundary, and Reference Application skeleton are established. | planned |

## Acceptance

- Service / Provider is the documented architecture for device-dependent capabilities.
- Provider interfaces are capability-sized and support runtime capability/availability discovery where required.
- `CameraService`, `AudioService`, and `AiService` have distinct Provider boundaries without a monolithic DeviceProvider.
- the Reference Application skeleton functions independently of Editing Studio and exposes provider-capability diagnostics.
- the Phase 1.1 release is a stable handoff for Phase 1.2 capture-provider implementation.

## Phase Plan Gate

Phase Plan Gate: PROCEED

- target: calibrated expected duration centered on 6h; allowed ceiling 8h
- estimate_calibration: the former combined Phase 1.1 plan was split at its natural implementation and consumer-acceptance boundaries
- planning_demand: bounded-settled
- recommended_parent_profile: gpt-5.6-terra / high
- profile_cost_role: architecture foundation
- expensive_reasoning_kernel: Service / Provider abstraction, capability/availability semantics, and Reference Application ownership boundary
- frozen_profile_transition_handoff: Phase 1 immutable public package/model/profile/repository release
- parent_reasoning_mode_policy: standard
- estimated_at_recommended_profile: 300 minutes, uncertainty range 240–360 minutes; below the 6h target but within the 8h ceiling
- incoming_semantic_handoffs: Phase 1 release handoff recorded above
- merge_attempts_for_every_sub_4h_child: none; this Phase is estimated at 5h
- rebalance_attempts_for_every_sub_5h_child: none; this Phase is not below 5h
- adjacent_merge_structural_rejection_evidence: merging with Phase 1.2 would couple architectural boundary decisions with native/provider implementation and produce an estimated 660-minute unit, exceeding the 480-minute ceiling
- profile_cost_only_rejection_forbidden: true
- short_child_basis: none
- overhead_tradeoff: the Phase 1.1 release freezes the provider SPI before native/plugin work consumes it
- agent_reasoning_mode_policy: default standard; consider pro only at an eligible agent launch when frozen quality-first evidence justifies it
- runtime_suitability: re-evaluate in the Phase execution task
- source: 2026-09-17 successor re-split and re-estimation

## Flutter Validation Boundary

This Flutter package has no SBT repository-full suite, so no aggregate SBT validation policy applies. Phase 1.1 requires `flutter analyze`, `flutter test`, focused architecture tests, and a Reference Application skeleton smoke appropriate to the admitted implementation.

Focused validation, independent review, Step acceptance, closure ledger, and release commit remain required. iPhone/Android capture smoke and `nict-editing-studio-app` consumer acceptance belong to Phases 1.2 and 1.3.

## Non-Goals

- Reopening Phase 1 public package, model, profile, or repository contracts.
- Book-specific or Editing Studio-specific domain types in Textus Flutter Core.
- A monolithic DeviceProvider spanning unrelated capabilities.
- Concrete camera/audio implementations, text capture, review, submit, and device smoke evidence; these belong to later successor Phases.
- Complete offline-first queueing, production background synchronization, or complex conflict resolution.
- Advanced native/on-device AI capture workflows such as automatic knowledge formation or domain-specific metadata/facet extraction.
- Server-side Semantic Grounding or Knowledge Formation.

## Planning references

- `docs/phase/phase-1.md`
- `docs/notes/mobile-capture-runtime-provisional-specification.md`
- `docs/journal/2026/09/2026-09-15-textus-mobile-editing-studio-boundary.md`
- `docs/journal/2026/09/2026-09-17-device-service-provider-reference-application.md`
- `docs/phase/phase-1.2.md`
- `docs/phase/phase-1.3.md`
