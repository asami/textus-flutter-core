# Formal CNCF Display Text update client

ESA5-03 adds the descriptor and update-first client slice to the existing
`CncfDisplayReadClient` library. `CncfDisplayReadProfile.mutationRevision` is an
optional trusted pin; existing read callers retain their constructor/API shape.
Mutation calls reject locally when that pin is absent. Component, resource,
definition and mutation revisions and all producer provenance remain independently
selected caller authority. Received metadata never supplies those pins.

The selected producer authority is `server-esa5` at Step base
`ae214739872de8423033b75a66bb274101140d17`, its
`docs/spec/display-reference-app-handoff-v1.md` and the two original mutation
goldens in `src/test/resources/display/protocol/v1`. Generic schemas follow CNCF
`docs/spec/display-mutation.md` R1–R5, `display-mutation-service.md` C3 and current
`DisplayMutationResultCodec`/`DisplayMutationResult`, including their optional
outer Presentation Context extension. The selected Conclusion/Observation wire
supplies failure taxonomy and ordered cause facets.

## Public consumption

`describeMutation()` returns `CncfDisplayMutationDescriptor` after authenticated
GET `display/describeMutation.json`, using resourceType, Detail screenId and
`textus.output.shape=envelope`. Its immutable `fields` retain producer order;
each `CncfDisplayMutationField` exposes `locator`, `editability`, optional explicit
`bindingId`, `acceptedKinds` and inert `web` hints. Locators have scoped value
equality. Intrinsic readonly fields carry no inferred binding; a currently
readonly bound field retains its explicit ID. `supports(operation)` and
`isAvailable(operation)` are independent. Neither authenticates a caller.

The descriptor decoder checks exact schema/object members, literal version 1,
source/selection/provenance, scoped and binding uniqueness, closed tags, nonempty
unique known kinds, mandatory Boolean Web flags and values/validation containers.
Canonical decimal strings and canonical nonnegative Int hint lengths are checked;
patterns, values, help and control hints remain data. No inverse binding, target,
domain validation or authorization is inferred.

`update(descriptor:, observation:, changes:)` accepts a genuine formal Detail
observation and a nonempty ordered list of `CncfDisplayTextChange(locator, text)`.
It repeats source/definition admission, requires one canonical positive Long
String observation, gates current update support/availability, and rejects
unknown, repeated, unbound, readonly, non-Text or Web-vetoed changes before I/O.
The four Web vetoes are hidden, system, readonly and multiple. Domain validity,
including whether a blank title is acceptable, remains server-owned. Empty
description Text is transport-valid.

One PUT `display/update.json` uses only the same Detail selectors and envelope
selection. Its one strong `If-Match: "revision-N"` is derived from the original
formal resource observation, never a flat ResourceRecord or business revision.
The raw JSON body has schema/version, resourceType, definition with
mutationRevision, provenance, resourceId and ordered located Text changes. It has
no componentId, binding target/path or resource revision. Omitted fields remain
absent. Rendering escapes UTF16 code units before UTF8 encoding, preserving
leading/trailing text, newlines, Japanese, surrogate pairs and isolated surrogates
without trimming or normalization.

## Receipt and continuation boundaries

`CncfDisplayMutationResult` exposes descriptor, outcome, resourceId and exact
decimal String revision independently of its optional `display`. Only updated
and unchanged are admitted for this API. Original-observation arithmetic is exact:
updated requires observed+1 through Long maximum; unchanged requires observed.
The strict bounded JSON parser retains numeric token spellings, rejects repeated
decoded keys and limits container depth to 64. Outer revisions never pass through
double. Quoted, fractional, exponent, leading-zero and overflow revisions reject;
version `1.0`/`1e0` reject despite numeric equivalence.

Ready requires exact nested formal Detail source, definition, ID and receipt
String revision. Pending retains the authoritative receipt and one of
view-not-current/projection-unavailable. `retryCommand` is always false and
`reloadRequired` reports missing Ready projection. No receipt is fabricated for
errors or indeterminate acknowledgements. An explicit future safe read belongs
to the common controller; Core performs no hidden reload or command replay.

The optional result `presentationContext` reports outer acknowledgement presence
without manufacturing a value. If supplied with Ready, it must match the nested
supported context. The same client flow adopts outer context when supplied,
otherwise Ready nested context; Pending with absent outer context retains the
current continuation. Read responses retain their existing omission/reset
semantics. Core owns the generic ASCII header carrier, and App code neither
copies headers nor allocates variants or flows.

## Authenticated command ownership and failures

The existing private transport handles GET and PUT, with per-request ephemeral
token lookup, HTTPS or explicitly opted-in numeric loopback, no redirects/retries,
262144 response bytes, timeout, body cancellation and borrowed/owned client
cleanup. Starting a command reserves the client before any await and may retire
an older safe GET. All later read/describe/update calls reject busy until command
terminal; they cannot abort or replace it. Safe GETs retain their existing
supersession behavior. Disposing retires publication and aborts transport; it
does not establish rollback. Generation/disposal checks follow credential,
header and body waits.

`CncfDisplayReadException` retains its compatible const construction and redacted
string, adding optional `failure` and `outcomeUnknown` (default false).
Connection, timeout, malformed response or invalid success after dispatch is
unknown. Local validation and credential failures before dispatch are not.
HTTP status remains `statusCode`, separate from Conclusion meaning.

`CncfDisplayFailure` preserves immutable `conclusion` and ordered `facets` and
exposes category/symptom, optional diagnostic code/path, `isConflict`,
`isEditableRejection`, optional scoped `fieldLocator` and
`reconciliationRequired`. Only taxonomy argument/invalid plus the approved code
DSP96_MUTATION_VALUE_INVALID at an exact requested field path is an editable
rejection. Operation/conflict is identified by taxonomy, never HTTP 409 or message
text. Every other admitted failure requires authoritative reconciliation; an
unadmitted failure has no typed semantics and is unknown. Exception/failure
strings never reflect endpoint, payload, token, provider throwable or message.
Consumers should present only approved code/scoped field information.

Conclusion metadata retains every JSON number as a private immutable lexical
token inside the recursively immutable maps/lists. This includes status numbers,
Long expected/actual facets above web integer precision and arbitrary valid
decimal/exponent metadata; none is rounded, coerced or rejected by a local Int
limit. `CncfDisplayFailure.numberLexeme(Object? value)` returns its exact token
String, or null for every nonnumeric value, including a numeric-looking String.
Callers can explicitly parse a known facet when required. These metadata numbers
provide no mutation observation or authorization authority. Descriptor/version/
hint integer admission, outer receipt Long checks and nested read decoding retain
their separately defined scalar rules. This representation is the frozen parent
clarification `ESA5-03-FAILURE-NUMBER-001`; it adds no public numeric type or wire
schema.

## Controlled executable evidence and remaining owners

`test/display/cncf_display_mutation_test.dart` authors observable HTTP request,
raw lexical JSON, descriptor/readonly matrices, receipt/context, Conclusion and
held token/response/body scenarios, with adjacent Given/When/Then clauses.
The two mutation fixtures retain producer bytes; generated result/failure test
inputs are controlled client tests. Existing read specifications remain owned
regression inputs. The parent owns formatting, analysis, focused test execution,
independent review and acceptance. This document claims no test execution, native
roundtrip, full validation or deployment acceptance. TFAF owns the common editor
and reconciliation UI; App owns trusted composition/pins. ESA5-04 through ESA5-07,
including actual native environment and final validation, remain required.
