# ESA4-02 provisional Display contract acceptance — Core

Date: 2026-10-02
Consumer/parent: nict-editing-studio-app Phase 4
Status: ESA4-02 accepted and locally committed; ESA4-03 in_progress/OPEN

Core commit `7a38c67e165cceb25f85a310ed5582491553d64f`, TFAF commit
`0b3ebaab0f33762c371c21cd2aabbecf716e4810`, and app commit
`739d4694811a46f21ee80cb92fe67a4461e2adc2` are the actual ESA4-02
accepted commits. Original Phase bases and accepted ESA4-01/Phase 2/3 receipts
remain historical authority; these heads do not replace original bases.

## Shared acceptance evidence

Review ledger `esa4-reviews-20261002-root-01` revision 7 retains native
`esa4-02-review-20261002-root-01` revision 1 as FINDINGS, with
`CPB-ESA4-02-SPEC-GROUPING-01` and `CPB-ESA4-02-SPEC-GWT-01`.
Independent `esa4-02-focused-review-v3-result-20261002-root-01` revision 1
resolved those IDs, remained FINDINGS, and reported
`CPB-ESA4-02-SPEC-LOCAL-NAMING-01`. Parent exact16-token M0 proof
`esa4-02-mcr-01-proof-20261002-root-01` revision 1 and amendment
`esa4-02-mcr-01-amendment-20261002-root-01` revision 1 closed naming.
Commit-integrity failure `VF-ESA4-02-COMMIT-WHITESPACE-01` was closed by
exact one-final-LF removal under `esa4-02-whitespace-fix-02-proof-20261002-root-01`
revision 1 and `esa4-02-whitespace-fix-02-amendment-20261002-root-01`
revision 1. No native review was rewritten PASS; M0 is a recorded parent
amendment, not a new independent review.

Retained actual evidence comprises 44 Core/Capture successes and four app
successes, the 11-test representative subset, targeted analyzers and static
checks. Exact postcommit reconciliation recorded 18 committed paths, unchanged
accepted contents/modes for 40 states, and three preserved dirty paths with
contents/index unchanged. This is historical ESA4-02 evidence; no new tests
are claimed by this journal.

## Public consumer boundary and next Slice

ESA4-02 accepted Core's candidate models/codecs/context policy, separate raw
ports, immutable scripted playback and generic fixture decoding. App owns its
actual asset and public-barrel consumer; TFAF records its future public consumer
mapping. Scripted receipts prove representation/consumption, not semantic commits.

ESA4-03 / S01 authors the neutral semantic source and actual asset source specs;
its validation and independent review remain pending. S02 Core session and S03
TFAF UI remain required. There is no package Phase acceptance, publication,
runtime UI acceptance, real-server admission or app Phase closure claim.
Existing Capture, legacy ResourceDetailView actions and Common Settings remain
under their accepted contracts. Empty HYG/DEV ledgers require no empty follow-up
journals. See the [public consumer note](../../../notes/display-protocol-presentation-context.md).
