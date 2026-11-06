# Registered Material to Studio handoff

## Participant failure classification

Studio producer commit `1a309691c0a0a62ba53d3bab6875a4bd69a3b7c5`,
`docs/spec/participant-japanese-error-presentation-v1.md`, defines the bounded
participant error input. Only `submitRegisteredMaterial` v2 opts into the internal
`studio_submission_failure.dart` decoder. Legacy `submit`, TKL, Drive and User
Account HTTP contracts retain their existing handling. No public DTO, barrel,
queue schema or migration is added.

| HTTP | Integer detailCode | Taxonomy category / symptom | Known safe code | Status fallback |
| --- | ---: | --- | --- | --- |
| 400 | 10899020100 | argument / invalid | studioInputInvalid | studioHttp400 |
| 401 | 91599020100 | security / authentication-required | studioAuthenticationRequired | studioHttp401 |
| 403 | 91699020100 | security / permission-denied | studioPermissionDenied | studioHttp403 |
| 404 | 61099020100 | resource / not-found | studioNotFound | studioHttp404 |
| 409 | 81299020100 | state / conflict | studioConflict | studioHttp409 |

Known classification requires JSON content type (optional charset), the actual
HTTP status, integer `error.detailCode` and exact
`error.conclusion.observation.taxonomy.category` / `symptom`. If present,
`error.status` must be an integer equal to HTTP status. If present,
`error.conclusion.status` must be an object; its optional integer `detailCode`
must equal the required detailCode and optional integer `webCode` must equal
HTTP status. Missing required values, wrong types (including explicit nulls),
inconsistency, malformed JSON, wrong content type or unknown tuples use the
status fallback. Parsing uses the existing bounded response bytes. Arbitrary
message, debug, cause, facets, owner, URL and token fields are never consulted.

Other 4xx/5xx use `studioHttpUnknown`; 408, 429 and 5xx keep retryable true,
other errors false. 401 retains the configuration stage, other statuses the
transport stage. Exceptions use fixed generic English without server content.
Other statuses, including redirects, delegate to existing generic handling.
Before potential dispatch the transport outcome remains notSent. Afterwards
only a completed 401 with `authRequired`, `studioAuthenticationRequired` or
`studioHttp401`, or a completed 403 with `permissionDenied`,
`studioPermissionDenied` or `studioHttp403`, is rejected. All other failures
remain unknown, including cancellation or timeout after headers alone.

The handoff owner persists only the eleven safe codes (five known, five status
fallbacks, plus `studioHttpUnknown`) when the current run catches a remote
unknown/rejected adapter failure. The existing string `failure.code` carries
that classification through SQLite and reopen; exception messages are never
persisted. A retired run discards the classification and retains
`acceptanceUnknown`. Untrusted/legacy codes still collapse to
`acceptanceUnknown` / `handoffRejected`, and notSent retains `handoffNotSent`.
Failure kind, durable state, ACK rules, immutable source, packet, request ID,
target and lease ownership are unchanged. A 409 supplies no update-conflict
diagnosis or permission to replay. Only explicit reconciliation can schedule
the same saved intent again.

Controlled HTTP executable scenarios are authored in
`test/submission/registered_material_http_transport_test.dart`; connected App
SQLite/UI scenarios belong to the App consumer. Host qualification and
independent focused Step review have passed for this bounded addition.
Actual server/device acceptance and whole-Phase closure remain outstanding.

Core provides an explicit v2 handoff of an existing saved TKL Registered source.
The normative wire authority is Studio's `docs/spec/book-material-intake-v2.md`,
frozen at `aea71d140073367ed5bc6071b9319b30340da2bc`. This implementation
continuation supplies no connected acceptance or formal Phase closure.

`RegisteredMaterialSubmissionPacket` retains `sourceRequest`, the complete
immutable `HttpSubmissionConnection target`, and a
`RegisteredMaterialAssociation`. Its schema is
`textus.registered-material-reference/1`; its MaterialRef is literal and its
`RegisteredMaterialResource` values contain ordered unique `key`/`resourceId`
tokens. Construction validates the original TKL Book intent and exact ordered
mapping. DTO construction confers no saved-registration authority.

`RegisteredMaterialSubmissionCodec.packetToJson` emits exactly nine v2 keys,
including `registeredMaterial`. Originals retain full reference/provenance and
have no receipt. Opaque payload, histories, extensions, nulls, Unicode and lists
are preserved. The decoder requires the original source and target explicitly;
strict keys/types and source equality prohibit silent source reconstruction or
repair. Existing DateTime values retain their existing UTC/microsecond model;
nested opaque timestamp strings retain their exact spelling. Legacy wire v1 and
legacy persisted request version 2 remain separate contracts.

