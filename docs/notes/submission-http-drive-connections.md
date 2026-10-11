# Submission HTTP and Drive connections

- Current status (2026-10-11): Core TFC2-01 owning review passed and was committed at `cd9da12f7219c8096762f5c16f3f2f5bb3998a65`. TFC2-02 parent intake and independent protected review passed; its exact commit, TFC2-03 and full Core Phase 2 acceptance remain pending. The dated entry below separates scoped native results from controlled HTTP acknowledgements.
- Historical B1 receipt status: source and executable specifications authored; initial parent HB1 passed (1 test), and final parent focused validation passed all 266 tests across 15 suites, including HB1, with 0 failures. Final analysis found no issues, dry format covered 10 files with 0 changes, and the diff check exited 0. Parent mechanical checks were complete; independent protected review was pending at that receipt stage. This did not accept the complete ESA6-06 Step.
- Owner: Textus Flutter Core maintainer for connection values and concrete adapter contracts; the Phase 6.1 parent owns validation, review, transition and cross-repository acceptance.
- Update rule: update this note when a public connection, credential, reservation, acknowledgement or cancellation contract changes. Record validated evidence separately and retain the pending native/account/server obligations until their own evidence exists.

The [durable submission contracts](durable-material-submission.md) remain the queue authority. The new [connection values](../../lib/src/submission/submission_connections.dart), [Drive adapter](../../lib/src/submission/drive_submission_storage_adapter.dart) and [HTTP transport](../../lib/src/submission/http_submission_transport.dart) supply concrete borrowed ports. Only `http: ^1.6.0` is added to the existing dependency set. The shared HTTP implementation is internal and unexported.

Connection definitions use a closed version 1 JSON schema. Drive definitions contain a stable safe connection id, an explicit account id and an existing folder id. HTTP definitions contain a stable safe connection id, the exact encoded HTTPS endpoint and an explicit bearer-token requirement. Endpoints exclude user information, queries and fragments. Construction performs no IO. Definitions have no credential fields and B1 supplies no settings writer or storage backend. A referenced id must retain its target/account identity; a future credential owner may rotate a secret without silently changing that target.

`SubmissionCredentialProvider.bearerToken(connectionId)` is borrowed. Drive always requests the exact connection id; HTTP does so only when bearer authorization is required. Null/malformed credentials produce safe nonretryable configuration authorization failures; provider exceptions produce safe retryable configuration credential failures. Tokens are never serialized, logged, persisted in reservations/receipts/failures or used as queue identity. A manually supplied expiring token does not fulfill durable account authorization.

Preparation makes one authenticated fixed-host `generateIds` GET and returns an immutable reservation, without sending original bytes. The existing service checkpoints that reservation on SQLite before upload. It binds connection/account/folder, request/material/original, MIME type and positive byte length. A lost preparation result may leave an unused id; it creates no remote binary object.

Upload synchronously copies the caller's supplied bytes before its first await. It validates exact local binding and byte length before credential or HTTP calls. All lengths, including those above five MiB, use resumable binary creation followed by one unchanged whole-file PUT. Each HTTP request disables redirects. The transient Location must be HTTPS on `www.googleapis.com`, with the fixed upload path, port 443/default and exactly one resumable upload type and nonblank upload id; user information and fragments are rejected. Transient sessions are never persisted or exposed in receipts/errors. No conversion to Google Workspace, deletion, update, permission change or public sharing is performed.

Remote app properties carry exact ASCII identity pieces (`request0`, `material0`, `original0`, with suffix `1` only when needed). Splitting at 64 characters preserves tokens through 128 characters while respecting Google's key-plus-value bound. A 409 at initiation or PUT requires one authenticated metadata GET for the same persisted file id. Verification binds id, MIME type, exact decimal size, the single configured parent, `trashed: false`, expected identity pieces and a valid explicit-zone remote creation time. Missing verification after 409 and incomplete 308 uploads safely permit durable retry. Metadata mismatch never yields a receipt. This checks identity/binding/size and does not prove byte integrity or server-readable permission.

Google creation timestamps accept strict RFC3339 calendar/time values with up to nine fractional digits. Only the receipt's UTC `storedAt` is truncated to Dart microseconds; allowlisted metadata retains the actual returned timestamp string. Local time never replaces remote creation time. Receipt metadata contains only version, connection/account/folder, original id, MIME type, byte length and created time.

HTTP submission posts the existing packet codec as UTF-8 JSON to the exact configured endpoint, with JSON Accept and the immutable request id as Idempotency-Key. The packet excludes the local document and raw original bytes; payload/material receipt/provenance, opaque presentation/execution namespaces and manual whitespace retain their exact values. Only 200/201 with JSON and a strict acknowledgement matching both request and subject can be returned to the queue. Generic 2xx, a Drive receipt or storage completion cannot publish Submitted.

Each prepare, upload and submit invocation owns one monotonic total deadline, default 45 seconds and positive through 45 seconds. Credentials, headers, send and response streaming share its remaining allowance. Responses are bounded to 262144 bytes. Operation-owned AbortableRequest triggers and stream subscriptions cancel active IO on deadline or cancellation. Run predicates are checked at entry, before sends and after awaits; false/throwing predicates yield safe cancellation and prevent subsequent internal requests. Borrowed clients/providers are never closed. Late futures/errors are observed; timeout cannot undo a remote effect already dispatched. The existing queue's external 60-second bound is retained.

