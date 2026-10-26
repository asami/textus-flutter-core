# TKL delivery in the existing durable queue

Current disposition, 2026-10-27: the bounded TKL follow-on is accepted and closed
with App Phase 6.3's ordinary completion. The source is locally committed;
original phases remain closed. Earlier dated authoring/pending statements below
retain their historical scopes. Current requirements and selected evidence are
indexed by the owning delivery plan; no execution report, new grant, public
release or main integration is added by this management update.

Status: implementation in progress; live provider/device acceptance pending.

The App-led ESA63 work adds explicit TKL intent to SubmissionRequest and TKL
progress/safe direct-upload receipts to the existing SQLite row. Legacy request
and record JSON remain readable. No database reset or second queue is used.
Android background composition builds the borrowed TKL HTTP client from the
service bootstrap/authentication connection.

TKL supplies the retained route: direct `googleDriveResumable` preferred when
supported, otherwise `tklMultipart` with a capability reason. Core never changes
route after permission/network failure or unknown outcome. Provider PUTs use the
narrow session URI without the TKL bearer. Core checkpoints resource/transfer
references and length before notifying TKL; no session URI or general server
credential enters queue/status JSON. Reopening either notifies from that receipt
or asks TKL to inspect the original session before another PUT.

MaterialRegistered is distinct from Submitted. Only confirmed TKL registration
exposes MaterialRef; it never manufactures a Studio acknowledgement. Status can
show physical upload completion while independent TKL confirmation is pending.
Prior legacy Drive requests retain reservations, receipts and selected connections.

334 related submission specifications pass, followed by 23 final focused
native-response/direct-transfer/recovery cases (overlapping, not additive).
Final scoped static analysis reports no issues. Native Record JSON is camelCase;
retained snake_case projections remain readable without renaming opaque context.
No actual TKL deployment/Google/device result or Phase acceptance is claimed.
