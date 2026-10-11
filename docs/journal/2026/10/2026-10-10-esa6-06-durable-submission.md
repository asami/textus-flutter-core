# ESA6-06-A durable submission authoring

Current status: parent host software validation passed; FIX34 actual selected
Android NC1 and separate-process NC2, existing Q4 and all 115 selected Core cases
passed in `esa61-fix34-validation-20261011@1`. Historical parent receipt
`esa61-drive-consent-timing-validation-20261011@2` records successful main/test
compilation and 31 JUnit policy tests with zero failures/errors/skips, six-path
whitespace checks without diagnostics and 23 resolved local links.
`esa61-native-drive-post-timing-actual-20261011@3` records actual ND1 human
exact-account Google consent/dedicated-folder verification, ND2 stable-original
68-byte upload/idempotence with independent metadata/binary readback, and ND3
fresh-process silent credentials with the same original/folder/file/reservation/
receipt and 68-byte readback without grant UI/create/upload. Each native stage
exited 0 with one pass, zero failures and two explicit other-stage skips.
Independent protected timing review, B2 whole-boundary source integration,
wider shared foreground/headless, offline/restart/OS-stop and security behavior,
Core Phase 2/TFAF Phase 3 closure, whole 153-path Step independent acceptance
and exact Step commits, full App Phase review, aggregate validation and release
remain pending. No real Book-media or server-implementation acceptance is inferred.

Current timing status: Independent focused review
`esa61-drive-timing-focused-review-20261011@1`, admitted in review ledger revision
28, found P1 `CPB-ESA61-DRIVE-TIMING-001` in the native `authorizeDrive` entry's
enclosing 20-second deadline. The shared entry repair and six AT9–AT14 regressions
are authored under `esa61-drive-native-entry-fix-20261011@2`. Parent receipt
`esa61-drive-native-entry-validation-20261011@1` now records successful main/test
compilation and all 37 JUnit policy cases with zero failures/errors/skips.
Postrepair ND1 invoked the actual public entry over the retained grant/account/
folder and exited 0 with one pass, zero failures and two other-stage skips;
build 19.5 seconds, preserving install 8.4 seconds, test 3 seconds. AT9 proves
53-second SDK-plus-consent success through the shared entry under virtual time.
This native smoke establishes no new human consent or actual greater-than-20-
second waiting. The finding remains unresolved until fresh independent review.
Historical 31-case/native-three-stage passes retain their original scopes;
ND2/ND3 were not rerun here. Whole 153-path Step, Core Phase 2/TFAF Phase 3,
full App Phase review, aggregate validation and release remain unaccepted.

Owner: Textus Flutter Core implementation slice, PHASE-6.1 / ESA6-06 / ESA6-06-A.
Parent retains validation, review, transition, commit and Phase authority.

Update rule: Append parent-recorded exact validation/review evidence and any admitted
contract change. Preserve the original slice/Phase history and acceptance limits.

The earlier authoring and validation sections below retain their historical
stage attribution. Their pending statements describe obligations at that
authoring/receipt stage; only the dated latest parent receipt at the end
projects subsequent actual results. Earlier failures remain failed.

Frozen manifest: esa61-submission-core-manifest-20261010@1, authority
esa6-1-authority-20261009@1, binding esa6-1-goal-binding-20261009@1, epoch
esa6-1-epoch-1@1. Mutation is limited to its 16 Core paths. App and TFAF are read-only
consumers for this slice.

The [public handoff note](../../../notes/durable-material-submission.md) records
immutable generic request/record values, exact version 1 codec and local-only
document exclusion from packets. The new dedicated SQLite queue atomically
publishes intent, preserves subject uniqueness and complete checkpoints/history,
strictly decodes indexed rows, and fences claims, expiry and lease renewal.
The service borrows originals/queue/ports, performs one remote operation per run,
prepares all missing reservations before uploading, renews ownership before
dispatch, exposes safe stage failures/retry and separates server acknowledgement
from storage success. Export additions and sqflite dependencies preserve accepted
photo/audio/transcript/document schemas and existing consumer APIs.

Validation repair `VAL-ESA61-SUBMISSION-SQLITE-CONTENTION-001` bounds exclusive
transaction entrance to three attempts, yielding 25ms outside the transaction
only for primary SQLite BUSY/LOCKED before the callback begins. Entered callbacks
are never replayed; callback/commit errors, other errors and exhausted contention
propagate. The real concurrent Q3 claims now explicitly require one null loser
as well as one winner. Parent Q3 validation passed; independent acceptance remains
pending.

## Authored scenarios

| IDs | Source | Given / When / Then obligation |
| --- | --- | --- |
| M1/M2 | [model](../../../../test/submission/submission_model_test.dart) | Mutable nested intent/checkpoints / public constructors and exact wire decoders / deep immutable value equality, UTC roundtrip, malformed input refusal and opaque empty-material acceptance. |
| Q1 | [service](../../../../test/submission/submission_service_test.dart) | Actual original photo/audio files and real SQLite / offline Commit, distinct reopen after each one-operation stage / exact bytes, provenance, whitespace, context, Ready checkpoints and matching fake server acknowledgement. |
| Q2 | [queue](../../../../test/submission/submission_queue_store_test.dart) | Independent handles and caller JSON / equal/conflicting enqueues and reopen / accepted intent remains unchanged and unique per subject. |
| Q3 | queue | Competing handles and explicit clock / claim, renewal, rollback, expiry and stale token mutations / one active winner, deterministic order and preserved fenced checkpoints. |
| Q4 | queue | Actual file database and checkpoint/history / reopen, mismatches, actual transaction failure, corrupt body/index or future schema / exact retention, observable rejection and subsequent write recovery. |
| Q5 | service | Independent storage/transport failures or incorrect identities / bounded stages, automatic due time and explicit retry / safe full history, retained receipts, empty-material bypass and no storage-only Submitted. |
| Q6 | service | Controlled remote success with real durable reservation/request / selected checkpoint write loss and distinct restart / propagated local error and exact idempotent file/server identity replay. |
| Q7 | service | Scheduler failure or Submitted duplicate / durable Commit/retry before wake / safe notice, retained intent and no repeat wake/send for Submitted. |
| Q8 | service | Controlled owner/close/read/remote barriers and explicit short timeout / invalidation, stolen/expired lease or late completion / no old-owner publication, valid release and usable borrowed resources. |
| Q9 | service | Missing/corrupt original or queue and changing consumer JSON / Commit/process/invocation-order/close boundaries / no fabricated persistence, no deletion and unchanged intent snapshots. |

