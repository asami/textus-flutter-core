# Native voice text and multimedia demo capabilities

Status: PLANNED; implementation not started
Decision date: 2026-11-08 (Asia/Tokyo)
Consumer: [App Phase 7.2](../../../../Project2026/nict-editing-studio-app/docs/phase/phase-7.2.md)
Priority: required November 10 demo contribution

## Scope

Support the Framework's common voice dialog and multiple Book annotation
consumer through public Core capabilities. Framework owns presentation, App owns
Book meaning/associations, and existing material/transfer owners retain storage
and delivery authority. Preserve closed Core Phases and current workstreams;
this bounded demo contribution does not start a new numbered Core Phase.

| ID | Delivery | Consumer acceptance |
| --- | --- | --- |
| TFC-INPUT01 | Actual Android/iPhone capability and contract inventory | ESA72-01: signing/builds, microphone/speech, Japanese native cleanup, prepared model and video/media support; concrete gaps and owners |
| TFC-INPUT02 | Transient speech input | ESA72-02/03: actual final transcript on explicit stop, optional real interim events, permission/cancel/cleanup and visible unsupported states; no compulsory persistent audio Material |
| TFC-INPUT03 | Native Japanese cleanup | ESA72-02/06: prepared-model offline inference with no commercial AI API call; explicit meaning-preserving cleanup operation, truthful availability, limits and failure |
| TFC-INPUT04 | Selected video/media lifecycle | ESA72-02/04/05: capture or import video and preserve playable originals/references through current storage/transfer boundaries; reuse photo/audio capabilities |
| TFC-INPUT05 | Native and connected qualification | ESA72-05..07: both phones, cancellation/denial/unavailable/long input, legacy regression and actual save/delivery/Web original read; ordinary checks and handoff |

- [ ] TFC-INPUT01 actual matrix and selected contracts accepted.
- [ ] TFC-INPUT02 native speech and transient cleanup lifecycle accepted.
- [ ] TFC-INPUT03 native Japanese cleanup and offline/no-commercial-API behavior accepted.
- [ ] TFC-INPUT04 required media/video lifecycle accepted.
- [ ] TFC-INPUT05 both-device/connected handoff accepted.

## Reuse and platform gaps

Inspect the existing AudioCaptureService/AudioTranscriptionProvider and
GeneratedDraftService/provider boundaries first. Reuse compatible behavior;
saved-original transcription and annotation-only textReadability do not by
themselves implement generic transient dictation cleanup. Preserve original
quotation, annotation and history semantics.

Apple Foundation Models and Android AICore/Gemini Nano are native adapter
candidates, not accepted device capabilities. Inventory the selected real OS,
language, model state and per-operation support early. Keep native platform
calls in Core's ordinary adapters/companions; add no app-owned recorder or
server-owned substitute for on-device cleanup. Report actual support limitations.

A permission probe never proves inference quality. Prepare/download models
explicitly before rehearsal; unavailable capabilities remain visible to the
caller. Cancel/dispose must retire owned microphone/inference callbacks and
release resources before another operation. Preserve source text on failure.
Honor the actual model/input limits without silent truncation.

## Demo meaning and evidence

The selected benefits concern text cleanup: after model preparation it works
without network access, and repeated cleanup does not generate metered commercial
AI API calls. Verify a real native inference path and the absence of such calls;
offline output alone is not evidence if it came from a cache or canned fixture.
No API billing dashboard, secret enrollment or new usage ledger is required.

Document speech recognition's own on-device/network behavior separately. Model
download and Material transfer are separate operations; do not claim the entire
app or every processing stage has zero cost or works offline. Restore connectivity
before the normal authenticated upload/reopen scenario.

Use actual Japanese rough text with fillers, meaningful 'あと', proper names,
numbers, negation and spoken self-correction. Retain raw and polished text for
human comparison; prompt intent alone does not prove meaning preservation.
Controlled Dart/native tests and actual device observations remain distinct.

## Targets and handoff

Nov 8 JST: TFC-INPUT01 first, then freeze the bounded provider/media work.
Nov 9: integrate with Framework/App, prepare models and qualify actual device
offline cleanup plus ordinary original delivery/reopen.
Nov 10: smoke the exercised configuration; report gaps/forecast honestly.

These are requested targets, not proven feasibility. Core/Framework preparation
can proceed alongside App 7.1 under separately issued work. App 7.2 records joined
acceptance, and Core retains its producer results; no earlier acceptance is reset.
