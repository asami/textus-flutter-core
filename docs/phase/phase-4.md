# Phase 4 — Optional Firebase client providers

status=planned
planned_at=2026-11-08
execution_started=false
owner=textus-flutter-core

Progress: [Phase 4 checklist](phase-4-checklist.md). Scheduling is deferred. The first item on selection is TFC4-01.

## Goal

Supply optional client adapters for diagnostics, push, app attestation and presentation settings behind Core's Service / Provider interfaces. See the [Core provider boundary](../design/firebase-provider-boundary.md).

## Delivery groups

| Subphase | Step | Observable outcome |
| --- | --- | --- |
| 4.1 Diagnostics | TFC4-01 | Deliver an opt-in Crashlytics adapter through the application composition. |
| 4.2 Push registration | TFC4-02 | Bind installation and token changes to an authenticated recipient. |
| 4.3 App attestation | TFC4-03 | Supply app evidence only to the selected protected service. |
| 4.4 Presentation settings and handoff | TFC4-04 | Expose typed UI settings with local defaults for a selected consumer. |

## Dependencies and completion

Start with diagnostics as a standalone Android route. Pair push with server registration and Framework navigation. Attestation qualifies a separate server endpoint. Use deterministic provider doubles for local behavior and an isolated deployment for real SDK acceptance. Coordinate the relevant capabilities with [CNCF Phase 121](https://github.com/asami/goldenport-cncf/blob/main/docs/phase/phase-121.md) and [textus-flutter-application-framework Phase 5](https://github.com/asami/textus-flutter-application-framework/blob/main/docs/phase/phase-5.md).

The checklist records each Step's acceptance criteria and the Phase closure decision.
