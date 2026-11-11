# Participant submission runtime

This specifies ESA610-UA-SUBMISSION-001 / CORE-RUNTIME-07 in the connected
Phase 6.10 Step. The internal composition owner and the public platform factories
borrow the existing accepted UserAccount scope and native configuration. The
executable scenarios below are host specifications, not execution receipts,
native or server qualification, App activation, or connected-Step acceptance.

## Public composition inputs

The Android factory retains its existing lifetime and optional borrowed scheduler
and adds source-compatible named parameters:

```dart
Future<SubmissionBackgroundResources> openDefaultAndroidSubmissionResources({
  required SubmissionRunLifetime lifetime,
  SubmissionWakeScheduler? scheduler,
  UserAccountSubmissionScope? authenticationScope,
  bool restoreParticipantAuthentication = false,
  bool requiresAuthentication = false,
});
```

The iOS factory retains its existing optional borrowed credentials and scheduler:

```dart
Future<SubmissionBackgroundResources> openDefaultIosSubmissionResources({
  required SubmissionRunLifetime lifetime,
  SubmissionWakeScheduler? scheduler,
  SubmissionCredentialProvider? credentials,
  UserAccountSubmissionScope? authenticationScope,
  bool requiresAuthentication = false,
});
```

iOS provides no owned-restore option or OS-background execution. Its default
foreground scheduler captures the exact borrowed scope, explicit required policy
and legacy credential port for every fresh batch. Each batch obtains current
configuration and its own internal participant runtime over a fresh batch
lifetime, while borrowing the existing shared queue, originals and scheduler.

`SubmissionParticipantRuntime` is an internal final class, without a package
export. Its async `open` requires the actual configuration snapshot, borrowed
legacy credential provider and `SubmissionRunLifetime`; optional scope and both
boolean policies default to null/false. Only factory-facing readonly policy,
context, binding, credential provider, current predicate, exact-target predicate
and idempotent close are exposed. Diagnostics are the fixed type name. No token,
record, native handle, account selector or additional actor registry is public.

## Inert opening and local required policy

With no participant declaration, a supplied scope is invalid. Ordinary omitted
policy preserves legacy behavior: the exact borrowed legacy credential provider,
null participant context/binding, all existing snapshot HTTP definitions, and
current ownership while the lifetime and helper remain open. Even explicit
`restoreParticipantAuthentication: true` performs no authentication construction,
protected-store lookup or network operation for legacy configuration.

`requiresAuthentication: true` supports readable blocked composition before
operator setup exists. Without a declaration it produces null context/binding,
no permitted HTTP targets, a false authentication current predicate, and an
advanced denying provider. Both credential methods return null without IO. It
never falls back to legacy credentials or invents an authority/account/sender.

A participant declaration always requires authentication, including when the
caller omits or passes false for the explicit policy. With no supplied accepted
scope and no explicit restore request, opening remains inert and readable with
null context/binding and the advanced denying provider. Actual queue, history
and transfer-status reads remain available. Dispatch through both the ordinary
submission service and Registered Material handoff service checks required
authentication before original access, credential lookup or adapter work. Bound
and unbound saved rows therefore remain blocked without a matching current
accepted context. Opening neither claims nor rebinds, retries, erases or selects
queue intent.

## Actual authority and exact trusted targets

The declaration identifies the actual approved UserAccount authority by exact
profile ID and canonical base URI. A borrowed concrete scope must match both
values. Its binding comes solely from the actual accepted backend account;
display labels and queued account IDs do not establish acceptance. The exact
scope/context/binding and advanced provider are borrowed directly. Borrowed
opening invokes no current callback, token method, login, restore or network IO.

The immutable per-instance target map contains only the declaration's explicitly
trusted existing HTTP definitions. Snapshot validation establishes membership;
missing IDs are never silently omitted. Target equality includes ID, endpoint
and bearer requirement. Same origin, URL resemblance, selection, reference-access
bindings or an existing token do not add recipients. HTTP transports and TKL
clients are constructed only for those declared definitions. The normal legacy
path retains its original all-snapshot-target behavior.

HTTP transports receive the runtime credential provider. TKL clients additionally
capture its exact accepted authentication binding. Adapter current predicates
combine the factory lifetime with participant ownership, and retain the existing
cancelled future. No server path, header schema, payload, retry policy or issuer
is introduced. Local trusted-recipient intent still requires real producer realm
acceptance; this runtime creates no server authorization grant.

Google Drive retains configuration's separate Google credential purpose. No
UserAccount ACCESS is forwarded to Drive. Its run predicate nevertheless retires
the participant run when participant ownership becomes invalid.

## Explicit Android headless restoration

Only the conjunction of a participant declaration, no borrowed scope and explicit
restore permission constructs the actual `UserAccountHttpAuthenticationBackend`
for the declared authority and a `UserAccountAuthenticationClient` with
`ownsBackend: true`. The client restores once. Its existing protected-native CAS,
get-my-account validation, 401 rotation and accepted-candidate publication remain
authoritative; the composition layer adds no retry, token getter, fake backend,
service bearer, account selector or substitute identity.

A normal unauthenticated result yields readable blocked mode. An escaping auth
operation or cleanup failure fails open with the fixed safe
`StateError('Participant submission authentication is unavailable')` after owned
cleanup. A cleanup failure cannot publish an empty or usable accepted context.
An accepted restore creates a scope from that exact backend, the declared target
definitions and a current predicate bound to this lifetime/helper. Native B or a
currently accepted B cannot adopt persisted A intent.

The existing Android callback retains its `networkAllowed == false` branch before
resource acquisition. Only the allowed branch requests owned restore. Offline
start therefore reads no configuration, protected credential, queue or original.
Native start/stop/run ID, one-start, terminal-result and resource cleanup semantics
remain in force. Ordinary foreground opening and iOS opening never implicitly
restore or log in.

