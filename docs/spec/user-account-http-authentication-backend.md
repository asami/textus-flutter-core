# Native UserAccount HTTP authentication backend

`UserAccountHttpProfile` and `UserAccountHttpAuthenticationBackend` are exported
from `textus_flutter_core.dart`. The backend implements the restorable normalized
[client port](user-account-authentication-client.md). Wire DTOs and native
credential storage remain internal. Each backend serves one client lifetime;
constructors perform no network, platform-channel, storage or restoration IO.

## Explicit authority and resource ownership

A profile requires `profileId` and `serviceBaseUri`. Raw configuration uses
`UserAccountHttpProfile.fromString` with a string base. Before URI parsing can
normalize the input, it rejects raw backslash and C0/DEL controls, raw or
once-percent-decoded dot traversal, and decoded path separators or controls.
The original constructor accepts an explicitly supplied, already-parsed
canonical `Uri`; it validates that URI but cannot recover source syntax erased
by earlier parsing. The slot is an exact match for
`[A-Za-z0-9][A-Za-z0-9._-]{0,127}`. Both entries require an absolute base with a
nonempty host, HTTPS, no userinfo/query/fragment, backslash, control characters,
remaining dot traversal or encoded path separators, and one normalized trailing
slash. Endpoint selectors are fixed relative operations, never server-supplied URLs.
`allowDevelopmentHttp: true` permits HTTP only for localhost, loopback literals
and literal RFC1918 addresses, never arbitrary DNS/public HTTP. A positive
`requestTimeout` defaults to 15 seconds and is at most 60 seconds. Configuration
errors and diagnostics contain no profile, URI, received data or credentials.

Injected `http.Client` and internal `NativeAuthenticationCredentialStore`
instances remain borrowed. Omitted handles are owned. Closing is idempotent,
withdraws memory, aborts/drains accepted work and releases only owned handles;
it preserves accepted protected records and performs no implicit logout or
retained-work deletion. Concurrent work or a pending staged completion is
rejected safely. Close also reports its fixed safe `serviceUnavailable` failure
when staged rollback remains unresolved, even after its pending completion was
drained. It still releases every owned handle once; borrowed handles remain
open. There is no cookie jar, environmental credential lookup,
credential getter, queue adapter, token issuer, account mapper, refresh timer,
client TTL, telemetry or automatic retry.

## Native HTTP policy

Every request is a fresh `http.AbortableRequest` with redirects disabled and
`Accept: application/json`. JSON requests have JSON Content-Type. Requests
contain no ambient Cookie or Authorization; only `get-my-account` and `logout`
receive the current ACCESS Bearer. REFRESH is used only in a refresh JSON body.
The explicit base binds these fixed operations:

| Operation | Method/body | Success |
| --- | --- | --- |
| `login` | POST `{identifier,password}` | Exact seven-key pair or email challenge |
| `verify-two-factor-login` | POST `{challengeId,code}` | Exact seven-key pair |
| `get-my-account` | GET, no body, ACCESS Bearer | Open account root with exact expected `id`; optional `handle` only supplies display name |
| `refresh-access-token` | POST `{refreshToken}` | Exact six-key pair, no credential identity |
| `logout` | POST `{userAccountId}`, accepted ACCESS Bearer | HTTP 200, exactly zero body bytes |

The [wire specification](user-account-http-wire-v1.md) defines exact key,
identity and token validation. Received bytes are bounded to 65536, including
streamed bodies. Expected JSON 200 bodies use strict UTF-8 and JSON decoding.
One deadline covers send plus the entire body. Retirement aborts transport and
prevents a next request. Late replies from noncooperative injected clients have
their streams cancelled and errors observed. No raw body, headers, URI or cause
is retained in diagnostics.

Login 401/403 maps to `invalidCredentials`; verification 401/403 to
`challengeRejected`; account/refresh 401/403 to `authorizationRequired`.
429/5xx maps to `serviceUnavailable`. Unexpected status, redirect, shape,
UTF-8/JSON or body overflow maps to `invalidResponse`. Transport error, abort or
timeout maps to `transportUnavailable`. Native persistence failures use safe
`serviceUnavailable`. Error bodies are never parsed for diagnostics.

## Protected record and transaction ownership

The existing native credential store holds one private JSON record with exact
keys `schemaVersion: 1`, `profileId`, `authorityBaseUri`, `userAccountId`,
`accessSessionId`, `accessToken`, `refreshSessionId`, `refreshToken`, `writeId`.
Profile and normalized authority must match the selected binding exactly.
Identity/token fields obey the wire rules; `writeId` is a fresh random 32-digit
lowercase hex transaction identity. Records have strict types and at most 65536
UTF-8 bytes. They contain no password, code, credential ID or display label.
Malformed/foreign records fail closed and remain retained. Protected product
records are never ordinary settings, logs, journals or Git fixtures.

