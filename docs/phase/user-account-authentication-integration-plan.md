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
[milestone schedule](https://github.com/KnowledgeHubProject/nict-editing-studio/blob/codex/ess3-server-editing/docs/milestone/2026-11-10-nict-demo.md#intermediate-delivery-targets-jst).
Run proportionate boundary/consumer specifications and integrated review; record
actual platform proof separately. Normal owner validation/release rules apply.

## UC-01..04 acceptance allocation — 2026-11-02

The [client security obligations](../spec/user-account-authentication-client.md#untrusted-client-producer-obligations--2026-11-02)
are part of TFC-UA01..03 and their connected acceptance.

- [ ] TFC-UA02 / UC-01: native credential handling and redaction pass; App 6.10
  inspects its actual distributables for embedded server secrets.
- [ ] TFC-UA02 / UC-02..04: existing delivery/auth clients preserve account scope,
  surface denial and independent TKL verification without false registration/
  ACK; connect with Studio/TKL's two-user and forged-completion tests.
- [ ] TFC-UA03: equivalent browser credential/transport/presentation behavior,
  linked to App 7 bundle inspection and actual Web ingress acceptance.

Reuse the closed TKL delivery workstream and its evidence; do not reopen it or
build another transfer runtime. Record gaps against this active integration
and the owning CNCF/TKL requirement, with one integrated review.

## SDK and media destination acceptance — 2026-11-02

Deliver the [MS-01/02 common contract](../spec/media-sdk-and-egress-acceptance.md)
as the media/transport portion of this connected workstream. Preserve closed
capture/delivery phases and reuse their implementations and evidence.

- [ ] TFC-UA01 / MS-01: inventory relevant resolved SDKs/plugins and transitive
  dependencies, media/credential access and automatic collection; map local/
  remote processing and recipients with App ESA610-01. Use existing lockfiles
  and reports rather than a new dependency registry.
- [ ] TFC-UA02 / MS-02: common native adapters/configuration and SDK diagnostics
  satisfy declared media egress, no silent cloud fallback and no media/text/
  secret logging. Exercise authorized positive transfer and startup, preview,
  denied permission, cancellation, offline/retry and recipient-change cases.
  Link separate Android/iPhone observations with App Phase 6.10.
- [ ] TFC-UA03 / MS-01/02: qualify the Web dependencies/adapters and hand the
  observed destination/processing behavior to Framework/App Phase 7; reuse
  native evidence only for shared behavior and identify platform-specific gaps.

Core owns reusable configuration/transport behavior; App owns final packaged
composition and platform acceptance. Native third-party SDK traffic is assessed
explicitly, not assumed intercepted by Core's HTTP client. Use synthetic media,
sanitized results and existing integrated review; record unknowns as open.

## Simple standard setup allocation — 2026-11-02

- [ ] TFC-UA01/02 / SB-01/03: qualify supported native defaults with only
  necessary account/provider onboarding; consumers need no custom credential
  storage, guard setup or technical security parameters.
- [ ] TFC-UA03 / SB-02: shared Web/native policy meaning is preserved for
  supported strengthening; expose unsupported capability/equipment prerequisites
  without claiming protection or silently falling back.

Follow the [baseline contract](https://github.com/asami/goldenport-cncf/blob/main/docs/spec/small-business-security-baseline-and-options.md). Reuse UC/MS
consumer evidence. Optional strong-authentication providers and physical
controls are future selectable delivery, not universal current-phase gates.
