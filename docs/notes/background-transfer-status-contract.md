# Background transfer status contract

Current status: ESA6-06-S1 source and executable specifications authored. Parent
DR1 passed (1 test), and the selected 20-suite software accumulator passed
(339 tests, 0 failures). Parent analysis reported `No issues found!`; dry format
reported 13 files with 0 changed. Independent S1 acceptance remains pending.
The S2 execution reference-access guard is required before consumer runtime acceptance.

Owner: Textus Flutter Core owns durable intent, fenced dispatch checkpoints,
transport outcome attribution and the public immutable status projection. TFAF
owns shared presentation over this contract; App owns Book labels/navigation.

Update rule: Update this note and its executable specifications together when an
admitted schema, dispatch, projection or action contract changes. Add validation
and acceptance claims only from parent-recorded evidence for the exact tree.

Import [the public Core library](../../lib/textus_flutter_core.dart).
[SubmissionTransferStatus](../../lib/src/submission/submission_transfer_status.dart)
projects a validated [SubmissionRecord](../../lib/src/submission/submission_record.dart)
with an explicit observation time. It performs no IO, wake, retry, queue mutation
or network check. It works on every Dart platform and owns no resources. Network
and reference observations default to `unknown` on every independent call,
including after restart. An observation cannot grant execution permission.

The snapshot retains exact `requestId`, `kind`, `subjectId`, UTC durable
`updatedAt`, UTC `observedAt`, safe storage/transport connection ids, independent
`upload` and `submission`, request-ordered frozen `files`, frozen `actions`,
`acknowledgementUncertain` and matching `acknowledgement`. It exposes no credentials,
raw errors, inferred live process, bytes sent, percentage or active/failed file.
File values contain the original reference and only their actual reservation and
nullable receipt. A file succeeds exactly when that receipt exists; otherwise
it remains queued. Original bytes and ownership remain with their original store.

## Persistence and earliest dispatch

[SubmissionCodec](../../lib/src/submission/submission_codec.dart) writes exact record
version 2 with mandatory nullable `transportCheckpoint`. Request/packet version 1,
original photo/audio references, edited transcript whitespace, local documents,
provenance, failure and receipt shapes remain unchanged. SQLite schema and
`user_version` remain 1, with the same indexed table and configured database path.
Reads never rewrite rows, repair corruption, migrate roots or delete originals.
Unknown versions, missing/extra keys, invalid types/calendar times or inconsistent
relationships throw `FormatException` observably.

A checkpoint's exact keys are `claimCount`, `startedAt`, `isLegacyUnknown`.
`pending` requires a positive claim count and UTC time, all matching upload
receipts, a non-submitted record, count no greater than its current claim and
time no later than `updatedAt`. `legacyUnknown` has null claim/time and true
legacy attribution. This records earliest potentially unconfirmed dispatch,
without proving that bytes left the process.

Exact deployed record version 1 remains readable. For any non-submitted row with
positive claim count and every required receipt, including zero required uploads,
the decoder retains `legacyUnknown`. That schema cannot prove whether transport
ran. Other old rows have no checkpoint; submitted old rows retain their matching
acknowledgement. The first actual transition writes version 2 while preserving
the immutable request, indexed identities, reservations, receipts and history.

[The queue](../../lib/src/submission/submission_queue_store.dart) persists
`markTransportDispatch` under its existing matching unexpired lease fence before
transport. Incomplete receipts reject the operation. An earlier pending or legacy
checkpoint is retained idempotently. Claim, renewal, release, retry and material
writes preserve it. Matching server acknowledgement clears it atomically.
Trusted `notSent` or `rejected` clears only a nonlegacy checkpoint attributed to
the exact failing current claim, with transport/configuration failure stage.
Incompatible attribution rejects the transaction. Later refusal, configuration
failure or cancellation cannot erase an earlier possible acceptance.

[SubmissionService](../../lib/src/submission/submission_service.dart) records that
checkpoint after complete packet validation, rechecks caller lifetime after the
await, then renews the valid lease immediately before submit. Failed persistence,
expired/stolen ownership or retired caller prevents dispatch. Timeout, raw failure,
mismatched acknowledgement and local complete-write loss retain uncertainty.
Close releases valid unfinished intent to ready while preserving that uncertainty;
late acknowledgement cannot publish submitted state for a retired owner.

[HttpSubmissionTransport](../../lib/src/submission/http_submission_transport.dart)
attributes pre-send safe errors as `notSent`. After its potential-send boundary,
only explicit 401 `authRequired` and 403 `permissionDenied` refusals are `rejected`.
Other results, including 409, redirects, rate limiting, 408/5xx, connection loss,
cancellation, timeout and absent/malformed/mismatched 2xx acknowledgement, are
`unknown`. Safe code/message/stage/retryability remain fixed. No body, credential
or raw cause is retained; the client is borrowed and no internal retry occurs.
Other adapters default to unknown attribution.

## Upload operation mapping

Apply rows in order. `running` establishes a durable unexpired claim only.

