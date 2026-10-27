# Android secure submission runtime

- Historical status before native entry correction: Parent receipt `esa61-fix34-validation-20261011@1` records actual Fold NC1 and subsequent separate-process NC2 success: each exited 0 with one pass, zero failures and one explicit other-stage skip. NC1 built in 10.3 seconds and installed in 12.6 seconds (session 86912); NC2 built in 9.8 seconds and installed in 2,237ms (session 66497). Existing Q4 passed (session 87003); the ten-suite Core accumulator passed all 115 cases with zero failures/skips (session 35506). Source analysis found no issues and dry format checked one file with zero changes. Both native stages observed `tokenPresent=true`, `atRest=true` and `queueCount=0`; empty-queue factory observations establish no queued Book recovery or dispatch, and known-value absence at rest supplies no hardware-backed security certification. Then-latest parent receipt `esa61-drive-consent-timing-validation-20261011@2` records successful main/test compilation, 31 JUnit policy cases with zero failures/errors/skips, six-path whitespace checks without diagnostics and 23 resolved local links. `esa61-native-drive-post-timing-actual-20261011@3` records ND1 actual exact-account human Google consent/dedicated-folder verification; ND2 stable-original 68-byte upload/idempotence and independent metadata/binary readback; ND3 fresh-process silent credentials, the same original/folder/file/reservation/receipt and 68-byte readback without grant UI/create/upload. Each native stage exited 0 with one pass, zero failures and two explicit other-stage skips. Earlier failures and authored-only receipts remain historical; NB1, 288 host tests, 15 native policy tests and consumer APK retain their original producer scopes. At that receipt stage, independent protected timing review, B2 whole-boundary source integration, wider shared foreground/headless, offline/restart/OS-stop and security behavior, Core Phase 2/TFAF Phase 3 closure, whole 153-path Step independent acceptance and exact Step commits, full Phase review, aggregate validation and release remained pending. No real Book-media or server-implementation acceptance is inferred.
- Current timing status (2026-10-11): `esa61-drive-native-entry-focused-review-20261011@1` returned PASS, admitted by `esa61-drive-native-entry-focused-admission-20261011@1` in App ledger revision 29, resolving `CPB-ESA61-DRIVE-TIMING-001`. `esa61-drive-native-entry-validation-20261011@2` records successful main/test compilation and 37 policy cases with zero failures/errors/skips, plus post-entry ND1 actual public authorization/retained-folder smoke over an existing grant (exit 0, one pass, zero failures, two other-stage skips). AT9 succeeds at virtual 53 seconds; no actual greater-than-20-second human wait is proven. This is App-owned narrow entry acceptance, not Core Step2 acceptance. Core TFC2-01 passed its owning review and was committed at `cd9da12f7219c8096762f5c16f3f2f5bb3998a65`; TFC2-02 independent owning review passed; its commit, TFC2-03 and full Core Phase 2 remain pending. TFAF/App closure is separate. Earlier failed, authored-only and pending receipts below are historical and superseded only for current status by the dated TFC2-02 entry.
- Owner: Textus Flutter Core maintainer; App owns consumer configuration, Book policy and native acceptance fixtures; TFAF owns the shared configuration/status UI.
- Update rule: update this note when public contracts or observed acceptance evidence changes. Record exact executed commands/results and their scope before changing pending status. Keep actual device and Drive evidence distinct from controlled host/policy evidence.

## Public configuration and ownership

The following attempts and diagnostic/timing authoring statements retain their
historical receipt-stage outcomes; later evidence is projected in the dated entry.

