# Submission reference access contract

Current status: ESA6-06-S2 source and executable specifications authored under
`esa61-submission-reference-guard-manifest-20261010@1`. This editor executed no
tests, analyzer, formatter, native build or runtime command. Parent validation
passed RA3 (1 test), the 23-suite accumulator (375 tests), and three native suites
(20 tests) with actual Kotlin compilation; the consumer debug APK compiled.
Final analyzer, dry-format and diff gates remain parent-owned; only their actual
logs establish their results. Independent protected source acceptance remains
pending. Native durability, actual Drive/server access, upstream package Phase
acceptance and whole ESA6-06/App Phase 6.1 acceptance remain separate obligations.

Owner: Textus Flutter Core owns safe configuration, its native persistence,
borrowed local policy, leased dispatch guard and fresh status queries. TFAF owns
shared settings/status presentation. App owns Book mapping, operator provisioning
and device/remote acceptance.

Update rule: Change this note, the dated journal and executable specifications
together only under an admitted contract. Add executed validation or acceptance
claims only from parent evidence for the exact candidate. Keep controlled facts,
source/software acceptance and physical/remote acceptance separately attributable.

## Explicit configuration

Import [Core](../../lib/textus_flutter_core.dart).
[SubmissionConfigurationSnapshot](../../lib/src/submission/submission_configuration.dart)
adds optional `Map<String, List<String>> referenceAccessBindings = const {}` and
copies/freezes every map and list. Keys are exact registered HTTP transport ids;
ordered values are unique exact registered Drive access ids. The map has at most
128 entries and at most 128 aggregate associations. The combined definition limit
remains 128, each serialized definition remains bounded to 65,536 UTF-8 bytes,
and the complete snapshot remains bounded to `128 * 65536` bytes.

A binding is an explicit operator declaration that the server resolver for that
transport has been provisioned to resolve material references using those exact
access identities. It is no remote permission proof. Account names, OAuth tokens,
grant bits, public URLs, selected pairs and an upload receipt are insufficient.
Core does not create sharing/grants or configure a server. Missing map/key is
unknown; a present empty list explicitly revokes access; insufficient lists deny.

`SubmissionConfigurationStore.setReferenceAccess({required String
transportConnectionId, required List<String> storageConnectionIds})` atomically
replaces one mapping. Equal writes are idempotent and `[]` retains explicit empty
revocation. There is no delete-binding API in S2. Whole-map validation occurs
before commit. Other mappings, selection, definitions, secrets and immutable
queued intent survive. Custom store implementations must implement this new
required method; silent empty or permissive fallback is unsupported.

[AndroidSubmissionConfigurationStore](../../lib/src/submission/android_submission_configuration.dart)
sends exactly `setReferenceAccess` with exactly `transportConnectionId` and
`storageConnectionIds`. Local safe-token/duplicate/count errors fail before IO;
native transaction checks establish registered membership/kinds and aggregate
bounds. Writes return exactly null. Android-only, borrowed-channel, monotonic
closed facade, late-result rejection and fixed safe failure rules remain. Close
joins accepted calls and retires only its captured native configuration owner.
The next sequential facade acquires fresh native ownership over retained data.

## Closed codecs and encrypted selection

Canonical snapshot output is version 2 with exactly six keys: `version`,
`driveConnections`, `httpConnections`, `selectedStorageConnectionId`,
`selectedTransportConnectionId`, `referenceAccessBindings`. The final map is
mandatory. Exact literal version 1 with the old five keys reads with bindings
`{}` and grants no access. Missing/extra keys, unknown/noninteger version,
wrong scalar/map/list types, duplicate references, unsafe/dangling/wrong-kind ids
and violated bounds reject observably. Reads do not repair or rewrite data.

