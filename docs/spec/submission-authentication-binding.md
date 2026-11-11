# Local submission authentication binding

This document specifies ESA610-UA-SUBMISSION-001 / CORE-BINDING-01. It is an
unaccepted implementation Slice in the connected Phase 6.10 Step. Its values
retain immutable participant intent and fence a single claimed queue operation.
They provide no credential, verified login, server authorization, or public TKL
trust contract. Production authenticated composition remains subsequent work.

## Immutable identity

`SubmissionAuthenticationBinding` snapshots `UserAccountHttpProfile.profileId`,
the profile's canonical `serviceBaseUri` as `authorityBaseUri`, and the exact
opaque nonblank `userAccountId`. Account validation is the existing
`AuthenticatedUserAccount` validation. Unicode, whitespace and punctuation are
retained; Core derives no server principal or `owner_id`. Equality and hashing
include all three fields. The value retains no credential, challenge, scope,
session, clock or authority client. Its diagnostic is the fixed type name.

The closed binding JSON schema has precisely these fields:

```json
{
  "version": 1,
  "authorityProfileId": "authority.main",
  "authorityBaseUri": "https://authority.example/account/",
  "userAccountId": "opaque account identity"
}
```

Encoding returns a fresh detached map. Decoding uses the shared safe JSON
helpers and the existing `UserAccountHttpProfile.fromString` parser. The base
string must equal the resulting canonical URI spelling; absent trailing slashes
and other noncanonical stored identities are rejected without repair. The
parser's development HTTP switch is used only to interpret a retained
LAN/loopback identity. It grants no runtime HTTP permission. Missing/extra keys,
unknown versions, bad types, unsafe profiles/bases and blank accounts produce
safe fixed errors without reflecting input.

`SubmissionAuthenticationContext` retains a binding and a borrowed synchronous
`isCurrent` callback. Construction invokes nothing. Its getter returns false
when the callback throws. Its diagnostic is the fixed type name. The context
has no credential access or owned lifetime to close. A subsequent real
authenticated composition must supply it explicitly.

## Request and persistence compatibility

`SubmissionRequest.authenticationBinding` is optional and defaults to null. It
participates in immutable equality/hash identity alongside the existing ordered
materials and opaque JSON. A different account, profile, base, or bound/unbound
identity cannot replace a previously enqueued Commit with the same ID. Existing
SQLite idempotence and subject uniqueness enforce that conflict without adoption.

| Local request | Encoding |
| --- | --- |
| Unbound legacy storage route | Existing exact v1, with no binding/TKL key |
| Unbound TKL route | Existing exact v2, with its unchanged nonnull TKL value |
| Bound route | Closed v3, existing common keys plus nonnull `authenticationBinding` and required `tklDelivery` |

In v3, `tklDelivery` is null for the legacy storage route and otherwise uses its
existing codec unchanged. Null/missing/invalid binding, missing TKL slot,
malformed nonnull TKL value, extra keys and unknown versions are rejected.
Reading v1/v2 produces a null binding and does not adopt, upgrade or rewrite
stored intent. Record codecs v1–5, SQLite database v2 and all TKL and
RegisteredMaterial wire schemas remain unchanged.

The server packet retains exactly its existing v1 selected fields: `version`,
`requestId`, `kind`, `subjectId`, `createdAt`, `payload`, `extensions`, and ordered
`materials` with receipts. Local document, participant binding and authority
identity are excluded.

## Claimed-operation dispatch fence

`SubmissionService` borrows optional `authenticationContext`. Construction and
lifecycle hooks perform no authentication IO. Commit remains explicit local
intent: it can validate originals, persist a bound request and request the usual
wake without a context or network operation. Equal duplicate and conflict
semantics remain unchanged.

An offline `processNext` returns before callback, queue, original or adapter
work. Online processing first checks the ordinary caller predicate, then uses
the existing `claimNext` as its first selection. Once an actual record is owned,
participant admission occurs before original reads, reference-policy work or
storage/TKL/transport work:

| Request binding | Borrowed context | Result |
| --- | --- | --- |
| Absent | Absent | Complete legacy path; no new callback |
| Present | Absent | Denied |
| Absent | Present | Denied; no adoption |
| Present | Different profile/base/account | Denied |
| Present | Equal, withdrawn or throwing | Denied |
| Present | Equal and current | Admitted for this claimed operation |

Initial denial uses the existing failure path with configuration stage,
`authenticationRequired`, retryable false, and the fixed message
`Sign in to the account bound to this submission.` The ordinary caller
predicate remains active while this denial persists. Accepted immutable intent,
originals, reservations, receipts and previous uncertainty remain retained. A
denial cannot create an acknowledgement or clear an older unknown dispatch.

After admission, one local predicate captures the original caller predicate,
the exact request binding and the same borrowed context. All existing
`processNext` guards, renewals, reference-access checks, catch paths and the
existing TKL predicate plumbing use it. No global current-request state or new
account is captured. Context withdrawal follows the existing cancelled/release
route; late success and error completions are observed and discarded without
publishing a late reservation, receipt, progress or ACK. Existing remote effects
may already have happened. Reservations/checkpoints and transport uncertainty
remain available for same-intent reconciliation; cancellation asserts no remote
rollback. Explicit retry by B cannot turn an A-bound request into B's intent.