Fixture setup/teardown, remote callbacks and forwarding write/read barriers carry
adjacent Given/When/Then clauses tied to real actions and observable assertions.
They use Flutter `group`/`test`/`expect`; no source/header/version/metadata-only
assertions are added. Controlled fake identities are test-only ports.

## Parent-executed host validation

The manifest selected offline Flutter dependency resolution, representative Q1,
the three new submission suites plus the eight direct capture/audio/public-library
consumer suites, `dart analyze lib test`, exact-path dry formatting, diff check and
mechanical documentation/specification preflight. The implementation worker ran
none of these. Offline resolution initially lacked sqflite_common_ffi in the cache;
the bounded normal Flutter dependency resolution then succeeded. Dependency delta
is exactly sqflite `^2.4.4+1` and development-only
sqflite_common_ffi `^2.4.3`; existing SDK/version/dependency constraints remain.

Parent execution after the two recorded validation repairs passed representative
Q1 (one test), concurrent Q3 (one test) and the eleven-suite accumulator (99 tests,
zero failures). `dart analyze lib test` reported no issues; dry formatting of the
13 owned Dart paths changed zero files; `git diff --check` passed. The controlled
host ports and FFI database establish software behavior only. Independent review
and the separately required native and actual Drive evidence remain pending.

Remaining B/C/D work includes actual Core storage/HTTP/auth/native scheduling,
TFAF facade/state UI and App Book Commit mapping. Native registry/APK and Android
separate-isolate SQLite/WorkManager restart/offline evidence are owed separately
from FFI host software checks. Real Drive acceptance remains separate from fake
ports. ESA6-07 fake transport success/failure/retry/offline acceptance, ESA6-08
original-media/provenance server handoff, exact Step commits, the sole epoch 1
comprehensive Phase review, final aggregate validation and the distinct Phase
release commit remain parent-owned required work. Actual server implementation
and EditingStudio server acceptance remain outside this slice.

## 2026-10-10 — FIX23 protected Core correction authored

Parent-frozen `esa61-submission-core-readiness-fix23-20261010@1` retains the
original Phase authority and admitted nested Core participant. Candidate23 is
reserved after consumed22; the parent owns accounting, validation, review and
transitions. This bounded author pass changes only the seven manifest paths.

`VF-ESA61-CORE-SQLITE-OPEN-001` moves the unchanged SQLite 5000ms busy wait before
the initial FULL synchronous pragma. `VF-ESA61-CORE-MISSING-LIST-001` removes only
the later stat from the two missing-path catches: document null and collection
empty describe the failed operation, and later creation is visible to a fresh
call. Schema/API, transaction entrance retry, error observability, original bytes,
corruption checks and atomic writes retain their contracts.

| Scenario | Given / When / Then obligation |
| --- | --- |
| Q4 opening an independent handle waits for an existing lock | Warm real production FFI queue and durable intent / real main-event-loop raw EXCLUSIVE lock, observed production configure entry and 50ms COMMIT / successful independent open, exact FULL=2 and busy_timeout=5000, retained original plus subsequent enqueue/read/reopen. |
| F1 missing listing remains empty when the collection is then created | Actual absent native directory / native ENOENT followed by real collection/final JSON creation before rethrow / first public listing empty, fresh listing sees retained created id and exact file. |
| F2 missing read remains null when the document is then created | Actual absent native file / native ENOENT followed by parent/final object creation before rethrow / first public read null, fresh read sees the exact retained created object. |
| F3 nonmissing read and listing failures preserve documents and originals | Accepted real document/original bytes / selected read/list permission failures / same errors observable and fresh document/list/material reads retain accepted data. |

The forwarding factory preserves supplied open options/callbacks and only
observes configure entry. Its immediate error observer and finally block join
opening/release work and close owned handles before fixture deletion. Scoped IO
wrappers delegate real selected operations, construct unselected entities through
native super constructors, leave filesystem type checks native and reject
unsupported members explicitly. All authored scenarios, callbacks, helpers and
cleanup have adjacent semantic Given/When/Then clauses.

Parent-selected validation covers the new representative regressions, Core's
ten-suite accumulator and unchanged App BU7 queue acquisition/query and W5
held-camera exit consumers, plus analysis/format/diff and independent protected
source conformance review. This authoring records no executed validation result
or new commit. Earlier host and source acceptance facts remain historical; the
protected correction awaits fresh parent evidence. Native/actual Drive,
whole-Step and Phase acceptance remain pending, including the final aggregate
driver and distinct Phase release gate.

## 2026-10-11 — FIX32 native initial schema correction authored

Parent-frozen `esa61-submission-native-init-fix32-20261011@1` admits only the five
existing Core paths for `VF-ESA61-NATIVE-INITIAL-SCHEMA-001`, under the original
Phase authority, binding and epoch. Parent retains validation, independent
review, accounting, transitions and commit authority.

The actual Fold NC1 APK build and install passed, but its first configuration
snapshot returned `configurationUnavailable` before fixture writes. The parent
recorded this original failure in
`esa61-submission-native-configuration-validation-20261011@1`, session 20151,
exit 1, log `submission-native-configuration-write-20261011.log`. The follow-up
`esa61-submission-native-schema-observation-20261011@1` found version 0 with only
Android-owned `android_metadata`: one `locale TEXT` column, nullable, no default
and no primary key. The prior guard rejected every non-SQLite-internal table,
including this platform-created table, before Core initialization.

The authored pure policy permits exactly an empty initial schema or that single
canonical Android metadata table/column signature. The actual store collects
ordered table names and all six `PRAGMA table_info` fields, preserving a null
default, then validates before creating the unchanged Core tables/version in the
existing transaction. Unknown/Core tables, mixed or duplicate/case-mismatched
metadata and malformed columns fail safely. There is no normalization, adoption,
metadata manipulation, reset, data/key deletion or application-row inspection.
FULL writes, busy timeout, close-on-error, schema version, ciphertext, AAD, key,
public channel, queue and ownership contracts retain their existing semantics.

| Scenario | Given / When / Then obligation |
| --- | --- |
| `initialSchemaAcceptsEmptyAndAndroidMetadataOnly` | Empty observations or the exact platform locale signature / actual initial-schema policy validation / accepted return and unchanged supplied tables/columns. |
| `initialSchemaRejectsUnknownTablesAndInconsistentMetadata` | Unknown/Core tables, mixed/duplicate/case-mismatched metadata or columns without a table / actual policy admission attempt / `configurationUnavailable`, safe exception fields and unchanged observations. |
| `initialSchemaRejectsMalformedAndroidMetadataColumns` | Canonical table name with missing/extra/renamed/wrong-type/incorrect-index/not-null/default/primary-key column changes / actual policy validation / fixed safe failure and unchanged observations. |