[SecureSubmissionStore](../../packages/textus_flutter_core_android_submission/android/src/main/kotlin/org/textus/flutter/core/submission/SecureSubmissionStore.kt)
reuses only the existing encrypted `selection(id,sealed)` singleton row.
Version 1 is exactly `version`, `storageConnectionId`, `transportConnectionId`;
an absent row is legitimate empty v1. Version 2 adds mandatory
`referenceAccessBindings`. Pure
[SubmissionConnectionPolicy](../../packages/textus_flutter_core_android_submission/android/src/main/kotlin/org/textus/flutter/core/submission/SubmissionConnectionPolicy.kt)
checks syntax/bounds plus registered membership/kinds inside every existing
transaction. Snapshot emits canonical v2; selection writes v2 preserving
bindings; one binding replace writes v2 preserving selection. Definition, secret
rotation and Drive grant writes leave selection/bindings unchanged. Reading old
selection never writes it.

The database stays version 1 with the same tables/columns/indexes/root, stable
key alias, AAD prefix and AES-GCM envelope. Selection plaintext remains bounded
to 65,536 bytes. No migration, new dependency, key reset, plaintext/RAM fallback
or corruption deletion is introduced. Connection codecs remain version 1;
request/packet remain version 1; queue record remains version 2; originals,
photo/audio/transcript and their provenance remain unchanged.

## Borrowed policy and two dispatch checks

[SubmissionReferenceAccessPolicy](../../lib/src/submission/submission_reference_access.dart)
is an exported borrowed local-only interface with
`Future<SubmissionReferenceAccessState> evaluate(SubmissionPacket packet)`.
`ConfiguredSubmissionReferenceAccessPolicy({required SubmissionConfigurationStore
configuration})` borrows the store and reads a fresh snapshot for every required
evaluation. Its static `evaluateSnapshot({required SubmissionPacket packet,
required SubmissionConfigurationSnapshot snapshot})` is pure. Zero materials
return available before store IO. Required packets must have the registered
exact transport, complete matching receipt keys, registered actual receipt access
ids and a sufficient binding for that transport. Unknown transport/access ids
deny; an absent binding is unknown; a sufficient explicit map is available.
Selected pairs and merely `request.storageConnectionId` do not select access.
There is no cache, credentials/network/scheduling call or policy-owned close.

[SubmissionService](../../lib/src/submission/submission_service.dart) accepts a
nullable optional borrowed `referenceAccessPolicy`. Omitted/null is unknown,
denying nonempty material dispatch. Commit, enqueue, offline handling, prepare
and upload remain independent so originals can upload before access provision.
After matching receipts, transport lookup and complete packet validation, it
bounds a fresh policy evaluation by `operationTimeout`, checking caller lifetime
before and after the await. It then persists the S1 dispatch checkpoint and
renews the lease, checks policy freshly again, checks current lifetime and renews
the lease once more immediately before submit. No-upload bypasses both policy
calls. Cancelled/closed/expired/stolen owners cannot dispatch or change another
owner's claim.

| Current policy result | Persisted configuration failure | Retry | Outcome |
| --- | --- | --- | --- |
| unknown/unavailable | `referenceAccessRequired`: `Server access to uploaded materials must be configured.` | false | trusted `notSent` |
| read exception/timeout | `referenceAccessUnavailable`: `Server access configuration is unavailable.` | true; normal persisted retry delay | trusted `notSent` |

No arbitrary input, native detail or cause is retained. Refusal retains every
successful upload. Trusted `notSent` clears only a current nonlegacy S1 checkpoint
attributed to that exact failing claim. Earlier and legacy uncertainty remain.
The two checks reduce revocation windows but do not form an atomic transaction
across queue/configuration stores or prove real remote permission. The same
immutable idempotent packet/request remains required for acknowledgement recovery.

## Fresh public queries and composition lifetime

The service adds `findTransferStatus(String id, {required DateTime observedAt,
SubmissionNetworkState networkState = SubmissionNetworkState.unknown})`,
`findTransferStatusForSubject(String kind, String subjectId, {same named args})`
and `listTransferStatuses({same named args})`. They use uncached borrowed queue
reads without commands, wakes, claims, retry, originals, credentials or HTTP.
Missing returns null before policy; submitted matching acknowledgement, partial
uploads and no-upload require no policy read. Other records evaluate current
policy afresh per record under `operationTimeout`; omitted policy conveys unknown.
Policy read errors/timeouts throw fixed
`SubmissionConfigurationException.safe('configurationUnavailable')` without
empty/success/unknown fallback. Queue corruption/persistence errors propagate.

