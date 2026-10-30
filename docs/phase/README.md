# Core Phase index

## Planned media input/capability integration — 2026-10-31

[Shared media capabilities](media-input-capabilities-plan.md) provide image
import and platform/device/permission-aware capture, recording and playback
for App Phase 7 ESA7-08. Web import is the baseline; unknown availability is not
hardware absence. Framework owns common controls/reasons. Existing native
providers and submission flow are reused; no closed Phase is reopened.

## Planned User Account authentication integration — 2026-10-31

[Common authentication client](user-account-authentication-integration-plan.md)
uses textus-user-account as the human authentication/session authority, with
CNCF security enforcement. Core owns shared client/state, platform credentials
and authenticated transport; Framework owns common login UI. Deliver native
support for App 6.10 first, then browser support for App 7, coordinated with
Studio Server 5. This bounded workstream preserves the broader planned Phase 3
and all closed phases; no execution or acceptance is claimed here.

## Accepted TKL delivery follow-on — 2026-10-27

[TKL-managed Material delivery](tkl-managed-material-delivery-plan.md) adds the
TKL client/configuration boundary to the existing submission runtime for
[App Phase 6.3](../../../../Project2026/nict-editing-studio-app/docs/phase/phase-6.3.md).
The bounded follow-on is accepted and closed. Workspace Shared Drive has actual
acceptance; My Drive shares the public contract with controlled coverage.
Original Phase 2 stays closed; its prior planning text does not require replay
or reimplementation. Independent on-device AI follow-ups remain separate.

## Current accepted delivery

| Phase | Status | Delivery |
| --- | --- | --- |
| [Phase 2](phase-2.md) | closed | Generic background transfer runtime, durable state, targeted retry and public consumer handoff. |

The [Phase 2 checklist](phase-2-checklist.md) and
[completion journal](../journal/2026/10/2026-10-11-phase-2-completion.md)
identify actual reviews, validation and the required distinct release receipt.
TFAF Phase 3 and Editing Studio App Phase 6.1 retain their own acceptance and
release obligations. This index starts no successor work.

## Earlier Phase records

- [Phase 1](phase-1.md) and [its checklist](phase-1-checklist.md)
- [Phase 1.1](phase-1.1.md)
- [Phase 1.2](phase-1.2.md)
- [Phase 1.3](phase-1.3.md)

Their historical statuses and separate on-device AI follow-ups are retained in
their authoritative documents; Phase 2 closure does not accept that work.

## Planned sensitive interaction follow-on

[Phase 3](phase-3.md) retains the GitHub Sensitive Interaction proposal under
the user-approved number and targets TFAF Phase 4. It remains PLANNED with no
execution started. The [numbering decision](../journal/2026/10/2026-10-27-phase-plan-reconciliation.md)
preserves completed Phase 2 and both histories.
