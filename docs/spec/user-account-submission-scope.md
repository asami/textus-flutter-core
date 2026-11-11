# UserAccount submission scope

This document specifies ESA610-UA-SUBMISSION-001 / CORE-SCOPE-02 in the same
connected Phase 6.10 Step as CORE-BINDING-01. It defines a Core-owned credential
port borrowing actual accepted UserAccount authentication. Source authoring does
not establish connected-Step acceptance, real server trust, or phone acceptance.

## Public API and local identity

`AuthenticatedSubmissionCredentialProvider` is an optional extension of
`SubmissionCredentialProvider`. Its additional method is:

```dart
Future<String?> bearerTokenFor({
  required SubmissionAuthenticationBinding binding,
  required HttpSubmissionConnection connection,
});
```

The existing `bearerToken(String connectionId)` interface and implementations
remain source compatible. The new interface alone proves no authenticated
identity. `UserAccountHttpAuthenticationBackend.createSubmissionScope` is the
Core factory:

```dart
UserAccountSubmissionScope createSubmissionScope({
  required Iterable<HttpSubmissionConnection> trustedTargets,
  required bool Function() isRunCurrent,
});
```

The returned final `UserAccountSubmissionScope` has a private constructor. Its
public readonly `context` and `binding` retain only the existing local submission
identity: this backend's exact profile ID, canonical authority base, and actual
accepted opaque account ID. No account argument or display-label inference is
available. Scope diagnostics are the fixed `UserAccountSubmissionScope` type
name. Credentials, native storage and ownership witnesses remain private.

Construction requires an accepted backend session, no closed/busy/pending state,
and no unresolved staged-write cleanup. A challenge, saved bytes alone, or an
unaccepted session candidate cannot create a scope. Construction performs no
native/network IO, authentication, restore, refresh, or callback invocation. It
rechecks accepted ownership after iterating caller-provided targets, so
reentrant authentication or close cannot escape admission.

## Explicit credential recipients

The factory snapshots 1–128 unique `HttpSubmissionConnection` definitions into a
private immutable map. Every definition must require a bearer token; the existing
typed connection constructor enforces HTTPS. Empty, duplicate, anonymous,
over-limit or failing iterables are rejected safely. Each later lookup must match
the supplied binding and the target's exact id, endpoint and bearer requirement.
Same origin, similar URLs, connection labels and environment configuration never
infer recipients. Mutating the caller's original list cannot retarget the scope.

`trustedTargets` is an operator declaration of intended credential recipients.
It is not evidence that a server realm accepts or permits UserAccount ACCESS.
The subsequent producer handoff/configuration must supply the accepted recipient
set before normal runtime activation. No new issuer, public server route, TKL
trust contract or principal mapping is derived here. A Google Drive resumable
instruction is not such a target; this Slice grants no UserAccount ACCESS to
Drive.

Wrong bindings or recipient definitions return null before callback/native/HTTP
work and do not retire an otherwise valid scope. The scope's legacy id-only
`bearerToken` always returns null without callback or IO.

## Token-free lifetime and no revival

A private witness retains only the accepted native revision, product write ID,
opaque account ID and an in-memory authentication epoch. It holds no record,
session ID, ACCESS or REFRESH token. The epoch is local product lifetime state;
it is neither native storage schema nor persisted submission identity.

The epoch advances when an authentication action passes the existing operation
guard and is admitted, when sign-out synchronously withdraws the active owner,
and on first backend close. Busy/pending/unresolved-cleanup admission and the
existing client/session-commit publication barriers retain their semantics.

`context.isCurrent` checks internal owner/profile/binding/account/epoch state
before and after invoking the borrowed run callback. Closed, busy, pending or
unresolved-cleanup state denies ownership. Callback errors become false. A
callback that starts logout, refresh or close while returning true cannot admit
credentials. Once false is observed, the scope permanently retires. False then
true cannot renew it. These checks perform no IO.

An explicit restore through another client borrowing the same backend retires
old scopes even when exactly the same saved record and revision are accepted and
the old scope was never polled during restore. Same-account logout/login and
refresh also cannot revive an old scope. A newly admitted scope can resume the
same immutable queue binding, because session identity and epoch are absent
from that persisted binding.

## Readonly protected credential lookup

After exact request and current-scope checks, the backend reserves a normally
completing tracked drain before dispatching its native read, including reentrant
dispatch. Each lookup reads the existing protected profile once. It performs no
UserAccount HTTP, write, remove, clear, refresh or retry.

After the read, the scope/current epoch and exact active in-memory session
identity are rechecked. The existing record decoder validates the returned
protected value. Its native revision must equal the witness revision, and its
entire record must equal the still-accepted backend record, including product
write ID, account and both session/token pairs. Missing or valid changed records
return null. They are never adopted, refreshed or erased, and another owner's
token cannot be returned. Only the backend's own accepted ACCESS token can leave
through this port. REFRESH, passwords, verification codes, records and session
metadata are never returned.

