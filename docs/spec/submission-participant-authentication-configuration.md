# Participant submission configuration

`SubmissionParticipantAuthenticationConfiguration` is immutable operator intent
for one real UserAccount authority and an explicitly ordered set of trusted
submission connection IDs. The model contract belongs to
`ESA610-UA-SUBMISSION-001 / CORE-CONFIG-05`; native configuration persistence is
implemented under `CORE-NATIVE-CONFIG-06` in the same connected Phase 6.10 Step.
Neither change activates authenticated runtime composition or establishes
server trust, deployment qualification or partial Step acceptance.

## Authority and target value

The named constructor requires `String authorityProfileId`,
`String authorityBaseUri` and `List<String> trustedConnectionIds`. It validates
the raw profile/base through `UserAccountHttpProfile.fromString` with its default
HTTPS policy. Development HTTP is not enabled. The stored profile ID is the
validated profile's exact ID; the stored base is its canonical immutable `Uri`.
Only that parser's defined canonical base construction is permitted. Inputs are
not otherwise trimmed, repaired or normalized.

Trusted IDs use the existing submission `j.token` policy. There must be 1–128
unique IDs, in the supplied order. The list is defensively copied and deeply
immutable. The complete encoded definition must fit 65536 UTF-8 bytes. Invalid
constructor input produces exactly
`ArgumentError('Invalid participant submission configuration')` with no retained
raw value, name or cause. Equality and hashing include the profile, canonical
base and ordered IDs. The diagnostic is only the fixed type name.

The `authority` getter creates the corresponding `UserAccountHttpProfile` with
the existing default request timeout. Construction and projection perform no
IO, credential access, login, refresh, retry, session creation or environment
lookup. No `allowDevelopmentHttp`, timeout or other runtime option is persisted.
There is no principal/account map, alternate issuer or inferred server realm.

The exact closed v1 JSON definition is:

```json
{
  "version": 1,
  "authorityProfileId": "operator.main",
  "authorityBaseUri": "https://authority.example/account/",
  "trustedConnectionIds": ["server"]
}
```

`toJson` returns a fresh detached map and list. `fromJson` uses the shared safe
`j.decode`/closed-schema conventions. Missing/extra keys, unknown versions,
nulls, wrong types, invalid identities/targets, duplicates and bounds violations
produce a safe `FormatException`. The retained base string must already equal
the parser's canonical URI spelling. For example, an explicit constructor input
ending in `/account` can become `/account/`, but retained JSON ending in
`/account` is corrupt and is rejected. Decoding never repairs stored identity or
substitutes an empty declaration.

## Whole-snapshot admission and compatibility

`SubmissionConfigurationSnapshot.participantAuthentication` is an optional
readonly value and defaults to null. Every trusted ID must match an exact
registered `httpConnections` entry whose `requiresBearerToken` is true. Missing,
Drive-kind and anonymous targets are invalid. A nonnull selected transport in
participant mode must itself be one of the explicit trusted IDs. A null
transport selection is valid. Whole-snapshot validation completes before the
snapshot is published.

Same-origin URLs do not grant membership. The independent
`referenceAccessBindings` map continues to describe server resolver access to
Drive storage only. It neither supplies nor expands participant trust. A
participant declaration needs no reference-access entry. Existing resolver
binding validation and bounds remain in force.

| Input/state | Required codec behavior |
| --- | --- |
| Legacy v1 snapshot | Existing exact five keys; null participant mode; no adoption of existing HTTP targets |
| Existing v2 snapshot | Existing exact six keys including `referenceAccessBindings`; null participant mode |
| Null participant mode on encoding | Byte-for-byte existing v2 map shape/order with no new nullable key |
| Nonnull participant mode | Closed v3: existing six keys plus nonnull `participantAuthentication` containing the closed v1 DTO |
| Corrupt v3 | Reject missing/extra keys, missing/null/invalid participant value, missing/invalid references, bad target membership, wrong types and unknown versions |

Reading v1/v2 preserves existing definitions and selections, retains v2 resolver
bindings, and never infers a participant declaration. V1 continues its existing
empty-reference projection when later encoded as v2. V3 freezes and detaches
targets, selections, references and participant values. Queue/request/record and
server packet schemas, native SQL schema versions and accepted queued intent
remain outside this change. There is no database version bump.

## Optional persistence capability

The existing `SubmissionConfigurationStore` interface is unchanged. External
base implementers remain usable without a new member. The separate optional
`SubmissionParticipantConfigurationStore implements SubmissionConfigurationStore`
declares:

```dart
Future<void> setParticipantAuthentication(
  SubmissionParticipantAuthenticationConfiguration? configuration,
);
```

