# Authenticated submission transports

`HttpSubmissionTransport` and the service-operation paths of
`TklMaterialDeliveryHttpClient` select credentials from immutable local participant
intent and an explicitly configured typed HTTP connection. Construction is inert:
it performs no credential, native-store, HTTP, login, consent or scheduling work.
Clients and credential providers remain borrowed.

## Selection before credential IO

| Local binding | Provider | Connection | Selection |
| --- | --- | --- | --- |
| Present | `AuthenticatedSubmissionCredentialProvider` | Bearer required | Call only `bearerTokenFor` with the exact binding and typed connection |
| Present | Legacy provider | Any | Deny with `authRequired` before lookup or send |
| Present | Any | Anonymous | Deny with `authRequired` before lookup or send |
| Absent | Advanced provider | Any | Deny with `authRequired` before either provider method or send |
| Absent | Legacy provider | Bearer required | Preserve the existing id-only `bearerToken` lookup |
| Absent | Legacy provider | Anonymous | Preserve credential-free packet dispatch |

An advanced lookup never falls back to the legacy method, including after null,
invalid syntax or failure. An old unbound queue entry cannot adopt the current
account. Packet target matching precedes credential selection for both v1 and
Registered Material v2. The existing strict HTTPS and authenticated TKL root
requirements remain in force.

## Local intent and wire contract

The v1 packet uses `packet.request.authenticationBinding`; the Registered Material
v2 packet uses `packet.sourceRequest.authenticationBinding`. The TKL client's
optional immutable `authenticationBinding` captures the local actor selected by
composition. Every service call, including discovery, prepare, lookup, status,
finalize and multipart upload, selects against that same configured typed service
root. A response, delivery reference, destination or derived operation URI cannot
create or replace the binding.

The binding is local participant intent, never a server owner assertion. Existing
packet serializers, ACK identities, idempotency keys, JSON and multipart fields
stay unchanged. No account, authority, scope or owner headers are added. The sole
credential header remains `Authorization: Bearer <ACCESS>` on the explicitly
selected service request. Refresh credentials are never forwarded by the concrete
account scope.

## Lifetime, safe failure and uncertainty

Selection and lookup use the existing operation checks, cancellation, monotonic
total deadline and late-error observation. Credential wait and HTTP response
reading share one deadline; selection adds no timer, retry or refresh. Invalid or
missing tokens produce safe configuration `authRequired`; provider exceptions
produce safe retryable `credentialUnavailable`. Raw causes and credentials are
excluded from error text and receipts, and no logging is introduced. Cancellation
and timeout retain precedence through operation checks.

Packet failure before potential dispatch is `notSent`. Once a request may have
been sent, a retired predicate, deadline or late ACK cannot create acceptance;
uncertainty stays `unknown` except for the existing conclusive authorization
refusal rules. TKL mutations failing before send have `outcomeUnknown == false`.
Cancellation cannot roll back a remote effect already in progress.

`UserAccountSubmissionScope` retains its existing accepted-account/native-owner
and run lifetime. It supplies only ACCESS for the exact binding and declared
endpoint. Logout, refresh, replacement login, close or run withdrawal retire the
old scope; a later explicit admission requires a fresh scope. Transport selection
does not change that lifecycle or establish server trust. An endpoint declaration
is local configuration, not proof that TKL or Studio accepts that authority's
tokens or authorizes the account for a resource.

## Direct provider upload and remaining gates

`uploadDirect` and `uploadDirectStream` use only the supplied narrow provider
session. They never look up UA or legacy credentials and never attach an
Authorization header, including later chunks. Exact bytes, confirmed offsets,
ranges, narrow instruction validation and redirect refusal remain unchanged.
Their existing caller cancellation/current predicates must be supplied by
composition; this Slice alone does not authorize a local queue actor for direct
upload. The legacy Drive adapter is unchanged. The concrete account scope's
id-only legacy port returns null, so it cannot supply UA ACCESS to Drive.

Registered handoff integration, platform/native protected-store acceptance,
App composition and account/run fences, and server-side authority verification
and resource authorization remain separate gates. TKL/CNCF/Studio producers own
server trust development. This transport Slice supplies no generic Authorization
forwarding, URL trust inference, redirect following, cross-account queue adoption
or server acceptance beyond the existing strict matching ACK contract.

Executable specifications are in
`test/submission/authenticated_submission_transport_test.dart`, using synthetic
credentials, controlled HTTP and a test-local native CAS seam through the actual
backend, authentication client, native store and submission scope.
