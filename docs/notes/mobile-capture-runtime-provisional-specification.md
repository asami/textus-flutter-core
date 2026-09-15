# Textus Mobile Capture Runtime — Provisional Specification

status=provisional
recorded_at=2026-09-15
consumer=KnowledgeHub Phase 1 / NICT Editing Studio App

## Purpose

Textus MobileはFlutterで実装する、domain-independentなMobile Capture Runtime / reusable libraryである。

Reference Application固有のBook / Asset / Agriculture semanticsを持たず、スマートフォンで現実世界のInformationを取得・確認・訂正・保存・同期する共通機構を提供する。

```text
Domain Flutter App
      |
      v
Textus Mobile
  Capture / Local / Sync / AI Assistance
      |
      v
Server-side Application / KnowledgeHub
```

## Core responsibilities

- CaptureSession / CaptureItem mobile lifecycle
- Camera / image acquisition boundary
- text / note input
- media metadata
- local temporary storage
- user review / correction primitives
- Capture Profile extension mechanism
- local / remote repository boundary
- synchronization boundary
- connectivity / sync state
- AI-assisted extraction / classification extension point
- server API client abstraction

## Capture Profile

Application-specific capture semantics are injected through a profile rather than hard-coded into Textus Mobile.

```text
CaptureProfile
  id
  itemTypes
  workflow hints
  validation
  extraction hints
  correction policy
  presentation hints
  sync policy
```

Initial consumer:

```text
NICT Editing Studio App
  BookCaptureProfile
    Cover
    Colophon
    RelevantPage
    Excerpt / Note
```

Future consumers may provide AssetCaptureProfile or FieldCaptureProfile without modifying the core runtime.

## Architecture boundary

```text
Flutter UI / Domain App
        |
Textus Mobile Application Service
        |
Local Repository ---- Sync Boundary ---- Remote Repository / API Client
```

UI must not be directly coupled to remote server operations so that Local Commit / Deferred Sync can be strengthened later.

## Phase 1 minimum

- Flutter package / reusable module baseline
- iPhone / Android execution support
- CaptureSession
- CaptureItem
- camera image capture
- image preview
- text note input
- Capture Profile contract
- review / correction primitives
- submit / sync request
- result / error state
- server-client abstraction

## Deferred from Phase 1

- complete offline-first queue
- robust background Deferred Sync
- advanced native/on-device AI
- full voice recognition workflow
- multiple production Capture Profiles
- complex conflict resolution

## Boundary with CNCF / KnowledgeHub

CaptureSession / CaptureItem are initially owned by Textus Mobile as information-acquisition interaction/runtime concepts.

Server-side CNCF owns canonical Information / Knowledge primitives.
KnowledgeHub owns Semantic Context / Grounding / Knowledge Formation.

Textus Mobile sends capture provenance and acquired content; it does not perform canonical server-side Knowledge Formation.

## Acceptance

- A Flutter application can depend on Textus Mobile without importing Editing Studio semantics.
- A BookCaptureProfile can define its capture item types outside Textus Mobile core.
- iPhone and Android can create and review a CaptureSession.
- Capture content can be submitted through an abstract remote boundary.
- error / sync state is visible to the consumer application.
- future Local Commit / Deferred Sync can be added without rewriting consumer UI flow.
