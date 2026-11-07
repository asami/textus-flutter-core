# Phase 7 browser authentication advance

App's user selected advance Phase 7 development while the remaining Phase 6.10
acceptance is held. TFC-UA03 now has a browser constructor on the existing Core
HTTP backend, a volatile private credential slot and same-origin cookie-free
Fetch transport. See the [browser contract](../../../spec/browser-user-account-authentication.md).
No second authentication client or identity provider is added.

Host authentication regression: 125 passed. Chrome Core scenarios: 3 passed.
Actual server/participant and same-user phone Material access remain unaccepted;
the selected operational endpoint/account handoff is still needed. Preserve
every open UA01/02/03 and App acceptance condition and native Phase 6.10 evidence.

The same boundary now includes `UserAccountHttpSession`, reusing the existing
accepted credential lease, epoch retirement and protected-store draining rules.
App gets scoped HTTP access rather than a token. Service URI policy, safe bounded
replies and uncertainty after a dispatched mutation remain Core responsibilities;
Book/Candidate/Information commands and content remain with their owners.
The host authentication/session selection passed 128 tests, including the three
new session behaviors. App's production Chrome root exercises the shared browser
transport and authenticated receipt listing. These are controlled implementation
results. No Core Phase, live participant gate or server persistence is accepted
by this journal entry.
