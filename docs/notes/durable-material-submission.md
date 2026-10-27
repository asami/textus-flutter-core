# Durable material submission

Current status (2026-10-11): Core TFC2-01 owning review passed and its Step was
committed at `cd9da12f7219c8096762f5c16f3f2f5bb3998a65`. TFC2-02 documentary
evidence and parent intake are complete; independent protected Step review
passed. The exact Step commit remains pending. TFC2-03 and whole Core Phase 2 acceptance remain pending.

Historical ESA6-06-A authoring status: host software validation passed while
independent acceptance review was pending. That slice supplied contracts, SQLite
persistence and controlled-port specifications and started no background driver.

Owner: Textus Flutter Core owns generic intent, durable queue state, storage and
transport ports. TFAF will delegate through these public APIs and project queue
state. App supplies its confirmed ISBN OR title gate and Book mapping.

Update rule: Update this note with any admitted public schema, queue transition,
ownership or retry-contract change and the associated executable specification.
Add acceptance claims only with parent-recorded evidence; never infer native,
Drive or EditingStudio server acceptance from controlled host ports.

## Public handoff

Import [textus_flutter_core.dart](../../lib/textus_flutter_core.dart).
[SubmissionRequest](../../lib/src/submission/submission_request.dart) synchronously
snapshots local `document`, server `payload`, ordered materials, provenance and
opaque `extensions`. It interprets no domain or arm identifiers. One immutable
Commit per `(kind, subjectId)` is accepted in this Phase. Equal request ids are
idempotent; conflicting ids or another intent for the subject throw `StateError`.
New Commit validates every original via the borrowed `LocalCaptureStore`, then
atomically persists ReadyToSubmit before requesting wake. Equal existing intent
does not reread originals. Wake failure returns a safe scheduling notice with the
durable record. Commit performs no storage/transport operation.

[SubmissionRecord](../../lib/src/submission/submission_record.dart) is a complete
immutable state/checkpoint/history value. Original references retain the accepted
CaptureMaterialReference schema, extensions and descriptive original name. There
is no original migration, integrity hash, byte copy, recapture or deletion.
Existing photo/audio/document/transcript and CaptureRemoteRepository contracts
remain compatible through additive exports and dependencies.

All values use ordinary Dart equality/hashCode. Nested JSON is frozen, finite,
string-keyed and acyclic. Logical tokens use the existing capture-reference token
grammar. Provider and connection ids are tokens; remote ids are descriptive
nonblank strings and never become local paths. Invalid constructor input throws
`ArgumentError`. [SubmissionCodec](../../lib/src/submission/submission_codec.dart)
uses exact version 1 request/record schemas, explicit nullable keys, enum names,
integer counts and valid explicit-zone ISO dates normalized to UTC. Malformed or
unsupported persisted values throw `FormatException` without automatic repair.
Packet JSON contains ordered originals/provenance/receipts, payload and extensions;
the local document and original bytes are excluded. Ports must exclude credentials
from reservation data, metadata, extensions, safe messages and transport payloads.

## Queue and bounded driver

[SubmissionQueueStore](../../lib/src/submission/submission_queue_store.dart) is the
only durable state authority. [SqliteSubmissionQueueStore](../../lib/src/submission/sqlite_submission_queue_store.dart)
opens a dedicated version 1 file, with independent owned handles, FULL synchronous
writes, busy timeout 5000ms and exclusive transactions. Request/subject uniqueness
is enforced by the indexed table. Every row decode checks indexed identities;
claim scans/decode all rows, so corruption is observable even in an ineligible row.
Selection is deterministic by creation time then id. No transaction awaits a
remote adapter. Unsupported versions are rejected without reset/drop/fallback.
Injected DatabaseFactory enables tests without replacing the global factory.
Exclusive transaction entrance makes at most three attempts, with a 25ms yield
outside the transaction between attempts, only for primary SQLite BUSY/LOCKED
errors before the callback begins. An entered callback is never replayed;
callback/commit errors, other errors and exhausted entrance contention propagate.
The default application-support factory supports Android/iOS/macOS; Web and other
default platforms throw `UnsupportedError`. Plugin/IO/database errors propagate.

Ready, due retryable Failed and expired Submitting are claimable. Submitted,
nonretryable Failed and nonexpired claims are excluded. A claim increments count,
assigns a unique token and expires at supplied UTC now plus lease duration.
Checkpoint, failure, release, complete and renewal require a matching unexpired
submitting lease; stale ownership throws `SubmissionLeaseLostException` without
writing. Renewal never revives an expired owner. Transitions retain the immutable
request, checkpoints and full failure history, with monotonic `updatedAt` even
under clock rollback. Expiry follows supplied wall time; no exact wall-clock
timing guarantee is made when that clock moves backwards.

