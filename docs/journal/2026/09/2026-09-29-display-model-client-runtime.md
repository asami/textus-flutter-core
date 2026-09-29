# Display Model Client Runtime Direction

Date: 2026-09-29
Status: architectural direction

Textus Flutter Core will own the client/runtime boundary for the CNCF Display Model Protocol. This is separate from its existing capture runtime work and must not introduce application-specific meaning into Core.

Responsibilities include versioned protocol decode/validation, runtime Display Model representation, common loading/failure/refresh state where appropriate, Action dispatch primitives, and a source abstraction that permits mock/fixture and CNCF-backed sources to be exchanged.

Display Model is already presentation-oriented when it reaches Core: semantic names and server-native values have been projected into abstract UI roles and displayable values. Core does not reconstruct domain meaning and does not perform CNCF semantic View -> Display projection.

textus-flutter-application-framework consumes these runtime Display Models and decides visual realization. The first acceptance path is mock List/Detail -> CNCF List/Detail replacement without rewriting standard UI, followed by one Action round-trip.

Cross-project coordination is owned by textus-knowledge-workbench docs/strategy/knowledge-application-integration.md.