## Retirement, no revival and ownership

Owned backend/client acquisition is captured before awaiting restore. Lifetime
cancellation immediately starts helper close even while resource opening is
pending. After restore, opening rechecks lifetime/helper retirement before scope
publication. A retired open fails and joins its acquired auth cleanup. No timer
or global replacement factory is used.

Helper close marks it closed synchronously, returns the same future, and closes
only the newly created client/backend through the existing owned-backend
contract. Partial client acquisition closes the already captured backend. Close
joins accepted native lookup work, observes abandoned/late future failures, and
preserves the same honest safe failure for awaiters. It does not log out or erase
protected credentials. Borrowed scopes, backends and legacy providers are never
closed by the helper.

Platform cleanup retires the factory lifetime immediately and closes owned
delivery HTTP promptly. It drains the handoff and ordinary services, joins helper
authentication cleanup, then closes owned queue/configuration/scheduler resources
according to their existing ownership. iOS starts scheduler retirement before
the first cleanup await and joins its active transient owner before closing the
root queue. Transient iOS owners never close the shared queue or scheduler. Every
acquired cleanup is attempted even after an earlier failure. Android cleanup
reports the fixed configuration-unavailable failure; iOS retains its fixed
resource-close failure. Partial opens also attempt helper cleanup.

A finished batch can borrow the same still-current root scope again because its
helper lifetime never becomes the root scope's lifetime. Once an actual scope
has retired, later callbacks returning true cannot revive it. An auth change
requires a fresh accepted scope and composition. Saved queue identity remains
immutable across these transitions.

## Executable authoring map and remaining acceptance gates

The two new host files use the actual helper, authentication backend/client,
protected native MethodChannel/CAS seam, platform factories and file-backed
SQLite/configuration. Retained sessions are seeded by actual preceding Core
login and closed without logout. Synthetic HTTP uses scoped `http.runWithClient`.
Temporary support roots, native/platform/channel overrides and host SQLite
factories are test-owned and restored. Held operations use completers and
explicit lifecycle/native messages without sleeps or real network/device access.

| Specification | Given | When | Then |
| --- | --- | --- | --- |
| Helper legacy and local policy | Legacy snapshot and visible provider/construction seams | Open with restore flag, or explicit required policy | Legacy remains inert; required mode denies both ports without authority, fallback or IO |
| Scope admission | Real accepted scope and absent/mismatched declaration | Open once | Fixed safe error before callback, native or HTTP work |
| Borrowed ownership | Real accepted A and counting root callback | Open, close helper, then use scope | Exact context/binding/provider; inert open; root remains usable |
| Exact targets | Declared definitions plus same-origin outsider and altered definition | Probe runtime target admission | Only exact declared ID/endpoint/bearer tuple is admitted |
| Owned restore | Retained real A login closed without logout | Explicitly restore and request advanced credentials | Exact accepted A binding and ACCESS only; retained record preserved |
| Foreign owner | Real accepted/restored B, or native B replacing A's slot | Request A credentials/dispatch | No adoption, token forwarding or foreign credential erasure |
| Absent/refused session | Absent protected entry or authority refusal | Execute real restore | Readable blocked mode, no dummy account or legacy fallback |
| Existing rotation | Real retained A and controlled 401/rotation/account responses | Restore once | Only the existing single rotation protocol, no added retry |
| Opening retirement | Held actual native restore/candidate write, optionally failed rollback | Retire lifetime and release accepted work | No scope publication; safe honest failure after owned cleanup |
| Owned drain/failure | Accepted held native lookup and independent HTTP/native close failures | Close helper and release lookup | Synchronous retirement, same future, joined native drain and every cleanup attempted |
| Platform gates | Real saved ordinary and Registered rows, missing originals and no/mismatched/unbound/retired scope | Read status, then drive both services | Status remains readable; authentication refusal precedes originals, token and HTTP |
| Platform target maps | Bound A plus undeclared HTTP/TKL/handoff definitions | Drive actual adapters/services | A ACCESS only at declared targets; outsider has no adapter; v2 packet unchanged |
| Separate Google purpose | Real original, accepted A and Google credentials | Attempt Drive reservation | Only separate Google token reaches Google; no UA lookup or forwarding |
| Legacy compatibility | Actual legacy config and original factory defaults | Dispatch unbound legacy row | Existing provider/packet succeeds without participant auth construction |
| iOS batch ownership | Resumed iOS, real root scope and shared queue | Complete fresh batches, close root, retire old scope and recompose | Borrowed root survives batch cleanup; retired scope stays invalid; fresh scope can be current |
| iOS missing setup | Explicit required root with absent declaration | Wake default fresh scheduler batch | Captured required policy prevents legacy escape |
| Android offline | Actual headless channel and observable seams | Start with network disallowed | Zero resource, auth, queue or original work |
| Android opening stop | Retained real A and saved queue with held restore read | Start allowed run, send matching stop, release read | Cancelled terminal result, owned auth drain, queue never claimed |
| Platform unwinding | Corrupt test queue or independent owned cleanup failures | Fail actual partial open or close | Every acquired handle attempted; fixed safe close error; borrowed owners and durable artifacts retained |

Parent validation covers these two suites and the existing Android background,
iOS scheduler/resources, auth and queue consumers, plus targeted analysis. The
complete connected Step still requires independent protected review and selected
commit. Actual native profile/phone behavior, producer/server authority and target
acceptance, App/root integration and activation, UC/MS/SB/demo gates, final
repository/native checks, the sole Phase full review and release remain explicit
later gates. No physical-device, cloud, server or Phase acceptance is claimed by
this authoring unit.
