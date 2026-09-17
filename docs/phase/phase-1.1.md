# Phase 1.1 - Flutter Device Runtime Foundation / Reference Application

status=planned
depends_on=docs/phase/phase-1.md
split_from=PHASE-1
external_consumer=KnowledgeHubProject/nict-editing-studio-app Phase 1

## Purpose

Establish the reusable Flutter device-runtime foundation against Phase 1's released public package, capture model, CaptureProfile, and repository contracts.

Phase 1.1 defines the common Service / Provider architecture for device-dependent capabilities, proves it with concrete capture capabilities, and builds a dedicated Textus Flutter Core Reference Application for executable documentation and iPhone/Android device acceptance.

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

Phase 1.1 owns a dedicated Textus Flutter Core Reference Application. It is an executable example and device acceptance harness, not a domain application and not a disposable sample.

It demonstrates and validates:

- camera/image capture;
- audio recording;
- text-note input;
- review, correction, removal, and reorder;
- submit through a stub/application-provided repository integration;
- device capability and provider availability diagnostics.

The Reference Application is also the controlled integration surface for future device capabilities and on-device AI experiments. Editing Studio-specific BookCaptureProfile and domain semantics stay in `nict-editing-studio-app`.

## Work Stack

| ID | Stage | Outcome | Status |
| --- | --- | --- | --- |
| TFC-04 | Device runtime foundation | Service / Provider architecture, capability/availability boundary, and reference-app skeleton are established. | planned |
| TFC-05 | Capture providers | Camera and audio device capabilities plus text-note input work through the Reference Application on admitted devices. | planned |
| TFC-06 | Reference application | Executable example supports capture and device/provider diagnostics independently of Editing Studio. | planned |
| TFC-07 | Review / submit | CaptureSession review, correction, removal, reorder, submit, and success/failure/sync state work through the Reference Application. | planned |
| TFC-08 | Device and external acceptance | Reference Application is exercised on iPhone/Android; NICT Editing Studio BookCaptureProfile consumes the runtime without core domain leakage. | planned |
| TFC-09 | AI boundary / Phase 2 handoff | AiService / AiProvider extension boundary plus Local Commit / Deferred Sync and concrete on-device-AI follow-up are documented. | planned |

## Acceptance

- Service / Provider is the documented architecture for device-dependent capabilities.
- Provider interfaces are capability-sized and support runtime capability/availability discovery where required.
- Camera and audio prove the architecture through the Reference Application.
- image, audio, and text items can be captured and then reviewed, corrected, removed, and reordered through the reusable runtime.
- submit crosses the Phase 1 abstract repository/API boundary and exposes success, failure, and sync state.
- the Reference Application functions independently of Editing Studio and provides device/provider diagnostics.
- the Reference Application path is exercised on iPhone and Android within explicitly admitted execution scope.
- the external application defines BookCaptureProfile semantics without introducing Book-specific core types.
- `AiService -> AiProvider` is defined consistently with the general Service / Provider architecture without requiring advanced AI workflows in this Phase.
- Local Commit / Deferred Sync and concrete on-device AI work are handed off to a later Phase.

## Phase Plan Gate

Phase Plan Gate: REPLAN-BEFORE-EXECUTION

The scope is intentionally broader than the previous Phase 1.1 plan because it now establishes the device-runtime architecture and a durable Reference Application in addition to the capture vertical slice. Before execution, split/re-estimate the work into bounded children that retain the project's approximately 6h target and 8h ceiling per executable Phase/subphase. Do not preserve the former 420-minute estimate as evidence for this expanded scope.

The natural split boundaries are TFC-04 foundation, TFC-05/TFC-06 provider/reference-app vertical slice, and TFC-07/TFC-08 acceptance/integration. TFC-09 remains the architecture/handoff closure. Exact grouping should be calibrated at execution planning time.

## Flutter Validation Boundary

This Flutter package has no SBT repository-full suite, so no aggregate SBT validation policy applies. Phase 1.1 requires `flutter analyze`, `flutter test`, focused behavior tests, Reference Application acceptance evidence, and iPhone/Android smoke evidence for admitted capabilities.

`nict-editing-studio-app` source mutation and its consumer smoke require that repository to be in the explicitly admitted execution scope. Focused validation, independent review, Step acceptance, closure ledger, and release commit remain required.

## Non-Goals

- Reopening Phase 1 public package, model, profile, or repository contracts.
- Book-specific or Editing Studio-specific domain types in Textus Flutter Core.
- A monolithic DeviceProvider spanning unrelated capabilities.
- Complete offline-first queueing, production background synchronization, or complex conflict resolution.
- Advanced native/on-device AI capture workflows such as automatic knowledge formation or domain-specific metadata/facet extraction.
- Server-side Semantic Grounding or Knowledge Formation.

## Planning references

- `docs/phase/phase-1.md`
- `docs/notes/mobile-capture-runtime-provisional-specification.md`
- `docs/journal/2026/09/2026-09-15-textus-mobile-editing-studio-boundary.md`
- `docs/journal/2026/09/2026-09-17-device-service-provider-reference-application.md`