Parent receipt `esa61-native-drive-actual-attempt-20261011@1` records actual
ND1 (`drive-authorize`), session 23896, exit 1: zero passes, one failure and two
explicit other-stage skips. The actual APK build and preserving install
succeeded; authorization failed with `authorizationCancelled`. ND2 and ND3 were
not launched. Parent chunk `e232e1` observed AndroidUtils:
`mismatch between getCallingPackage com.example.nict_editing_studio_app and getLaunchedFromPackage com.google.android.gms for activity com.google.android.gms.auth.api.credentials.authorization.ui.AuthorizationActivity [CONTEXT service_id=259 ]`.
This package mismatch is an observed clue; its causal role is unconfirmed.
The official [Identity API](https://developers.google.com/android/reference/com/google/android/gms/auth/api/identity/Identity)
supports both Activity and Context authorization-client overloads, so this
observation does not establish that the existing Context overload is invalid.
The [AuthorizationClient contract](https://developers.google.com/android/reference/com/google/android/gms/auth/api/identity/AuthorizationClient)
defines SDK authorization results and Intent result parsing with ApiException
failure; the authored diagnostics observe only fixed events and numeric status.

The following diagnostic receipt describes the historical candidate with its
original 20-second whole-call timeout, before the timing repair below.
`esa61-drive-authorization-diagnostics-manifest-20261011@2` authors best-effort
`TextusDriveProof` observations guarded by `ApplicationInfo.FLAG_DEBUGGABLE`.
Events contain only frozen literals and optional integer codes or boolean 0/1;
no account, connection, folder, request identity, token, Intent/result body,
message or stack is recorded. Non-OK matching results with nonnull data are
parsed only in a debug build for status observation; their result is ignored
and they still fail with `authorizationCancelled`. Existing SDK failure,
ownership fences, consent transitions, grant persistence, cleanup and 20-second
timeouts retain their behavior. At that authoring stage, diagnostics were pending parent
compilation and one planned native reproduction with retained markers and a
preserving install. The original failed attempt remains failed. No executable
specification change applies: ND1/ND2/ND3 and existing lifecycle policy scenarios
and assertions remain unchanged. The author ran no validation or reproduction.
At that authoring stage, actual grant, folder access, upload/readback, producer own-Phase and Step/Phase
acceptance remain open. The chronological
[journal receipt](../journal/2026/10/2026-10-10-esa6-06-durable-submission.md)
preserves the scoped history.

Parent receipt `esa61-native-drive-post-oauth-attempt-20261011@2` records the
postconfiguration ND1 failure, session 18728, terminal chunk `499126`, exit 1:
zero passes, one failure and two explicit other-stage skips. Dedicated Cloud
setup was actually completed, but no native grant was proven. The fixed
`TextusDriveProof` events in chunk `2fd291` show SDK request at 08:02:12.570,
SDK result with resolution and launch at 08:02:20.174, and finalization at 08:02:32.547.
The expected resolution pause had `pause_cancel:0`; no Activity result or
resolution return was observed before the original whole-call deadline.
Approximately 7.6 seconds of SDK waiting left only about 12.4 seconds for
human consent. This establishes the bounded timing defect without proving
human rejection or a Google grant. ND2 and ND3 were not launched.

`esa61-drive-consent-timing-fix-20261011@1` now authors separate fixed bounds
in [SubmissionAuthorizationTiming](../../packages/textus_flutter_core_android_submission/android/src/main/kotlin/org/textus/flutter/core/submission/SubmissionAuthorizationTiming.kt),
used by [explicit authorization](../../packages/textus_flutter_core_android_submission/android/src/main/kotlin/org/textus/flutter/core/submission/GoogleDriveAuthorization.kt).
SDK waiting remains 20 seconds; explicit foreground human consent gets its own
120 seconds, within an absolute 160-second call bound. The total includes a
20-second bounded margin for local configuration/grant work. Silent credential
retrieval remains bounded to 20 seconds and never launches consent. No stage
restart, automatic retry, broader scope or account selection is introduced.
Captured engine/activity ownership, matching-result routing, cancellation,
grant persistence, final cleanup and fixed private diagnostics retain their
contracts. [AT1–AT8](../../packages/textus_flutter_core_android_submission/android/src/test/kotlin/org/textus/flutter/core/submission/SubmissionAuthorizationTimingTest.kt)
are authored JUnit virtual-time and actual pure-lifecycle scenarios, with the
test-only coroutines-test dependency matching production coroutines 1.7.3.
They have not been executed by the repair author and supply no native-grant
proof. Parent compilation, selected policy validation, one meaningful actual
ND1 with human-operated consent and independent review were pending at that
authoring stage; ND2/ND3 required their successful predecessors. Historical
failures remain failed. The later parent receipt below records scoped policy
and native passes; own-Phase, whole Step and Phase acceptance remain open.

Import [Textus Core](../../lib/textus_flutter_core.dart). `SubmissionConfigurationSnapshot` is immutable, uses a closed version 1 JSON schema, and retains every configured target. It has at most 128 definitions with unique safe ids across Drive and HTTP. Selections are nullable and must reference the exact kind. Selection supplies defaults for new intent; it never retargets an accepted request.

`AndroidSubmissionConfigurationStore` implements the owned `SubmissionConfigurationStore` handle and the borrowed `SubmissionCredentialProvider` port. `snapshot`, `putDrive`, `putHttp` and `select` expose only safe definitions. Identical target registration is idempotent. Reusing an id for another kind, account, folder, endpoint or bearer requirement returns `connectionConflict`. No retarget/delete operation exists. `setHttpBearerToken` rotates or removes a separately encrypted secret under the matching HTTP identity; anonymous targets reject nonnull credentials. `bearerToken` is the only retrieval operation that returns an ephemeral token. Tokens have no field in configuration JSON, queue packets, receipts or public exception history.

`authorizeDrive` is an explicit foreground action. `authorizationState` observes availability using fresh exact-account silent authorization; a remembered grant alone is insufficient. `SubmissionAuthorizationState` is `available`, `authorizationRequired` or `unavailable`. Availability does not promise that a network or destination is ready. The Android preset requires the exact device Google account email without implicit rewriting or account selection. Foreground consent requires a resumed attached Activity and permits one pending resolution. Silent calls never launch consent. Explicit foreground authorization bounds SDK waiting to 20 seconds, human-resolution waiting to 120 seconds from that stage's start, and the complete call to 160 seconds; silent credential calls retain their 20-second bound. Calls are fenced by their engine/activity owner; an unrelated pause/detach cancels consent. Only the expected transition of a launched resolution may survive its pause and retained configuration reattachment.

Closing the configuration facade prevents new calls, joins its accepted calls, discards late results, and retires only the current native configuration context before cancelling authorization and closing its captured database handle under serialized IO. The next configuration operation in the same attached engine lazily constructs a fresh store/authorization context over the unchanged database and key. Its current Activity binding and observed resumed state are restored. A closed Dart facade stays closed; sequential foreground owners may open and close repeatedly. This does not grant simultaneous independent configuration-facade ownership. Close never removes configuration or cancels durable work. The optional MethodChannel is borrowed. Unknown native errors are replaced with a fixed safe configuration failure; SDK causes, details, accounts and secret values are never reflected. Web and non-Android default platforms fail explicitly before channel IO.

Each accepted configuration operation captures its engine and context owner. Store reads, grant writes, SDK dispatch/await completion and terminal replies check that context; retired operations use only their captured old handle and cannot obtain the replacement handle or publish a late secret. Close replies require only their engine owner. Scheduling acquires no configuration context. Detach invalidates ownership before cancellation, joins accepted jobs and closes captured resources, including retired handles whose close was interrupted. Failed partial construction cancels/closes its acquired resources and installs no live slot. Default-factory snapshot failure cleanup can therefore be followed by a fresh open without engine recreation.

Each fresh native authorization context receives a distinct resolution request code, starting at 21861 and ending at 65535. Codes never wrap or reset during the plugin object's lifetime, including engine reattachment and failed construction. Exhaustion fails safely with `configurationUnavailable`. Only the live context's matching code can route an Activity result; a retired consent result cannot satisfy fresh consent. Exact-account authorization and the public channel schemas are unchanged.

## Persistence and Android setup

The native store is `Context.noBackupFilesDir/textus_submission_config.sqlite`, version 1, with `connections(id,sealed)` and singleton `selection(id,sealed)`. Exclusive transactions use FULL synchronous writes and a 5-second busy timeout. Complete connection definitions, HTTP secrets and explicit Drive grant bits are AES-256/GCM authenticated envelopes under one stable AndroidKeyStore alias. Each envelope has a version byte, fresh 12-byte IV and authenticated ciphertext; plaintext is bounded to 65,536 bytes. AAD binds the version and exact row identity. Only safe connection ids remain plaintext. Key initialization is synchronized across this process's engines. A missing key with existing sealed rows is a safe failure; neither keys nor corrupt databases are reset or replaced and no plaintext/RAM fallback is provided. This is a dedicated secure boundary; generic SettingsService is not a secret store. Hardware-backed key storage is not claimed.

`PRAGMA busy_timeout = 5000` returns one numeric row. Android's `execSQL` routes through `SQLiteStatement.executeUpdateDelete` and the non-query execution path, which rejects that row. FIX33 uses `compileStatement(...).use` and `simpleQueryForLong()` in the native configuration store to execute and consume the scalar result, requires exactly `5000L`, and closes the owned statement on success or failure before the unchanged transaction begins. The existing FULL assignment still uses `execSQL`. The actual FIX33 NC1 advanced through the retained sequential configuration assertions and owner cleanup, then failed at queue acquisition as recorded below. Parent FIX34 evidence now records complete selected NC1 and separate-process NC2 passes, including retained configuration/token/selection reload; broader native and independent acceptance remain owed.

The dedicated durable queue opens through sqflite. Installed `sqflite_android` 2.4.4 routes `execute` to `SQLiteDatabase.execSQL`, so its first default queue open rejected the same result-returning timeout assignment in the actual FIX33 NC1. Installed `sqflite_common` 2.5.13+1 routes awaited `rawQuery` through `txnRawQuery`; Android `doQuery` uses `rawQueryWithFactory`, traverses the cursor into results and closes the nonpaged cursor in `finally`. FIX34 changes only this existing queue assignment to awaited `rawQuery`, consuming its result before the unchanged `execute('PRAGMA synchronous = FULL')` and schema access. The 5000ms wait, FULL writes, version 1, transactions, retry and ownership contracts are retained. Parent FIX34 validation passed existing Q4's independent-handle lock/retained-record assertions with exact busy_timeout=5000 and FULL=2 and all 115 selected Core cases. Actual NC1/NC2 acquired the default factories and observed equal retained empty queues; their `queueCount=0` does not establish queued Book recovery or submission.

Before creating Core tables in a version-zero database, the store observes all tables using the existing non-SQLite-internal predicate, ordered by name. Initialization permits exactly an empty table list with no metadata columns, or the single table `android_metadata` with exactly one column: index 0, name `locale`, type `TEXT`, nullable, null default and primary-key position 0. Android creates that platform table before Core's open returns. Unknown or pre-existing Core tables, metadata mixed with another table, duplicate or case-mismatched names, columns without their table and any missing, extra or changed column field fail with the fixed `configurationUnavailable` vocabulary. The observation reads schema only, never application rows. No table, metadata, data or key is rewritten or deleted to gain admission. Core's original tables and version 1 are created only after policy validation in the same transaction; existing version, encryption, AAD, key, close-on-error and queue contracts are retained.

The registration package has no dependency back to Core. Android requirements follow the existing audio package: min SDK 26, compile SDK 36, Java 17, Kotlin 2.4 and AGP 9.1. Dependencies are WorkManager 2.12.0, play-services-auth 22.0.0 and coroutines-android 1.7.3. The plugin contributes INTERNET and ACCESS_NETWORK_STATE permissions; WorkManager's normal manifest initializer remains enabled. Configure a Google Cloud Android OAuth client for the actual consumer application package and its signing certificate fingerprint, including the debug fingerprint for debug-device acceptance. Enable the Drive API in the corresponding project. These product credentials/setup values belong to the consumer; Core supplies no guessed client, account or target.

Register an exact account email and an existing accessible Drive folder id, then explicitly request that account's `drive.file` grant in foreground. The AuthorizationRequest pins `Account(accountId,"com.google")` and requests only `https://www.googleapis.com/auth/drive.file`. No default account, SELECT_ACCOUNT override, GET_ACCOUNTS permission, manually persisted Google token or refresh token is used. An arbitrary existing folder is not necessarily accessible under `drive.file`: actual account/app access must be established for the selected folder during native/Drive acceptance. Core never changes sharing/permissions. Play Services must be available. Expired token caching/refresh is handled by fresh AuthorizationClient calls for that exact account.

## Default resources and durable wakes

`openDefaultAndroidSubmissionResources(lifetime: ..., scheduler: ...)` opens the accepted default application-support `textus_submission.sqlite` queue and `textus_capture` original root, with the existing schemas. It reads secure configuration and builds adapters for **all** persisted definitions, including formerly selected ids. It owns one HTTP client, service, queue and native configuration handle. The optional scheduler is borrowed; the default Android scheduler facade is owned. Opening performs no network, consent, Commit or scheduling. Missing definitions produce the accepted queue's safe missing-connection failure, without fabricated adapters or acknowledgements.

`SubmissionBackgroundResources.close` belongs to the composing caller; a `SubmissionBackgroundRunner` borrows it and never closes it. Default close is idempotent, retires the run, closes the HTTP client, joins service operations before queue close, and attempts every owned cleanup even if another fails. LocalCaptureStore has no close. Partial acquisition after cancellation is cleaned. B1 adapters borrow the same configuration provider and receive the same current predicate and cancellation future. They never close foreground-owned resources.

`SubmissionRunLifetime` has a safe id, monotonic `isCurrent`, cancellation Future and idempotent `retire`. The runner validates 1–8 dispatches and a positive budget of at most 180 seconds, measured with Stopwatch. It refuses overlapping invocations. Offline and retired invocations return before queue/original/credential ports. Each accepted service operation remains bounded to 60 seconds. After each awaited operation it rechecks ownership; retirement prevents any next dispatch or late acknowledgement/checkpoint through the accepted service and B1 adapters.

The runner continues through progress, success and business failure to handle other eligible jobs. A final queue scan schedules ready rows, retryable failure due times and unexpired claim expiry; submitted/nonretryable failed rows are ignored. Delays are nonnegative and bounded to 24 hours; a farther-future due time causes another scan, never an earlier business retry. Unexpected runtime failures expose only `failure` with a 30-second infrastructure delay. Submitted is solely an existing durable queue acknowledgement state.

`AndroidSubmissionBackgroundScheduler.initialize` registers only Core's top-level entry point and persists its positive Flutter callback handle before scheduling. `requestRun` waits for native enqueue completion. WorkManager uses connected normal nonexpedited one-time work and unique `textus_submission` APPEND_OR_REPLACE ordering, retaining wakes added during active completion. Infrastructure Result.retry uses exponential 30-second backoff. Business due times use separately appended delayed work. WorkManager Data carries no request payload, account, path or token. Closing a scheduler retires only that foreground wrapper, leaving durable jobs intact.

Each CoroutineWorker owns one main-thread FlutterEngine with normal automatic plugin registration and a verified DartCallback; there is no fallback to default `main`. Core initializes the headless root binding, installs start/stop before `ready`, and uses a dedicated background channel. Native installs its handler before Dart execution, starts with a safe run id and observed validated-network bit, and accepts only the closed terminal `{outcome,operations,nextDelayMs}`. Native total timeout is 270 seconds including startup. Stop retires native ownership before signaling Dart; NonCancellable grace is bounded to 5 seconds before main-thread engine destruction. Late/mismatched callbacks cannot publish a result. A pending terminal waits for delayed enqueue before success; bootstrap/invalid packet/enqueue failures retry. OS stop propagates cancellation. An engine-death claim recovers through the accepted five-minute lease, with a no-work scan scheduling its expiry.

CoroutineWorker's final `onStopped` cancels the `doWork` coroutine. The worker realizes the OS-stop event through that cancellation path and its bounded `finally` cleanup. It does not override the final method. AuthorizationResult granted scopes are URI strings; requested scopes remain `Scope` values. These concrete SDK signatures were supplied by the parent's official API readback during authoring; the parent reports consumer compilation passing, while device execution remained pending at that authoring stage.

Android force-stop prevents scheduled execution until the user reopens the application. OS quotas and connected constraints can delay normal background work. No custom service, notification, wake lock or destructive rollback is supplied. Original media and remote effects are retained.

## Evidence and remaining delivery

The parent recorded the actual initial NC1 failure in `esa61-submission-native-configuration-validation-20261011@1` (session 20151, exit 1; `submission-native-configuration-write-20261011.log`) and the exact version-zero platform schema in `esa61-submission-native-schema-observation-20261011@1`. This failure happened before any fixture configuration put. FIX32 adds pure behavior tests for empty/canonical acceptance, unknown or inconsistent tables and malformed metadata columns, with safe failures and unchanged input observations. Its parent compilation and 23 pure-policy passes are controlled policy evidence only. The corrected actual NC1 still failed in `esa61-fix32-native-validation-20261011@1` (session 69731, exit 1; `submission-fix32-native-configuration-write-20261011.log`) at the first snapshot before fixture put/select/token/proof writes; build took 12.8 seconds and install 13.1 seconds. NC2 was not launched. `esa61-fix32-native-schema-observation-20261011@1` confirms version 0, canonical metadata only, no Core tables and no unknown tables. The earlier metadata guard was a real latent source defect; it was not a proven sole explanation of the original safe failure.

Parent record `esa61-fix33-native-validation-20261011@1`, with its policy/mechanical reference, records FIX33 compilation and 23 pure-policy passes. The actual Fold NC1 command `flutter test integration_test/book_submission_native_test.dart -d 67021FDDJ000JA --no-pub --no-uninstall --dart-define=SUBMISSION_NATIVE_PROOF=true --dart-define=SUBMISSION_PROOF_STAGE=configuration-write --reporter expanded` ran in App, session 59561, exit 1, log `submission-fix33-native-configuration-write-20261011.log`; build took 22.2 seconds and install 2,553ms. Its initial snapshot, fixed dummy definition/token/access writes, temporary selection, same-engine close/reopen/exact token reload, persisted empty access revoke/reopen, access restore/exact original selections and preservation of nonfixture definitions completed. Configuration owner cleanup also completed. At the first default-resource queue open, `sqlite_submission_queue_store.dart:55` raised `SqfliteDatabaseException`: the nonquery path rejected `PRAGMA busy_timeout = 5000`. First factory completion/list, second factory, at-rest canary observation and successful-write marker were not reached. The run had zero passes, one failure and one explicit other-stage skip; the separate NC2 launch was not started because the NC1 success/marker prerequisite was unmet. This narrows the original initial configuration failure to the evidenced queue acquisition failure; it supplies no complete native or Step acceptance and leaves historical failed receipts failed.

FIX34's original authored-only receipt for `VF-ESA61-QUEUE-BUSY-PRAGMA-001` remains in the [durable submission journal](../journal/2026/10/2026-10-10-esa6-06-durable-submission.md), followed chronologically by the parent validation receipt `esa61-fix34-validation-20261011@1`. Adjacent semantic Given/When/Then clauses describe the independent handle, awaited timeout query and consumed results before FULL writes/schema access. Existing NC1/NC2 setup, actions, assertions, order and explicit other-stage skips, Q4 and the ten selected Core suites are unchanged. This status editor ran no tests, validation, analysis, formatting validation, runtime, self-review or commit; final prose/links/whitespace intake belongs to the parent.

Parent NC1 completed configuration writes, same-engine reopen and exact token reload, persisted access revoke/reopen/restore, original selections and configuration-owner cleanup, two sequential default factories with queue-list equality, noBackup known-value absence and the saved opaque successful marker. NC2 was a separately launched Flutter process after NC1 success over retained App data; it read the marker, retained configuration/token/restored selections, default factories and at-rest observations. Exact token assertions emitted no token value. The safe observations in both stages are `tokenPresent=true`, `atRest=true`, `queueCount=0`. They prove the selected configuration/factory persistence observations; they do not prove queued Book recovery/dispatch, hardware-backed keystore/security certification, consent, Drive, HTTP, headless wake/dispatch, offline or OS-stop behavior.

Executed parent commands and results on 2026-10-11 are below. App workdir was `../../../../..`; Q4 and Core10 workdir was `../..`. The receipt supplies source analysis/dry-format commands/results without a separate workdir field.

- App NC1: `flutter test integration_test/book_submission_native_test.dart -d 67021FDDJ000JA --no-pub --no-uninstall --dart-define=SUBMISSION_NATIVE_PROOF=true --dart-define=SUBMISSION_PROOF_STAGE=configuration-write --reporter expanded`; session 86912, exit 0, one pass, zero failures, one explicit other-stage skip; build 10.3 seconds, install 12.6 seconds.
- App NC2: `flutter test integration_test/book_submission_native_test.dart -d 67021FDDJ000JA --no-pub --no-uninstall --dart-define=SUBMISSION_NATIVE_PROOF=true --dart-define=SUBMISSION_PROOF_STAGE=configuration-restore --reporter expanded`; session 66497, exit 0, one pass, zero failures, one explicit other-stage skip; build 9.8 seconds, install 2,237ms.
- Core Q4: `flutter test --no-pub test/submission/submission_queue_store_test.dart --plain-name "Q4 opening an independent handle waits for an existing lock" --reporter expanded`; session 87003, exit 0, one pass, zero failures/skips.
- Core10: `flutter test --no-pub test/submission/submission_queue_store_test.dart test/submission/submission_service_test.dart test/submission/submission_background_runner_test.dart test/submission/submission_reference_guard_recovery_test.dart test/submission/submission_transfer_query_test.dart test/submission/submission_http_integration_test.dart test/capture/local_capture_store_test.dart test/capture/file_capture_store_absence_race_test.dart test/audio/audio_capture_service_test.dart test/audio/audio_transcript_codec_test.dart --reporter expanded`; session 35506, exit 0, ten suites, 115 passes, zero failures/skips.
- Analysis: `dart analyze lib/src/submission/sqlite_submission_queue_store.dart`; exit 0, `No issues found`.
- Dry format: `dart format --output=none --set-exit-if-changed lib/src/submission/sqlite_submission_queue_store.dart`; exit 0, one file, zero changes.

At the FIX34 receipt stage, native/headless, Google grant, actual Drive, producer own-Phase, whole 150-path Step independent acceptance, exact Step commits, ESA6-07/08, the sole epoch 1 comprehensive Phase review, final aggregate and distinct release obligations remained open. Saved photo/text compatibility and original audio/editable transcript remain original Goal obligations; this scoped evidence establishes no Step or Phase acceptance.

Authored host suites are [configuration](../../test/submission/submission_configuration_test.dart), [runner including NB1](../../test/submission/submission_background_runner_test.dart), and [channel](../../test/submission/android_submission_channel_test.dart). The fixture uses real files and SQLite plus controlled B1 HTTP responses. NB1 preserves original bytes, full provenance/context and exact current edited whitespace across distinct service/queue lifetimes, exercises held-network retirement, and recovers a lease with an injected clock. It does not connect to Drive or a server. Native NB5–NB7 JUnit suites exercise pure connection, lifecycle and work policy; they do not prove encryption, SQL, engine cancellation or Google consent.

The reopen repair adds K1–K3 in the existing native lifecycle suite: distinct handles over retained controlled definition/selection backing, idempotent captured cleanup, stale store/grant/token guards across reopen/detach, factory-failure recovery, distinct resolution codes and exhaustion without reset. These exercise the actual internal ownership policy used by the plugin, with controlled handles. D1 exercises fresh public Dart facade snapshot/credential retrieval after close, continued old-facade rejection without IO and independent scheduler registration/wake. D2 invokes the actual default-resource factory twice successfully over one temporary application-support root, real original bytes and host SQLite, including a failed snapshot acquisition with cleanup before the second successful open. It compares the exact retained queue request/record and original bytes, with no consent or wake during open/close. The scoped SQLite factory and path-channel hook are restored after owned cleanup. All new scenarios have adjacent Given/When/Then clauses. At that authoring stage, these regressions awaited parent execution; controlled configuration/channel and pure-policy results cannot prove Android encryption, native shared SQL or a real Google grant.

The following executed results were supplied by the parent on 2026-10-10; this repair editor performed no validation. Core commands ran in the admitted Core checkout, the native command in App `android`, and the APK command in App.

- `flutter test --no-pub test/submission/submission_background_runner_test.dart --plain-name NB1 --reporter expanded`: exit 0, one representative passed.
- `flutter test --no-pub test/submission/submission_configuration_test.dart test/submission/submission_background_runner_test.dart test/submission/android_submission_channel_test.dart test/submission/drive_submission_storage_adapter_test.dart test/submission/http_submission_transport_test.dart test/submission/submission_connections_test.dart test/submission/submission_http_integration_test.dart test/submission/submission_model_test.dart test/submission/submission_queue_store_test.dart test/submission/submission_service_test.dart test/capture/local_capture_store_test.dart test/capture/capture_model_test.dart test/repository/capture_repository_test.dart test/textus_flutter_core_test.dart test/audio/audio_capture_service_test.dart test/audio/audio_transcript_test.dart test/audio/audio_transcript_codec_test.dart test/audio/pcm_wave_audio_test.dart --reporter expanded`: exit 0, 18 suites, 288 passed, zero failed; displayed output was truncated. This is the selected accumulator, not repository-full validation.
- `dart analyze lib test packages/textus_flutter_core_android_submission/lib`: initial exit 2, eight warnings and ten infos. The bounded repair removes eight redundant promoted assertions, braces nine existing statements and documents one line-specific constructor style exception preserving public `close`. Final parent analysis on 2026-10-10 exited 0 with `No issues found!`.
- The parent-selected 12-path `dart format --output=none --set-exit-if-changed` and `git diff --check` each exited 0 before this style repair; dry format reported zero changed files. The final parent executions on 2026-10-10 also exited 0, with 12 paths and zero changes for dry format.
- `./gradlew :textus_flutter_core_android_submission:testDebugUnitTest --tests 'org.textus.flutter.core.submission.*' --console=plain`: exit 0, three pure-policy suites, 15 passed and zero failed, with actual plugin Kotlin compilation.
- `flutter build apk --debug --no-pub`: exit 0 in 21.0 seconds. This proves consumer compilation, registration and manifest compatibility. Existing AGP/Kotlin legacy-plugin and SDK metadata deprecation warnings remain; no migration was performed in this slice.

The repair editor's only source-authoring command was the manifest's exact six-file `dart format --output=write`: exit 0, six files formatted, one changed. It supplies no validation result. At that receipt stage, independent B2 protected source conformance remained pending. Host responses are controlled; pure-policy tests and APK compilation do not prove device encryption, shared-engine SQL, Google consent, background restart or actual Drive upload.

Final source-check commands supplied by the parent on 2026-10-10, all run in the admitted Core checkout:

- `dart analyze lib test packages/textus_flutter_core_android_submission/lib`: exit 0, `No issues found!`.
- `dart format --output=none --set-exit-if-changed lib/src/submission/submission_configuration.dart lib/src/submission/android_submission_configuration.dart lib/src/submission/submission_run_lifetime.dart lib/src/submission/submission_background_resources.dart lib/src/submission/submission_background_runner.dart lib/src/submission/android_submission_background.dart lib/textus_flutter_core.dart packages/textus_flutter_core_android_submission/lib/textus_flutter_core_android_submission.dart test/submission/submission_configuration_test.dart test/submission/submission_background_runner_test.dart test/submission/android_submission_channel_test.dart test/support/submission_background_fixture.dart`: exit 0, 12 files, zero changed.
- `git diff --check`: exit 0.

Parent admitted the actual 288 host passes, 15 native pure-policy passes and successful consumer APK for the earlier candidate. That bounded style repair changed only statically redundant promoted nonnull assertions, braces around unchanged single-statement branches, one line-specific constructor style comment and evidence documentation. Its request construction, original bytes, queue operations, test actions/assertions/order/selection, native sources and dependencies were unchanged in meaning. This earlier admission adds no native runtime, Google grant, actual Drive or whole Step acceptance and does not validate the subsequent native reopen repair. This repair editor performed no validation.

At the following historical receipt stage, mandatory D/App device acceptance had selected NC1/NC2 retained configuration/token/selection and default-factory observations, plus the scoped ND1/ND2/ND3 evidence recorded below. It still owes broader encrypted key/secret and original/default-root compatibility acceptance, shared foreground/headless configuration transactions, offline/restart behavior, stopped late callbacks and lease recovery. The 68-byte synthetic Drive fixture supplies no real Book-media acceptance. TFAF C still owns shared configuration/status/Commit/retry controls; App D still owns Book gating, current-edit flush, immutable payload mapping and List/Detail status. Independent protected timing review, B2 whole-boundary source integration, B completion, whole 153-path ESA6-06 acceptance, Step commits and producer/App Phase acceptance remain distinct open boundaries.

- [Durable queue contract](durable-material-submission.md)
- [Accepted HTTP and Drive adapter contract](submission-http-drive-connections.md)
- [B2 authoring journal](../journal/2026/10/2026-10-10-esa6-06-secure-android-background.md)

## 2026-10-11 — Parent-observed timing policy and actual Drive validation

Historical pre-entry receipt: the pending gates below describe this receipt stage.
The later dated TFC2-02 entry records the actual narrow entry-review result.

Parent receipts `esa61-drive-consent-timing-validation-20261011@2` and
`esa61-native-drive-post-timing-actual-20261011@3` supply these executed results.
Status manifest `esa61-drive-native-status-m0-fix-20261011@2` addresses
`MCR-ESA61-DRIVE-STATUS-001` in this note and the
[chronological journal](../journal/2026/10/2026-10-10-esa6-06-durable-submission.md).
This documentation author ran no tests, Gradle, Flutter, network, ADB, project
scripts, validation, self-review, staging or commit. Parent owns document/diff,
whitespace/link intake, independent review and transitions. No source, test,
grant policy or public contract is changed by this status projection.

In `../../../../../android`, parent executed
`./gradlew :textus_flutter_core_android_submission:testDebugUnitTest --tests 'org.textus.flutter.core.submission.*' --console=plain`:
session 75113, launch chunk `ca0aef`, terminal chunk `27d864`, exit 0,
`BUILD SUCCESSFUL` in 10 seconds, main/test compilation successful. The four
JUnit suites passed 31 tests with zero failures, errors or skips: authorization
timing 8, connection policy 10, run lifecycle 9 and work policy 4. Parent also
recorded six-path untracked no-index whitespace checks (exit 1 indicating
differences, zero diagnostics) and 23 resolved local links. Existing Gradle
deprecation warnings remain. These controlled policy/compiler observations
supply no actual Google grant, upload or restore evidence.

All following preserving Flutter commands ran in
`../../../../..`, using the frozen
`esa61-native-drive-execution-plan-20261011@1` argv. The private JSON locator
appears only as a command path; no account/client/token/grant-secret contents
are reproduced. Logs are retained in App `.codex-workflow/phases/PHASE-6.1/`.

- ND1: `flutter test integration_test/book_submission_drive_native_test.dart -d 67021FDDJ000JA --no-pub --no-uninstall --dart-define=SUBMISSION_DRIVE_NATIVE_PROOF=true --dart-define=SUBMISSION_DRIVE_PROOF_STAGE=drive-authorize --dart-define-from-file=../../../../../.codex-workflow/phases/PHASE-6.1/runtime/native-drive-account-20261011.json --reporter expanded`; session 58494, launch chunk `864cef`, yielded polls `62a644`/`5ed672`, terminal chunk `3938c4`, exit 0, one pass, zero failures, two explicit other-stage skips; build 15.8 seconds, preserving install 3.0 seconds, test 18 seconds; log `submission-native-drive-drive-authorize-post-timing-20261011.log`.
- ND2: `flutter test integration_test/book_submission_drive_native_test.dart -d 67021FDDJ000JA --no-pub --no-uninstall --dart-define=SUBMISSION_DRIVE_NATIVE_PROOF=true --dart-define=SUBMISSION_DRIVE_PROOF_STAGE=drive-upload --dart-define-from-file=../../../../../.codex-workflow/phases/PHASE-6.1/runtime/native-drive-account-20261011.json --reporter expanded`; session 85618, launch chunk `e3f133`, yielded poll `9b1233`, terminal chunk `8650dd`, exit 0, one pass, zero failures, two explicit other-stage skips; build 21.0 seconds, preserving install 2,780ms, test 10 seconds; log `submission-native-drive-drive-upload-post-timing-20261011.log`.
- ND3: `flutter test integration_test/book_submission_drive_native_test.dart -d 67021FDDJ000JA --no-pub --no-uninstall --dart-define=SUBMISSION_DRIVE_NATIVE_PROOF=true --dart-define=SUBMISSION_DRIVE_PROOF_STAGE=drive-restore --dart-define-from-file=../../../../../.codex-workflow/phases/PHASE-6.1/runtime/native-drive-account-20261011.json --reporter expanded`; session 59786, launch chunk `7ea0dc`, terminal chunk `0164bf`, exit 0, one pass, zero failures, two explicit other-stage skips; build 16.3 seconds, preserving install 2,905ms, test 2 seconds; log `submission-native-drive-drive-restore-post-timing-20261011.log`.

Each stage actually passed its selected scenario; its two other-stage skips
prove nothing about those stages. ND1 establishes actual exact-account explicit
human-operated Google consent and retained dedicated-folder verification.
Diagnostic chunk `d070dd`, process 19319, in
`drive-post-timing-events-20261011.log` records `sdk_result_resolution:1`,
`resolution_launch`, `pause_cancel:0`, `activity_result_code:-1`,
`activity_result_data:1`, `resolution_returned` and `grant_complete`.
ND1 alone establishes no image upload/restore. ND2 establishes actual Core
default original-store/Drive adapter upload, stable reservation idempotence and
independent remote metadata/alt-media binary readback of 68 bytes. ND2 alone
establishes no fresh-process restore. ND3 ran in a separate fresh Flutter
process and silently retrieved exact-account credentials with the unchanged
default Core original/folder/file/reservation/receipt and independent 68-byte
readback; its restore stage performed no grant UI, create or upload.

AT1's 53-second virtual SDK-plus-consent success proves the longer budget
behavior through production timing wrappers. The actual ND1 test took 18
seconds; it does not prove actual human waiting exceeded the former 20-second
whole-call bound. Earlier fixed event clock readings are device event-clock
observations, not independently verified JST wall-clock timestamps. All prior
failed receipts remain failed, and authoring-only receipts retain their authors.
SDK 20 seconds, foreground consent 120 seconds, total 160 seconds and silent
20 seconds, exact account/`drive.file`, ownership/security and public
payload/provenance contracts are unchanged by this documentation repair.

Independent protected timing review and B2 whole-boundary source integration,
wider shared foreground/headless, offline/restart/OS-stop and security behavior,
Core Phase 2/TFAF Phase 3 own closure, whole 153-path Step independent acceptance
and exact Step commits, ESA6-07/08, the sole epoch 1 comprehensive App Phase
review, final aggregate validation through `scripts/validate-full.sh` and
distinct Phase release with persisted closure records remain owed. This scoped
synthetic fixture proves no real Book-media or server-implementation acceptance.
No same-file target-program debt or separate existing debt was newly admitted.

## 2026-10-11 — Native authorization entry correction authored

Historical authoring receipt; the stated pending validation/review gates belong
to that authoring stage and are superseded for current status below.

Independent protected review `esa61-drive-timing-focused-review-20261011@1`
reported P1 `CPB-ESA61-DRIVE-TIMING-001`, admitted by the parent in review ledger
revision 28. The internal 20-second SDK, 120-second consent and 160-second total
wrappers were present, but the plugin's enclosing `authorizeDrive` entry still
cancelled the call after 20 seconds. AT1 exercised the internal wrappers without
that enclosing entry. The historical actual ND1 took 18 test seconds and supplies
no evidence of human consent exceeding 20 seconds. The finding remains unresolved
at this authoring stage; authoring alone grants no closure.

Parent-frozen `esa61-drive-native-entry-fix-20261011@2` authors a shared closed
method dispatcher in
[SubmissionAuthorizationTiming](../../packages/textus_flutter_core_android_submission/android/src/main/kotlin/org/textus/flutter/core/submission/SubmissionAuthorizationTiming.kt).
The [native plugin](../../packages/textus_flutter_core_android_submission/android/src/main/kotlin/org/textus/flutter/core/submission/TextusFlutterCoreAndroidSubmissionPlugin.kt)
routes `authorizeDrive` through its fixed 160-second total wrapper and
`authorizationState`/`bearerToken` through its fixed 20-second SDK wrapper.
Unknown internal entry methods fail with `configurationInvalid` before invoking
the operation. Existing internal stage bounds, arguments, acquisition, captured
owner/result fences, cancellation, cleanup and job/Activity routing are retained.
Exact account, `drive.file`, no-consent silent calls, security and public payload
contracts are retained.

Six new controlled
[AT9–AT14 scenarios](../../packages/textus_flutter_core_android_submission/android/src/test/kotlin/org/textus/flutter/core/submission/SubmissionAuthorizationTimingTest.kt)
exercise the shared production entry method names. AT9 nests the internal stages,
waits 8 seconds for SDK and another 45 seconds for consent, and requires one
available result and cleanup at 53 seconds. AT10 bounds unresolved foreground
local work at 160 seconds. AT11/AT12 retain exact 20-second silent state/token
deadlines. AT13 uses the real pure consent lifecycle and captured owner to require
immediate caller cancellation, one finish/cleanup and rejected late completion.
AT14 rejects an unknown method before operation invocation. Adjacent semantic
Given/When/Then clauses describe controlled setup, dispatch, boundary actions,
observable assertions and owned teardown; all children and pending waits are
retired. AT1–AT8 retain their existing setup, actions, assertions and order.
These scenarios establish no Android SDK, native UI or real Google grant result.

This receipt is authored only: the repair author ran no tests, Gradle, Flutter,
network, device/runtime operation, validation, self-review, staging or commit.
Parent owns the planned 37-case accumulator (14 timing, 10 connection, 9 lifecycle
and 4 work), postrepair ND1 native public entry smoke over the retained account
and markers, five-path diff/whitespace/link intake and fresh M2 independent review.
Those results remain pending until actually recorded. Historical 31-policy-case
and ND1/ND2/ND3 passes remain historical scoped evidence; unchanged ND2/ND3 retain
only their synthetic 68-byte upload/readback and fresh-process restore scope.
No actual greater-than-20-second human consent is claimed. Whole 153-path Step,
Core Phase 2/TFAF Phase 3, comprehensive App Phase review, aggregate validation
and distinct release remain open. No same-file target-program debt or separate
existing debt was newly admitted.

## 2026-10-11 — Parent-executed native entry policy and smoke receipt

Historical pre-review receipt; its pending finding statement records that stage.
The dated TFC2-02 entry below projects the later admitted PASS.

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

- Cwd: `../../../../../android`.
- Argv rendered as a command: `./gradlew :textus_flutter_core_android_submission:testDebugUnitTest --tests 'org.textus.flutter.core.submission.*' --console=plain`.
- Session 63248; launch chunk `23daf3`; terminal chunk `92b05d`; exit 0,
  `BUILD SUCCESSFUL` in 8 seconds, main/test compilation successful.
- Four JUnit suites passed 37 cases with zero failures/errors/skips: timing 14,
  connection 10, lifecycle 9, work 4.
- Log: `../../../../../.codex-workflow/phases/PHASE-6.1/submission-native-drive-entry-policy-20261011.log`.
- JUnit XML directory: `../../../../../build/textus_flutter_core_android_submission/test-results/testDebugUnitTest/`;
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

- Cwd: `../../../../..`.
- Argv rendered as a command: `flutter test integration_test/book_submission_drive_native_test.dart -d 67021FDDJ000JA --no-pub --no-uninstall --dart-define=SUBMISSION_DRIVE_NATIVE_PROOF=true --dart-define=SUBMISSION_DRIVE_PROOF_STAGE=drive-authorize --dart-define-from-file=../../../../../.codex-workflow/phases/PHASE-6.1/runtime/native-drive-account-20261011.json --reporter expanded`.
- Session 49241; launch chunk `d85ccf`; terminal chunk `b5ed7e`; exit 0,
  one pass, zero failures and two explicit other-stage skips.
- APK build 19.5 seconds; preserving install 8.4 seconds; test 3 seconds.
- Log: `../../../../../.codex-workflow/phases/PHASE-6.1/submission-native-drive-authorize-post-entry-20261011.log`.
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

At this pre-review receipt stage, P1 `CPB-ESA61-DRIVE-TIMING-001` remained
unresolved pending fresh independent M2 review of the repaired entry boundary. Whole 153-path Step independent acceptance
and exact commits, Core Phase 2/TFAF Phase 3 closure, comprehensive App Phase
review, final aggregate validation through `scripts/validate-full.sh` and distinct
Phase release remain unaccepted. No real Book-media or server implementation
acceptance is inferred. No same-file target-program debt or separate existing
debt was newly admitted.

## 2026-10-11 — TFC2-02 native evidence and current limitations

The [owning Step journal](../journal/2026/10/2026-10-11-tfc2-02-acceptance.md)
records this factual six-document subset within the exact 49-path Step boundary
(original 47 plus two shared Phase progress documents); Core total scope remains
80 paths. No source, executable specification, configuration or runtime change
is authored here. Historical failures remain failed; the receipts above retain
their author, date, stage and limitations. Historical absolute command/workdir
locators are rendered relative to this note's directory, with `flutter`/`dart`
as portable tool names; private credential contents are excluded.

`esa61-drive-native-entry-focused-review-20261011@1` returned PASS and was
admitted as `esa61-drive-native-entry-focused-admission-20261011@1` in App
ledger revision 29. It resolved `CPB-ESA61-DRIVE-TIMING-001`: explicit
`authorizeDrive` uses the shared fixed 160-second entry bound; silent state/token
retain 20 seconds. Internal SDK 20-second and consent 120-second bounds, captured
ownership, retirement/cancellation, singular cleanup and late-result fences
remain intact. The review returned empty current-blocker, Hygiene and Development
Candidate lists within that narrow scope. It did not accept the whole Step or
producer Phases and is borrowed context for Core TFC2-02.

`esa61-drive-native-entry-validation-20261011@2` records main/test compilation
and 37 policy passes (14 timing, 10 connection, 9 lifecycle, 4 work), zero
failures/errors/skips. AT9 survives eight SDK seconds plus 45 consent seconds and
succeeds at virtual 53 seconds; AT10–AT14 exercise foreground/silent deadlines,
cancellation and unknown-method refusal. Actual post-entry ND1 passed once with
zero failures and two other-stage skips, invoking the public channel and verifying
the retained folder over an existing grant. Its three test seconds establish
no new consent UI or actual human waiting beyond 20 seconds.

`esa61-fix34-validation-20261011@1` supplies actual NC1 and separately launched
NC2 success: each exit 0, one pass, zero failures, one other-stage skip. Encrypted
configuration/token/selection reload, sequential default-factory acquisition and
known-value absence at rest were observed, with `queueCount=0`. These are empty
queue observations, not nonempty WorkManager dispatch or hardware certification.
The production SQLite correction also passed real Q4 and ten-suite/115-case
coverage with no failures/skips, clean scoped analysis and zero dry-format changes.
Earlier 23-suite/375-case software evidence retains its controlled remote scope.

`esa61-native-book-validation-final-20261011@1` separately records actual
NQ1 ready immutable intent/original persistence, NQ2 fresh-process ready
original/context/newer Draft restore, NQ3 actual WorkManager first failure then
one explicit retry and second `authRequired` failure (two claims/history), and
NQ4 fresh-process failed original/context/newer Draft/Core status restore. Each
selected stage exited 0 with one pass, zero failures and five other-stage skips.
Held wake and supplied offline are controlled inputs; they establish no physical
radio toggle, OS-stop or lease-recovery experiment.

`esa61-native-drive-post-timing-actual-20261011@3` retains actual ND2 synthetic
68-byte original upload, stable reservation idempotence and independent metadata/
binary readback. ND3 used a fresh process with silent exact-account authorization,
the same original/folder/file/reservation/receipt and independent 68-byte readback,
without grant UI/create/upload. Each selected stage exited 0, passed once with
zero failures and two other-stage skips. ND2/ND3 were not rerun by the entry smoke.
These scoped successes establish no complete Book-media upload, headless Drive
upload, server acceptance, Candidate formation or hardware security certification.

Core TFC2-01 is accepted/committed at
`cd9da12f7219c8096762f5c16f3f2f5bb3998a65`. Core TFC2-02 independent protected
owning review passed; its exact commit, TFC2-03, full-package validation,
comprehensive Core Phase review and release remain pending. Whole App 153-path Step acceptance,
TFAF Phase 3, App Phase review/aggregate validation and distinct release remain
separate gates. WorkManager constraints, OS quotas and force-stop limits remain
applicable. The documentary author ran no validation or review; the parent owns
diff/link/whitespace verification and owning acceptance.

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
