# Direct-upload integrity development plan

Status: planned; no implementation or live acceptance performed.

The user requested a plan for server-authorized new-file direct upload into an
allowed Drive folder, followed by independent content-hash verification. The
selected route uses backend service-account credentials and per-file resumable
URLs, never a general Google token on the phone.

TFC-TKL01 binds expected SHA-256 and verification status. TFC-TKL02 streams the retained original digest before prepare, then sends direct resumable chunks without Google credentials. TFC-TKL03 reconciles interruptions through TKL, preserves originals and exposes verification failures. Keep existing queue, safe receipts and legacy route disposition; do not persist session URLs in ordinary queue/status data.

[Contract, sequence and pending acceptance](../../../../../../Project2026/nict-editing-studio-app/docs/notes/direct-upload-integrity-plan.md).

Existing App Phase 6.3/direct-provider work is reused. Current tests and live
observations do not by themselves prove SHA-256 validation. No active worktree,
queue, credentials, deployment, live allowance, commit or release was changed
by this documentation update.
