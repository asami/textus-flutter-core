# Direct-upload content integrity

Status: planned; not accepted.

TFC-TKL01 binds expected SHA-256 and verification status. TFC-TKL02 streams the retained original digest before prepare, then sends direct resumable chunks without Google credentials. TFC-TKL03 reconciles interruptions through TKL, preserves originals and exposes verification failures. Keep existing queue, safe receipts and legacy route disposition; do not persist session URLs in ordinary queue/status data.

Canonical cross-project contract: [plan](../../../../Project2026/nict-editing-studio-app/docs/notes/direct-upload-integrity-plan.md).

SHA-256 here verifies transferred binary content only. Do not use it for update
tracking, management-state identity or unchanged-input certification. Preserve
existing runtime work and completed evidence; implement only the remaining delta.
