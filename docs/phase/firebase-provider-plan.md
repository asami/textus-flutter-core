# Optional Firebase client providers

Status: planned, unscheduled. Contract: [Core Service / Provider boundary](../design/firebase-provider-boundary.md).

| Work | First useful route and acceptance |
| --- | --- |
| Diagnostics | Compose an opt-in Crashlytics adapter in an isolated Android application build. Trigger a synthetic fault, inspect the delivered report and its automatic fields, and confirm collection settings and allowed diagnostic context. Use synthetic Material markers to detect disclosure. Verify ordinary startup with the adapter omitted. Qualify iOS separately and record supported targets. |
| Push notifications | Connect registration and token refresh to the authenticated server registration endpoint. On logout/account switch, retire the previous binding. With Framework and the server, open one review notification and read current authorized data. Verify denied OS permission, duplicate or missed push, and continued ordinary inbox access. |
| Attestation | Supply evidence on requests to the configured protected service using the selected platform provider. Qualify accepted and unavailable evidence with server ingress, including a request for another account's resource. Verify that calls to unrelated destinations receive no token. |
| Presentation settings | When a consumer selects Remote Config, expose typed presentation values with local defaults. Exercise offline startup and invalid values. Keep authentication, operation mode, external destinations and TKL configuration under their existing owners. |

Start with diagnostics as a standalone client capability. Pair the notification and attestation routes with the [CNCF plan](https://github.com/asami/goldenport-cncf/blob/main/docs/phase/firebase-integration-plan.md), and user interaction with the [Framework plan](https://github.com/asami/textus-flutter-application-framework/blob/main/docs/phase/firebase-presentation-plan.md). Use provider doubles for deterministic local checks and an explicitly configured isolated deployment for real SDK acceptance. Record each platform actually qualified.