An implementation must atomically validate and replace the declaration against
the complete current snapshot. Explicit null clears only this declaration; the
subsequently persisted snapshot uses ordinary v2. Every setter must preserve
target definitions, selection, resolver reference bindings, queued intent and
native credentials. An invalid complete result leaves the previous committed
state intact. A different operator profile is explicit future intent. It must
never retarget old queue rows, erase credentials or silently adopt credentials
from another authority/account.

Both `AndroidSubmissionConfigurationStore` and
`IosSubmissionConfigurationStore` implement this optional capability alongside
their existing borrowed credential port. Unknown or absent native capability
remains `configurationUnavailable`; there is no ephemeral fallback. Factories,
App composition and operational trust still require their connected gates.

## Native persistence contract

Android sends exactly `setParticipantAuthentication` with the sole argument
`configuration`, containing the shared DTO's closed JSON or explicit null.
Missing/extra native argument keys are invalid. Construction remains inert and
the Android platform guard remains in force even for an injected channel. The
method reuses existing configuration acquisition, serialized IO, generation
checks, single replies and native draining. It introduces no credential context,
timeout, logout, permission, scheduling or close path.

The existing authenticated encrypted selection singleton accepts exact old
versions 1 and 2 without rewriting them on read or adopting their HTTP targets.
Selection v3 contains the v2 fields plus a nonnull participant DTO. Explicit
clear writes the canonical v2 selection without an extra nullable key. Snapshots
use the shared v2 form for null mode and shared v3 for participant mode. SQLite,
connection definitions and secure row versions remain 1; no table, key alias,
credential vault or migration is added.

The pure Android policy admits only the exact v1 DTO keys, a profile matching
`[A-Za-z0-9][A-Za-z0-9._-]{0,127}`, a nonblank UTF-8 base bounded at 65536 bytes
and 1–128 unique ordered safe target IDs. Maps/lists are detached. It performs
basic Java `URI` structural validation: HTTPS, nonempty raw authority without
`@`, no query, fragment, backslash or control character, and an absolute path
starting and ending with `/`. It preserves supplied strings. Full canonical
authority and path semantics remain authoritative in the common Dart DTO on
send and snapshot decode; native structural validation neither repairs stored
strings nor creates server trust. A structurally admitted but semantically
corrupt native authority fails `configurationInvalid` during Dart snapshot
decode. It remains stored unchanged and cannot supply usable scope input.

Every native selection transaction requires trusted IDs to exist as HTTP
definitions. Missing or Drive-kind targets fail `connectionMissing`; anonymous
targets and a nonnull selected transport outside the declaration fail
`configurationInvalid`. Ordinary selection and reference mutations preserve
the complete declaration and mode. Definition registration retains immutable
identity, selection and secrets. Existing encrypted serialization bounds apply
before commit; failed validation/sealing leaves previously committed rows intact.

iOS reads exact singleton snapshot bodies v2 or v3 through the shared strict
decoder and continues rejecting legacy v1, unknown versions and malformed or
extra/missing/null v3 data. A new database initializes v2; its database schema
stays at 1. Every operation reads a fresh complete snapshot through the existing
handle and shared SQL coordinator. Setter validation constructs the complete
result before writing in the same transaction. Missing/wrong-kind trusted IDs
fail `connectionMissing`; anonymous targets, undeclared selected transport and
other invalid resulting snapshots fail `configurationInvalid`. SQL IO remains
`configurationUnavailable`. Selection and `_next` mutation paths carry the
current declaration; null setter input explicitly clears it. No cache, database
replacement, migration or additional table is introduced.

Both native setters preserve credentials and queued intent across replacement,
clear, failed validation and reopening. They neither derive trust from resolver
access, origin equality nor a credential's mere presence. They read no token,
grant or protected authentication slot and perform no network or authentication
operation. Their existing ownership rules remain: close retires immediately,
joins accepted work, suppresses late results and closes only its owned handle;
already dispatched writes may commit and borrowed credentials remain untouched.

## Authentication and deployment gate

Configured participant mode must determine fail-closed dispatch even when there
is no accepted account or authentication context. A caller-supplied JSON/class
value alone is never server trust. An actual accepted Core scope must come only
from real login and explicit operator targets. The profile ID/base identifies
the real producer-approved UserAccount authority; it is neither a second issuer
nor an authorization grant.

Deployment activation waits for the producer trusted-recipient contract and
actual runtime qualification. UserAccount ACCESS must never be put on direct
Drive sessions or legacy grants. Native persistence, platform/App composition,
real account acceptance and complete connected-Step review remain required.
Native configuration persistence alone does not activate runtime authentication.

## Executable specification map

`test/submission/submission_participant_authentication_configuration_test.dart`
uses actual DTO/snapshot/codec operations and a base-only store implementer.
These scenarios are authoring obligations, not execution receipts. Each case
places the operation in When and observes its result in Then; rejection cases
execute once and capture the resulting error before asserting it.