[SubmissionService](../../lib/src/submission/submission_service.dart) serializes
mutating commands in invocation order and recovers after failures. Reads delegate
strictly and uncached. `find`/`findForSubject` return null only for absence; list is
immutable. `processNext(networkAllowed: false)` returns offline before claim,
reads, adapters, predicate or scheduler calls. Online processing performs at most
one remote operation per invocation:

1. Prepare the first material missing a reservation, then persist and release Ready.
2. Once every reservation exists, read the first original missing a receipt, upload
   with its persisted reservation, then persist and release Ready.
3. Once all receipts exist, send the immutable packet and persist matching server
   acknowledgement as Submitted.

Only explicit server acknowledgement produces Submitted. An empty material list
bypasses storage. Missing connections and mismatched provider/key/acknowledgement
results produce observable safe nonretryable configuration failures. Immediately
before dispatch Core rechecks owner currency and atomically renews the lease after
any awaited local read; an expired/stolen owner dispatches nothing.

[SubmissionStorageAdapter, SubmissionTransport and SubmissionWakeScheduler](../../lib/src/submission/submission_adapters.dart)
are borrowed ports. Storage must replay a persisted reservation idempotently,
including pre-generated Drive file ids. Transport must be idempotent by request id.
Local lease fencing alone cannot promise network exactly-once effects. Upload/server
success followed by local write loss is an observable unacknowledged durable state;
restart reuses checkpoints and immutable identities, never fabricates local success.

## Failure, cancellation and ownership

Expected adapter failures supply trusted safe stage/code/message/retryable fields;
unknown exceptions use fixed generic text. Raw exceptions, headers, bodies,
credentials and lease tokens are not serialized into failures. Missing/corrupt
originals fail before Commit publication or as nonretryable local-material failure
during processing. Genuine SQLite/corruption/write errors remain observable and
recoverable. History records the executing claim count and UTC occurrence time.
Retryable failure is due after 30s by default; nonretryable failure has no due time.
Explicit retry retains originals/checkpoints/history, changes Failed to Ready,
leaves Ready/Submitted unchanged, rejects active Submitting, and requests wake only
after durable state mutation. Unknown retry id fails without scheduling.

Default operation timeout is 1 minute under a 5-minute lease. Positive configurable
durations require lease greater than timeout. Late completion is observed/discarded;
remote idempotency remains necessary. Caller `isRunCurrent` is checked before claim,
before dispatch and after awaits before checkpoint. Expected cancellation releases
a valid claim Ready; lost lease returns leaseLost and never changes another owner.
A throwing predicate best-effort releases its valid claim then propagates the
primary error without publishing failure/acknowledgement.

Service close invalidates run ownership immediately, prevents new calls, drains
its accepted work/read calls and best-effort releases unfinished valid claims.
Close before enqueue prevents new publication; already durable intent completes
its wake and returns its durable result. Close is idempotent. Queue/material store,
adapters and scheduler stay borrowed and usable. Store close drains its instance's
reads/writes and closes only its owned handle. Neither close deletes data.

## Executable specifications and acceptance limits

[Model specifications](../../test/submission/submission_model_test.dart) author
M1/M2 immutable roundtrip and malformed-value behavior.
[Queue specifications](../../test/submission/submission_queue_store_test.dart)
author Q2/Q3/Q4 file reopen, competing handles, expiry/renewal, strict corruption
and real SQLite transaction-failure behavior.
[Service specifications](../../test/submission/submission_service_test.dart)
author Q1/Q5–Q9 original-byte handoff, one-operation stages, fake acceptance,
retry, checkpoint-write loss, scheduler errors, cancellation, timeout and timing.
[Test fixtures](../../test/support/submission_fixture.dart) isolate real files and
host SQLite while controlling storage/transport/wake ports independently.

Parent host validation on 2026-10-10 passed all 99 tests in the three submission
suites and eight direct capture/audio/public-library consumer suites. Representative
Q1 and concurrent Q3 also passed separately. Analysis reported no issues, exact-path
dry formatting changed no files, and diff checking passed. Independent review is
pending. These executed FFI concurrency specifications establish host behavior only.
At that receipt stage, native plugin
registry/APK, Android separate-isolate SQLite and WorkManager restart/offline
recovery remain required in later slices. Real Drive API acceptance is separate
from controlled storage; fake transport acceptance belongs to ESA6-07. Actual
EditingStudio server acceptance remains deferred. No Step/Phase completion,
publication, deployment or release is claimed here.

## 2026-10-10 — FIX23 independent-open and operation-time absence correction

Frozen repair `esa61-submission-core-readiness-fix23-20261010@1` addresses
`VF-ESA61-CORE-SQLITE-OPEN-001` and `VF-ESA61-CORE-MISSING-LIST-001` under the
retained PHASE-6.1 / ESA6-06 authority. SQLite configuration now installs the
existing `busy_timeout = 5000` before `synchronous = FULL`, so the first
schema-touching configuration operation can wait for another handle's lock.
The version 1 schema, independent-handle ownership and transaction entrance
retry contract are retained; this adds no initialization retry or hard real-time
open promise.