Adjacent semantic Given/When/Then clauses also describe the immutable column
value, pure admission policy and real store observation/validation/creation
boundary. Existing tests, assertions and execution order are retained.

This is authored-only evidence: this repair editor executed no tests, analysis,
Gradle, formatting, runtime, self-review or commit. Parent-selected native policy
compilation/tests, the original actual NC1 write proof and distinct-process NC2
restore proof remain pending. Earlier producer source passes retain their original
scopes and do not establish this correction or native persistence acceptance.
Native/headless, Google grant, actual Drive upload/readback, producer own-Phase,
complete Step independent acceptance, Step commits, full Phase review, final
aggregate validation and the distinct Phase release remain separately owed.

## 2026-10-11 — FIX33 native busy-timeout scalar correction authored

Parent-frozen `esa61-submission-native-busy-fix33-20261011@1` admits only the three
existing Core paths for `VF-ESA61-NATIVE-BUSY-PRAGMA-001`, under the original
Phase authority, binding and epoch. Parent retains validation, independent
acceptance, accounting, transitions, commits and all Phase closure authority.
The original whole 150-path ESA6-06 Step and Phase 6.1 scope remain unchanged.

FIX32 actually compiled and passed 23 pure-policy tests. Its corrected Fold NC1
APK built in 12.8 seconds and installed in 13.1 seconds, then the first snapshot
still returned `configurationUnavailable` before fixture put/select/token/proof
writes. Parent record `esa61-fix32-native-validation-20261011@1` retains session
69731, exit 1 and log `submission-fix32-native-configuration-write-20261011.log`.
NC2 was not launched because NC1 failed. The fresh schema observation
`esa61-fix32-native-schema-observation-20261011@1` remains version 0 with only
the canonical Android metadata table, no Core tables and no unknown tables.
The prior metadata guard was a real latent source defect; it was not a proven
sole explanation of the original safe failure. Historical failed receipts remain
failed, and policy passes establish no actual Android SQL or persistence success.

The frozen source evidence confirms a direct API violation: the busy-timeout
assignment returns one numeric row, while Android `execSQL` uses
`SQLiteStatement.executeUpdateDelete` and the non-query path, which rejects
that row. The store's safe catch hides the lower native exception, so attribution
as the sole device cause remains unproven before direct native success.
The bounded correction uses `compileStatement("PRAGMA busy_timeout = 5000").use`
and `simpleQueryForLong()`, requires exactly `5000L`, and closes the statement on
success or failure before the unchanged `beginTransaction()`. Adjacent semantic
Given/When/Then clauses describe the acquired FULL-durability database, scalar
execution/owned cleanup and exact wait before transactional schema admission.
The FULL assignment, strict empty/canonical schema policy, CREATE/version,
commit/rollback, close-on-error, key/AAD/encryption, channel and ownership logic
retain their existing contracts.

This receipt is authored-only evidence. This repair editor executed no tests,
Gradle, analysis, runtime, formatting validation, self-review or commit. No new
tests or assertion changes were authored. The existing actual NC1 and distinct
process NC2 remain the parent-selected regression oracle for acquisition/scalar
setup, snapshot, writes, reopen, revoke/restore, default-resource factory,
at-rest observations and process reload; all setup/actions/assertions/order and
stage skips are retained. FIX33 awaits parent native validation and independent
acceptance. Prior producer evidence retains its original scopes. Native/headless,
Google grant, actual Drive upload/readback, producer own-Phase, whole Step
independent acceptance, Step commits, full Phase review, final aggregate
validation and the distinct Phase release remain separately owed.

## 2026-10-11 — FIX34 durable queue busy-timeout query correction authored

Parent-frozen `esa61-submission-queue-busy-fix34-20261011@1` admits only the three
existing Core paths for `VF-ESA61-QUEUE-BUSY-PRAGMA-001`, under the original
Phase authority, binding and epoch. Parent retains validation, independent
acceptance, accounting, transitions and commit authority. The original whole
150-path ESA6-06 Step and Phase 6.1 scope remain unchanged.

FIX33 actually compiled and passed 23 pure-policy tests. Parent receipt
`esa61-fix33-native-validation-20261011@1` records the actual Fold NC1 session
59561, exit 1, log `submission-fix33-native-configuration-write-20261011.log`,
APK build 22.2 seconds and install 2,553ms. Initial configuration snapshot,
fixed dummy definition/token/access writes, temporary selection, same-engine
close/reopen and exact token reload, persisted empty access revoke/reopen,
access restore, exact original selections and preserved nonfixture definitions
completed. Configuration owner cleanup completed before the default-resource
factory attempt. This establishes configuration acquisition progress after FIX33.

The first default queue open then failed at
`sqlite_submission_queue_store.dart:55` with `SqfliteDatabaseException` because
the nonquery execution path rejected the result row from
`PRAGMA busy_timeout = 5000`. First factory completion/list, second factory,
at-rest canary observation and successful-write marker were not reached. NC1
had zero passes, one failure and one explicit other-stage skip. NC2 was not
launched because the entire NC1 stage and marker prerequisite failed. All
original failed receipts remain failed; sequential configuration progress does
not establish complete native persistence or distinct-process acceptance.

`VF-ESA61-QUEUE-BUSY-PRAGMA-001` maps to one bounded replacement: the existing
queue `onConfigure` now awaits `rawQuery('PRAGMA busy_timeout = 5000')` before
the unchanged FULL `execute`. Installed sqflite Android `execute` uses
`SQLiteDatabase.execSQL`; its nonpaged query path uses `rawQueryWithFactory`,
traverses the result cursor and closes it in `finally`. Awaiting that query
consumes the numeric assignment result before FULL writes and schema access.
Version 1, the exact 5000ms wait, transaction entrance retry, callback execution,
ownership and close contracts retain their semantics. No guard, helper, timeout,
schema, public API, dependency or test change is authored.

Adjacent production Given/When/Then clauses describe the acquired independent
handle whose schema may be locked, the result-returning wait assignment awaited
as a query, and consumption before FULL writes/schema access. Existing Q4
remains the regression oracle for a real independent open under an EXCLUSIVE
lock, retained records, exact busy_timeout=5000 and FULL=2, subsequent enqueue
and fresh reopen. The original NC1/NC2 scenarios and all their setup, actions,
assertions, order and stage skips are retained.

