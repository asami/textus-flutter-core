# Textus User Account authentication client

Decision date: 2026-10-31
Status: accepted integration direction; implementation/acceptance pending

## Authority and common client

`textus-user-account` is the human-account authentication authority. Reuse its
public contracts for login, session refresh and logout; it verifies credentials,
resolves UserAccount and issues/rotates/revokes AccessSession/RefreshSession.
CNCF constructs SecurityContext and enforces operation/entity authorization.
Core neither verifies passwords nor issues a parallel application session.

Producer references: [CML](https://github.com/asami/textus-user-account/blob/main/src/main/cozy/user-account.cml)
declares login, logout and refreshAccessToken; the
[integration design](https://github.com/asami/textus-user-account/blob/main/docs/design/external-federation-security-integration.md)
defines producer/CNCF boundaries. Concrete deployed selectors, input/result
types, challenge responses, endpoint and native/browser transport bindings must
be inventoried before implementation; these references are not deployed proof.

Core supplies a reusable authentication client and safe observable state:
signed out, sign-in in progress, authenticated account, and action-required or
failure outcomes. Exact public types follow the selected producer contract.
Book-specific code must not implement another credential/session client.

Core owns transport integration, platform-appropriate protected credential
handling, existing producer refresh semantics, logout/re-authentication and the
authenticated request adapter. Domain consumers receive account/state/result
information and an authenticated client capability, not raw token material in
settings, journals, presentation models or submission records. Web and native
may use different credential/session transports while sharing account semantics.

## User identity and lifecycle

Same-account phone and Web sessions resolve to the same UserAccount. Do not
infer identity from labels/email or share raw session credentials across devices.
Use the producer's actual refresh/expiry/revocation behavior; add no independent
client lease/TTL or copy/hash comparison as a permission condition.

Logout invokes the selected producer's current-session termination and clears
usable local credentials/private authenticated state. Local cleanup does not
prove remote revocation if the endpoint is unavailable; report that outcome.
Do not use logoutAll for ordinary logout unless the user explicitly selects it.
Account changes must not silently reassign queued uploads or retained drafts.
Integrate with the existing submission credential port and preserve offline
capture; protected remote work waits for the appropriate account credentials.

Application login is distinct from TKL/Google Drive provider consent. Drive
access tokens and destination settings do not become Studio user credentials.

## Acceptance

- A real selected user-account login establishes the normalized account used
  by authenticated server operations; labels alone do not establish identity.
- Native iPhone/Android integrations can log in, submit under the correct owner
  and log out; browser adapter later uses the same account model.
- Supported refresh and refusal paths preserve producer semantics; revoked or
  rejected credentials cannot be treated as authenticated by client state.
- Logout distinguishes local clearance from remote revocation failure, and a
  new login cannot silently send another account's pending work.
- Presentation consumers do not receive raw credentials and no Book-specific
  authentication or separate account store is required.

Delivery: [integration plan](../phase/user-account-authentication-integration-plan.md).

## Untrusted-client producer obligations — 2026-11-02

Support the shared [UC-01..04 acceptance profile](https://github.com/asami/goldenport-cncf/blob/main/docs/spec/untrusted-client-material-acceptance.md).
Core owns the reusable client portion; server authorization/admission remains
in CNCF and TKL.

- UC-01: no server-wide secret/service-account key in client code, resources or
  generated configuration. Keep user credentials in the selected platform
  facility and redact tokens/transfer URLs from ordinary diagnostics, queue and
  presentation. Public OAuth client IDs and endpoint addresses are permitted.
- UC-02/04: retain the authenticated account when composing requests; caller
  owner/role fields cannot establish authority. Surface server denial without
  fallback to a privileged identity, changing target owner or claiming success.
  Preserve the existing account-safe queued-work behavior.
- UC-03: report actual transfer results through the existing TKL contract and
  consume authoritative registration/verification state. Uploaded bytes alone
  cannot create a registered MaterialRef or Studio ACK in client state. Preserve
  pending/failure/reconciliation and do not synthesize server proof.

Application Framework presents the shared state; App supplies domain/UI work.
Acceptance links packaged artifact inspection in the consumer to Core's
credential/redaction tests and public-server denial/admission scenarios.
No custom anti-tamper client, duplicated authorization engine, or new lease
condition is needed.

SDK-owned media processing, telemetry and external destinations additionally
follow the [MS-01/02 contract](media-sdk-and-egress-acceptance.md). Authentication
transport inspection alone does not qualify native SDK networking or cloud
speech/OCR services; use the shared media adapters and actual consumer evidence.

## Small-business defaults — 2026-11-02

Under the [Textus baseline](https://github.com/asami/goldenport-cncf/blob/main/docs/spec/small-business-security-baseline-and-options.md), authentication/custody,
account-safe transport and UC/MS behavior are standard shared facilities, not
consumer opt-ins or app-specific security settings. Core exposes meaningful
policy results/prerequisites for Framework presentation; servers retain authority.
Stronger login methods consume actual User Account/IdP capability. A setting
does not invent a hardware authenticator, HSM or recovery service; unavailable
strengthening must not silently degrade to a weaker promised mode.

## Shared runtime-mode consumption — 2026-11-02

Consume the [common mode policy](https://github.com/asami/goldenport-cncf/blob/main/docs/spec/runtime-mode-security-defaults.md) through the existing configuration/
authentication adapters. Core owns native/Web endpoint, credential and pending
delivery scoping. Apps receive safe account/environment state, never a credential
or a client-controlled server authorization mode. Flutter debug/release is a
separate build choice.

Dev/test can use explicitly configured fixture adapters and synthetic resources.
Demo/production use the ordinary account/session contract; simulated identity
must not appear provider-verified. Reject missing mandatory bindings without
silent auto-login or endpoint fallback. Account/environment changes preserve
unsaved originals and prevent queued work from being submitted to another owner
or destination. Diagnostic detail never permits credential/media disclosure.