`RegisteredMaterialSubmissionTransport` exposes `connection` and
`submitRegisteredMaterial(RegisteredMaterialSubmissionPacket)`. The existing
`HttpSubmissionTransport` implements it alongside unchanged legacy `submit`.
Both use the same private bounded authenticated POST/ACK mechanics and endpoint,
with the original request ID as Idempotency-Key. V2 verifies every pinned target
field, then uses target credentials rather than the original TKL transport ID.
No arbitrary JSON send, storage adapter or physical receipt is introduced.

The same SQLite queue handle implements `RegisteredMaterialHandoffStore` using
its existing serialized transactions. Database version 2 adds only
`registered_material_handoffs`; migration permits exactly 1 to 2 and leaves
source bodies untouched. A UNIQUE source ID and stable handoff ID permit only
one immutable destination per intent. Creation rereads the actual source in the
transaction and requires a matching saved `materialRegistered` row plus its
Registered snapshot. The complete source, snapshot, deliveryRef, revision,
MaterialRef, ordered mapping, frozen packet and target are retained in the
closed/versioned handoff body. `sourceCheckpointUpdatedAt` means only the
original source row's checkpoint time. Unknown historical observation time
remains unknown. No `storedAt` or first `observedAt` is fabricated.

`RegisteredMaterialHandoffService` borrows `queue`, `store`, typed `transports`
and `scheduler`; optional `now`, `leaseDuration` (five minutes) and
`operationTimeout` (one minute, strictly shorter than lease) support bounded
execution. It exposes:

```dart
Future<RegisteredMaterialHandoffCommandResult> enqueueRegistered(
  String sourceRequestId, HttpSubmissionConnection target);
Future<RegisteredMaterialHandoffRecord?> findForSource(String sourceRequestId);
Future<List<RegisteredMaterialHandoffRecord>> list();
Future<RegisteredMaterialHandoffCommandResult> reconcile(String sourceRequestId);
Future<RegisteredMaterialHandoffRunResult> processNext({
  required bool networkAllowed, bool Function()? isRunCurrent});
Future<void> close();
```

Command results contain `record` and the separate safe `schedulingFailed` flag.
Run results contain an optional record and outcome
`noWork/offline/accepted/failed/outcomeUnknown/cancelled/leaseLost`.
`RegisteredMaterialHandoffRecord.state` is
`pending/sending/outcomeUnknown/failed/accepted`. Reads and explicit creation
perform no adapter/network/original IO; only durable pending creation or explicit
reconciliation requests a wake. No service API accepts a manual ACK.

Only pending rows dispatch, oldest first. A sending lease is persisted before
transport. Expired sending becomes unknown during the next online queue scan
and is never returned as a dispatchable claim. An actual matching ACK can accept
only under its owned live lease. Timeout, retirement after potential send,
unclassified failure and mismatched ACK retain unknown outcome; late responses
are discarded. Conclusive notSent/rejected failures require explicit replay as
well. ACK write failure propagates with the existing sending marker intact.
Explicit `reconcile(sourceId)` retains the identical packet/key/target and
refuses an active lease or accepted handoff. Close fences and drains operations
without closing any borrowed port.

`SubmissionService.registeredMaterialHandoffs` is an optional borrowed public
capability. Existing custom compositions remain null until explicitly composed.
Status reads join it into `SubmissionTransferStatus.studioHandoff` and the
submission operation. Registration/upload continue to describe the original
source. Pending is queued; live sending is running; expired sending/unknown is
outcomeUnknown; failed is failed; accepted uses the actual ACK and receivedAt.
The joined status may expose that ACK; the original source ACK stays null and
its transportConnectionId still identifies the TKL route. Source lists contain
one row per original intent. Legacy action enums are unchanged.

The default Android composition reuses the queue, scheduler, typed HTTP ports,
client, credentials and lifetime. Cleanup retires the client, drains handoff and
normal services, then attempts every remaining owned close. The existing
bounded runner checks the original queue first; only noWork opens handoff work,
with both process calls counted against the same operation/time budget. Pending
handoffs are due now; sending expiry requests only an observation wake;
unknown/failed/accepted have no automatic due time. No separate timer or runner
is added.

Executable specifications are authored in the three new registered-material
test files. Their `should` scenarios have adjacent Given/When/Then clauses and
cover wire shape, strict decoding, seeded opaque JSON, actual HTTP requests,
file-backed migration/reopen, immutable deduplication, uncertainty, reconciliation,
lease fencing, local ACK-write loss, status joining and bounded runner behavior.
Their execution and independent review belong to the parent workflow. Existing
queue/TKL/status/background consumers and changed-file analysis also remain
parent gates. The old queue test's “future version 2” fixture now uses future
version 3 because database version 2 is supported. Connected server/device acceptance, full Phase validation,
comprehensive review and release remain separate outstanding obligations.
