# iOS foreground submission execution

`SubmissionExecutionMode` describes observed execution capability only. Existing
custom `SubmissionBackgroundResources` default to `unknown`; the existing Android
default composition declares `background`, and the iOS default composition
declares `foreground`. The value grants no queue, network, credential or identity
authority and does not assert that delivery is ready or accepted.

## Explicit wake and lifecycle

`IosSubmissionForegroundScheduler` implements `SubmissionWakeScheduler` and
observes the Flutter binding's actual lifecycle. Its constructor retains only
callbacks and an optional borrowed binding. It must not resolve a binding, attach
an observer, create a timer, read storage or credentials, or start IO.

`requestRun()` accepts wakes only on non-Web iOS and rejects a closed owner.
Platform checks precede binding and port access. The first accepted wake attaches
one observer and reads the selected binding's current lifecycle. Only `resumed`
permits dispatch; null, inactive, hidden, paused and detached states do not.
Opening a resource composition never issues an implicit wake.

A wake records requested intent and a new generation, then schedules a
zero-duration timer when active and idle. Its Future completes when the wake is
accepted, without joining processing. Commit may still hold its serialized
service command while requesting that wake. Repeated wakes coalesce; a wake
during a run or cleanup is remembered and causes one subsequent scan, so a later
Commit cannot be lost after an earlier scan sees no work. A timer must recheck
open, active, requested and idle state before reserving a batch.

Before invoking an injected policy or resource opener, the scheduler reserves a
distinct safe `ios_foreground_<counter>` lifetime and its completion join. No
reentrant callback may create parallel ownership. The opener receives that
lifetime and the borrowed scheduler. It must not await the enclosing scheduler's
close inside its opening or cleanup callback; the same rule applies to App joins.

Before any resource, queue or credential port, dispatch checks the active/open
current owner and `networkAllowed`. Offline retains requested intent without a
polling timer and retries only on another explicit wake or resume. A throwing
policy is an infrastructure failure with a fixed 30-second retry while active.

The acquired resources are borrowed by the existing
`SubmissionBackgroundRunner`, with its normal eight-operation and 180-second
limits. Its lease, checkpoint, direct transfer, TKL fallback, verification,
registration and Studio acknowledgement algorithms remain authoritative. The
scheduler fences every await and always closes each acquired batch, including an
acquisition that completes after retirement. It never closes borrowed ports.

Every non-resumed lifecycle notification immediately cancels scheduled timers
and retires the active lifetime. Existing cancellation aborts bound HTTP and
rejects late checkpoints and acknowledgements. Requested intent is retained.
Resume can schedule a fresh lifetime only after the previous acquisition, run
and cleanup have drained. The old owner cannot publish success or overlap its
replacement. A remote effect already issued may exist; durable idempotency,
leases and checkpoints retain their existing authority. Pause/resume never
clears intent, requeues records or changes their persisted owners itself.

After clean cleanup, `drained` clears the request only if no newer generation
arrived. A newer wake causes a follow-up scan. `pending` uses its next delay,
falling back to 30 seconds when absent; `failure` uses its next delay or that same
safe fallback. Delays are clamped to zero through one day. Offline retains intent
without a timer. Cancellation waits for active resume. Unexpected run or cleanup
errors retain intent with a fixed 30-second infrastructure retry while active.
No scheduler outcome synthesizes durable acknowledgement or exposes raw errors.
Nonretryable failures and unknown handoff outcomes require their existing
explicit operator dispositions and are never coerced by resume.

`close()` retires synchronously: it marks the owner closed, removes its observer,
cancels its timer and retires the active run before awaiting anything. Repeated
close returns the same Future, joining the sole acquisition/run/cleanup once.
Late acquisitions are cleaned exactly once. Cleanup failure can expose only a
fixed safe `StateError`; closure never deletes data or closes borrowed resources.

## Default iOS resource ownership

`openDefaultIosSubmissionResources(lifetime:, scheduler:, credentials:)` guards
non-Web iOS before IO and checks its associated lifetime around every acquisition
and construction. Unsupported platforms remain `UnsupportedError`; other open
failures become `StateError('iOS submission resources are unavailable')`, without
paths or raw causes. A retired lifetime fails before opening configuration or
storage. Every acquired owner is cleaned after partial failure without deleting
or replacing durable files.

The main composition owns one `IosSubmissionConfigurationStore`, the default
durable SQLite queue, an HTTP client, submission/handoff services and, when no
scheduler was supplied, one foreground scheduler. It borrows capture persistence,
the credential provider and any supplied scheduler. Configuration delegates only
approved read-only credential retrieval; absent authorization stays absent. No
token writer, implicit Keychain/profile inference, account grant or network IO
is introduced during construction.

The complete current configuration supplies all persisted HTTP and Drive
definitions, independent of selection. Composition uses the existing
`HttpSubmissionTransport`, `DriveSubmissionStorageAdapter`,
`ConfiguredSubmissionReferenceAccessPolicy` and
`RegisteredMaterialHandoffService`. `TklMaterialDeliveryHttpClient` uses the same
authenticated service-root predicate as Android: bearer authentication is
required and the endpoint path ends with `/`. Existing transport, reference
access, TKL and Studio acceptance contracts are unchanged.

The default scheduler's opener captures the exact main queue and capture-store
instances. Each batch owns fresh configuration, client and services, so later
operator configuration is consumed without reopening the main composition. A
batch borrows the captured queue/capture persistence, credentials and scheduler;
its cleanup must never close those borrowed owners. No second queue handle is
opened for a batch. The existing queue's operation tail serializes foreground UI
and scheduler SQL in the same isolate, while SQLite retains its existing durable
and lease semantics. Separate configuration handles retain their coordinator.

Cancellation closes each owned HTTP client through the associated lifetime.
Main close synchronously retires the main lifetime and invokes owned scheduler
close before its first await, preventing new dispatch while UI services drain.
It observes that join immediately, drains the main services, joins all scheduler
and transient cleanup, and only then closes the owned queue and configuration.
It attempts every cleanup after any failure and shares one idempotent callback.
Supplied schedulers and credential providers are never closed. Cleanup errors
become `StateError('iOS submission resources could not be closed')` without raw
causes; data remains retained.

## Delivery and acceptance boundary

This capability is foreground-only. Persistent explicit intent can resume while
the App is open after an explicit wake and an authorized resumed lifecycle. It
does not implement or promise iOS OS-scheduled or headless background delivery.
It does not grant authorization or replace participant-owned configuration.

Temporary-file SQLite and controlled HTTP/credential scenarios exercise these
composition, lifecycle and ownership contracts. Genuine participant credentials,
server acceptance, native iPhone lifecycle/network behavior, Framework/App
integration and the remaining whole-Phase validation and protected review gates
remain distinct required evidence. Host FFI and controlled responses do not
establish those qualifications.
