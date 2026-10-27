# ESA6-06-S2 reference access guard authoring

Current status: Source/specification/documentation authoring complete for the
frozen S2 manifest `esa61-submission-reference-guard-manifest-20261010@1`.
No editor validation, formatter, native build, device, network, commit or release
command was executed. Parent validation passed RA3 (1 test), the 23-suite
accumulator (375 tests), and three native suites (20 tests) with actual Kotlin
compilation; the consumer debug APK compiled. Final analyzer, dry-format and diff
gates remain parent-owned, with results established only by their actual logs.
Independent protected source review remains pending for this exact tree.

Owner: Textus Flutter Core owns these nineteen paths and their public/native
configuration, dispatch and query behavior. The App Phase 6.1 parent owns
validation, review, repairs and transitions; TFAF/App retain consumer ownership.

Update rule: Append exact parent validation/review evidence only when supplied,
with its candidate and limits. Keep native/device/Drive/server/upstream Phase and
whole Step closure separate from controlled host/pure-policy authoring evidence.

The [S2 contract](../../../notes/submission-reference-access-contract.md) records
the exact required store method, nullable borrowed policy, three public query
APIs, closed snapshot/selection v2 output and exact old v1 reads with no binding
grant. Bindings deeply copy exact registered HTTP-to-Drive ids, permit explicit
empty revocation and bound both map entries and aggregate associations to 128.
Combined definitions/byte limits remain unchanged. Native selection reuses the
same encrypted singleton/envelope, database version, stable key alias/AAD/root and
64 KiB plaintext limit without migration. Selection, secret/grant updates and
queued request/packet/original schemas retain their frozen meanings.

The configured policy observes actual receipt access ids, complete keys and exact
registered kinds from current safe configuration. An explicit binding declares
operator-provisioned server resolver access; it proves no remote permission and
performs no authorization/network/sharing/scheduling. Missing binding is unknown;
empty or insufficient is unavailable. No-upload returns before store IO.

The service allows original prepare/upload before provisioning, bounds fresh
policy before the S1 dispatch checkpoint and again after checkpoint/first renewal,
then checks current ownership and renews immediately before submit. Unknown or
unavailable persists nonretryable `referenceAccessRequired` with fixed message
`Server access to uploaded materials must be configured.` Read exception/timeout
persists retryable `referenceAccessUnavailable` with fixed message
`Server access configuration is unavailable.` and the actual normal retry delay.
Both are trusted `notSent`: only the current attributable checkpoint may clear;
earlier/legacy uncertainty and uploaded originals survive. Idempotent immutable
retry remains required; two checks provide no cross-store atomic guarantee.

Fresh id/subject/list queries use only queue reads and bounded local observations,
with immutable UTC S1 statuses and independent network defaults. Missing, partial,
submitted and no-upload skip policy. Omitted policy stays unknown; policy failures
throw only fixed safe `configurationUnavailable`, while queue corruption remains
an error. Close joins accepted reads/work and discards late results before owned
default composition closes queue/configuration. The default composition injects
the same live owned configuration and retains its opening immutable adapter maps.

Authored occurrences:

- RA1: exact different receipt access ids, unrelated selection, missing/empty/
  insufficient maps, unknown ids, fresh changed store and zero-material IO bypass.
- RA2: independent literal old schema, mandatory v2 map, deep freezing, malformed
  ids/types/keys/version/bounds, atomic equal/replace/revoke with retained selection,
  definitions, secret rotations and actual immutable queued intent.
- RA3: actual FileCaptureStore photo/audio and SQLite upload-success/access-wait,
  provision/same-id retry, one controlled acknowledgement, distinct real service/
  queue reopen plus explicitly serialized/populated distinct test configuration,
  unchanged packet, original bytes, provenance/context and Japanese whitespace.
- RA4: omitted-policy denial, no-upload bypass, after-mark revocation clearing only
  current checkpoint, earlier/legacy uncertainty retention, held first/second
  policy across cancel/close/lease steal/expiry, safe raw/timeout failures, actual
  retry deadline and no reupload. Barriers release and drain in finally.
- RA5: exact channel/two arguments/null write, pre-IO rejection, fixed safe native
  failures, old-read/current-output, malformed v2, retained controlled backing
  across fresh facades, selection/secret preservation and late-owned-call close.
- RA6: actual pure Kotlin old/current selection policy, preserved unrelated maps,
  explicit replace/revoke, exact kinds, closed scalars and association bounds.
- RA7: fresh public queries over actual SQLite states/receipts/uncertainty,
  immutable ids/progress/UTC/network reset, live binding changes and unchanged
  durable facts with no commands/credentials/remote calls; fault/corruption/safe
  timeout/error and held late read joining close while ports remain borrowed.
- RA8: actual default factory over test-private real files/SQLite, mock-native
  safe configuration changes after opening, full-receipt denial before bearer/
  authorization/HTTP, fresh foreground owner retaining queue/originals/access
  declaration; scoped path/SQLite/HTTP hooks restore after owned cleanup.

Helpers, callbacks and cleanup carry adjacent semantic Given/When/Then clauses.
The generic fixture's controlled available policy is explicitly test-only. The
background fixture provisions an explicit controlled server-to-Drive binding and
uses the actual configured policy over that same memory port. No production
permissive implementation is supplied.

Parent evidence records RA3: 1 passed; the 23-suite accumulator: 375 passed;
three native suites: 20 passed with actual Kotlin compilation; and the compiled
consumer debug APK at `build/app/outputs/flutter-apk/app-debug.apk`. Each command
exited 0. Final analyzer, 13-file dry-format and diff checks remain parent-owned;
only their actual logs prove those mechanical gate results. Independent protected
source acceptance remains pending. Native encrypted selection write/reopen with
distinct foreground/headless owners, credential/selection retention and explicit
revocation still require App D device acceptance. Mock-native backing, Memory port
and pure Kotlin tests do not prove native SQLite/Keystore/Google behavior. Actual
Drive upload/readback and server reference accessibility remain separately owed.
No Core Phase 2/TFAF Phase 3 execution or closure, whole ESA6-06 acceptance, App
Phase 6.1 acceptance, Step commit, deployment or release is claimed. The existing
`HYG-ESA61-S1-DOC-001` is retained as a separate canonical documentation follow-up.

Related history: [S1 status](../../../notes/background-transfer-status-contract.md),
[A durable intent](../../../notes/durable-material-submission.md),
[B1 adapters](../../../notes/submission-http-drive-connections.md),
[B2 native ownership](../../../notes/android-submission-runtime.md),
[App Phase plan](../../../../../../../docs/phase/phase-6.1.md) and
[App checklist](../../../../../../../docs/phase/phase-6.1-checklist.md).
