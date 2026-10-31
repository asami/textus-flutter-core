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

Producer references: [CML](../../../textus-user-account/src/main/cozy/user-account.cml)
declares login, logout and refreshAccessToken; the
[integration design](../../../textus-user-account/docs/design/external-federation-security-integration.md)
defines producer/CNCF boundaries. Concrete deployed selectors, wire input/result
types, challenge responses, endpoint and native/browser transport bindings must
be inventoried before the real adapter is implemented; these references are not
deployed proof.

Core supplies a reusable authentication client and safe observable state:
signed out, sign-in in progress, authenticated account, and action-required or
failure outcomes. The normalized backend port below precedes the still-pending
HTTP wire binding and is not a deployed server contract.
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
categories, not mappings of unprovided HTTP codes. Unexpected backend exceptions
become `serviceUnavailable` without exposing their causes.

The closed `UserAccountSignInResult` family consists of
`UserAccountSignedIn(account)`, `UserAccountChallengePending(challengeId, channel)`
and `UserAccountSignInRejected(reason)`. Only the exact channel `email` and a
nonblank opaque challenge reference are admitted. Challenges never establish
authentication. The reference remains private between Core and the backend;
verification sends that exact reference and the supplied code. Unsupported or
malformed challenges fail as `invalidResponse`. A backend must validate and
normalize the authoritative account before constructing a successful result.

The backend implements `signIn(identifier, password, operation)`,
`verifyChallenge(challengeId, code, operation)`, `refresh(operation)`,
`signOut(operation)` and `close()`, with named arguments as declared in Dart.
Its responsibilities are authority communication and protected session storage.
It must honor `UserAccountAuthenticationOperation.isCurrent` and `cancelled`
before credential persistence/publication and drain retired work in bounded
time. Only Core creates/retires the operation; observing its cancellation cannot
renew it. No production backend or credential issuer is supplied here, and App
or Framework must not fill this port with its own credential verifier/token
issuer. The port is not an HTTP decoder or an accepted endpoint specification.

## Commands, serialization and disposal

- `signIn` requires `signedOut` or `failure`; account switching requires logout.
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
- `cancel` accepts sign-in/verification/refresh work or an idle challenge. It
  retires the operation immediately, clears account/challenge and exposes
  `cancelling` until accepted work drains. It then becomes `signedOut` with
  `cancelled`; new sign-in is blocked during drain. Late success/errors cannot
  restore authentication. Cancellation does not prove remote revocation.
- `signOut` can retire and join accepted authentication work, withdrawing account
  and challenge synchronously into `signingOut` before any await. Its fresh
  backend operation starts after the old work drains; all new login work remains
  blocked until logout completes. `UserAccountLogoutResult.localCleared` and
  `remoteRevocation` remain independent. Revocation values are `confirmed`,
  `failed`, `notAttempted` and `unknown`. Local clearance yields `signedOut` even
  when revocation failed/is unknown. Failed clearance yields `failure` with no
  account; unexpected throws return the fixed `false`/`unknown` result. The
  snapshot retains the last logout result. Ordinary logout is current-session
  only.
- `close` synchronously retires state/operations into `closed`, drains accepted
  work and closes an owned backend exactly once. Borrowed backends remain open.
  It is idempotent and performs no implicit logout or retained-work deletion.
  An owned backend close failure surfaces only as the fixed safe
  `StateError('Authentication close failed')`. `dispose` retires synchronously,
  arranges observed asynchronous drain and never notifies after notifier
  disposal. Neither late callbacks nor callback reentrancy revive closed state.

## Remaining real-provider and consumer binding

The server-owner handoff is recorded in the
[foundation journal](../journal/2026/10/2026-10-31-user-account-authentication-foundation.md).
Source evidence supports login, email challenge verification, authoritative
account projection, rotating refresh pairs and current-session logout. Accepted
participant HTTP endpoint/envelope/EntityId specimens and runnable deployment
are still absent. Existing Studio Material intake/editor is fixed to a
development Service and does not establish participant ownership.

Real HTTP normalization, native protected storage and cancellation-safe credential
commit/drain remain required Core work. Account-safe authenticated submission
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
