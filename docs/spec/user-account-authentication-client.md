# Textus User Account authentication client

Decision date: 2026-10-31
Status: accepted integration direction; implementation/acceptance pending

## Authority and common client

`textus-user-account` is the human-account authentication authority. Reuse its
public contracts for login, session refresh and logout; it verifies credentials,
resolves UserAccount and issues/rotates/revokes AccessSession/RefreshSession.
CNCF constructs SecurityContext and enforces operation/entity authorization.
Core neither verifies passwords nor issues a parallel application session.

Producer references: [CML](../../../textus-user-account/src/main/cozy/user-account.cml)
declares login, logout and refreshAccessToken; the
[integration design](../../../textus-user-account/docs/design/external-federation-security-integration.md)
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