FileCaptureStore document reads and collection listings return null/empty for
the missing-path error observed by that operation. A later stat cannot
reinterpret that observation after a concurrent writer creates the path. A
fresh operation can observe the new final document; reads/listing perform no
writes, and nonmissing errors, corruption and original-material failures remain
observable.

The queue specification authors `Q4 opening an independent handle waits for an
existing lock`: a real no-isolate raw EXCLUSIVE lock, production FFI configuration
entry observation, a 50ms main-event-loop COMMIT, exact record retention, subsequent
enqueue/read/reopen and actual FULL/5000 pragma values. Scoped real-file
[absence specifications](../../test/capture/file_capture_store_absence_race_test.dart)
author F1 native ENOENT listing followed by collection/final-file creation, F2
native ENOENT read followed by valid-object creation, and F3 unchanged nonmissing
read/list errors with retained accepted documents and original bytes. Fresh
operations must see the retained created data in F1/F2. Helpers and cleanup carry
adjacent semantic Given/When/Then clauses.

Consumer coverage selected by the parent includes the Core ten-suite submission,
capture and audio accumulator, App BU7 independent queue acquisition/query and
W5 held-camera exit with concurrent capture storage. This authoring addendum
records no command pass or new commit. Historical host validation and source
acceptance facts remain historical; this protected correction awaits fresh parent
validation and independent source conformance review. Native scheduling/restart,
actual Drive, whole-Step and Phase acceptance remain pending at their parent-owned
gates.

## 2026-10-11 — TFC2-02 owning evidence entry

The [owning Step journal](../journal/2026/10/2026-10-11-tfc2-02-acceptance.md)
records the six-document authoring subset of the exact 49-path Step boundary
(original 47 plus two shared Phase progress documents), within unchanged Core
80-path scope. Existing durable execution, ownership, targeted retry and earliest
unknown-dispatch contracts are adopted unchanged. Earlier authoring/pending and
failure receipts above remain historical; this dated projection supersedes their
present-status implications without changing their outcomes.

`esa61-submission-reference-guard-software-validation-20261010@1` records RA3
passing separately (one case), the 23-suite accumulator passing 375 cases with
zero failures, and source analysis with no issues. Real originals and SQLite
exercise local guard denial, later configuration and same-id retry/reopen with
the exact immutable packet; remote ports and acknowledgements are controlled.
This is scoped software evidence, not repository-full validation or a server result.

The later `esa61-fix34-validation-20261011@1` covers the production awaited
`rawQuery` timeout correction: Q4 passed with retained records, FULL=2 and
busy_timeout=5000; ten suites passed 115 cases with zero failures/skips. Scoped
queue analysis found no issues and dry format changed no files. Actual NC1/NC2
retained encrypted configuration and acquired the default factories over an
empty queue (`queueCount=0`); they establish no nonempty dispatch.

Distinct later `esa61-native-book-validation-final-20261011@1` records NQ1/NQ2
nonempty ready original/immutable intent and newer Draft persistence across
processes, NQ3 actual WorkManager execution with two `authRequired` claims and
one explicit retry, and NQ4 fresh-process failed original/context/status restore.
Each selected stage passed once, with zero failures and five explicit other-stage
skips. These supplied-offline/held-wake observations prove no physical radio
toggle or OS-stop experiment. Native entry and scoped synthetic Drive results
are recorded in [the runtime note](android-submission-runtime.md).

Core Step1 is accepted and committed; Step2 protected owning review passed
and its exact commit remains pending. Step3, full-package checks, comprehensive
Phase review and distinct release remain pending. TFAF/App closure is separate. No complete Book upload, hardware security
certification, real server acceptance or Candidate formation is inferred. The
documentary author ran no validation or review; the parent owns those gates.

## 2026-10-11 — Owning TFC2-02 acceptance before commit

The parent completed the six-document intake and selected 49-path whitespace/link
checks. Independent protected review `tfc2-02-owning-step-review-20261011@1`
returned PASS over 49 owning and 84 selected paths, including all 34 target
programs and five configuration inputs. Current blockers, Hygiene and Development
Candidate findings were explicitly empty. The review inspected actual scoped
RA3/375, later SQLite Q4/115, clean analysis, native 37-case and NC/NQ/ND results;
it executed no product validation. Their controlled/native/synthetic limits remain.

This dated receipt supersedes only earlier current-status implications; historical
failures, authored-only receipts and their outcomes remain unchanged. The parent
prepares the exact 49-path local Step commit. Its native outcome is still pending.
This is no standalone package or whole-Phase release. TFC2-03, Core full-package
validation/comprehensive Phase review/distinct release, TFAF Phase 3 and App
Step/Phase/aggregate/release closure remain required. Existing contracts and source
are unchanged by this factual bookkeeping; no new remote/server result is inferred.
