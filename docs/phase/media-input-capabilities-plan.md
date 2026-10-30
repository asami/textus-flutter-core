# Shared media input/capability integration

Status: PLANNED; execution not started
Decision date: 2026-10-31
Consumer: App Phase 7 ESA7-08; Application Framework media action facade

Implement the [media contract](../spec/media-input-capabilities.md). Preserve
existing closed phases and the accepted capture/submission interfaces. This
bounded workstream is part of Phase 7's integration, not a new broad device SDK.

| ID | Delivery | Acceptance |
| --- | --- | --- |
| TFC-MEDIA01 | Inventory and common capability/result boundary | Reuse native providers; identify actual Web adapter support and device/permission observability; distinguish unsupported, absent and unknown |
| TFC-MEDIA02 | Web image import and native adapter alignment | Select/preview and submit a supported image via existing media/TKL flow; no camera/mic permission needed; cancellation and ordinary format rejection preserve work |
| TFC-MEDIA03 | Device/permission-aware capture, recording and playback | Report accurate actionable states to Framework; accept supported device operations, denied/no-device paths and state changes; no platform-wide camera prohibition or automatic prompting |

- [ ] TFC-MEDIA01 public boundary and actual platform support matrix recorded.
- [ ] TFC-MEDIA02 actual Web import and relevant native regression evidence accepted.
- [ ] TFC-MEDIA03 common states and selected supported operations accepted with Framework/App.

Inventory TFC-MEDIA01 risks early with ESA7-01, but start new media-input
implementation only after App 7/Server 5's basic phone → Web → persisted
Information route works (Nov 6 JST target). Reuse the existing native capture
path; do not replace Phase 6.10's accepted phone input. App first connects Fold
editing, then ESA7-08/Core/Framework connect Web import (Nov 7 target), followed
by joined rehearsal/release Nov 8 and a Nov 9 defect buffer. Core owns adapters
and capability state. Record gaps/forecast if targets slip; no extra review
cycle or automatic acceptance follows a date. See the
[milestone schedule](../../../../Project2026/nict-editing-studio/docs/milestone/2026-11-10-nict-demo.md#intermediate-delivery-targets-jst).

Within this follow-on integration, start with Web import and existing native
Fold capture. Connect the
selected browser's actual camera/mic adapters where supported; record unsupported
adapters explicitly rather than invent working controls. Universal browser/device
support and output-device selection are not Phase 7 prerequisites. Use focused
contract scenarios plus actual chosen Web/Fold acceptance and normal integrated
review/release; avoid duplicated device frameworks or polling infrastructure.

## Phase 8 follow-on

ESA8-06 consumes shared adapters for explicit image clipboard paste, drag/drop
and multiple-file selection, converging on the existing import/upload pipeline.
Qualify content/cancel and per-item upload/retry results; do not read clipboard
in the background or fetch copied URLs automatically. This is later work, not
a TFC-MEDIA01..03 or App Phase 7 closure gate.
