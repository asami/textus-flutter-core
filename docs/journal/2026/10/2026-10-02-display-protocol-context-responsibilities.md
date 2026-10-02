# Display Protocol context responsibility decisions

Date: 2026-10-02
Status: planning history; no implementation or acceptance evidence
Owner: textus-flutter-core
Proposal: [display-protocol-presentation-context.md](../../../notes/display-protocol-presentation-context.md)

The Editing Studio app user requested UI-driven protocol and server-model
evolution proposals using the current development-only server sample. The
user added A/B and multi-arm support, then clarified that experiment/arm
information travels as context while the UI application remains unaware of
experiment logic. Framework UI can select a definition by the supplied arm.
Allocation, lifecycle, metrics and evaluation remain server/Experiment duties.

The user generalized this beyond experiments and identified presentation-relevant
CNCF ExecutionContext content as the source of the protocol context. Core owns
receive/decode/transport/lifetime/propagation; TFAF owns context-driven definition
selection and visual realization; the app registers declarative configuration
and composes public APIs. Core carries the context and does not choose screen definitions.

At the explicit request to leave notes/journal in both packages, the linked
proposal records this boundary. The app proposal is
[the shared UI-driven handoff](../../../../../../Project2026/nict-editing-studio-app/docs/notes/display-protocol-presentation-context-proposal.md).
Physical codec, per-field ExecutionContext mapping, context continuation and
arm-definition version correspondence require joint CNCF/server/Core/TFAF
review. No runtime API, accepted protocol or dependency Phase is created here.

Only new notes/journal documentation is written. Existing source and accepted
releases are unchanged. No test, runtime, commit or publication is performed.
