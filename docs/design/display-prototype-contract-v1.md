# Provisional Display prototype contract v1

Date: 2026-10-02
Owner: textus-flutter-core; parent app PHASE-4 / ESA4-02 / S01
Status: development-only candidate API; implementation authored, validation and independent acceptance pending.

This is the frozen client candidate contract. It is distinct from a production
CNCF wire codec and from the server sample's identity/version. No endpoint,
production admission, publication or real-server execution is implied.
Public consumers import `package:textus_flutter_core/textus_flutter_core.dart`.

Inputs: [Core responsibility proposal](../notes/display-protocol-presentation-context.md),
[app R01–R10 and SC01–SC20](../../../../Project2026/nict-editing-studio-app/docs/notes/display-client-prototype-requirements.md),
[server revision-1 sample](../../../../Project2026/nict-editing-studio/docs/journal/2026/10/2026-10-01-display-model-phase-96-sample.md).
The [canonical application asset](../../../../Project2026/nict-editing-studio-app/config/display_prototype_fixture.json)
owns every NICT string, semantic state and mapping; Core specifications use neutral inline data.

## Frozen API and wire decisions

All new symbols are provisional and exported additively from Core's public
barrel. They use Dart names consistent with existing Core contracts, public
doc comments, final fields, defensive collection copies and immutable
collection views. Existing files retain their complete current content.
No new dependencies, generated files, persistence, HTTP routes or platform
APIs. JSON wire spellings below are exact and use camelCase except the
stable lowercase value/outcome tags. Reject missing/extra keys and wrong
types at each known object boundary with FormatException. Public invalid
constructor arguments may use ArgumentError. Identifiers must be nonblank
but preserve their supplied bytes; do not normalize/trim IDs or text values.
All codecs take JSON-compatible Map<String,Object?> and return that type.

### A. display_protocol.dart

- sealed DisplayValue with TextDisplayValue(String value),
  NumberDisplayValue(num value), BoolDisplayValue(bool value),
  TimestampDisplayValue(DateTime value) and MissingDisplayValue(). Provide
  Text/Bool/Missing constructors are const; Number/Timestamp constructors
  validate their inputs at runtime and are not required to be const. Provide
  DisplayValue.fromJson, instance toJson and value equality/hashCode. Wire is
  `{type:"text|number|bool|timestamp",value:<typed value>}`; missing is exactly
  `{type:"missing"}`. Number is finite, bool is not number, null is not Missing.
  Timestamp accepts an explicit UTC instant only and serializes ISO-8601 UTC.
  Decode only calendar-valid YYYY-MM-DDTHH:mm:ss[.fraction]Z; validate components
  so DateTime.parse normalization cannot admit invalid days. Preserve text
  exactly, including empty/whitespace strings, combining marks and line breaks.
- DisplayFieldLocator(screenId,sectionId,fieldId): named constructor arguments,
  exact value equality and toJson/fromJson with those three keys. Repeated field
  IDs in distinct sections are valid; a scoped locator is the editable identity.
- DisplayField(id,label,role,DisplayValue value), DisplaySection(id,fields),
  DisplayAction(id,label,bool enabled), DisplayProvenance(producerId,sourceId,
  String revision) all use required named arguments and exact-key codecs.
  Ordered lists preserve order; duplicate field IDs within one section or row,
  section IDs, action IDs or resource IDs in one list reject. Roles are open
  nonblank strings, not domain mutation targets. No edit/Operation metadata
  is added to DisplayField or DisplayAction.
- DisplayEditBinding(locator,writable,inputValue,requiredNonBlank) has those
  exact keys. inputValue is typed semantic input beside the model. Read-only
  binding uses MissingDisplayValue for input and requiredNonBlank=false.
  Validate binding locators are unique and each resolves exactly one field in
  the Detail, including its exact model screenId.
  No reverse parsing of projected values into semantic input.
- DisplayResourceSummary(resourceId,sourceRevision,fields) represents a list
  row. DisplayListModel(screenId,title,detailScreenId,items) and
  DisplayDetailModel(screenId,title,sections,actions) hold presentation only.
  DisplayListData(resourceType,snapshotId,provenance,model) and
  DisplayDetailData(resourceId,sourceRevision,provenance,bindings,model) wrap
  metadata and models. Source revisions are positive actual int; snapshotId,
  protocol, context and definition versions have separate identities.
- Data wire is exactly `{metadata:{...},model:{...}}`. List metadata has
  resourceType,snapshotId,provenance; list model has screenId,title,
  detailScreenId,items. Each list item has resourceId,sourceRevision,fields.
  Detail metadata has resourceId,sourceRevision,provenance,bindings; Detail
  model has screenId,title,sections,actions. Provenance Detail revision must
  equal sourceRevision.toString(), and List provenance revision equals
  snapshotId. This is a candidate representation of the accepted minimum
  logical vocabulary, not an implementation or extension of Cozy's Scala API.