This receipt is authored only. This repair editor ran no tests, validation,
analysis, formatter validation, runtime, self-review or commit. Parent owns fresh
original NC1 followed by distinct-process NC2, existing Q4 and the ten-suite
115-case Core accumulator, source/dry-format/whitespace/document checks and
independent acceptance. No same-file debt was newly admitted. Native/headless,
Google grant, actual Drive upload/readback, producer own-Phase, ESA6-07 fake
transport success/failure/retry/offline, ESA6-08 original-media/provenance handoff,
whole Step independent acceptance and exact Step commits, the sole epoch 1
comprehensive Phase review, final aggregate validation and the distinct Phase
release remain separately owed. Saved photo/text compatibility and original
audio/editable transcript obligations remain part of the original Goal; server
implementation and successor Phases remain outside this repair.

## 2026-10-11 — FIX34 parent validation receipt

Parent receipt `esa61-fix34-validation-20261011@1` supplies the executed results
for `esa61-submission-queue-busy-fix34-20261011@1`, with author intake
`esa61-fix34-author-intake-20261011@1` and mechanical reference
`esa61-fix34-author-mechanical-20261011@1`. The status-only manifest
`esa61-fix34-status-docs-manifest-20261011@1` addresses
`M0-ESA61-FIX34-STATUS-001` in the two owned documents with additional charge 0
under consumed Fix34. Original authority, binding, epoch, whole 150-path
ESA6-06 Step and Phase 6.1 Goal obligations are retained. Historical failures and
the earlier authored-only receipts above retain their original scopes.

NC1 completed fixed configuration writes, same-engine reopen and exact token
reload, persisted empty access revoke/reopen, access restore, original selections,
preservation of nonfixture definitions and configuration-owner cleanup. It also
completed two sequential actual default-resource factories with queue-list
equality, noBackup known-canary/account/folder/endpoint absence and saving the
opaque successful marker. NC2 ran in a separately launched Flutter process after
actual NC1 success over retained App data. It read the marker, configuration,
token and restored selections, completed the default factories and at-rest
observations. Exact token assertions emitted no token value; both stages reported
only the safe observations `tokenPresent=true`, `atRest=true`, `queueCount=0`.

The parent executed the following commands. App workdir was
`/Users/asami/src/Project2026/nict-editing-studio-app`; Q4 and Core10 workdir was
`/Users/asami/src/Project2026/nict-editing-studio-app/.codex-workflow/checkouts/textus-flutter-core`.
The source analysis and dry-format entries supply commands/results without a
separate workdir field in the receipt.

- NC1: `/opt/homebrew/bin/flutter test integration_test/book_submission_native_test.dart -d 67021FDDJ000JA --no-pub --no-uninstall --dart-define=SUBMISSION_NATIVE_PROOF=true --dart-define=SUBMISSION_PROOF_STAGE=configuration-write --reporter expanded`; session 86912, terminal chunk `1202bc`, exit 0, one pass, zero failures, one explicit other-stage skip. APK build 10.3 seconds, install 12.6 seconds; log `submission-fix34-native-configuration-write-20261011.log`.
- NC2: `/opt/homebrew/bin/flutter test integration_test/book_submission_native_test.dart -d 67021FDDJ000JA --no-pub --no-uninstall --dart-define=SUBMISSION_NATIVE_PROOF=true --dart-define=SUBMISSION_PROOF_STAGE=configuration-restore --reporter expanded`; session 66497, terminal chunk `5a6b6a`, exit 0, one pass, zero failures, one explicit other-stage skip. APK build 9.8 seconds, install 2,237ms; log `submission-fix34-native-configuration-restore-20261011.log`.
- Q4: `/opt/homebrew/bin/flutter test --no-pub test/submission/submission_queue_store_test.dart --plain-name "Q4 opening an independent handle waits for an existing lock" --reporter expanded`; session 87003, terminal chunk `ce737f`, exit 0, one pass, zero failures/skips; log `submission-fix34-core-q4-20261011.log`. Existing independent-handle lock/retained-record assertions preserve exact busy_timeout=5000 and FULL=2.
- Core10: `/opt/homebrew/bin/flutter test --no-pub test/submission/submission_queue_store_test.dart test/submission/submission_service_test.dart test/submission/submission_background_runner_test.dart test/submission/submission_reference_guard_recovery_test.dart test/submission/submission_transfer_query_test.dart test/submission/submission_http_integration_test.dart test/capture/local_capture_store_test.dart test/capture/file_capture_store_absence_race_test.dart test/audio/audio_capture_service_test.dart test/audio/audio_transcript_codec_test.dart --reporter expanded`; session 35506, terminal chunk `3ef995`, exit 0, ten suites, 115 passes, zero failures/skips; log `submission-fix34-core-accumulator-20261011.log`.
- Source analysis: `/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart analyze lib/src/submission/sqlite_submission_queue_store.dart`; chunk `c26798`, exit 0, `No issues found`; log `submission-fix34-core-analysis-20261011.log`.
- Dry format: `/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart format --output=none --set-exit-if-changed lib/src/submission/sqlite_submission_queue_store.dart`; chunk `fde5c1`, exit 0, one file, zero changes; log `submission-fix34-core-format-20261011.log`.

These logs are retained by the parent in App's
`.codex-workflow/phases/PHASE-6.1/`. The
[current runtime note](../../../notes/android-submission-runtime.md) records the
same scoped evidence. This status editor ran no tests, validation, analysis,
formatter validation, runtime, self-review or commit. Parent owns final
prose/links/whitespace intake and transitions; prior actual source validations
are reused for this documentation-only delta without a test rerun.

`queueCount=0` proves default-factory acquisition and retained empty-queue
observations; it does not prove queued Book recovery or submission/dispatch.
Known-value absence at rest supplies no hardware-backed keystore/security
certification. This receipt supplies no consent, Drive, HTTP, headless wake or
dispatch, offline or OS-stop proof. No scenario, assertion, schema, API,
acceptance criterion, repository owner or Phase status changed.

Remaining obligations include B2 independent source conformance, broader native
and shared foreground/headless configuration acceptance, exact-account Google
grant/silent refresh, actual Drive upload/binary readback, offline/restart/OS-stop
and lease recovery, producer own-Phase closure, whole 150-path Step independent
acceptance and exact Step commits. ESA6-07 fake transport
success/failure/retry/offline, ESA6-08 original-media/provenance handoff, the sole
epoch 1 comprehensive Phase review, final aggregate validation through
`scripts/validate-full.sh` and the distinct Phase release commit with persisted
closure records remain parent-owned. Saved photo/text compatibility and original
audio/editable transcript remain part of the original Goal. This receipt grants
no Step or Phase acceptance; server implementation and successor Phases remain
outside this repair. No same-file target-program debt was newly admitted.

## 2026-10-11 — Bounded Drive authorization diagnostics authored