## Executable scenario map

These are authoring references, not execution receipts. Every scenario has
adjacent semantic Given, When and Then clauses in the two new test files. The
fixtures use real FileCaptureStore originals and SQLite handles; controlled
ports provide synthetic facts without a real authentication provider.

`test/submission/submission_authentication_test.dart`:

| Scenario | Given | When | Then |
| --- | --- | --- | --- |
| Opaque identity/inert values | Canonical profile, Unicode/whitespace account, throwing callback | Construct values; explicitly observe lifetime | Exact fields; zero constructor calls; safe names; false on callback error |
| Equality/hash | Equivalent identity and distinct account/profile/base values | Compare and use set keys | Equal hash; all identity edges separate |
| Blank accounts (2 cases) | Valid profile, blank ID | Construct binding | Existing safe nonblank rejection |
| Detached/development identity | Canonical LAN identity | Round trip and mutate input/output maps | Immutable exact identity and fresh encodings |
| Closed binding schema (18 cases) | Missing/extra/type/version/unsafe/noncanonical inputs | Decode each retained value | Safe FormatException without marker reflection |
| Bound local v3 (2 routes) | Saved photo/audio and opaque consumer data | Encode/decode and mutate output | Exact v3 keys, immutable identity/order, independent binding |
| Legacy v1/v2 (2 cases) | Unbound request | Encode/decode | Exact expected JSON and omitted keys; no adoption |
| Invalid request schemas | Valid v3 plus malformed copies | Decode | Missing/null/invalid binding, malformed TKL, extras and unsupported versions rejected |
| Server packet | Bound originals and controlled receipts | Encode packet | Exact unchanged v1 shape; no local document/binding/authority |
| SQLite bound identity | A-bound real row | Reopen/equal enqueue; offer account/profile/base/unbound conflicts | Idempotence; immutable intent retained without overwrite |
| SQLite unbound identity | Old unbound row | Reopen and offer bound same ID | Conflict; persisted v1 remains unbound |

`test/submission/submission_service_authentication_test.dart`:

| Scenario | Given | When | Then |
| --- | --- | --- | --- |
| Inert/offline (2 callbacks) | Bound row and counting/throwing context | Construct service; offline pump | No callback, queue call, originals or adapters |
| Context-free Commit | Bound saved originals | New/equal/conflicting Commit | Local validation/enqueue/wake; duplicate avoids reads; conflict preserves row |
| Initial denial (7 cases) | Missing/wrong-account/wrong-profile/wrong-base/withdrawn/throwing/legacy-context combination | Claim online and reopen native row | Durable fixed configuration failure; no original/adapter/reference work; bytes and intent retained |
| Same A/reopen/B retry | A and actual saved photo/audio | Reserve; reopen as B; retry B; explicitly continue A | B denied without adoption; A finishes ordered prepare/upload/ACK and persisted ownership |
| Late reservation/error (2 cases) | A with held storage prepare | Withdraw before future success/error | Cancelled/released; no late progress/failure/ACK |
| Late upload receipt | Prepared A originals and held upload | Withdraw, complete upload, then claim as B | Receipt discarded; reservation/bytes retained; B denied without another upload |
| Late ACK/uncertainty | A with held transport after dispatch checkpoint | Withdraw; complete ACK; deny B; explicitly retry A | No late ACK; older uncertainty survives B; only A reconciliation completes |
| Legacy unknown | Real SQLite row imported through exact old record schema | Participant context claims then reopens | Legacy unknown checkpoint survives denial with no invented attribution |
| Caller cancellation | Bound row, false caller predicate | Online pump | No claim or auth callback |
| Legacy compatible | Unbound originals and no context | Existing five stages and reopen | Unchanged prepare/upload/ACK and v1 intent |
| TKL initial denial | Bound originals and configured controlled client | B claims A | No find/destination/prepare/read; durable denial |
| TKL withdrawal/continuation | Matching A and held prepare | Withdraw before reply; same A reconciles correlation | No late progress; actual bytes later register through existing stages without a Studio ACK |

Services close before borrowed queues. Held operations use explicit completers;
there are no sleeps or duration-based polling loops, global factory changes or
target-platform overrides. Expected failures are explicitly asserted.

## Subsequent connected-Step work

The parent owns execution of the new tests and the selected existing submission
model, queue, service, TKL, dispatch-recovery and RegisteredMaterial handoff
suites, targeted analysis, diff verification and independent protected review.
This authoring Slice does not establish their results or Step acceptance.

Real credential/trust composition, authenticated adapter integration,
RegisteredMaterial handoff account propagation, native/platform/App/UI wiring
and complete accumulator review remain subsequent work. Root sending stays
gated. There is no new public TKL trust design, principal derivation, native
store, DB table/migration, server wire change, background policy change,
publication, commit or partial native installation in this Slice.
