# Shared image input and media capability contract

Decision date: 2026-10-31
Status: accepted direction; implementation and platform acceptance pending

## Common operations and capability state

Core provides platform adapters behind the same application-facing operations:
image import, camera capture, microphone recording and media playback. Reuse
existing capture/material/submission contracts rather than creating a separate
Web Material model. Image import is the baseline on Web and large native screens;
it selects an existing file/photo and requires no camera or microphone grant.
Cancellation returns a normal no-selection outcome, not a failed upload.

Represent adapter support, observed device availability and permission state
separately. At least distinguish supported/unsupported, available/absent/unknown,
and allowed/requestable/denied-or-policy-blocked/unknown as meaningful outcomes
for the selected platform, with busy/disconnected/operation failure where known.
These are semantic requirements, not a demand for a new generic state engine.
Do not label an unsupported adapter as absent hardware, or unknown visibility
as permission denial. Final operation results remain authoritative when the
device or permission changes after observation.

Web availability is based on the implementation and actual browser/device
capabilities, not `Web == no camera` or `USB == camera`. Built-in and external
cameras use the same boundary. Browser device enumeration can omit information
because of permission or policy, so lack of enumeration is not conclusive proof
that no device exists. Avoid probing by starting capture just to paint buttons.

## Explicit use and permission lifecycle

Request only the needed camera/microphone access after a user chooses the
corresponding action. Opening/resizing/unfolding the UI, switching modes or
logging in does not request permission, capture or play media. User-account
authentication and server resource authorization remain distinct from OS/browser
device permission. No login result grants camera/microphone rights.

Where supported, observe device/permission changes and refresh the common state;
otherwise re-evaluate at the next explicit action or user-requested retry.
Do not require continuous polling or claim that every platform exposes reliable
permission queries. Release capture resources when their use ends; a lost device
or revoked permission stops the affected operation with an accurate outcome,
without deleting already captured content or unrelated drafts.

Playback uses explicit user action and reports autoplay/device failures.
Ordinary playback is not gated on microphone permission. Choosing a specific
output device is a separate optional capability, not baseline playback.

## Imported media and server integration

Return imported image content/reference and metadata through existing Core
media contracts. A browser file is not a native filesystem path or a registered
TKL resource. Apply normal format/size validation at the existing boundaries,
preserve the original and route user-confirmed submission through the existing
TKL-managed delivery contract. Selection alone is not upload/registration.
Keep temporary resource lifetime distinct from retained originals.

Web camera/microphone adapters require a secure browser context and compatible
deployment policy; expose configuration blocking separately from absent hardware.
Native adapters use OS permissions. Browser and native adapters may differ
internally, while consumers use the same operations/status semantics.

## Full input follow-on

App Phase 8 ESA8-06 extends acquisition to explicitly pasted image content,
drag/drop and multiple-file selection. Normalize these into the same existing
media/delivery contract as the Phase 7 picker route; no second uploader or
registration model. Clipboard reads are user initiated, not background polling.
Distinguish image data from text/URLs and report unsupported kinds rather than
automatically downloading remote URLs. Retain per-item identity/content through
preview, cancel, delivery/retry and TKL registration. Specific platform adapters
are qualified separately; unavailable paste does not disable file import.

## Acceptance

- Web image selection/preview/submission/reopen works without camera/mic access;
  cancellation leaves the current work intact.
- Unsupported, known absent, unknown/requestable, denied/blocked and available
  states reach consumers accurately; an unknown device does not get stuck as absent.
- Allowed capture/recording works on the selected supported device; unavailable
  operations do not block import, reference browsing or ordinary text editing.
- Device removal or permission changes produce honest outcomes and do not
  discard content. No layout/mode change starts a permission prompt or recording.
- Existing native capture consumers remain usable; a Web stub reports unsupported
  until its actual adapter is implemented and accepted, never apparent success.

References: [device enumeration](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/enumerateDevices),
[capture permissions](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia),
[file selection](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/input/file).
Delivery: [media capability plan](../phase/media-input-capabilities-plan.md).