Parent-frozen `esa61-drive-authorization-diagnostics-manifest-20261011@2`
admits the existing native authorization file, runtime note and this journal
under original Phase 6.1 authority, binding and epoch, ESA6-06. The pre-edit
governance supplement freezes the event literals and sanitized evidence.
Parent retains compilation, native reproduction, independent acceptance,
transitions and commits.

Actual attempt `esa61-native-drive-actual-attempt-20261011@1` records ND1
`drive-authorize`, session 23896, exit 1, zero passes, one failure and two
explicit other-stage skips. Its actual APK build and preserving install
succeeded, then authorization returned `authorizationCancelled`. The retained
log is `submission-native-drive-drive-authorize-actual-20261011.log` in the
parent App Phase 6.1 records. ND2 and ND3 were not launched; no upload or restore
proof was obtained. Private marker/configuration changes remain retained without
clearing, reset or a new reservation. Earlier failed and successful receipts
retain their original outcomes and scopes.

Parent chunk `e232e1` observed AndroidUtils:
`mismatch between getCallingPackage com.example.nict_editing_studio_app and getLaunchedFromPackage com.google.android.gms for activity com.google.android.gms.auth.api.credentials.authorization.ui.AuthorizationActivity [CONTEXT service_id=259 ]`.
This is a clue with no confirmed causal attribution. Official
[Identity overloads](https://developers.google.com/android/reference/com/google/android/gms/auth/api/identity/Identity)
support Activity and Context; the existing Context use is not established as
invalid. The official
[AuthorizationClient contract](https://developers.google.com/android/reference/com/google/android/gms/auth/api/identity/AuthorizationClient)
describes authorization results and Intent parsing with ApiException failure.

The authored private synchronous helper uses `android.util.Log`, fixed tag
`TextusDriveProof` and `ApplicationInfo.FLAG_DEBUGGABLE`. It emits only frozen
literal events with optional single integer codes or boolean 0/1 and catches
diagnostic exceptions. Observations surround existing lifecycle/cancellation,
owner acquisition/guard rejection, SDK request/result, resolution launch/return,
matching Activity result, actual grant writes and final owner finish. Pause,
detach and finish use their already-evaluated decisions once. Unsuccessful SDK
Tasks preserve `credentialUnavailable` and listener/late-task handling while
observing only ApiException status or the fixed missing-status event.

Matching non-OK Activity results with nonnull data receive best-effort SDK
diagnostic parsing only when debuggable; successful parsing is ignored, and
ApiException contributes only its numeric status. Unmatched/retired or null-data
results are not parsed. All matching cancellation paths retain exactly
`authorizationCancelled`; no credential or grant is accepted from diagnostics.
Exact account and `drive.file`, owner fences, grant persistence, cleanup and
20-second timeout behavior are retained without retry or consent bypass.

Executable-specification authoring is `not_applicable`: business behavior and
ND1/ND2/ND3, lifecycle policy scenarios, assertions and order are unchanged.
No source-shape or log-text test was added. No same-file target-program debt was
newly admitted; separate causal correction requires a later parent-frozen Fix
Manifest and the selected fix worker.

This receipt is authored only. At that authoring stage, the author performed no tests, validation,
network/device/runtime activity, self-review, staging or commit. Parent owns
plugin compilation/existing policy suites and one planned ND1 diagnostic
reproduction over retained markers with preserving install and unique receipt;
ND2/ND3 require actual ND1 success. The
[runtime note](../../../notes/android-submission-runtime.md) records the same
pending status. No failure is classified fixed by authoring. Actual Google grant,
folder access, Drive upload/binary readback, broader native/headless acceptance,
producer own-Phase, whole Step independent acceptance, exact Step commits,
ESA6-07/08, comprehensive Phase review, aggregate validation and distinct Phase
release remain parent-owned and open.

## 2026-10-11 — Separate SDK and foreground consent timing authored

Parent-frozen `esa61-drive-consent-timing-fix-20261011@1` addresses
`VF-ESA61-DRIVE-CONSENT-DEADLINE-001` within exactly six Core paths under the
original Phase 6.1 authority, binding and epoch, ESA6-06. Core Phase 2 TFC2-03
retains its separate runtime-prerequisite and closure responsibility. Parent
owns validation, independent review, accounting, transitions and commits.

Actual setup receipt `esa61-cloud-setup-actual-20261011@3` records Drive API
enabled, OAuth branding completed with External Testing, the specified test
user and only `drive.file` saved, and an Android OAuth client successfully
created for the actual consumer package and signing identity. No account,
client identifier, signing fingerprint or credential is reproduced here.
Cloud configuration alone does not prove propagation, native grant or Drive
access. The same private account/marker/folder reservation and retained App
data remain the acceptance prerequisites.

Postconfiguration receipt `esa61-native-drive-post-oauth-attempt-20261011@2`
records actual ND1 `drive-authorize`, session 18728, terminal chunk `499126`,
exit 1, zero passes, one failure and two explicit other-stage skips. APK build
took 16.6 seconds and preserving install 3.1 seconds. The parent retains
`submission-native-drive-drive-authorize-post-oauth-20261011.log` and
`drive-post-oauth-events-20261011.log` in its App Phase 6.1 records. ND2 and ND3
were not launched. All previous failed attempts retain their failed outcomes;
this attempt supplies no successful grant, upload or restore.

Fixed `TextusDriveProof` events from chunk `2fd291`, process 16354, show SDK
request at 08:02:12.570, `hasResolution` and resolution launch at
08:02:20.174, expected `pause_cancel:0`, and owner finalization at
08:02:32.547. No Activity result or resolution return was observed. The SDK
response after about 7.6 seconds consumed part of the existing 20-second
whole-call deadline, leaving about 12.4 seconds for human resolution before
final cleanup cancelled it. This directly evidences the internal shared-budget
defect without attributing a human rejection or proving every earlier cause.

The new internal
[timing policy](../../../../packages/textus_flutter_core_android_submission/android/src/main/kotlin/org/textus/flutter/core/submission/SubmissionAuthorizationTiming.kt)
contains only fixed timeout constants and three generic suspend wrappers:
SDK 20,000ms, explicit foreground consent 120,000ms, complete authorization
160,000ms. [GoogleDriveAuthorization](../../../../packages/textus_flutter_core_android_submission/android/src/main/kotlin/org/textus/flutter/core/submission/GoogleDriveAuthorization.kt)
uses those wrappers only around the existing complete explicit call, its
first SDK await and its pending-resolution await. The outer bound leaves
20 seconds of bounded margin for local configuration/grant work. Silent
`bearerToken`/`state` retain the existing 20-second/no-consent behavior. Exact
account and `drive.file`, engine/activity/lineage and result-code fences,
single pending resolution, captured cleanup order, grant writes and fixed
no-secret diagnostics retain their contracts. There is no restart or retry.

The new [SubmissionAuthorizationTimingTest](../../../../packages/textus_flutter_core_android_submission/android/src/test/kotlin/org/textus/flutter/core/submission/SubmissionAuthorizationTimingTest.kt)
authors eight JUnit4 scenarios through the production timing wrappers and,
where required, the existing actual pure consent lifecycle. AT1 waits 8 seconds
for SDK then 45 seconds for consent, succeeding at 53 seconds. AT2 preserves
the unresolved SDK's 20-second deadline and prevents consent. AT3 establishes
the independent 120-second consent bound, cancelled pending reply, no controlled
publication and one captured-owner finish. AT4 bounds unresolved local work
at 160 seconds. AT5 establishes immediate caller cancellation, singular cleanup
and rejected late completion. AT6 rejects a retired SDK continuation without
finishing a replacement owner; AT7 rejects the continuation after unrelated
prelaunch pause. AT8 retains launched consent across its expected pause and
configuration reattachment, accepts one delayed result and rejects duplicate
or stale completion. Adjacent semantic Given/When/Then clauses accompany
scenario setup, child behavior, actions, observable assertions and owned
teardown. Controlled results are not Android/SDK/Drive success evidence.

Only test-only `kotlinx-coroutines-test:1.7.3` is added to
[the plugin build](../../../../packages/textus_flutter_core_android_submission/android/build.gradle),
matching production coroutines 1.7.3. Virtual scheduler advances process their
boundaries explicitly; no real sleeping, dispatcher replacement, public hook,
injected production duration or source/log predicate is introduced. Every
scenario cancels/joins its owned child and retires its deferreds; expected
timeouts/cancellation are handled within child results. Existing lifecycle,
work and connection scenarios/assertions are unchanged.

This receipt is authored only. At that authoring stage, the repair author ran no tests, Gradle, Flutter,
network, device operation, validation, self-review, staging or commit. Parent
owns compilation and the selected four-suite policy accumulator, source/diff
and document intake, one meaningful postrepair ND1 with actual human-operated
consent, and fresh independent protected-boundary review. ND2/ND3 require
actual predecessor success. The [runtime note](../../../notes/android-submission-runtime.md)
records the same timing and pending evidence. No same-file target-program
debt or separate existing debt was newly admitted. Actual native grant,
Drive upload/binary readback, broader native/headless behavior, producer
own-Phase, whole Step and exact Step commits, ESA6-07/08, comprehensive Phase
review, full aggregate validation and distinct release remained separately owed
at that authoring stage. The subsequent scoped parent results follow.

## 2026-10-11 — Parent-executed timing policy and actual Drive receipt

Parent receipts `esa61-drive-consent-timing-validation-20261011@2` and
`esa61-native-drive-post-timing-actual-20261011@3` supply the following actual
results. Status manifest `esa61-drive-native-status-m0-fix-20261011@2` addresses
`MCR-ESA61-DRIVE-STATUS-001` in this journal and the
[runtime note](../../../notes/android-submission-runtime.md). Original authority,
binding, epoch and Goal remain retained. This author ran no tests, Gradle,
Flutter, network, ADB, project scripts, validation, self-review, staging or
commit. Parent owns document/diff/whitespace/link intake, review and transitions.
No source/test changes, reruns, new grant policy or acceptance are inferred.

In `/Users/asami/src/Project2026/nict-editing-studio-app/android`, parent executed
`./gradlew :textus_flutter_core_android_submission:testDebugUnitTest --tests 'org.textus.flutter.core.submission.*' --console=plain`:
session 75113, launch chunk `ca0aef`, terminal chunk `27d864`, exit 0,
`BUILD SUCCESSFUL` in 10 seconds with successful main/test compilation. Four
JUnit suites passed 31 tests with zero failures/errors/skips: authorization
timing 8, connection policy 10, run lifecycle 9 and work policy 4. Six-path
untracked no-index whitespace checks returned exit 1 for differences with zero
diagnostics; 23 local links resolved. Prior Gradle deprecation warnings remain.
These are controlled policy/compiler results, distinct from real grant and
remote-byte evidence. The existing
[timing policy](../../../../packages/textus_flutter_core_android_submission/android/src/main/kotlin/org/textus/flutter/core/submission/SubmissionAuthorizationTiming.kt),
[authorization source](../../../../packages/textus_flutter_core_android_submission/android/src/main/kotlin/org/textus/flutter/core/submission/GoogleDriveAuthorization.kt)
and [AT1–AT8 tests](../../../../packages/textus_flutter_core_android_submission/android/src/test/kotlin/org/textus/flutter/core/submission/SubmissionAuthorizationTimingTest.kt)
retain their prior authored contracts.

All following preserving Flutter commands ran in
`/Users/asami/src/Project2026/nict-editing-studio-app`, using the frozen
`esa61-native-drive-execution-plan-20261011@1` argv. The private account JSON
locator is shown only as a command path, without account/client/token/grant-secret
contents. Logs are retained in App `.codex-workflow/phases/PHASE-6.1/`.

- ND1: `/opt/homebrew/bin/flutter test integration_test/book_submission_drive_native_test.dart -d 67021FDDJ000JA --no-pub --no-uninstall --dart-define=SUBMISSION_DRIVE_NATIVE_PROOF=true --dart-define=SUBMISSION_DRIVE_PROOF_STAGE=drive-authorize --dart-define-from-file=/Users/asami/src/Project2026/nict-editing-studio-app/.codex-workflow/phases/PHASE-6.1/runtime/native-drive-account-20261011.json --reporter expanded`; session 58494, launch chunk `864cef`, yielded polls `62a644`/`5ed672`, terminal chunk `3938c4`, exit 0, one pass, zero failures, two explicit other-stage skips; build 15.8 seconds, preserving install 3.0 seconds, test 18 seconds; log `submission-native-drive-drive-authorize-post-timing-20261011.log`.
- ND2: `/opt/homebrew/bin/flutter test integration_test/book_submission_drive_native_test.dart -d 67021FDDJ000JA --no-pub --no-uninstall --dart-define=SUBMISSION_DRIVE_NATIVE_PROOF=true --dart-define=SUBMISSION_DRIVE_PROOF_STAGE=drive-upload --dart-define-from-file=/Users/asami/src/Project2026/nict-editing-studio-app/.codex-workflow/phases/PHASE-6.1/runtime/native-drive-account-20261011.json --reporter expanded`; session 85618, launch chunk `e3f133`, yielded poll `9b1233`, terminal chunk `8650dd`, exit 0, one pass, zero failures, two explicit other-stage skips; build 21.0 seconds, preserving install 2,780ms, test 10 seconds; log `submission-native-drive-drive-upload-post-timing-20261011.log`.
- ND3: `/opt/homebrew/bin/flutter test integration_test/book_submission_drive_native_test.dart -d 67021FDDJ000JA --no-pub --no-uninstall --dart-define=SUBMISSION_DRIVE_NATIVE_PROOF=true --dart-define=SUBMISSION_DRIVE_PROOF_STAGE=drive-restore --dart-define-from-file=/Users/asami/src/Project2026/nict-editing-studio-app/.codex-workflow/phases/PHASE-6.1/runtime/native-drive-account-20261011.json --reporter expanded`; session 59786, launch chunk `7ea0dc`, terminal chunk `0164bf`, exit 0, one pass, zero failures, two explicit other-stage skips; build 16.3 seconds, preserving install 2,905ms, test 2 seconds; log `submission-native-drive-drive-restore-post-timing-20261011.log`.

Every selected stage actually passed; other-stage skips are not proof of those
stages. ND1 establishes actual explicit human Google consent for the exact
account and retained dedicated-folder verification. Diagnostic chunk `d070dd`,
process 19319, in `drive-post-timing-events-20261011.log` records
`sdk_result_resolution:1`, `resolution_launch`, `pause_cancel:0`,
`activity_result_code:-1`, `activity_result_data:1`, `resolution_returned` and
`grant_complete`. ND1 alone supplies no image upload/restore proof. ND2 proves
actual default Core original-store/Drive adapter upload, stable reservation
idempotence and independent actual metadata/alt-media binary readback of 68
bytes; it alone supplies no process restore proof. ND3 ran in a separate fresh
Flutter process, silently retrieved exact-account credentials and retained the
same default Core original/folder/file/reservation/receipt with independent
68-byte readback. Restore performed no grant UI, create or upload.

AT1 proves 53-second virtual SDK-plus-consent success through the production
wrappers. Actual ND1 took 18 test seconds and does not prove actual human
waiting exceeded the former 20-second whole-call bound. Earlier fixed clock
receipts are device event-clock observations, not independently verified JST
wall-clock timestamps. Original failed receipts remain failed; all original
authors retain author-only attribution. SDK 20 seconds, foreground consent 120
seconds, whole call 160 seconds and silent 20 seconds, exact account/`drive.file`,
owner/security and public payload/provenance contracts are unchanged here.

Independent protected timing review, B2 whole-boundary source integration,
wider shared foreground/headless, offline/restart/OS-stop and security behavior,
Core Phase 2/TFAF Phase 3 own closure, whole 153-path Step independent acceptance
and exact Step commits, ESA6-07/08, the sole epoch 1 comprehensive App Phase
review, final aggregate validation through `scripts/validate-full.sh` and
distinct Phase release with persisted closure records remain separately owed.
The scoped 68-byte synthetic fixture establishes no real Book-media or server
implementation acceptance. No review, Step, producer Phase or release acceptance
is granted by this documentation. No same-file target-program debt or separate
existing debt was newly admitted.

## 2026-10-11 — Native authorization entry deadline repair authored

Independent protected review `esa61-drive-timing-focused-review-20261011@1`
found P1 `CPB-ESA61-DRIVE-TIMING-001`; parent admission retains the same ESA6-06-B2
boundary in review ledger revision 28. The internal timing repair was present,
but the actual native `authorizeDrive` branch still enclosed authorization in
`withTimeout(20000L)`. AT1's 53-second virtual success bypassed that enclosing
entry, while the actual historical ND1 completed in 18 test seconds. These
results did not close the original greater-than-20-second entry failure. Earlier
failed receipts remain failed. This finding remains unresolved at this authoring
stage until parent execution and fresh independent review establish closure.

Parent-frozen `esa61-drive-native-entry-fix-20261011@2` owns exactly five existing
Core paths under retained Phase authority, binding and epoch. The
[timing policy](../../../../packages/textus_flutter_core_android_submission/android/src/main/kotlin/org/textus/flutter/core/submission/SubmissionAuthorizationTiming.kt)
adds one internal pure dispatcher: `authorizeDrive` selects the existing fixed
160-second authorization wrapper, while `authorizationState` and `bearerToken`
select the existing fixed 20-second SDK wrapper. Unknown internal methods fail
with safe `configurationInvalid` before operation invocation. All three
[native plugin branches](../../../../packages/textus_flutter_core_android_submission/android/src/main/kotlin/org/textus/flutter/core/submission/TextusFlutterCoreAndroidSubmissionPlugin.kt)
use that dispatcher with their existing arguments. Acquisition, captured owner
guards, singular replies, error codes, cleanup/jobs and Activity result routing
retain their existing behavior. Internal SDK 20/consent 120/total 160-second
bounds, exact account and `drive.file`, silent no-consent behavior, security and
public payload/provenance contracts are retained. No file, dependency or API is
added.

The existing
[timing specification](../../../../packages/textus_flutter_core_android_submission/android/src/test/kotlin/org/textus/flutter/core/submission/SubmissionAuthorizationTimingTest.kt)
appends exactly six entry scenarios; AT1–AT8 retain their setup/actions/assertions
and order.

| Scenario | Given / When / Then obligation |
| --- | --- |
| AT9 `nativeEntryAllowsSdkAndConsentToExceedTwentySeconds` | Controlled SDK/consent replies and shared `authorizeDrive` entry with nested internal authorization / SDK reply at 8 seconds, consent pending another 45 seconds then completion / entry survives 53 seconds, returns available once, cleans once and rejects a duplicate reply. |
| AT10 `nativeEntryBoundsUnresolvedForegroundWorkAtOneHundredSixtySeconds` | Owned unresolved local work / shared foreground entry at 159,999ms then 160,000ms / live before the boundary, exact timeout, zero publication, one cleanup and retired pending work. |
| AT11 `nativeEntryKeepsAuthorizationStateAtTwentySeconds` | Owned unresolved silent state operation / exact method dispatch at 19,999ms then 20,000ms / live before the boundary, exact timeout, zero publication and one pending-wait cleanup. |
| AT12 `nativeEntryKeepsBearerTokenAtTwentySeconds` | Owned unresolved silent token operation / exact method dispatch at 19,999ms then 20,000ms / live before the boundary, exact timeout, zero publication and one pending-wait cleanup. |
| AT13 `nativeEntryPropagatesCallerCancellationAndRejectsLateCompletion` | Real pure consent lifecycle, captured resumed owner and launched pending resolution under entry plus internal authorization / caller cancellation at virtual time zero then late completion / cancellation observed, one captured finish/cleanup, retired owner/pending reply, rejected late completion and zero publication. |
| AT14 `nativeEntryRejectsUnknownMethodBeforeInvokingOperation` | Unknown internal method and operation invocation counter / actual closed dispatcher / safe `configurationInvalid` before invocation, count zero and no child or deferred. |

Adjacent semantic Given/When/Then clauses accompany actual setup, entry dispatch,
controlled stage callbacks, scheduler boundaries, observable assertions and owned
teardown. Every owned child is cancelled/joined and pending waits are retired.
There is no wall sleep, source/log predicate, duration injection or production
test hook. Controlled entry-policy evidence supplies no native SDK/UI/grant proof.

This receipt is authored only. The author ran no tests, Gradle, Flutter, network,
device/runtime operation, validation, self-review, staging or commit. Parent owns
five-path source/diff/whitespace/link intake, the planned 37-case native policy
accumulator (14 timing, 10 connection, 9 lifecycle, 4 work), postrepair ND1 public
MethodChannel entry smoke over retained account/markers and fresh protected M2
independent review. Results remain pending until actual parent receipts exist.
Prior 31-case results and actual ND1/ND2/ND3 passes remain historical in scope;
unchanged ND2/ND3 retain only the synthetic 68-byte upload/readback and restore
proof. Neither the historical 18-second ND1 nor authoring proves actual human
consent exceeded 20 seconds. The [runtime note](../../../notes/android-submission-runtime.md)
records the same status. Whole 153-path Step acceptance/exact commits, Core Phase
2/TFAF Phase 3 closure, comprehensive App Phase review, aggregate validation and
distinct Phase release remain parent-owned and open. No same-file target-program
debt or separate existing debt was newly admitted.

## 2026-10-11 — Parent-executed native entry policy and smoke receipt

Parent receipt `esa61-drive-native-entry-validation-20261011@1` binds these
actual results to `esa61-drive-native-entry-fix-20261011@2` and parent source
intake `esa61-drive-native-entry-author-intake-20261011@1`. This is the factual
evidence projection required by the existing documentation Update rule. The
documentation author ran no tests, Gradle, Flutter, network, device/runtime
operation, validation, self-review, staging or commit. Code/spec/Gradle are
unchanged by this projection; parent owns document intake, independent review,
accounting, transitions and acceptance.

Parent policy receipt `esa61-drive-native-entry-policy-validation-20261011@1`
records this exact command and working directory:

- Cwd: `/Users/asami/src/Project2026/nict-editing-studio-app/android`.
- Argv rendered as a command: `./gradlew :textus_flutter_core_android_submission:testDebugUnitTest --tests 'org.textus.flutter.core.submission.*' --console=plain`.
- Session 63248; launch chunk `23daf3`; terminal chunk `92b05d`; exit 0,
  `BUILD SUCCESSFUL` in 8 seconds, main/test compilation successful.
- Four JUnit suites passed 37 cases with zero failures/errors/skips: timing 14,
  connection 10, lifecycle 9, work 4.
- Log: `/Users/asami/src/Project2026/nict-editing-studio-app/.codex-workflow/phases/PHASE-6.1/submission-native-drive-entry-policy-20261011.log`.
- JUnit XML directory: `/Users/asami/src/Project2026/nict-editing-studio-app/build/textus_flutter_core_android_submission/test-results/testDebugUnitTest/`;
  suites are `SubmissionAuthorizationTimingTest`, `SubmissionConnectionPolicyTest`,
  `SubmissionRunLifecycleTest` and `SubmissionWorkPolicyTest` under
  `TEST-org.textus.flutter.core.submission.<suite>.xml`.

AT9 now supplies executed controlled evidence of 8-second SDK waiting plus
45-second consent waiting, surviving and succeeding at 53 seconds through the
shared production entry and nested authorization stages. AT10–AT14 supply
controlled foreground/silent deadlines, cancellation/cleanup and unknown-method
refusal evidence. These policy/compiler results establish no native SDK/UI/grant
success or actual human waiting duration. Existing Gradle warnings remain.

Parent then executed the exact postrepair ND1 public entry smoke:

- Cwd: `/Users/asami/src/Project2026/nict-editing-studio-app`.
- Argv rendered as a command: `/opt/homebrew/bin/flutter test integration_test/book_submission_drive_native_test.dart -d 67021FDDJ000JA --no-pub --no-uninstall --dart-define=SUBMISSION_DRIVE_NATIVE_PROOF=true --dart-define=SUBMISSION_DRIVE_PROOF_STAGE=drive-authorize --dart-define-from-file=/Users/asami/src/Project2026/nict-editing-studio-app/.codex-workflow/phases/PHASE-6.1/runtime/native-drive-account-20261011.json --reporter expanded`.
- Session 49241; launch chunk `d85ccf`; terminal chunk `b5ed7e`; exit 0,
  one pass, zero failures and two explicit other-stage skips.
- APK build 19.5 seconds; preserving install 8.4 seconds; test 3 seconds.
- Log: `/Users/asami/src/Project2026/nict-editing-studio-app/.codex-workflow/phases/PHASE-6.1/submission-native-drive-authorize-post-entry-20261011.log`.
- Physical preflight retained exact USB device `67021FDDJ000JA` in chunk
  `534c24`, awake observation `bf2451` and unlocked NexusLauncher foreground
  observation `fb11ad`; the wireless listing referred to the same physical device.

This ND1 invoked actual public MethodChannel `authorizeDrive` and verified the
retained dedicated folder over the existing grant/account/markers. It did not
establish new human consent UI or actual greater-than-20-second human waiting.
The private JSON appears only as the recorded command locator; account/client/
token/grant-secret contents are excluded. ND2 and ND3 were not rerun in this
invocation. Their previous `esa61-native-drive-post-timing-actual-20261011@3`
results retain the scoped 68-byte upload/idempotence/independent binary readback
and fresh-process silent restore proof. Other-stage skips prove nothing about
those stages. Historical 31-case and native-three-stage passes remain historical
in scope; original failures and authored-only/pending-at-authoring paragraphs
retain their outcomes and attribution.

P1 `CPB-ESA61-DRIVE-TIMING-001` remains unresolved until fresh independent M2
review of the repaired entry boundary. Whole 153-path Step independent acceptance
and exact commits, Core Phase 2/TFAF Phase 3 closure, comprehensive App Phase
review, final aggregate validation through `scripts/validate-full.sh` and distinct
Phase release remain unaccepted. No real Book-media or server implementation
acceptance is inferred. No same-file target-program debt or separate existing
debt was newly admitted.
