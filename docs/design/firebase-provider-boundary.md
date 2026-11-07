# Firebase in the Textus architecture

Decision of 2026-11-08. This document defines ownership for future integrations. Each service can be adopted independently.

Firebase is an optional infrastructure provider for Textus client applications. The existing Flutter Core Service / Provider model applies to native and Web clients. A Textus service expresses what its caller needs. A provider implements that capability for a particular platform and deployment. The application selects providers when composing the build. Firebase SDK types, project configuration and initialization stay inside that integration.

| Owner | Responsibility |
| --- | --- |
| textus-flutter-core | Own reusable client contracts, platform support and provider outcomes. Keep Firebase SDK dependencies in opt-in adapters so builds can select capabilities individually. |
| textus-flutter-application-framework | Present shared user interactions such as notification permission, opening an item and displaying capability availability. |
| Consuming application | Select providers for each platform and environment, supply platform registrations, and map a user action to a domain screen. Operators supply server credentials at deployment. |
| CNCF and deployed server components | Verify request evidence at ingress, authorize Operations and resources, and dispatch user notifications through the existing UserNotificationProvider contract. |

Core's [development plan](../phase/firebase-provider-plan.md) and the [CNCF architecture](https://github.com/asami/goldenport-cncf/blob/main/docs/design/firebase-provider-boundary.md) describe the client and server handoff.

## Services and data ownership

| Firebase capability | Textus boundary |
| --- | --- |
| Crashlytics | The client diagnostics adapter reports approved error codes and diagnostic context under the deployment's collection policy. Keep Material content, transcripts, account credentials and raw request payloads outside diagnostic reports. Apply the policy to automatic crash reports as well as application-supplied fields. |
| Cloud Messaging | A deployed CNCF notification provider delivers a minimal notification to an installation registered for the intended account. Core handles platform registration and changes of token or account. Opening a notification retrieves current state through the authenticated domain API. The server inbox and domain record remain authoritative even if delivery is missed or duplicated. |
| App Check | Where a deployment enables app attestation, Core obtains provider evidence and attaches it only to the intended service. Ingress verifies it for the configured application and enforces the endpoint's attestation policy. UserAccount identifies the user. CNCF independently authorizes the requested Operation and resource. |
| Remote Config | A client provider can supply presentation choices with local defaults, within the behavior supported by the installed build. Trusted host configuration selects dev/test/demo/production, security policy and permitted external effects. TKL supplies Material destinations. |

User identity and session lifecycle belong to textus-user-account. Any future Firebase Authentication integration would enter through its federation contract. TKL owns Material identity, metadata and storage placement. Core's durable submission queue owns pending client delivery. Choosing diagnostics, notifications or attestation creates no requirement to adopt Firestore, Firebase Storage or Firebase Authentication.

Each selected provider expresses the behavior it can actually supply on the platform. An unavailable optional diagnostics or push service leaves the user able to work through the normal application route. If a protected endpoint requires attestation, missing or invalid evidence yields an explicit refusal at that boundary. Each deployment selects its permitted outbound data and destinations.

See the [Core Service / Provider decision](../journal/2026/09/2026-09-17-device-service-provider-reference-application.md), [authentication client contract](../spec/user-account-authentication-client.md) and [TKL delivery boundary](../notes/tkl-managed-material-delivery.md).
