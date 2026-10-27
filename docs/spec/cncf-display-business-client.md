# Formal ordinary resource Business client

ESA5-05 adds `CncfDisplayBusinessBinding`, `CncfDisplayBusinessResult` and
`CncfDisplayReadClient.invokeBusiness(binding:, observation:)` to the existing
formal read library. Core owns the ordinary resource request and receipt adapter.
TFAF owns the common command controller, action presentation and explicit safe
reconciliation. App declares trusted binding values and labels. Core performs no
implicit read, query, descriptor request or command replay.

## Authority and selected contract

The original Phase 5 ESA5-05 CyclePlan freezes this ordinary route separately
from Display Mutation and the development prototype. The selected producer is
`server-esa5` at `ae214739872de8423033b75a66bb274101140d17`, particularly
`docs/spec/display-reference-app-handoff-v1.md`,
`src/main/scala/org/simplemodeling/textus/editingstudio/impl/EditingStudioReferenceBusinessServiceFactory.scala`,
`src/test/scala/org/simplemodeling/textus/editingstudio/application/display/ReferenceRuntimeFixture.scala`
and its independent `PostgresqlReferenceAcceptanceSpec.scala` oracle. Existing
`test/fixtures/cncf_display_reference_v1` read inputs are genuine local producer
baselines. Ordinary ACKs in the new client specifications are explicitly
controlled responses; they are not producer goldens or new server execution.

The selected reference configuration is:

| Binding member | Trusted value |
| --- | --- |
| componentId | `org.simplemodeling.textus.EditingStudio` |
| actionId | `request-review` |
| bindingId | `ess.reference.request-review` |
| service | `reference-business` |
| operation | `requestReview` |
| expectedOutcome | `review-requested` |
| revisionIncrement | `1` |

Bindings are immutable caller configuration, with no wire decoder, descriptor
URL or dynamic routing. Component/action/binding identities and outcome must be
nonempty, already trimmed Strings without controls. Service is one path segment
matching `^[A-Za-z][A-Za-z0-9-]*$`; operation matches
`^[A-Za-z][A-Za-z0-9]*$`. Revision increment defaults to 1 and must be in
1..2147483647. Invalid trusted configuration throws `ArgumentError` consistently.
Increment describes this independently trusted one-resource command contract;
it is not a universal claim about Business Operations.

Invocation re-admits the complete original observation wire as formal Detail
against the client's selected profile and requires one resource. The binding
component must match the selected profile. Exactly one current model action must
match both actionId and bindingId and have availability `enabled`. Wire label and
availability are inert current-state hints; neither supplies routing or
authorization. The ordinary binding does not depend on mutationRevision or a
mutation descriptor. Flattened ResourceRecord revisions are never observations.

The original revision must be a canonical positive Long decimal String, with
observed+increment no greater than 9223372036854775807. Arithmetic uses BigInt.
All preparation precedes token lookup and dispatch. Resource identity is never
trimmed, coerced or normalized. Unpaired UTF16 surrogates reject locally because
UTF8 form encoding would replace them; valid Unicode pairs and literal plus,
space, percent and form delimiters are preserved on decoding.

## Ordinary request and receipt

One POST goes to `${service}/${operation}.json` beneath the selected endpoint.
The sole query member is `textus.output.shape=envelope`. The request has no
Display resourceType/screenId/resourceId query selectors or domain parameters.
Its exact body is `resourceId=${Uri.encodeQueryComponent(originalResourceId)}`,
with `Content-Type: application/x-www-form-urlencoded;charset=utf-8`. It has no
JSON Business body, body revision or descriptor. One strong `If-Match:
"revision-N"` carries the original formal resource revision.

The framework envelope's `data` must be an object with exactly resourceId,
revision and outcome. Resource ID must equal the captured original String;
outcome must equal the trusted expectedOutcome. Revision must be an actual
canonical positive Long JSON integer token and equal observed+increment.
Quoted numbers, booleans, null, decimal/exponent/negative/leading-zero tokens,
overflow, missing/extra members, duplicate decoded keys and malformed JSON
reject. Display, projection and Presentation Context members are extra data,
not an alternate receipt shape. The existing bounded strict raw JSON parser
retains numeric lexemes, including values above 2^53 and Long maximum.

`CncfDisplayBusinessResult` exposes only the original immutable `binding`,
`resourceId`, exact decimal String `revision` and `outcome`. It has no Display or
context. The ordinary receipt cannot adopt, clear or synthesize generic context.
The current admitted context remains available for the caller's later explicit
safe read. Receipt storage, result presentation and safe refresh belong to the
common controller. ESA5-05 does not add automatic reload; ESA5-06 owns that
continuation.

## Existing exchange policy

The private exchange gains default-preserving `displaySelectors` and
`bodyContentType` options. Ordinary Business selects false and the form media
type; existing read/update request selectors, bytes and headers keep their
defaults. No public raw transport is introduced. Ordinary requests use the same
per-request ephemeral bearer lookup, HTTPS or explicit numeric-loopback opt-in,
ASCII generic context carrier, redirect/retry prohibition, 262144-byte response
limit, 64-container JSON depth limit, timeout, body cancellation, generation
checks and borrowed/owned HTTP client policy.

Business reserves the existing exclusive command owner synchronously before
token lookup. Concurrent or reentrant read/query/describe/update/Business calls
reject busy before credentials, including token, send and response-body waits.
The command may supersede an older safe read; normal safe-read supersession
remains the existing policy. Disposal retires publication and aborts transport
without establishing rollback or closing a borrowed client.

The same redacted `CncfDisplayReadException` and structured `CncfDisplayFailure`
taxonomy apply. A valid Conclusion may identify conflict on HTTP 400; message
text and status alone do not determine semantics. Business requests no editable
fields, so a diagnostic resembling an update field path grants no editable
rejection. Unadmitted error bodies, malformed success, connection failure,
timeout or disposal after dispatch are unknown outcomes, with no fabricated
receipt. Pre-dispatch failures are not unknown writes. No automatic POST retry
or Core read follows either result.

`OrdinaryOperationTransport` remains a distinct development prototype using
`textus.operation.prototype.v1` JSON. This formal REST adapter neither aliases
that wire nor adopts its context or integer metadata.

## Authored evidence and remaining gates

`test/display/cncf_display_business_test.dart` authors observable controlled HTTP
specifications with adjacent Given/When/Then comments. It covers exact route,
form, selectors, strong header, separate receipt and no implicit requests;
configuration and action/binding/profile/List/increment/overflow predicates;
raw Long and malformed/duplicate-key ACKs; Unicode form preservation and
unpaired rejection; generic context retention and credential refresh;
structured conflict and redaction; held token/send/body exclusivity and
reentrancy; pre/post-dispatch timeout/disposal, late delivery and borrowed-client
survival. Existing accepted read/update tests remain regression inputs.

This document records authored implementation and specifications, pending parent
validation and independent review. It claims no focused test pass, analyzer
pass, server/native roundtrip, Phase acceptance, publication or deployment.
The parent owns selected focused Core checks, consumer admission, integrated
Step review and commits; ESA5-07 retains actual native/context and full gates.
