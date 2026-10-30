# Common User Account client for mobile and Web

Date: 2026-10-31
Status: planning only

The developer requested textus-user-account authentication shared through
Flutter Core and Application Framework. The
[specification](../../../spec/user-account-authentication-client.md) assigns
account/session authority to user-account and shared client/state/platform
credential handling to Core. The [workstream](../../../phase/user-account-authentication-integration-plan.md)
delivers native support to App 6.10 before Web support to App 7, coordinated
with Studio Server 5 and Framework. Existing submission credential facilities
are reused; no alternate account/session store is introduced.

The broader planned Sensitive Interaction Phase 3 and closed phases remain
unchanged in status. This bounded work does not require implementing every
planned provider, nor waive dependencies of selected capabilities. Actual
producer/transport availability is checked at entry. No code, tests, runtime,
commit or deployment was performed by this documentation update.