Returned lists and S1 values are immutable and preserve actual identity,
receipt progress, failure/deadline/checkpoint/acknowledgement facts with UTC
`observedAt`. Caller network observation defaults independently to unknown each
call. Neither observation is cached or persisted. Close is checked after every
await, joins accepted bounded reads through the existing service `_reads`, and
rejects a late query with `StateError`. Policy/configuration/queue remain borrowed.

[Default Android resources](../../lib/src/submission/submission_background_resources.dart)
inject the configured policy over the same owned live configuration, rather than
freezing bindings at the opening snapshot. Adapter maps retain all immutable
definitions from that snapshot, including formerly selected ids. Definitions
cannot retarget. No duplicate store, new resource field or reader is added.
Resource close retires the owner and joins service work/reads before closing queue
and configuration; original ownership, scheduler and HTTP client lifetimes remain.

## Authored evidence and delivery limits

RA1 covers exact access ids, unrelated selection, unknown/empty/insufficient maps,
fresh changes and no IO for empty packets. RA2 covers literal legacy/current
codecs, bounds, deep freezing and atomic replace/revoke preservation. RA3 is the
representative actual FileCaptureStore photo/audio and SQLite deny/provision/retry/
reopen scenario, comparing the immutable packet and unchanged originals/context.
RA4 covers omitted policy, no-upload bypass, revocation, current/earlier/legacy
uncertainty, held first/second checks, cancellation/close/competing lease/expiry and
safe failure/timeout. RA5 covers exact new channel writes, literal old reads,
controlled persisted backing and late-owned-call rejection. RA6 exercises actual
pure Kotlin selection policy. RA7 exercises public fresh queries over actual
SQLite including faults/corruption, immutable observations and close joins. RA8
invokes actual default composition over real files/SQLite with mock-native safe
snapshots and an explicit rejecting test HTTP port, live binding changes and a
fresh foreground owner. Held operations use entered/release signals, finite test
bounds and finally joins before borrowed resource owners close.

`ControlledReferenceAccessPolicy` is explicitly test-only; its available default
is an injected controlled fact. Production has no permissive fallback. The
background fixture explicitly provisions its controlled server-to-Drive binding
and uses the real configured policy over that same test store. Memory/native
channel mocks and pure Kotlin specs prove no Android SQL encryption, Keystore,
Google grant or native cross-engine durability. RA3's distinct decoded/populated
test configuration port proves no native persistence. Fake upload/acknowledgement
is not actual Drive readback or EditingStudio server acceptance.

Parent evidence records RA3: 1 passed; the 23-suite accumulator: 375 passed;
three native suites: 20 passed with actual Kotlin compilation; and the compiled
consumer debug APK at `build/app/outputs/flutter-apk/app-debug.apk`. Each command
exited 0. Final analyzer, 13-file dry-format and diff checks remain parent-owned;
only their actual logs prove those mechanical gate results. Independent protected
source acceptance remains pending. Later App D must establish real Android encrypted binding write/reopen,
fresh foreground/headless owners, revocation and selection/credential retention.
ESA6-07 separately owes actual Drive upload/readback and remote reference access.
Core Phase 2 and TFAF Phase 3 retain their separate startup/review/closure handoffs;
this S2 source slice starts/closes neither upstream Phase and accepts no whole
Step/App Phase. `HYG-ESA61-S1-DOC-001` stays a separate canonical follow-up in the
historical A note; it is not admitted cleanup here.

Related contracts: [S1](background-transfer-status-contract.md),
[A](durable-material-submission.md), [B1](submission-http-drive-connections.md),
[B2](android-submission-runtime.md), [S2 journal](../journal/2026/10/2026-10-10-esa6-06-reference-access-guard.md),
[App Phase 6.1](../../../../../docs/phase/phase-6.1.md) and
[App checklist](../../../../../docs/phase/phase-6.1-checklist.md).