| Requirement | Given | When | Then |
| --- | --- | --- | --- |
| Inert/token-free projection | Counting HTTP-client, timer and microtask boundaries | Construct real DTO and authority | Zero work; default timeout; exact safe JSON and fixed diagnostic |
| Defensive copies | Mutable IDs and literal maps | Construct/decode, mutate inputs/outputs, attempt frozen-list write | Exact ordered values retained; mutation rejected |
| Value identity | Equal canonical values and changed profile/base/order/membership | Compare/hash/store in set | Equal values coalesce; each changed identity separates |
| Raw versus retained base | Parser-admitted raw base without canonical suffix | Construct then decode raw retained spelling | Constructor canonicalizes; stored spelling rejected |
| Inclusive limits | 128 IDs and a calculated 65536-byte definition | Construct/roundtrip and offer one more byte | Exact limits survive; excess rejected |
| Invalid constructor inputs | Bad profiles, URL/userinfo/query/fragment/path/control/non-HTTPS bases, IDs, duplicates, empty/excess IDs and oversized UTF-8 body | Construct once per case | Fixed safe ArgumentError without retained input |
| Closed DTO | Missing/extra/version/null/type/invalid constructor values | Decode once per case | Safe FormatException without fallback |
| Legacy compatibility | Independent literal v1/v2 bodies | Decode/encode and use old constructor shape | Existing v2 bytes, targets/selections/references; no auto-adoption |
| V3 retention | Explicit trust and mutable targets/references/selection/wire maps | Construct/decode and mutate copies | Complete independent immutable state retained; same-origin target remains untrusted |
| No selection/reference prerequisite | Bearer target with absent selection and references | Construct and roundtrip v3 | Explicit participant value retained independently |
| Full target admission | Missing/Drive/anonymous/mixed-invalid targets or untrusted same/different-origin selection | Construct and decode once per case | Whole snapshot rejected before publication |
| Closed v3 | Missing/extra/unknown/null/type/corrupt definitions/references/selections/nested DTO, illegal v1/v2 participant key | Decode once per case | Safe corruption error; no synthesized empty state |
| Base compatibility | Base-only external-style implementation | Read and close through generic interface | Existing usable v2 value; no optional capability claimed |

`test/submission/submission_participant_configuration_store_test.dart` authors
the native-store host contract using the actual optional interface and shared
DTO, real file-backed iOS SQLite/FFI handles and a controlled Android
MethodChannel seam. Android host IPC and iOS host FFI are not physical native
proof. The Kotlin `SubmissionConnectionPolicyTest` exercises actual pure policy
functions and does not open Android SQLite or Keystore.

| Native requirement | Given | When | Then |
| --- | --- | --- | --- |
| Inert Android capability | Real base-typed Android handle and controlled channel | Construct, then call optional setter with DTO/null | No construction IO; exact method/arguments; explicit clear |
| Safe IPC failure | Unknown replies, errors or unsupported method | Execute setter once | Fixed safe error, no success fallback |
| Shared native decode | Literal v3 response or semantically bad retained authority | Read actual snapshot before authority projection | Detached shared DTO or `configurationInvalid`; no usable corrupt scope input |
| Durable mode lifecycle | Real iOS file and independent handles | Set, reopen, clear, reopen | v2→v3→v2; exact ordinary bytes restored; no credential reads |
| Mutation preservation | Participant declaration and registered targets | Add/idempotently put, select, revoke/replace references | Exact declaration/order survives; unrelated state remains |
| Atomic refusal | Missing/Drive/anonymous targets, undeclared selection, conflict or aggregate overflow | Execute actual setter/mutation | Safe category; complete SQLite rows unchanged |
| Freshness and coordination | Independent live handles | Concurrent setter/registration or external corruption before setter | Both committed facts retained or corruption rejected without repair |
| Authority replacement | Actual queued bound request and borrowed protected-store seam | Replace authority and clear | Only declaration/version changes; queue rows and protected owner untouched |
| Retained compatibility | Literal v2, legacy v1, future v4, malformed/closed v3 | Open real file | v2 reads without adoption; corrupt/unsupported rows remain unchanged |
| IO classification | Real SQL trigger refusing update | Execute valid setter | `configurationUnavailable`; no partial body write |
| Retirement | Controlled pending Android setter or iOS borrowed read plus accepted setter | Close, issue new call, release owned completion | Draining and late-result suppression; other handles/borrowed owner survive |
| Native pure policy | Literal old/current selections, malformed declarations and secret rows | Decode, mutate, replace and clear through actual policy | Closed/bounded shapes, exact membership, ordered detachment and old-mode/secret preservation |

The parent owns focused host/policy tests, targeted analysis, diff verification,
real native integration and the initial protected review of the complete
connected Step. These specifications and implementation statements are not
execution receipts, native readiness claims or Phase acceptance.