- DisplayFieldError(locator,code,message), with nullable locator for a global
  error. enum DisplayCommandOutcome {changed,noOp,rejected,conflict,unsupported}
  has exact wire tags changed,noop,rejected,conflict,
  unsupported. DisplayMutationResult(resourceId,outcome,currentRevision,
  committedRevision,fieldErrors,message,display) has nullable positive int
  revisions, nullable message and DisplayDetailData display; all keys required.
  changed requires committedRevision and matching currentRevision; noop
  requires currentRevision, committedRevision=null; rejected/conflict/unsupported
  have committedRevision=null and display=null. conflict requires currentRevision.
  A changed result may omit display or carry a stale Display to model pending;
  do not reject its successful command just because projection lags. Result
  resource identity must agree with included Detail. DisplayOperationResult
  has the same fields except display is absent from its closed shape; an
  Operation cannot supply implicit Display reload evidence. Its successful
  result is changed; reject noop for Operation. No mutation/replay logic here.

### B. presentation_context.dart

- PresentationContext(flowId,sourceId,componentId,families), immutable list.
  Wire keys schema="textus.presentation-context.v1", flowId,sourceId,
  componentId,families. At most 8 unique family namespaces. Do not serialize
  ExecutionContext, RuntimeContext, UnitOfWork, capabilities or security objects.
- PresentationContextFamily(namespace,int version,producerId,bool isRequired,
  DateTime? expiresAt,PresentationContextPayload payload). Wire keys namespace,
  version,producerId,required,expiresAt,payload, all mandatory, nullable expiry.
  Versions positive int, expiry explicit UTC/valid ISO instant, namespace and
  producer nonblank. An expiry at or before the injected now is expired.
- Sealed payloads: LocalePresentationPayload(localeTag) for namespace
  textus.presentation.locale v1; SuppliedArmPresentationPayload(namespace,
  presentationSet,armId,int definitionVersion,assignmentReference) for
  textus.presentation.arm v1; CorrelationPresentationPayload(flowReference,
  attemptReference) for textus.presentation.correlation v1; and
  OpaquePresentationPayload(Map<String,Object?> values) for unknown namespace
  or unsupported known version. Payload codecs have exactly the named keys;
  localeTag matches the explicit candidate subset
  `[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*`; arm fields are nonblank and definition
  version positive int. Arm is required whenever present. Correlation's
  flowReference must equal the enclosing flowId. Known v1 malformed payload
  rejects before support/expiry filtering, never becomes opaque.
- Every payload is a defensively frozen JSON object: string-keyed maps, lists,
  null, bool, String and finite num only; max 4096 UTF-8 bytes measured by
  jsonEncode, max container depth 4 including root object. Reject non-JSON
  values and excess count/size/depth even in later omitted optional families.
  Known payloads also obey limits. Unsupported versions remain opaque for
  structural decoding only, then policy rejects/omits; this is not pass-through.
- PresentationExtensionSupport(namespace,version,producerId) selects exactly
  one optional opaque family allowed to carry through. PresentationContextPolicy
  constructor requires allowedProducerIds and optionalExtensions (default
  empty); defensively copy. Known v1 support is fixed to the three namespaces.
  admit(context,{required sourceId,componentId,flowId,nowUtc}) returns
  PresentationContextAdmission(context,diagnostics). Diagnostics are immutable
  objects namespace,code,message. nowUtc is required UTC, no DateTime.now.
  Wrong source/component/flow, unallowed producer, required unsupported/unknown/
  expired family throw PresentationContextException(code,message). Optional
  expiry/unsupported version/unknown family is omitted with a diagnostic unless
  exact optional extension support permits unexpired opaque carriage. Required
  unknown always rejects, even if an optional allowlist entry exists.
- admitResponse(previous,received,{required nowUtc}) first admits received for
  previous source/component/flow, then checks producer update policy. Arm
  payload/producer/version/expiry remain exact and a present arm cannot vanish.
  Locale cannot change, disappear except by optional omission, or appear mid-flow.
  Correlation may replace attemptReference only, with identical flow/producer/
  version/expiry. Optional permitted opaque payload may be replaced wholesale
  only by the same exact namespace/version/producer/expiry, with bounds rechecked;
  never deep merge. No new family appears mid-flow. Optional omissions after
  expiry/unsupported filtering are allowed. Incompatible response throws;
  this pure policy never overwrites the previous context. Later runtime preserves
  selection/draft and exposes incompatibility; explicit discard/reset starts a
  new fixed fixture flow. An unexpired previously supported optional family
  missing without a filtering diagnostic rejects as an incompatible omission;
  expiry of the previous family itself also permits omission. Payload/context/
  family equality is structural.

### C. display_transport.dart

