# Media SDK and external destination acceptance

Decision date: 2026-11-02
Status: specified; implementation and connected acceptance pending
Consumers: App Phase 6.10 (Android/iPhone), then Phase 7 (Web/Fold)

Rationale: [mobile incident applicability and Textus response](https://github.com/asami/goldenport-cncf/blob/main/docs/journal/2026/11/2026-11-02-mobile-security-incidents-and-textus-response.md).
Distinguish legitimate model/diagnostic traffic from media transmission; SDK
use alone is not evidence of compromise or a reason for automatic removal.

## Ownership and scope

Core owns reusable capture/import, OCR/transcription, transfer and diagnostic
adapters and their configuration. Application Framework presents their states
and user choices; App owns the actual packaged composition and connected
acceptance. TKL remains the authority for Material storage destinations and
transfer instructions. No user-entered Drive configuration or App-specific
duplicate networking/credential implementation is introduced.

This extends the existing untrusted-client conditions with MS-01/02. It applies
to photographs, audio and derivatives such as thumbnails, OCR text, transcripts
and extracted metadata, including SDK-originated traffic outside the normal
Core HTTP client. OS photo/microphone permission does not authorize unrelated
external transmission.

## MS-01 — SDK and dependency assessment

For the selected build, identify shipped Dart packages, native Android/iOS
SDKs/plugins and Web dependencies, including transitive components with media,
network, analytics or crash-reporting access. Use existing lockfiles, dependency
reports and packaged artifacts; do not create a second dependency registry.

Record each relevant component's purpose, actual resolved version/source,
media/credential permissions, local versus remote processing, automatic startup
behavior, telemetry and configurable collection. Reconcile the declared SDK
behavior/configuration with the shipped build and observed behavior. Unknown
media transmission is an unresolved acceptance gap, not an assumed safe default.
Disable or replace unnecessary collection or SDKs that cannot satisfy this
contract. Model downloads are distinguished from uploading captured content.

## MS-02 — Explicit media destinations and behavior

Document each enabled transfer by feature, data category, receiving service/
operator and endpoint origin, purpose, trigger and local/remote processing.
Include OCR, transcription/AI, storage, analytics/crash reporting and native OS
speech services; a native API does not by itself establish on-device execution.
Record relevant provider retention/secondary-use settings and unknowns without
claiming that client traffic inspection proves server-side deletion.

Only the selected feature's configured and authorized route may transmit its
required data. TKL-issued transfer capabilities may select dynamic storage
destinations under the existing delivery contract; no hardcoded static hostname
list or duplicate URL authorization engine is required. Endpoint changes and
redirects must not silently forward content or credentials to an unrelated
recipient. Do not silently fall back from local processing to cloud processing.

The UI identifies external processing and its purpose before use, with any
required choice/consent; reuse the selected upload/processing action rather than
prompting for every chunk or retry. Selecting/capturing for a local draft alone
does not trigger cloud processing. Already authorized queued delivery retains
its existing background/retry semantics and account scope. Cancellation and
permission refusal must follow the actual operation contract; local work stays
available and the client does not claim already-transmitted bytes were recalled.

Media, OCR/transcript text, credentials and transfer URLs must not be included
in ordinary analytics, crash attachments or diagnostic logs. Assess SDK-owned
logging and networking as well as the Core transport. A Core HTTP adapter alone
cannot enforce the behavior of arbitrary third-party native code.

## Connected acceptance

- MS-01: dependency/configuration/artifact inspection identifies the relevant
  direct and transitive components and their purposes; unexplained collectors
  or required-but-unknown remote behavior remain open.
- MS-02 positive: using synthetic photo/audio samples, exercise the enabled
  capture/import, OCR/transcription and upload route; observed recipients and
  data categories match the declared feature contract, including TKL-authorized
  direct storage transfer and any approved remote AI service.
- MS-02 negative: startup/idle, local capture/preview, denied permissions,
  unselected remote processing, cancellation, offline and retry paths do not
  create unauthorized media transmission or fallback. Include telemetry/crash
  paths and SDK initialization. Test redirects/recipient changes at the relevant
  adapter boundary without sending real private data to arbitrary hosts.
- Android and iPhone have separately attributed evidence; Phase 7 adds Web
  dependency/network paths and Fold-specific gaps. Network observation alone
  is not proof about every payload: combine suitable instrumentation or test
  endpoints with SDK/configuration review, and state opaque/unobserved limits.
- Retain minimal sanitized observations (feature, destination, outcome, build/
  configuration) in normal acceptance records. Do not store private captures,
  secret-bearing packet dumps, whole-file copies or management-hash ledgers.

Reuse existing qualified evidence and review the integrated route once. This
does not require a generic scanner, new anti-tamper mechanism or a review for
every library. Delivery is allocated in the
[Core integration plan](../phase/user-account-authentication-integration-plan.md).