Status handling exposes fixed safe messages/codes only. Network exceptions, 408, 429 and 5xx allow queue retry. Drive 403 permits retry only for documented `rateLimitExceeded` and `userRateLimitExceeded` reasons; other 403 denies permission. 401 requires configuration authorization, other 4xx rejects the request and 3xx rejects redirects. Raw bodies, exception causes, headers, tokens, URLs and session ids never enter public failures. B1 performs no automatic retry/backoff; the durable queue controls retry.

The [connected HB1 specification](../../test/submission/submission_http_integration_test.dart) uses actual FileCaptureStore photo/audio references and real file SQLite. It closes/reopens distinct services and queues after preparation, lost upload checkpoint, replay, remaining upload and server acknowledgement. Controlled HTTP captures both unchanged originals; retry reuses the persisted id through 409 plus matching metadata. The [Drive](../../test/submission/drive_submission_storage_adapter_test.dart), [HTTP](../../test/submission/http_submission_transport_test.dart) and [definition](../../test/submission/submission_connections_test.dart) specifications cover the remaining HB2–HB8 contracts using adjacent Given/When/Then clauses under the [Dart rules](../rules/shared-directive-exceptions.md). Initial parent execution passed HB1 (1 test) and the focused 15-suite accumulator (266 tests, 0 failures). Offline dependency resolution selected cached `http 1.6.0` and exited 0; the parent dry format covered 10 paths with 0 changes, and the diff check exited 0. Initial analysis reported three syntax errors, which were fixed; the subsequent analysis reported 0 errors and six brace infos addressed by this exact readiness repair. The repair editor formatted only the three owned Dart paths. Final parent receipts record the 15-suite accumulator passing 266 tests with 0 failures, including HB1; analysis reported `No issues found!`, dry format covered 10 files with 0 changes, and the empty diff check passed. All four final commands exited 0. Parent mechanical checks are complete; independent protected review remains pending. Their HTTP responses are fake; B1 has made no actual Google account, Drive network or real server observation, and these host results do not establish native proof or complete Step acceptance.

At the historical B1 authoring stage, B2 remained mandatory: encrypted platform configuration/credential storage, explicit foreground grant for a specified Google account, silent background retrieval for that previously granted account, and Android WorkManager plugin initialization in a separate dispatcher isolate. The dispatcher must reopen the same default SQLite and original roots and prove stop/cancellation/recovery on native runtime. Secure auth, native scheduling and device proof were pending at that stage; later scoped observations are recorded below.

C/TFAF must consume Core configured connections and common Commit/status/retry UI. D/App must enforce the Book gate (ISBN OR title), flush the current editor before immutable Commit, map App payload/provenance, integrate ListDetail and provide the consumer APK evidence. Actual Drive binary write/readback remains separate ESA6-07 evidence; real server acceptance is deferred to ESA6-08 handoff and is not implied by controlled HTTP acknowledgement. All remaining original Phase obligations and canonical ledgers are retained.

## 2026-10-11 — TFC2-02 adapter evidence entry

The [owning Step journal](../journal/2026/10/2026-10-11-tfc2-02-acceptance.md)
adopts existing concrete adapters and immutable retry/reopen contracts unchanged.
HB1 uses real original photo/audio bytes and SQLite across service lifetimes;
its acknowledgements and HTTP are controlled. The later RA3 one-case and
23-suite/375-case results in
`esa61-submission-reference-guard-software-validation-20261010@1` retain the
exact original/provenance/context packet after guard denial, configuration and
same-id retry. Analysis found no issues. The subsequent
`esa61-fix34-validation-20261011@1` supplies Q4 and ten-suite/115-case evidence
for the actual timeout-query correction, retained FULL/5000 settings and records,
with clean scoped analysis and zero dry-format changes. These observations do
not turn a controlled acknowledgement into actual server acceptance.

`esa61-native-drive-post-timing-actual-20261011@3` records actual ND2 upload of
a synthetic 68-byte original through the Core default original store and Drive
adapter, stable reservation idempotence and independent remote metadata/binary
readback. ND3 ran in a fresh process, silently restored exact-account credentials
and the same original/folder/file/reservation/receipt, and independently read
back the same 68 bytes without grant UI, create or upload. Each selected stage
exited 0 with one pass, zero failures and two explicit other-stage skips.
They prove neither complete Book-media upload nor server acknowledgement.

`esa61-drive-native-entry-validation-20261011@2` supplies later 37-case policy
and main/test compilation success plus actual post-entry ND1 public authorization
and retained-folder verification over an existing grant. ND2/ND3 were not rerun
there. `esa61-drive-native-entry-focused-review-20261011@1`, admitted by
`esa61-drive-native-entry-focused-admission-20261011@1`, passed and resolved
`CPB-ESA61-DRIVE-TIMING-001` within the App-owned entry scope. Its controlled
53-second success establishes no actual greater-than-20-second human wait.
See [runtime evidence and limits](android-submission-runtime.md) for NC/NQ scopes.

The original B1 failures and pending-at-authoring statements retain their historical
outcomes. Core Step1 is accepted/committed; Step2 independent owning review
passed and its commit remains pending. Step3 and full Core Phase gates remain pending. TFAF/App closures are separate;
storage success establishes no Candidate or actual server acceptance. This author
ran no validation or review and changed no adapter, schema or specification.

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