- enum DisplayRequestKind {query,read,update,create,delete}; protocol schema
  textus.display.prototype.v1. DisplayRequestMetadata(context,observedRevision)
  requires context, nullable positive int revision; wire keys context,
  observedRevision. Read/query/create use null; update/delete require revision.
- sealed DisplayRequest with resourceType and metadata. Concrete
  DisplayQueryRequest, DisplayReadRequest(resourceId),
  DisplayUpdateRequest(resourceId,List<DisplayFieldInput> fields),
  DisplayCreateRequest(fields), DisplayDeleteRequest(resourceId).
  DisplayFieldInput(locator,value) has exact codecs. Duplicated update locators
  remain representable for a semantic rejection fixture, not silently deduplicated.
  Every request.toJson includes schema,kind,resourceType,metadata plus exactly
  the concrete resourceId/fields members; values are typed and immutable.
- OrdinaryOperationRequest(operationId,resourceId,metadata) serializes schema
  textus.operation.prototype.v1, operationId, input:{resourceId}, metadata.
  metadata observedRevision is required positive int; revision is not input.
- abstract interface DisplayTransport has Future<Map<String,Object?>> methods
  query(DisplayQueryRequest), read(DisplayReadRequest),
  update(DisplayUpdateRequest), create(DisplayCreateRequest),
  delete(DisplayDeleteRequest). OrdinaryOperationTransport has
  execute(OrdinaryOperationRequest). No client context getter/setter or callback
  propagation is required in the app; later Core session owns request construction.
- DisplayListResponse(context,data), DisplayDetailResponse(context,data),
  DisplayMutationResponse(context,result), OrdinaryOperationResponse(context,
  result), each fromJson/toJson. Exact Display envelope keys schema,kind,context,
  data; kind=list|detail|mutation. Ordinary Operation envelope has schema
  textus.operation.prototype.v1, context,result, no Display keys. Reject
  wrong schema/kind, malformed body/context and extra members before use.
- enum DisplayTransportFailure {unavailable,ambiguous};
  DisplayTransportException(failure,message). It is distinct from decoded
  rejection/conflict/unsupported outcomes and from context incompatibility.
  A read exception can be retried by later runtime; ambiguous commands are
  never automatically retried. Ports and codecs themselves perform no retry.

### D. scripted_display_transport.dart and display_prototype_fixture.dart

- ScriptedTransportReply.response(Map<String,Object?> wire) freezes the complete
  JSON-compatible wire. ScriptedTransportReply.failure(exception) throws the
  supplied DisplayTransportException when consumed. ScriptedDisplayExchange
  (kind,reply); ScriptedDisplayTransport(exchanges) implements DisplayTransport
  with one private FIFO cursor, no source mutation and no retry. Each invocation
  records an immutable DisplayTransportCall(kind,request) in calls before
  consuming one exchange; wrong kind/exhaustion throws StateError with an
  explicit fixture mismatch. Result is an asynchronous Future. Ordinary port
  uses ScriptedOrdinaryOperationTransport(replies) and immutable calls of the
  exact OrdinaryOperationRequest. Expose callCount and unmodifiable calls.
  Do not run the context policy inside raw fake ports: later common runtime
  must admit context before calling any transport; raw port observes what
  actually crossed the boundary. Context tests prove the pure admission policy
  here, not a runtime pre-side-effect guarantee that is not implemented yet.
- DisplayPrototypeFixture.fromJson/toJson, schema textus.display.fixture.v1,
  exact keys schema,reference,resourceType,contexts,displayResponses,
  operationResponses,semanticSeed,projectionBindings,operationBindings.
  reference keys sampleId,sampleRevision,provisionalVersion,developmentOnly;
  require developmentOnly=true and positive revision/version. contexts is a
  String-keyed map of PresentationContext. Response maps are named envelopes
  strictly decoded by their response kind/schema. Expose immutable getters
  contextFor(id), displayResponse(id), operationResponse(id); unknown IDs throw.
  semanticSeed/projectionBindings/operationBindings are immutable JSON
  collections (max depth 16, 65536 UTF-8 jsonEncode bytes per collection),
  preserving application-owned semantic/projection mapping data.
  They are inputs for the ESA4-03 generic fake source engine, not interpreted
  domain commands here. This decoder never implements application-specific
  collecting/review transitions. No raw protocol copy appears in the app.

## Application-owned fixture content and docs

Create config/display_prototype_fixture.json and register that one asset in
pubspec.yaml. Use sampleId ess.display-reference.v1, sampleRevision 1,
provisionalVersion 1, developmentOnly true; Core wire versions above are
explicitly candidate versions distinct from the server sample and CNCF codec.

