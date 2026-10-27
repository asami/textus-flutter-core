# Hygiene follow-up — 2026-10-27

Discovery: ordinary client source acceptance review; owner: textus-flutter-core.
Priority: P3. Category: pre-existing executable-specification readability.

HYG-ESA63-ORD-001 — OPEN. Core test/submission/submission_dispatch_recovery_test.dart:31 retains the pre-existing opaque scenario name DR1. Failure output does not describe its actual recovery behavior: durable dispatch uncertainty after ACK-save failure, reopening, and recovery through the identical idempotent packet without repeated uploads. This is nonblocking executable-specification readability debt; the scenario has substantive assertions and semantic Given/When/Then. A future test-maintenance task may add a descriptive behavioral name while retaining DR1 for traceability and preserving all behavior/assertions. This record authorizes no cleanup in the ordinary source commit.

Outside the current repair boundary: the name predates the delivery/handoff
delta and does not weaken its executable behavior. No maintenance task or
implementation is admitted by recording this item. Scheduling and later
task/commit references remain unassigned.
