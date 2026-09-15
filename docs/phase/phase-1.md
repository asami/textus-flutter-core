# Phase 1 - Mobile Capture Runtime Foundation

status=planned
planned_at=2026-09-15
consumer=KnowledgeHubProject/nict-editing-studio-app Phase 1

## Purpose

Build the minimum reusable Flutter Mobile Capture Runtime required by the KnowledgeHub Mobile Knowledge Formation vertical slice.

## Work Stack

| ID | Stage | Outcome | Status |
| --- | --- | --- | --- |
| TMR-01 | Flutter/runtime bootstrap | Reusable Flutter package/module structure builds and is consumable from an external Flutter app. | planned |
| TMR-02 | Capture model | CaptureSession, CaptureItem, item type, lifecycle, metadata, and provenance contracts are fixed. | planned |
| TMR-03 | Capture Profile | External applications can declare item types, validation, workflow/presentation hints without core modification. | planned |
| TMR-04 | Device capture | Camera/image acquisition and text note input work on iPhone and Android. | planned |
| TMR-05 | Review/correction | Reusable capture review, correction, removal, and reorder behavior is available. | planned |
| TMR-06 | Repository boundary | UI/application service uses local/remote abstractions rather than direct HTTP coupling. | planned |
| TMR-07 | Submit/sync baseline | CaptureSession can be submitted and exposes success/failure/sync state. | planned |
| TMR-08 | External app acceptance | NICT Editing Studio BookCaptureProfile consumes the runtime end-to-end on iPhone and Android. | planned |
| TMR-09 | Phase 2 handoff | Local Commit / Deferred Sync and AI extension points are documented without premature implementation. | planned |

## Acceptance

- `nict-editing-studio-app` can consume Textus Mobile as a dependency.
- Textus Mobile contains no Book-specific types such as Cover or Colophon in core.
- BookCaptureProfile can declare those types externally.
- CaptureSession works on iPhone and Android.
- image and text items can be reviewed and corrected.
- submit crosses an abstract remote repository/API boundary.
- failure/sync state is visible.
- runtime architecture permits Local Commit / Deferred Sync in Phase 2.

## Non-Goals

- Book-specific Editing Studio UX.
- server-side Semantic Grounding / Knowledge Formation.
- complete offline-first behavior.
- production background synchronization.
- sophisticated on-device AI.
- Asset / Field Capture implementation.

## Planning references

- `docs/notes/mobile-capture-runtime-provisional-specification.md`
- `docs/journal/2026/09/2026-09-15-textus-mobile-editing-studio-boundary.md`