sourceId=ess.display-reference.v1, componentId=nict-editing-studio,
producerId=nict-editing-studio. Known families and one allowlisted optional
nict.presentation.fixture.hints v1 use this producer. Context case IDs are
A,B,C,locale-only. Each has distinct fixed flowId fixture-flow-A/B/C/locale,
locale ja-JP and matching flow correlation attempt-1. A/B/C additionally carry
the required arm with namespace nict.editing-studio, presentationSet collecting,
opaque armId A/B/C, definitionVersion 1, assignmentReference fixture-assignment-A/B/C.
locale-only has no arm and includes the optional opaque hints {density:"comfortable"}.
All default expiresAt values are null. These are supplied producer examples,
not client allocation or UI branches. Future TFAF registry keys use all four
arm identity components; neutral absence requires explicit registration.

semanticSeed is the two exact R02 resources with positive source revision 1
and typed title/description/workflowState (collecting/review_pending).
projectionBindings declares screen capture-detail, section main, ordered title,
stage,description; title/description semantic input mappings (writable true,
title nonblank, description empty allowed), stage read-only projection lookup
collecting→収集中, review_pending→レビュー待ち. Operation binding request-review
has resource input only, expected collecting state, transition to review_pending;
it is development-only, with no endpoint/production authority assertion.

Named Display responses: list-1, detail-1, changed-2, noop-2, conflict-2,
unsupported-create, unsupported-delete, readonly-stage, invalid-title,
pending-2 (changed committed 2, Detail 1), list-2, detail-2, list-3, detail-3.
Named Operation response request-review-3: changed/current/committed 3, no
Display. Responses use case A context for basic replay examples. List fields
title/stage only, ordered two resources, no eager Detail; main Detail fields
have exact values/labels/roles and input bindings from R02/server sample.
Provenance producer/source matches the sample; Detail revision exact resource
revision and List provenance snapshot-N. Snapshots advance illustratively
1→2→3. changed-2 preserves description/state; detail-3 has review stage and no
request-review action. Noop leaves revision 2, conflict has current 2/no commit;
rejections/unsupported have no commit/Display and appropriate scoped/global
errors. Strings and source identities remain application-owned example data.


## Generic mapping collection shapes in the canonical asset

The closed fixture envelope and reference above surround named contexts and
strictly decoded response envelopes. Getter methods return a typed
PresentationContext or an immutable raw response map suitable for a
ScriptedTransportReply. Unknown names throw StateError with the missing ID.
Mapping collections are uninterpreted JSON inputs to the later source engine:

- semanticSeed is an ordered array of resourceId, positive sourceRevision,
  and fields mapping semantic names to typed DisplayValue wire objects.
  workflowState uses Text values collecting or review_pending.
- projectionBindings is an object with screenId, sectionId, ordered fields.
  Each field declares fieldId, semanticField, writable and requiredNonBlank;
  stage additionally declares lookup collecting→収集中 and
  review_pending→レビュー待ち. No inverse lookup is used.
- operationBindings maps request-review to developmentOnly=true,
  inputFields=[resourceId], expected workflowState=collecting and transition
  workflowState=review_pending. Revision remains request metadata.
  These collection shapes are application data, not closed Core domain schemas.

For example an update request has schema textus.display.prototype.v1,
kind update, resourceType collecting-reference, resourceId capture:book-1,
metadata containing context A and observedRevision 1, and fields containing
locator (capture-detail, main, title) with Text 日本の民話・改訂.
The ordinary Operation request has schema textus.operation.prototype.v1,
operationId request-review, input containing resourceId only, and metadata
containing the same flow context with observedRevision 2. Its successful
receipt commits 3 without Display. An explicit subsequent read returns
detail-3; this is distinct evidence from Operation playback.

## Responsibilities and future proof

Core owns typed models/codecs, bounded context admission/replacement policy,
separate raw ports and immutable scripted playback. Its pure policy does not
apply a command or enforce runtime pre-side-effect admission. The raw fake
records what actually crossed the port and never invokes the policy itself.
ESA4-03 supplies common session dispatch and a generic mutable fake source
engine; commands and projection freshness require executable semantic proof
there. ESA4-03 TFAF selects registered definitions by the complete key
(namespace, presentationSet, armId, definitionVersion); assignmentReference
remains fixed flow provenance. Neutral arm absence requires explicit
registration. ESA4-04 supplies app public composition and widget/Web evidence.

Codec/context/playback specifications and the app asset consumer specification
are authored with adjacent Given/When/Then setup/action/observable assertions.
They require parent validation and independent review. Scripted changed/noop/
conflict/pending envelopes establish representability and consumption only:
they do not prove atomic source mutation, revision conflict enforcement, no
replay in runtime, selection/draft retention, or arm widget realization.
SC01–SC20, Step acceptance, final Phase review/validation/release and Phase 5
real-server aggregate/E2E evidence retain their separate gates. Capture and
existing Resource/Settings APIs are retained without migration.
