# ESA5-03 Core formal Display update slice

Date: 2026-10-27. Implementation authority:
`ESA5-03-CORE-UPDATE-001`, selected `esa5-03-cycle-plan-001`, original PHASE-5
authority/binding/epoch retained. Initial implementation only, repair cycle zero.

The bounded Core change adds a separately pinned mutation revision, immutable
descriptor/field/Text-change/result/Conclusion APIs and authenticated exact
descriptor GET/update PUT on the existing client. The shared private exchange
preserves accepted read admission and transport policy while reserving command
ownership before token lookup. Safe reads can supersede safe reads; commands
cannot be superseded. A retired or malformed post-dispatch acknowledgement has
no fabricated receipt and never triggers replay.

Descriptor metadata remains an ordered hint, distinct from capabilities,
availability, authentication and domain admission. Request Text is escaped by
UTF16 code unit before UTF8. Original formal Detail revision supplies strong
If-Match; exact raw Long receipt spelling and BigInt arithmetic preserve web
precision through Long maximum. Ready and Pending retain their receipt/context
boundaries. Pending omission retains the flow. Conclusion taxonomy and approved
diagnostic code/scoped requested path, rather than status/message, drive safe
editable rejection; every other failure requires reconciliation.

Two exact producer mutation goldens were added from selected `server-esa5`;
their origin and terminal-LF policy are recorded beside them. New executable
specifications contain adjacent Given/When/Then for physical routes/headers/body,
lossless text, descriptor and result tampering, raw lexical versions/revisions,
structured ordered Conclusion evidence, context and held command lifecycle.
Result/error variants are controlled test authoring, not producer output.

Parent clarification `ESA5-03-FAILURE-NUMBER-001` resolves numeric retention
inside Conclusion metadata: every number remains a private immutable lexical
token, exposed losslessly through `CncfDisplayFailure.numberLexeme`, while
numeric-looking Strings remain Strings. Ordered nested maps/lists are recursively
frozen. Raw client specifications include 9007199254740993, Long maximum,
decimal/exponent spelling and nested immutability. This metadata representation
does not change descriptor, receipt or nested read scalar admission.

No formatter, analyzer, test, runtime, Git mutation or review was executed by this
implementation editor. The parent owns those gates and any separately delegated
repair. No acceptance, full/native roundtrip or release claim is made. TFAF/App
remain separate consumer owners; no producer, prototype or UI source changed.
ESA5-04 through ESA5-07 obligations are unchanged.

Same-file target-program debt addressed: the prior read-only exchange now owns
both safe reads and one authenticated command path without exposing raw public
transport or duplicating token/context/cancellation policy. No unrelated debt
was admitted or completed in this slice.

## Parent Step acceptance — 2026-10-27

ESA5-03 is accepted through the integrated independent protected Step review
and focused closure of CPB-ESA5-03-001 in the common Widget. Core401, TFAF84
and App52 focused tests passed;14 affected App consumer tests passed after
the private retired-route repair. Analysis, formatting and integrity checks
passed. Earlier authored-only descriptions and failed validation attempts are
retained as history. The accepted route is controlled common Edit/Save with
retained receipt and explicit safe Reload, without App-owned CRUD. Native
mutation, supplied-context and Business/E2E proof remain later Phase5 work;
this Step does not close the Phase or change producer capabilities.