Explicit sign-in withdraws private prior state, reads/validates any old record,
and removes only that read revision before sending credentials. CAS owner
change fails closed. Challenge results retain only the expected private account,
credential and challenge identities; they perform no account lookup or write.
Verification consumes that challenge and checks both account and credential
before account lookup. New login, attempted verification, logout and close clear
the private challenge.

Login/verification and rotated pairs use ACCESS to prove the exact account
before returning a staged completion. Its `persist` writes with
`expectedRevision: null`; conflicts never overwrite or retry. `accept` has no IO
and synchronously activates that exact candidate at the client publication
boundary. Unaccepted `discard` releases the candidate and removes only its own
returned write revision. A late write is rolled back before cancellation drains.
An indeterminate write gets one bounded read; only the full matching
profile/base/product writeId record may be conditionally removed. A newer or
foreign owner survives. Cleanup errors stay observable and do not imply cleared
storage. Failed rollback of an unaccepted own write withdraws active/challenge
state and retains an unresolved-cleanup flag plus a token-free local clearance
witness: product `writeId`, account and the known native revision. An
indeterminate native write whose rollback read also fails retains that witness
without a revision. Baseline-only restoration and a write CAS conflict do not
grant residual-write ownership. The witness contains no credential pair, record
or byte copy and cannot authorize authentication or remote logout.

While unresolved, login, verification, refresh and restoration are rejected
before disk reads or HTTP; neither retained bytes nor a new command can revive
the candidate. Client cancellation reports its fixed safe cleanup failure and
blocks restoration/sign-in. Close reports its fixed safe failure after draining
and releasing owned resources, without implicitly retrying removal. Protected
bytes may remain when native IO fails; this is no claim of durable erasure or
remote revocation across process loss. No path calls unconditional native
`clear()`.

Explicit refresh requires the accepted active pair. It withdraws private state,
reads/verifies the exact owned record revision and removes it via CAS before
sending the old REFRESH in the body. Rotation validates the exact same account
with new ACCESS and uses a fresh staged commit. Refusal, unknown rotation or a
changed account never reactivates the old pair.

## Explicit restoration and logout

Restoration reads only when called explicitly. Empty storage returns null with
no HTTP/write. Matching bytes must prove their exact account with stored ACCESS.
Successful proof returns a no-write staged completion whose persistence rereads
and checks the original revision before acceptance. Discard never removes that
baseline. Account 401 conditionally removes that identified old record, refreshes
once, then proves the account and stages a new replacement. Account 403 removes
only the identified invalid own record without refresh. Other failures do not
authenticate; transient transport/5xx retains the baseline for later explicit
restoration. No label is restored from disk.

Logout withdraws active pair/challenge synchronously. Local clearance retains a
token-free selection of the exact native revision, product writeId and account,
or a known-empty selection. Explicit sign-in/restoration selects its validated
baseline and session acceptance updates that selection. A fresh backend without
a prior selection selects only the first validated slot or known-empty state.
Conditional removal requires the present record to match the selected revision,
writeId and account. Repeated logout retains that selection after success or
failure; it cannot adopt a newer owner or a record arriving after known-empty
selection. Empty storage is locally cleared; failed IO/CAS or still-present
newer/foreign records are not. Only the accepted pair captured for the current
logout call authorizes remote current-session logout; retries do not retain
usable tokens and unvalidated disk bytes never authorize remote logout.
An explicit logout may retry unresolved staged cleanup once against its retained
local witness. A known revision must still match exactly. For an indeterminate
write with no known revision, the present validated profile/base record must
match the exact own product `writeId` and account; removal uses that read's
current native revision in CAS. A different owner survives without adoption,
removal or remote use. Only successful local clearance resolves the backend's
unresolved-cleanup flag and the client's staged-cleanup admission barriers;
failed IO or local-not-cleared results retain them. This explicit retry sends no
remote logout for an unaccepted pair and never retries automatically.
Local clearance is independent
of remote revocation: exact zero-byte HTTP 200 is `confirmed`; non-200/nonempty
is `failed`; uncertain transport is `unknown`; no accepted pair is
`notAttempted`. There is no logout-all, automatic retry, queue/draft/capture deletion or
refresh-as-access fallback.

## Connected acceptance still required

Synthetic host specifications exercise the real client/backend and the existing
store through a mocked native revision-CAS channel and controllable HTTP streams.
They are authored specifications, not execution receipts. The parent owns
validation and independent review of the whole connected Step, Framework facade
and normal App profile/startup restore integration. Queue credential/ownership
integration and actual Android/iPhone identity, owner-correct submission and
logout remain required subsequent integrated acceptance. These ten Core files
are not independently accepted authentication or whole-Phase completion.
