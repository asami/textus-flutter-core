# Phase 1 - Flutter Client Foundation / Capture Runtime

status=planned
planned_at=2026-09-15
consumer=KnowledgeHubProject/nict-editing-studio-app Phase 1

## Purpose

Build the minimum reusable Flutter client foundation / Capture Runtime required by the KnowledgeHub Mobile Knowledge Formation vertical slice while keeping the package usable beyond mobile-only applications.

Phase 1 begins with a reusable Flutter package setup. Details are recorded in `docs/journal/2026/09/2026-09-15-project-initial-setup.md`.

## Work Stack

| ID | Stage | Outcome | Status |
| --- | --- | --- | --- |
| TFC-00 | Project initial setup | Reusable Flutter package scaffold builds/analyzes/tests, exposes a public library entry point, and can be imported by NICT Editing Studio App. | planned |
| TFC-01 | Foundation bootstrap | Public/internal package boundaries are shaped on top of the verified package scaffold. | planned |
| TFC-02 | Capture model | CaptureSession, CaptureItem, item type, lifecycle, metadata, and provenance contracts are fixed. | planned |
| TFC-03 | Capture Profile | External applications can declare item types, validation, workflow/presentation hints without core modification. | planned |
| TFC-04 | Device capture | Camera/image acquisition and text note input work through a consumer on iPhone and Android. | planned |
| TFC-05 | Review/correction | Reusable capture review, correction, removal, and reorder behavior is available. | planned |
| TFC-06 | Repository boundary | UI/application service uses local/remote abstractions rather than direct HTTP coupling. | planned |
| TFC-07 | Submit/sync baseline | CaptureSession can be submitted and exposes success/failure/sync state through application-provided integration. | planned |
| TFC-08 | External app acceptance | NICT Editing Studio BookCaptureProfile consumes the runtime end-to-end on iPhone and Android. | planned |
| TFC-09 | Phase 2 handoff | Local Commit / Deferred Sync and AI extension points are documented without premature implementation. | planned |

## TFC-00 acceptance

- repository is a reusable Flutter package, not an application scaffold
- Dart package name follows `textus_flutter_core`
- public library entry point exists
- `flutter analyze` passes
- `flutter test` passes
- `nict-editing-studio-app` can import the package
- README documents dependency/analyze/test/local-development setup
- no KnowledgeHub / Book-specific dependency is introduced

## Acceptance

- `nict-editing-studio-app` can consume Textus Flutter Core as a dependency.
- Textus Flutter Core contains no Book-specific types such as Cover or Colophon in core.
- BookCaptureProfile can declare those types externally.
- CaptureSession works through the consumer on iPhone and Android.
- image and text items can be reviewed and corrected.
- submit crosses an abstract remote repository/API boundary.
- failure/sync state is visible.
- runtime architecture permits Local Commit / Deferred Sync in Phase 2.

## Non-Goals

- Book-specific Editing Studio UX.
- direct dependency on `nict-editing-studio` or `nict-knowledgehub` domain semantics.
- server-side Semantic Grounding / Knowledge Formation.
- complete offline-first behavior.
- production background synchronization.
- sophisticated on-device AI.
- Asset / Field Capture implementation.

## Planning references

- `docs/journal/2026/09/2026-09-15-project-initial-setup.md`
- `docs/notes/mobile-capture-runtime-provisional-specification.md`
- `docs/journal/2026/09/2026-09-15-textus-mobile-editing-studio-boundary.md`
