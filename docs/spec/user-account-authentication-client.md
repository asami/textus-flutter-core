# Textus User Account authentication client

Decision date: 2026-10-31
Status: safe state/backend-port foundation implemented; real-provider integration
and acceptance pending

## Authority and common client

`textus-user-account` is the human-account authentication authority. Reuse its
public contracts for login, session refresh and logout; it verifies credentials,
resolves UserAccount and issues/rotates/revokes AccessSession/RefreshSession.
CNCF constructs SecurityContext and enforces operation/entity authorization.
Core neither verifies passwords nor issues a parallel application session.

Producer references: [CML](https://github.com/asami/textus-user-account/blob/main/src/main/cozy/user-account.cml)
declares login, logout and refreshAccessToken; the
[integration design](https://github.com/asami/textus-user-account/blob/main/docs/design/external-federation-security-integration.md)
defines producer/CNCF boundaries. The native adapter uses the adopted
[root HTTP shapes](user-account-http-wire-v1.md) and an explicit selected
[authority profile](user-account-http-authentication-backend.md). A runnable
participant deployment, browser transport and physical consumer qualification
remain separate acceptance requirements.
Concrete deployed selectors, input/result types, challenge responses, endpoints
and native/browser transport bindings still require deployment-specific inventory;
these producer references alone are not deployed proof.

Core supplies a reusable authentication client and safe observable state:
signed out, sign-in in progress, authenticated account, and action-required or
failure outcomes. Its normalized backend port is implemented by the native
Core HTTP backend; the port itself is independent of HTTP wire representation.
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

## Implemented state and backend-port foundation

Import `package:textus_flutter_core/textus_flutter_core.dart` for
`UserAccountAuthenticationClient` and its normalized value types. A configured
client requires a `UserAccountAuthenticationBackend`, borrows it by default
(`ownsBackend: false`), and begins `signedOut`. The `.unavailable()` constructor
begins `unavailable` with `notConfigured`. Both constructors perform zero IO;
neither restores a session or starts refresh/background work.

`AuthenticatedUserAccount` holds a required nonblank, exact opaque
`userAccountId` and an optional authoritative `displayName`. Neither login input
nor a label supplies identity; UserAccount, principal and session IDs are
distinct. The account projection contains no password, access/refresh token or
session reference. The public immutable snapshot contains `status`, optional
`account`, optional `challengeChannel`, optional safe `failure`, optional
`lastLogoutResult`, and a monotonically increasing `revision` (initially zero).
Its `isAuthenticated` requires both `authenticated` status and an account.
Snapshots and their diagnostics do not expose credential inputs, challenge
references or backend errors. Presentation state does not authorize server work.

Statuses are `unavailable`, `signedOut`, `signingIn`, `challengeRequired`,
`authenticated`, `refreshing`, `cancelling`, `signingOut`, `failure` and `closed`.
Safe failure categories are `notConfigured`, `invalidCredentials`,
`authorizationRequired`, `challengeRejected`, `serviceUnavailable`,
`transportUnavailable`, `invalidResponse` and `cancelled`. These are client
categories; the concrete HTTP backend specifies its closed status mappings.
Unexpected backend exceptions
become `serviceUnavailable` without exposing their causes.

The closed `UserAccountSignInResult` family consists of
`UserAccountSignedIn(account, {sessionCommit})`,
`UserAccountChallengePending(challengeId, channel)`
and `UserAccountSignInRejected(reason)`. Only the exact channel `email` and a
nonblank opaque challenge reference are admitted. Challenges never establish
authentication. The reference remains private between Core and the backend;
verification sends that exact reference and the supplied code. Unsupported or
malformed challenges fail as `invalidResponse`. A backend must validate and
normalize the authoritative account before constructing a successful result.
The optional `UserAccountAuthenticationSessionCommit` is a Core-owned staging
completion with `persist(operation:)`, synchronous `accept()`, and `discard()`.
It exposes no credentials or application-issued session. Plain
`UserAccountSignedIn(account)` remains source compatible for existing backends.

The client captures completions even from late results, rejects a changed
expected account before persistence, awaits protected persistence, rechecks the
exact current operation, and accepts synchronously before publishing. There is
no asynchronous gap between final current check, acceptance and publication.
Every unaccepted completion is discarded and drained before action completion,
including late result, cancellation, close and persistence failure. Cleanup
errors are remembered even after the action retires. Still-current work fails
as `serviceUnavailable` with `lastLogoutResult` reporting `localCleared: false`
and `remoteRevocation: notAttempted`. The same safe facts expose the existing
logout retry action. Unresolved staged cleanup blocks restoration and sign-in
before backend IO until an explicit logout reports successful local clearance.
The internal drain future completes normally; retiring cancel/close callers
receive the safe cleanup outcome without retaining the underlying cause.
Completions are idempotent; discarding accepted work does not erase it. The
normal operation `cancelled` future also completes on successful finish and is
never an unconditional credential-cleanup trigger.

The backend implements `signIn(identifier, password, operation)`,
`verifyChallenge(challengeId, code, operation)`, `refresh(operation)`,
`signOut(operation)` and `close()`, with named arguments as declared in Dart.
Its responsibilities are authority communication and protected session storage.
It must honor `UserAccountAuthenticationOperation.isCurrent` and `cancelled`
before credential persistence/publication and drain retired work in bounded
time. Only Core creates/retires the operation; observing its cancellation cannot
renew it. `UserAccountHttpAuthenticationBackend` supplies the native Core
implementation. App or Framework must not fill this port with its own credential
verifier/token issuer. The port is not an HTTP decoder.

`UserAccountRestorableAuthenticationBackend` extends this port with
`restore(operation:)`, returning a normalized result or null for no stored
candidate. Only the client's explicit `restore()` interprets null as ordinary
`signedOut`. `canRestore` is true only for a configured restorable, idle client
in `signedOut` or `failure` with no failed-local-clear barrier. Restoration
reserves authentication work and uses `refreshing` plus the same staged
publication protocol. Constructors never restore or read storage; stored bytes
alone never establish authentication.

## Commands, serialization and disposal

- `signIn` requires `signedOut` or `failure`; account switching requires logout.
  An unresolved staged-cleanup failure also rejects sign-in before IO.
  Identifier/code validation is nonblank only; password validation is nonempty
  only. Exact supplied input, including password whitespace, reaches the backend.
  Credentials are not retained as client fields or included in thrown errors.
- `verifyChallenge` requires the current private challenge. Both sign-in actions
  enter `signingIn` with no account before backend IO. Only a current result can
  publish an account/challenge. Rejected or throwing work clears both.
- `refresh` requires authentication, withdraws the account while `refreshing`,
  and admits success only for the exact previous `userAccountId`. A changed ID
  or challenge is `invalidResponse`; rejection/exception fails closed and
  requires sign-in again. There is no client TTL or independent expiry timer.
- Every action reserves ownership before listeners/backend code run. Concurrent,
  reentrant, unavailable, closed and invalid-sequence authentication commands
  fail with a fixed safe `StateError` before starting a second backend operation.
- `cancel` accepts active authentication only while the snapshot is `signingIn`
  or `refreshing`, or an idle challenge. A synchronous authenticated-publication
  listener cannot cancel already accepted success; that direct command rejects.
  Reentrant logout still retires/joins and clears the accepted session, while
  reentrant close preserves its accepted record. Cancellation
  retires the operation immediately, clears account/challenge and exposes
  `cancelling` until accepted work drains. Successful cleanup then becomes
  `signedOut` with `cancelled`; new sign-in is blocked during drain. Failed
  staged cleanup instead becomes `failure`/`serviceUnavailable` with the fixed
  local-not-cleared/not-attempted logout facts, and cancellation fails with
  `StateError('Authentication cleanup failed')`. If close has superseded cancel,
  cancel still reports that failure without publishing over closed state. Late
  success/errors cannot restore authentication. Cancellation does not prove
  remote revocation.
- `signOut` can retire and join accepted authentication work, withdrawing account
  and challenge synchronously into `signingOut` before any await. Its fresh
  backend operation starts after the old work drains; all new login work remains
  blocked until logout completes. `UserAccountLogoutResult.localCleared` and
  `remoteRevocation` remain independent. Revocation values are `confirmed`,
  `failed`, `notAttempted` and `unknown`. Local clearance yields `signedOut` even
  when revocation failed/is unknown. Failed clearance yields `failure` with no
  account; unexpected throws return the fixed `false`/`unknown` result. The
  snapshot retains the last logout result. Ordinary logout is current-session
  only. Logout joining a staged-cleanup failure still attempts backend local
  cleanup after drain. Only `localCleared: true` clears that unresolved failure
  and the restoration barrier; unsuccessful or throwing cleanup keeps both.
- `close` synchronously retires state/operations into `closed`, drains accepted
  work and closes an owned backend exactly once. Borrowed backends remain open.
  It is idempotent and performs no implicit logout or retained-work deletion.
  Unresolved staged cleanup, including failure discovered during drain or
  remembered from an already-idle action, also makes close fail. Owned backend
  close is still attempted after draining, and every close failure surfaces only
  as the fixed safe `StateError('Authentication close failed')`. An ordinary
  already-reported logout failure alone does not change legacy close behavior.
  `dispose` retires synchronously,
  arranges observed asynchronous drain and never notifies after notifier
  disposal. Neither late callbacks nor callback reentrancy revive closed state.

## Remaining real-provider and consumer binding

The server-owner handoff is recorded in the
[foundation journal](../journal/2026/10/2026-10-31-user-account-authentication-foundation.md).
Source evidence supports login, email challenge verification, authoritative
account projection, rotating refresh pairs and current-session logout. Accepted
native HTTP root shapes are now specified by the internal wire/backend
contracts. A runnable participant deployment and application profile remain
required. Existing Studio Material intake/editor is fixed to a
development Service and does not establish participant ownership.

The native Core backend implements HTTP normalization, protected storage and
cancellation-safe staged credential commit/drain. Connected consumer acceptance
remains required. Account-safe authenticated submission
and queue ownership binding remain required integration work. No test fake is a
provider, no green state test establishes participant Material capability, and
no endpoint, JSON envelope, Bearer expiry or client TTL is inferred here.
Framework's common login UI may consume safe state while these bindings remain
pending. Android-first development does not complete or reduce the required
Android/iPhone real-provider and owner-correct submission acceptance below.

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

## Internal native storage prerequisite (2026-11-05)

The bounded [native credential storage specification](native-authentication-credential-storage.md)
adds internal opaque-byte Android/iOS storage with revision CAS, conditional
remove, explicit slot clear and handle retirement/drain. It is not root-exported
and supplies no backend, session issuer, account restoration or HTTP codec.
Parent validation and native qualification remain required. This prerequisite
does not complete the real-provider or consumer requirements above.

The production Core backend must still bind accepted HTTP specimens, a
server-normalized codec and authoritative provider account, refresh/current-
session logout and account-safe authenticated queue ownership. It must check
`operation.isCurrent` before persistence, conditionally remove only its own
returned late-write revision on cancellation, and drain retired work before
publishing. Storage `close` preserves persistent records and may drain an
already-issued write; it must never serve as logout or cancellation rollback.

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
