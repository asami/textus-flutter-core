# Browser UserAccount authentication

2026-11-07 — TFC-UA03 / App Phase 7 ESA7-01 implementation.
Live participant/server acceptance remains open.

`UserAccountHttpAuthenticationBackend.browser` reuses the existing HTTP wire
decoder, common authentication client, staged session acceptance, refresh,
challenge, cancellation and current-session logout. It supplies a private
in-memory credential slot instead of the native protected-store adapter. The
native constructor and borrowed/owned native handle behavior remain unchanged.

The slot belongs to one backend lifetime. It is not localStorage,
sessionStorage, IndexedDB, a settings record or an App account database. A new
backend/tab/reload has no stored session and requires login. Closing the backend
drops local credentials; it is not an implicit server logout or a claim of
secure memory erasure. Explicit logout retains the common distinction between
local clearance and remote revocation.

The default browser transport admits only the actual page origin and configured
authority path. It uses Fetch with `credentials: omit`, `redirect: error`,
`cache: no-store` and `mode: same-origin`. This preserves the server's explicit
Bearer contract without adding ambient cookies. The ordinary package:http
BrowserClient's `same-origin` credential setting is insufficient for that
contract. Cross-origin configuration is rejected before dispatch; no credential
redirect or cookie-based fallback is introduced. Deployment must serve the Web
client and selected API on the same origin. Existing explicit development-HTTP
profile admission remains necessary for loopback/LAN test configuration.

The existing backend still bounds authentication responses to 64 KiB and one
profile deadline, observes aborts, rejects malformed replies, and prevents late
retired sessions from publishing an authenticated account. The browser adapter
streams response bytes, aborts on cancellation/close, and exposes fixed safe
transport diagnostics. A caller-supplied HTTP client remains a borrowed Core
transport port for controlled tests; it is not a UI token field.

Tests exercise the real backend/common client using synthetic authority replies
on host and Chrome, including empty initial restore, login/account validation,
token rotation, logout, independent backend lifetimes and late-login retirement.
A browser transport test observes the actual Fetch options and response stream.
These are implementation qualifications, not actual participant login, phone
Material discovery, deployed HTTPS or cross-user acceptance.

## Authenticated service HTTP access

`createHttpSession` returns an account/profile-bound `UserAccountHttpSession`.
App supplies operations and business inputs; Core privately resolves credentials
and dispatches. The service base must pass the authority/same-origin policy.
Relative operations cannot escape it. Replies are streamed with a selected byte
bound and profile deadline; public replies expose only bounded bytes and ETag,
content type and cache-control headers. No token/cookie/redirect header or private
transport diagnostic is returned to presentation.

Refresh, logout or backend close retires the accepted-epoch lease. Reacquiring
after successful refresh leaves logical workspace identity with the caller.
Retirement discards late replies. A dispatched POST that loses its reply may
have committed. Complete HTTP409 is preserved as a status, without automatic
retry, refresh, revision guessing or identity replacement. Consumers must also
respect owning operations that can fail after partial effects: an HTTP failure
alone does not certify no effect. Native protected storage and the existing
submission scope retain their ownership semantics.

The browser session uses the same cookie-free, redirect-rejecting Fetch on the
selected service base. Native uses package:http through Core. Borrowed test
transports retain caller ownership. Tests cover scoped dispatch/If-Match, safe
reply headers, logout during a pending mutation, bounds and conflict without
replay. These checks do not qualify live service ownership or persistence.
