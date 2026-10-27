# ESA5-01 — formal CNCF Display read consumer

App Phase 5 starts a separate read consumer of the accepted ESS2-04 handoff.
`CncfDisplayReadClient` uses the normal query/read routes, per-request borrowed
credentials, a bounded JSON response, no redirect/retry and explicit caller
ownership. The owned standard client can be retired with its read flow.

The trusted App profile independently selects source, ABI, semantic contract,
definition and producer provenance. Received metadata cannot select or register
an implementation. String Long revisions, optional query snapshot, definition
revision and provenance remain separate; absent values are not fabricated.
The wire read model is separate from the Phase 4 development prototype.

The first consumer is deliberately the server's Text/Missing reference slice;
other value kinds reject explicitly until lossless typed consumers are added.
The locale slice supports ordinary canonical language/script/region/extension
tags; unsupported tags reject without normalization. No complete arbitrary
Display scalar/locale implementation or mutation support is claimed.
Supported supplied context is carried by Core; unknown positive-version families
are inert and not sent back. Missing output context clears the retained flow.
The HTTP metadata carrier uses compact canonical ASCII JSON: Unicode text is
escaped per UTF16 unit and decodes to exactly the same supplied values. No
base64/percent carrier, ASCII-only ID restriction or normalization is introduced.
Server authentication, assignment, resolver/session and expiry authority remain
server-owned. No arm allocation or security context is reconstructed locally.

Producer-authored goldens are static consumer inputs. Controlled HTTP peer and
widget tests remain distinct from native CNCF server and actual Android proof.
ESA5-01 stays open until its actual server connection is verified.

## Native read acceptance

The subsequent App-owned native read proof passed through the real Android
encrypted connection store and this public Core client against the selected
authenticated server. Exact string revisions and context absence were retained,
native writes stayed zero, and owned cleanup preserved the normal App. The
independent ESA5-01 Step conformance review passed. This accepts the bounded
read consumer; mutation, supplied-context realization, Business/reload and final
Phase validation remain with the later App Phase 5 Steps.
