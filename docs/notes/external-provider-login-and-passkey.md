# External provider login and provider-managed Passkey

Decision date: 2026-11-05
Status: planned; no implementation or provider qualification asserted

## Agreed responsibility

textus-user-account implements external authentication providers using Nimbus
OAuth/OIDC SDK and JOSE/JWT behind its existing component contracts. CNCF supplies
existing HTTP/security integration; it does not become a second provider engine.
User Account owns begin/callback verification, external identity mapping and
ordinary Textus session issuance/revocation. Pin and qualify the actual Nimbus
version/dependency set during implementation; do not expose SDK types publicly.

Flutter Core owns the common login client/state, system-browser launch and native
return handling, Web redirect/session adapter, protected session storage and
logout. Application Framework owns provider selection, progress, cancellation,
errors and signed-in/account UI. Applications configure and compose these common
facilities rather than implementing their own authentication flow.

## Providers and presentation

Google, Microsoft and LINE use OIDC; GitHub uses a separate OAuth adapter and
provider identity API, not an assumed OIDC ID token. Deliver the existing Google
first-route plan first, then extend to Microsoft, GitHub and LINE. Provider
availability is configured server-side; client choices never authorize an
unconfigured provider. Microsoft account/tenant policy is explicit configuration.

Locale controls recommendations/order only: initially Japanese recommends Google,
Microsoft and LINE; the default recommends Google and Microsoft. “Other login
methods” exposes all remaining enabled providers, including GitHub, regardless
of locale. Keep this mapping configurable. Locale never grants or restricts
identity/permissions. Do not infer account linking from an email match.

## Authentication flow and session boundary

Select provider -> request login start -> provider authentication in the system
browser -> server callback and verification -> establish a Textus session ->
return to App/Web and update the common login state. Keep provider secrets on the
server. Agree exact begin/complete/cancel contracts and trusted callback/return
locations before client implementation; do not invent endpoint paths here.

Correlate the transaction, provider/issuer, state, nonce and PKCE for the chosen
flow; reject expired, replayed and mismatched callbacks and invalid token claims.
Use verified issuer + subject for OIDC identity, and provider + stable subject
for GitHub. Resolve identities through explicit account-link policy.
Native return must not carry reusable credentials in URL/log/history; qualify a
single-use, transaction-bound completion exchange. Web uses the accepted browser
session contract. Platform adapters preserve account isolation on cancel, retry,
logout and app restart. Authentication tokens are not UI data.

## Provider-managed Passkey

Allow the provider's own Passkey ceremony through its supported authentication
surface, then accept its verified federated result through the normal session
path. Availability depends on the provider/account/browser/device; do not claim
that every listed provider supports the same ceremony. Textus does not register,
store or manage provider Passkeys, private keys or biometrics. Display the
provider login option rather than promising a separate guaranteed Passkey button.

OIDC success alone does not prove Passkey use. Record observed real-device
ceremonies separately from verified assurance claims. Reused provider sessions
or automatic sign-in are valid login outcomes but not Passkey-ceremony evidence.
Making Passkey mandatory requires a separate provider-specific policy and
verified assurance contract; it is not part of this delivery. Direct Textus
WebAuthn/enrollment remains a separate later plan, not removed or completed here.

## Delivery and verification

First agree the User Account/Core/Framework contracts, complete Google Web
login to an ordinary Textus session, then native Android/iOS return and shared
UI; qualify the existing Google cross-device Passkey scenario. Add other enabled
providers incrementally using the same account/session boundary. Retain each
platform/provider's actual evidence, including cancellation, denial, callback
replay/mismatch, account changes, refresh/logout, and secret redaction.

Login does not grant Google Drive access. Preserve the current November 10 demo
login scope: this external-provider/Passkey extension is subsequent development,
not a new demo gate. App Japanese wording may remain hardcoded for that demo;
locale-based provider recommendations belong to this later shared UI delivery.
