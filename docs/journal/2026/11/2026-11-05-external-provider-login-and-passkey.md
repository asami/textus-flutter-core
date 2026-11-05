# External login and provider-managed Passkey planning — 2026-11-05

The user requested planning, notes and journal updates across User Account,
Flutter Core and Application Framework for the agreed external authentication
architecture and provider-managed Passkey support.

Owner allocation: Implement common external-login state and browser launch/return, native completion exchange, Web session transport, protected credential storage and logout; keep provider verification and secrets server-side.

Updated [the development plan](../../../phase/user-account-authentication-integration-plan.md) and added
[the delivery note](../../../notes/external-provider-login-and-passkey.md).
The shared decision covers Nimbus in User Account, linked native/Web clients,
locale recommendations plus Other, Google/Microsoft/LINE OIDC and separate
GitHub OAuth, and provider-owned Passkey ceremonies without asserting Passkey
assurance from OIDC success. Existing direct WebAuthn plans are preserved.

Planning only: no dependency added, implementation, provider configuration,
external login, build or acceptance performed. Existing November 10 demo scope
and active/closed execution status remain unchanged.
