# Phase 3: Sensitive Interaction and Protected Client Context

Status: PLANNED
Plan date: 2026-10-16
Depends on: CNCF Phase 111
Related: Sensitive Information Architecture, Material transport security
Consumer: textus-flutter-application-framework Phase 4

## Goal

Provide the mobile/platform implementation boundary for sensitive interactions
without exposing highly sensitive provider values to ordinary application
state.

## Planned work

- protected storage abstraction for actual OAuth/session/refresh credentials
  using Android/iOS platform facilities;
- provider adapter boundary for UI-inclusive Sensitive Interaction;
- common result/reference contract aligned with CNCF Phase 111;
- Android and iOS implementation profiles with the same domain semantics;
- ensure Material IDs/URNs remain identifiers, not encrypted pseudo-credentials;
- minimize sensitive local persistence and define handling for classified local
  working data;
- evaluate payment, identity/login, biometric/signing/provider-consent cases as
  concrete adapter examples.

## Initial direction

Provider/OS-owned UI should capture excluded highly sensitive values whenever
available. Flutter Core receives only the bounded result/reference required by
the application contract.

Do not create generic card/CVV/password widgets as the preferred framework path.
Direct capture, when unavoidable, is an explicit exceptional profile.

## Plan identity reconciliation — 2026-10-27

The user approved retaining closed Phase 2 for Background Transfer and moving
this still-planned Sensitive Interaction proposal to Core Phase 3. The source
proposal and its CNCF Phase 111 dependency remain unchanged in meaning; its
consumer is the already reconciled TFAF Phase 4. No implementation or execution
is started by this renumbering. See the [decision](../journal/2026/10/2026-10-27-phase-plan-reconciliation.md).
