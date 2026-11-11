# Internal UserAccount HTTP object codec v1

This specification adopts a bounded root-object subset for the internal Core
authentication backend. It complements the
[authentication client contract](user-account-authentication-client.md).
`lib/src/authentication/user_account_http_wire.dart` is internal and is not
exported by the package root. It performs no HTTP, storage, credential lookup,
session issuance, logging, scheduling, platform access or client-state mutation.
Decoded data alone does not establish authentication authority.

## Adopted password-login subset

`decodeUserAccountHttpLogin(Object? document)` accepts an already decoded JSON
object with string keys. Responses are root objects, without a `data`, `body` or
capture-wrapper envelope. Exact boolean `authenticated` selects one of two
closed shapes; missing, additional, mixed or camelCase fields are invalid.

| Result | Exact root keys and values |
| --- | --- |
| `UserAccountHttpWireSessionPair` | `user_account_id`, `credential_id`, `access_session_id`, `access_token`, `refresh_session_id`, `refresh_token`, `authenticated: true` |
| `UserAccountHttpWireChallenge` | `user_account_id`, `credential_id`, `two_factor_required: true`, `challenge_id`, `channel: "email"`, `authenticated: false` |

Every non-flag field is a required string. A challenge has no session/token
pair and never constitutes authentication. Unsupported channels, string/numeric
flags, nulls, wrong types and error-bearing login records are invalid. These
shapes apply to initial password login. Verification accepts only the same exact
seven-key authenticated pair, never a new challenge. The backend additionally
checks both expected account and credential identities retained privately from
the challenge before requesting the account.

UserAccount, credential, access/refresh session and challenge identities are
opaque. Preserve each exact string without trimming, parsing or deriving an
EntityId, UUID or principal. An identity must be nonblank, contain at most 4096
UTF-8 bytes and contain no ASCII C0 character (U+0000 through U+001F) or DEL
(U+007F). Surrounding spaces in a nonblank identity remain significant.

Tokens have 1 through 8192 characters and must match the entire b64token form
`^[A-Za-z0-9._~+/-]+=*$`. Padding is allowed only at the end; whitespace,
controls, interior padding and trailing newlines are invalid. The full match
must equal the input, including at the final character. These bounds are local
defensive codec limits, not producer expiry or session-lifetime claims.

## Refresh and current-session logout

`decodeUserAccountHttpRefresh(Object? document)` accepts a distinct closed
six-key root: `user_account_id`, `access_session_id`, `access_token`,
`refresh_session_id`, `refresh_token`, `authenticated: true`. Every other field
is a required string under the same opaque/token rules. Missing, extra, mixed,
null or mistyped fields fail. In particular `credential_id` is absent; a
`UserAccountHttpWireRefreshPair` does not fabricate one and is not a login DTO.
Its diagnostic is exactly `UserAccountHttpWireRefreshPair`. Login's seven-key
check remains unchanged.

The native backend sends `POST verify-two-factor-login` with
`{challengeId, code}`, `POST refresh-access-token` with `{refreshToken}`, and
`POST logout` with `{userAccountId}` relative to its explicit service base.
Verification and refresh carry no Authorization or Cookie; logout uses only the
current accepted ACCESS Bearer. Refresh is never protected access. Logout
confirmation requires HTTP 200 and exactly zero response bytes; JSON `null`,
`{}`, whitespace and wrapper objects do not confirm revocation. The backend
owns status/byte handling rather than passing logout through an object decoder.

## Expected-account projection

`decodeUserAccountHttpAccount(document, expectedUserAccountId: ...)` accepts an
open ResourceAttributes root object with string keys. Required `id` and the
expected identity both obey the opaque-identity rules and must be exactly equal.
Any root `error` key rejects the record, regardless of its value or a valid `id`.
Other attributes are allowed and ignored. `owner_id` and public principals do
not substitute for account identity.

Optional `handle` alone supplies `AuthenticatedUserAccount.displayName`. Absent
or null yields null; a present non-null handle must be a string of at most 4096
UTF-8 bytes. Preserve its exact value, including empty or blank strings. No
fallback uses name, email, login name or request labels. The projection contains
only the exact `userAccountId` and optional display name; it retains no raw
attributes, credentials, tokens or session references.

## Isolation and diagnostics

Neither decoder modifies or retains the input map. Results hold validated final
strings only; later map mutation cannot change them. Wire DTO constructors are
module-private, and these types have no serialization facility. Their diagnostics
are exactly `UserAccountHttpWireSessionPair` or `UserAccountHttpWireChallenge`.
All invalid input, including null/scalar/list roots or non-string keys, produces
the same fixed `UserAccountHttpWireException(invalidResponse)` diagnostic. The
exception retains no input, cause, identity, token, URI or diagnostic payload.

The behavioral specification in
`test/authentication/user_account_http_wire_test.dart` uses independently authored
synthetic objects and semantic Given/When/Then scenarios. It does not read or
reproduce private execution captures. Authored specifications require parent
validation and independent review; this document is no execution receipt.

## Remaining integration gates

This pure codec completes only its internal object-decoding role within the
complete authentication backend Step. JSON byte decoding and byte-level limits,
trusted HTTP transport, headers/status/error/redirect policy, operation-lifetime
checks and credential-backed authoritative account lookup remain transport and
backend responsibilities before authenticated state publication or token
persistence. No unverified status mapping or error envelope is inferred here.

The native verification, refresh and zero-byte current-session logout shapes
above are adopted by the [concrete backend](user-account-http-authentication-backend.md).
The codec remains an internal part of that connected authentication Step. App
binding and account-safe queue ownership remain required. Composed Studio
and CNCF validation/review, live endpoint/Origin/CORS and participant configuration,
and physical Android/iPhone authentication and owner-correct delivery acceptance
remain separate gates. This codec does not complete the backend, native
authentication, delivery or the whole Phase.
