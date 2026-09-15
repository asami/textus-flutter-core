# Phase 1 - Flutter Client Foundation / Public Capture Contracts

status=planned
planned_at=2026-09-15
consumer=KnowledgeHubProject/nict-editing-studio-app Phase 1

## Purpose

Build the first independently closable unit of the reusable Flutter client
foundation: the package baseline and the public contracts that a later device
capture vertical slice consumes. This Phase owns package shape, capture-model,
capture-profile, and repository-boundary decisions; it does not implement the
device-to-consumer flow.

The project setup baseline is retained in
`docs/journal/2026/09/2026-09-15-project-initial-setup.md`.

## Work Stack

| ID | Stage | Outcome | Status |
| --- | --- | --- | --- |
| TFC-00 | Project initial setup | Reusable Flutter package scaffold builds/analyzes/tests, exposes a public library entry point, and establishes consumer import syntax without adding consumer-domain dependencies. | planned |
| TFC-01 | Foundation bootstrap | Public/internal package boundaries are shaped on top of the verified package scaffold. | planned |
| TFC-02 | Capture model | CaptureSession, CaptureItem, item type, lifecycle, metadata, and provenance contracts are fixed. | planned |
| TFC-03 | Capture Profile | External applications can declare item types, validation, workflow/presentation hints without core modification. | planned |
| TFC-06 | Repository boundary | The public UI/application-service boundary uses local/remote abstractions rather than direct HTTP coupling. | planned |

## TFC-00 acceptance

- repository is a reusable Flutter package, not an application scaffold
- Dart package name follows `textus_flutter_core`
- public library entry point exists
- `flutter analyze` passes
- `flutter test` passes
- the package exposes a domain-independent import surface for the later
  consumer acceptance in Phase 1.1
- no KnowledgeHub / Book-specific dependency is introduced

## Acceptance

- Textus Flutter Core has a public package entry point and no Book-specific
  types such as Cover or Colophon in core.
- CaptureSession, CaptureItem, CaptureProfile, and repository contracts are
  fixed at the public/runtime boundary.
- A downstream consumer can define BookCaptureProfile item types externally.
- The contract gives Phase 1.1 a stable basis for device capture, review,
  submission, and external-app acceptance.

## Flutter Validation Boundary

Phase 1 is a Flutter package Phase. Its execution requires `flutter analyze`,
`flutter test`, and a public-library import smoke appropriate to its settled
package boundary. There is no SBT repository-full suite or aggregate SBT
validation ownership in this repository.

## Phase Plan Gate

Phase Plan Gate: PROCEED

- target: calibrated expected duration centered on 6h; allowed ceiling 8h
- estimate_calibration: no comparable completed Phase is recorded; the split
  uses the original ten planned stages and their stated device/consumer
  acceptance obligations
- planning_demand: protected-decision
- recommended_parent_profile: gpt-5.6-terra / xhigh
- profile_cost_role: expensive reasoning kernel
- expensive_reasoning_kernel: durable public package, capture-model,
  CaptureProfile, and repository-boundary decisions
- frozen_profile_transition_handoff: none; this Phase produces the public
  runtime-contract release consumed by Phase 1.1
- parent_reasoning_mode_policy: standard
- estimated_at_recommended_profile: 360 minutes, uncertainty range 300–420
  minutes; at the 6h target and within the 8h ceiling
- incoming_semantic_handoffs: []
- merge_attempts_for_every_sub_4h_child: none; this Phase is not a short child
- rebalance_attempts_for_every_sub_5h_child: none; this Phase is estimated at
  6h
- adjacent_merge_structural_rejection_evidence: merging with Phase 1.1 would
  be 780 minutes and exceed the 480-minute ceiling; profile cost was not used
  as the rejection reason
- profile_cost_only_rejection_forbidden: true
- short_child_basis: none
- overhead_tradeoff: one extra release handoff, review, closure ledger, and
  commit establishes a durable public contract that allows the device/consumer
  slice to use a lower-cost suitable planning profile
- agent_reasoning_mode_policy: default standard; consider pro only at an
  eligible agent launch when the active interface supports it and frozen
  quality-first evidence justifies it
- runtime_suitability: re-evaluate in the Phase execution task
- source: applied split from Phase 1

## Split Record — 2026-09-16

The pre-split typed Phase Entry Gate returned `SPLIT_REQUIRED` before goal
creation (`request_sha256=fa4603d2efa5ac7376a2604067322fd44a7ce830f0daf529a52b28b812908e26`).
It recorded a 780-minute expected duration, a 1080-minute conservative upper
bound, and the ordered reasons `time-bound` and `reasoning-cost-isolation`.

The applied sequence is `PHASE-1 -> PHASE-1.1`. It uses Flutter-native
per-Phase validation: `flutter analyze`, `flutter test`, and the acceptance
smoke relevant to each Phase. The SBT-only aggregate final-validation contract
is not applicable because this repository has no `build.sbt`.

Phase 1 retains TFC-00, TFC-01, TFC-02, TFC-03, and TFC-06. Phase 1.1 owns
TFC-04, TFC-05, TFC-07, TFC-08, and TFC-09 exclusively. The receiving Phase
consumes this Phase's release handoff: the accepted public package/model/
profile/repository contract and its immutable release commit. Any required
change to those exports, lifecycle, profile, or repository semantics
invalidates that handoff and returns to the owning public-contract boundary.

The split adds one Phase handoff, independent review, closure ledger, and
commit. It avoids an oversized combined delivery unit and isolates the
protected public-contract decisions from the bounded device/consumer
implementation work. No prior completed Step, validation, decision, approval,
or commit exists to move; the original identity, planned date, and referenced
historical records remain here.

## Successor Scope

See [Phase 1.1](phase-1.1.md) for the only owner of device capture, review and
correction, submit/sync behavior, external-app acceptance, and Phase 2
handoff. Phase 1.1 depends on this Phase's release; it does not start merely
because this planning split is present.

## Non-Goals

- Camera/image acquisition and text-note interaction.
- Reusable review, correction, removal, or reorder behavior.
- Submit/sync behavior or external-app acceptance.
- Book-specific Editing Studio UX or domain semantics.
- Direct dependency on `nict-editing-studio` or `nict-knowledgehub` semantics.
- Server-side Semantic Grounding / Knowledge Formation.

## Planning references

- `docs/journal/2026/09/2026-09-15-project-initial-setup.md`
- `docs/notes/mobile-capture-runtime-provisional-specification.md`
- `docs/journal/2026/09/2026-09-15-textus-mobile-editing-studio-boundary.md`
