# Book Capture: Offline-first Confirmed Sync

Date: 2026-09-25
Status: active

## First Reference Application use case

The first Textus Flutter Core Reference Application captures a book as source material for KnowledgeHub.

1. Photograph a book and derive available metadata.
2. When online, enrich the entry with full online capabilities such as ISBN-based bibliographic lookup.
3. When offline, continue with capabilities available locally/on-device.
4. Record a voice comment and produce a transcript when the available provider permits it.
5. Let the user review the entry and explicitly confirm it for transfer.
6. Persist confirmed entries locally.
7. When Wi-Fi is available and the target server is reachable, upload confirmed entries automatically.
8. Keep unconfirmed entries local; connectivity alone must never cause them to be uploaded.

## Confirmation boundary

Capture confirmation means only that the user authorizes this captured entry to be transferred to the server. It is not KnowledgeHub Information admission. Server-side human editing/admission is a separate decision.

Lifecycle: Draft -> Edited -> CaptureConfirmed -> PendingSync -> Uploading -> ServerAccepted.

Only CaptureConfirmed/PendingSync entries are eligible for deferred sync.

## Raw-data contract

The smartphone sends source/raw capture data, preserving provenance and derivation: original book photographs; original voice recording; detected ISBN and locally/online derived bibliographic fields; transcript and other AI/provider-derived values; user corrections; capture/confirmation timestamps and derivation metadata.

Derived values do not replace original media. Server acknowledgement is required before local sync completion.

## Service / Provider implication

Online/offline differences are absorbed behind Services and capability-sized Providers. Examples include CameraService/CameraProvider, AudioService/AudioProvider, AiService/AiProvider, and bibliographic metadata providers. The application should reason about capability/availability rather than concrete platform engines.

## Server handoff

The uploaded entry is registered as raw source data. KnowledgeHub may use AI for provisional editing, but only server-side human editing/approval admits content as canonical Information. RDF/Open Knowledge publication is downstream from canonical Information and is not part of smartphone confirmation.