Readonly native/record failures while still current yield only
`StateError('Submission credentials are unavailable')`, without raw input or a
cause. A still-current scope can be explicitly retried after native read
recovery. Retirement during IO returns null, including a read that fails after
close. Returned futures are observed for abandoned callers while preserving the
same safe result/error for awaiters. Every reserved drain completes normally;
readonly failures alone do not become staged-write cleanup failure.

No new timeout policy exists. The later transport operation owns its total
credential-plus-HTTP deadline/cancellation. Native storage keeps its existing
accepted-call drain contract. A late lookup result never grants permission to
dispatch after the caller's operation retires.

## Close ownership and drain

First backend close synchronously advances the epoch and withdraws active
ownership, preventing new credential lookups. It captures outstanding lookup
drains and retains the existing auth-work, pending-candidate and unresolved
cleanup behavior. Owned HTTP close and owned native close are each attempted
once even when another cleanup attempt fails.

Owned native `close` must be called before awaiting readonly lookup drains: its
existing contract dispatches native retirement before draining accepted calls.
The backend then joins all reserved readonly work. A borrowed store/client is
never closed by the backend, but accepted readonly lookup work still finishes
before backend close completes. The explicit owner cleans borrowed handles.
Close causes no implicit logout, credential erasure or foreign-owner adoption.

Actual native close failure preserves the backend's existing safe failure
outcome; client wrapping remains the existing authentication-close failure.
Repeated backend close returns the same future. Late tokens/results cannot
revive closed or retired scopes.

## Executable scenario map

`test/authentication/user_account_submission_scope_test.dart` uses the genuine
HTTP authentication backend and authentication client, a controlled synthetic
HTTP client, and the existing mocked native MethodChannel/CAS seam. A forwarding
seam only holds a genuine unaccepted backend candidate. Fixtures use synthetic
accounts and tokens. Held work uses explicit completers; expected errors are
captured from executed operations. Test cleanup restores native mocks and
platform overrides after handle cleanup. This table is an authoring map, not an
execution receipt.

| Given | When | Then |
| --- | --- | --- |
| Signed-out, challenge, closed, busy, unaccepted or unresolved-cleanup state | Request scope admission | Fixed safe failure; no callback or extra IO |
| Accepted login and mutable explicit target list | Construct scope, mutate caller list, then look up original target | Exact opaque identity; inert construction; safe diagnostics; one readonly ACCESS lookup |
| Empty, duplicate, anonymous, failing or 129-target iterable | Construct scope | Fixed safe argument failure without input/cause or callback |
| 128 unique operator targets | Probe outsider and use final declared target | No inferred recipient; declared endpoint works |
| Target iterator closing backend | Construct scope | Post-iteration owner recheck denies escape |
| Wrong account/profile/base/id/endpoint/auth flag | Probe advanced and legacy ports, then exact request | Null without IO/callback; valid scope remains usable |
| Missing protected slot, B owner, changed pair or write ID | Lookup through A's scope | Null; no adoption, write, removal or binding mutation |
| Another real client borrowing same backend | Restore same saved record without polling old scope | Old epoch retired; fresh scope resumes identical binding |
| Unobserved old scope | Refresh or same-account logout/login | No revival; fresh scope returns current ACCESS |
| False/throwing run fence | Observe denial, then change to true | Permanent retirement; fresh scope required |
| Callback starting close/logout/refresh and returning true | Request token | Post-callback ownership check denies |
| Held native readonly lookup | Complete logout/refresh before releasing old read | Null late token; newer auth and protected state preserved |
| Native error or invalid record with private marker | Execute/capture lookup, recover, explicitly retry | Fixed safe error; no extra HTTP/CAS; retry can work |
| One/two held default-owned readonly lookups | Close before releasing reads | Native retirement and HTTP close precede drain; all reads joined; no late token/erase |
| Held lookup with borrowed handles | Close backend, release read, owner cleans handles | Backend joins work and preserves borrowing |
| Native handler reentering backend close | Dispatch protected read | Lookup was already reserved; close joins it |
| Owned native close failure with held read | Execute/capture close and release read | Honest safe close failure; HTTP cleanup attempted; same repeated future |
| Abandoned readonly lookup | Fail native read, then close backend | Error observed internally; readonly drain is normal cleanup |

## Remaining connected-Step gates

The parent owns the new scope suite, requalification of the existing four
auth/native suites, relevant connections tests, targeted analysis, exact diff
verification and independent protected focused review of the connected Step.
Initial binding evidence can be readmitted only after the parent checks its
actual import/API edges. This source document asserts no validation result.

Actual authenticated transport/adapters, registered handoff, default platform
compositions and App wiring remain subsequent frozen Slices. Producer trust and
recipient configuration, native/platform acceptance and the whole connected-Step
review remain required before runtime activation. This API alone cannot activate
participant sending. There is no native schema, server wire, actor registry,
persistence, auth retry policy, deployment, publication or commit change here.