| Durable/observed facts | Upload state | Waiting/failure/progress |
| --- | --- | --- |
| No required files | `notRequired` | Counts 0/0; no invented completion time |
| Every actual file receipt exists | `succeeded` | Exact receipt count; latest actual receipt time; no current failure/deadline |
| Some receipts missing and row failed | `failed` | Current safe aggregate failure, actual count, persisted retry deadline and any current waiting observation |
| Some receipts missing and current lease unexpired | `running` | Actual lease expiry and receipt count; no inferred active file |
| Some receipts missing and lease expired | `waiting` | `leaseRecovery`, actual expiry/count |
| Otherwise, explicit offline/policy restriction | `waiting` | `networkUnavailable` / `policyBlocked`; actual count |
| Otherwise, persisted future retry deadline applies | Current failed state retained | `retryScheduled`, exact persisted deadline/count |
| Otherwise ready/unknown network | `queued` | No invented connectivity, timestamps or percentage |

Partial successes are never repeated in the projection or attributed a failure.
The safe failure is aggregate because the durable failure has no material key.
Operation fields are `state`, `waitingReason`, `failure`, `nextAttemptAt`,
`leaseExpiresAt`, `completedAt`, `completedCount`, `totalCount`. Counts are actual
upload receipt/required file counts; submission counts are null. Deadlines appear
only for the still-applicable operation, and use actual persisted values even
after expiry. Pending work has no fabricated completion time.

## Submission operation mapping

| Durable/observed facts, in precedence order | Submission state | Waiting/failure/acceptance |
| --- | --- | --- |
| Exact matching server acknowledgement | `succeeded` | Actual acknowledgement and its receipt time; no actions/uncertainty |
| Required upload receipts missing | `waiting` | `materialUpload`; no submission-specific failure/deadlines/counts |
| Complete references and unexpired current claim | `running` | Actual expiry; uncertainty flag if checkpoint exists |
| Complete references, checkpoint and no unexpired claim | `outcomeUnknown` | Earliest uncertainty retained; current network/retry/lease facts and safe failure remain observable |
| Complete references, no checkpoint, expired lease | `waiting` | Actual expiry with lease-recovery/current waiting fact |
| Before known dispatch, required reference access unknown/unavailable | `waiting` | `referenceAccess`; successful uploads stay successful |
| Complete references, available access, failed row without checkpoint | `failed` | Current safe failure and actual retry facts |
| Otherwise, explicit network/policy waiting | `waiting` | `networkUnavailable` / `policyBlocked` |
| Otherwise ready | `queued` | No inferred Candidate creation or server acceptance |

No-upload intent bypasses the reference-access presentation gate. Network/policy
observations never undo actual receipts or acknowledgements. For uncertain
submission, a network waiting cause may coexist with an actual retry/lease
deadline; neither establishes whether the older dispatch was accepted.

## Actions and idempotent recovery

| Actual queue state | Supported presentation actions |
| --- | --- |
| Submitted | None |
| Failed | `retry` |
| Ready | `requestRun` |
| Submitting with unexpired lease | None |
| Submitting with expired lease | `requestRun` |

`SubmissionService.requestRun(id)` serializes a fresh uncached queue read.
Absent intent throws `StateError`. Submitted intent returns unchanged without
wake. Every other state can request the existing scheduler wake without requeue,
claim, upload, submit or new intent. Scheduler failure returns its existing safe
notice. Presentation exposes only the actions in the table; execution reads
freshly. Retry performs the existing failed-to-ready transition, retaining exact
request/subject/packet identity, reservations, receipts and history, and rejects
active submitting state. Borrowed resources remain usable after service close.

Acknowledgement recovery uses the same immutable idempotent request POST, with
the same `Idempotency-Key` and packet. Successful uploads are reused. There is
no reconciliation GET/status endpoint, replacement payload or second queue id.
Storage receipt is upload evidence; only matching server acknowledgement is
submission acceptance. Local fencing does not imply exactly-once remote effects.

## Executable specifications and acceptance attribution

[TS1/TS2](../../test/submission/submission_transfer_status_test.dart) author pure
operation/action/reference/network matrices and immutable actual progress.
[DR1–DR5](../../test/submission/submission_dispatch_recovery_test.dart) author real
FileCaptureStore photo/audio and SQLite write-loss/restart recovery, competing
handle/retirement fences, current-versus-earlier refusal, literal v1 reads and
v2 transitions, plus actual public HTTP transport over controlled streams.
[Fixtures](../../test/support/submission_fixture.dart) own disk/client lifetimes
and bounded entry/release barriers. These are authored specifications; this
worker has run no tests, analyzer, formatter or runtime commands.

Selected parent software validation passed; independent S1 acceptance remains pending. Host
FFI or controlled HTTP success is neither Android separate-isolate/WorkManager
restart acceptance, real Google Drive access/upload acceptance nor actual
EditingStudio server acceptance. Fake server acknowledgement remains controlled
ESA6-07 evidence only. Prior accepted A/B1/B2 and audio histories are preserved;
historical native Kotlin/APK compile evidence remains historical and does not
validate these changed Dart paths. The next S2 execution access guard and status
query integration remain mandatory. Core Phase 2 and TFAF Phase 3 keep separate
planned startup/review/closure histories; this App Phase work starts/closes neither
and substitutes for neither package's full acceptance. No ESA6-06 Step, App
Phase6.1 closure, publication, deployment or release is claimed.
