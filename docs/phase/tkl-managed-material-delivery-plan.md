# TKL-managed Material delivery — Core follow-on

status=planned
planned_at=2026-10-24
spec=../notes/tkl-managed-material-delivery.md
consumer=nict-editing-studio-app Phase 6.3

This is a follow-on to the delivered submission runtime. It does not reopen
accepted Core Phase 2 work or rewrite the older main-checkout Phase projection.
Reconcile the actual App-consumed Core worktree at entry; reuse its public queue,
native credential and transfer capabilities instead of implementing them again.

| ID | Delivery | Status |
| --- | --- | --- |
| TFC-TKL01 | Bind TKL's destination/preparation/finalization/reconciliation contract and authorization to public Core APIs. | OPEN |
| TFC-TKL02 | Deliver one complete Shared Drive path with persisted execution state and TKL registration, using existing background infrastructure. | OPEN |
| TFC-TKL03 | Close interruption/configuration-change/access failure branches and hand the public facade/status contract to TFAF/App. | OPEN |

- [ ] TKL supplies configuration; no mobile folder/drive-ID provisioning.
- [ ] Shared Drive and My Drive shared-folder contracts use the same Core API.
- [ ] Metadata and original associations survive TKL registration; upload success
  alone does not produce registration or Editing Studio submission success.
- [ ] Offline waiting, process restart, targeted retry and uncertain completion
  retain originals and the existing delivery destination.
- [ ] Existing queued direct-Drive work is preserved with an explicit migration
  disposition; no silent conversion, duplicate registration or queue reset.
- [ ] Focused behavioral specifications and affected consumer tests pass; one
  connected independent review covers the slice. Existing required release checks
  remain applicable; fixture results do not claim real Google authorization.

Dependencies: [TKL workstream](../../../textus-knowledge-lake/docs/phase/tkl-managed-mobile-material-delivery-plan.md),
[TFAF workstream](../../../textus-flutter-application-framework/docs/phase/tkl-managed-material-delivery-plan.md).
Core acceptance covers its public/runtime boundary; the App owns real-device
end-to-end acceptance, without requiring all unrelated producer phases to close.


## Direct new-file upload and SHA-256 verification — planned delta

Contract and connected acceptance: [direct-upload integrity plan](../../../../Project2026/nict-editing-studio-app/docs/notes/direct-upload-integrity-plan.md).

TFC-TKL01 binds expected SHA-256 and verification status. TFC-TKL02 streams the retained original digest before prepare, then sends direct resumable chunks without Google credentials. TFC-TKL03 reconciles interruptions through TKL, preserves originals and exposes verification failures. Keep existing queue, safe receipts and legacy route disposition; do not persist session URLs in ordinary queue/status data.

- [ ] Implement the owning DU items and affected contract/behavior specifications.
- [ ] Hand off actual evidence and limitations; this planning addition claims no implementation, live upload or Phase closure.
