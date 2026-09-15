# Textus Mobile / NICT Editing Studio App Boundary

Date: 2026-09-15

Status: Current architectural decision

## Decision

Mobile implementation is split into two projects.

```text
asami/textus-mobile
  reusable Flutter Mobile Runtime / Library

KnowledgeHubProject/nict-editing-studio-app
  Flutter application / Book domain consumer
```

Textus Mobile owns **how to capture information on mobile**.
Editing Studio owns **what to capture and what it means for the Editing Studio use case**.

## Textus Mobile responsibilities

- CaptureSession / CaptureItem runtime
- camera / media boundary
- local storage boundary
- review / correction reusable interaction
- synchronization boundary
- AI-assistance extension point
- Capture Profile mechanism
- API client abstraction

## Editing Studio responsibilities

- BookCaptureProfile
- Cover / Colophon / RelevantPage / Excerpt semantics
- bibliographic confirmation UX
- excerpt / annotation UX
- Editing Studio navigation and presentation
- KnowledgeHub-specific application workflow

## Server boundary

```text
NICT Editing Studio App
        |
        v
Textus Mobile
        |
        v
NICT KnowledgeHub Phase 6
 Knowledge Processing Framework
        |
        v
CNCF Phase 73
 Knowledge Primitives
```

Textus Mobile does not own Semantic Grounding or Knowledge Formation.

## Why two projects

- domain-independent mobile runtime can be reused by other Textus / KnowledgeHub applications
- Editing Studio can evolve its UX without polluting runtime code
- Book Capture becomes the first validation profile rather than the core runtime definition
- later Asset / Field capture can prove domain independence
- Flutter Web/Desktop options remain open for the app because the application repository is not named `*-mobile`

## Phase 1 direction

Phase 1 first establishes a thin vertical path:

```text
BookCaptureProfile
 -> CaptureSession
 -> CaptureItem
 -> Review
 -> Submit
 -> KnowledgeHub Information
```

Complete offline-first and advanced device AI are deferred until this path is stable.

## Current decision

1. `asami/textus-mobile` is the reusable Flutter runtime/library project.
2. `KnowledgeHubProject/nict-editing-studio-app` is the Flutter Editing Studio application.
3. Capture Profile is the primary extension boundary.
4. CaptureSession / CaptureItem remain in Textus Mobile initially.
5. Server-side canonical Information / Knowledge remain outside the mobile runtime.
