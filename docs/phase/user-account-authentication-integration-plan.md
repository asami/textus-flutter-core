# User Account authentication client integration

Status: PLANNED; execution not started
Decision date: 2026-10-31
Consumers: App Phase 6.10 ESA610-08, then Phase 7 ESA7-01; Flutter Application Framework

Implement the [common client contract](../spec/user-account-authentication-client.md).
This is a bounded producer workstream driven by Studio Server Phase 5 and the
App phases. Preserve closed Core phases and the broader planned Phase 3
Sensitive Interaction scope; do not renumber or claim either completed.

| ID | Work | Acceptance |
| --- | --- | --- |
| TFC-UA01 | With ESS5-01/02 inventory the deployed textus-user-account public login/session/refresh/logout contracts and CNCF wiring | Exact accepted contract and transport binding identified; no invented endpoint or Studio account store |
| TFC-UA02 | Common auth state/client, native protected credentials and submission integration | Actual native consumer login/owned submission/logout; refresh and account-change behavior under the producer contract; public Framework handoff |
| TFC-UA03 | Browser transport adapter and consumer handoff | Reuse common semantics for Web login/logout and same-user Material access; preserve native behavior |

- [ ] TFC-UA01 accepted contract and server capability available.
- [ ] TFC-UA02 common/native boundary accepted with App 6.10 and Framework.
- [ ] TFC-UA03 browser boundary accepted with App 7 and Server 5.

Sequence: server/account contract → common Core + Framework/native App 6.10 →
Web adapter/App 7 → joined demo. TFC-UA02 can be handed off before TFC-UA03;
mobile closure does not wait for Web or the entire broader Sensitive Interaction
program. Reuse existing credential/queue facilities and selected required
dependencies; missing producer capability stays an explicit producer requirement.
Passkey, federation, payment or signing expansion is not implied by this workstream.
Shared milestone targets (JST): TFC-UA01/server capability by Nov 2, TFC-UA02
with actual App 6.10 mobile acceptance by Nov 4, and TFC-UA03 with App 7's basic
phone → Web → persisted Information route by Nov 6. Core owns the client boundary;
Studio owns server composition and user-account owns identity/session issuance.
New Fold editing/media-import implementation follows that basic route. These
targets reuse existing evidence; report delays without adding review gates or
claiming acceptance from the calendar. See the
[milestone schedule](../../../../Project2026/nict-editing-studio/docs/milestone/2026-11-10-nict-demo.md#intermediate-delivery-targets-jst).
Run proportionate boundary/consumer specifications and integrated review; record
actual platform proof separately. Normal owner validation/release rules apply.
