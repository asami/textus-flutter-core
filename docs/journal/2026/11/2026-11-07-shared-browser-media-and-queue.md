# Shared browser media and queue — Phase 7 client work

The App user authorized advancing the non-server remainder of Phase 7 before
live connection. Implemented a shared explicit media-input/capability service,
content-validated JPEG/PNG/WebP acquisition, browser DOM file selection and
existing image-picker native adapters. Support, hardware and permission remain
separate observations. Unconnected browser camera/audio adapters report an
unsupported configuration with unknown hardware. Construction, passive inventory
and layout changes never request permission or start acquisition.

Implemented owned IndexedDB original Blob/document storage and a browser queue
adapter. Extracted the existing SQLite queue transitions into one shared engine;
the native schema/version/migration and lease/state contracts are retained.
Independent real Chrome handles qualify original/document reopen, bounded range
reads, atomic competing claims, subject-conflict rollback and retained unknown
dispatch. Existing native queue and handoff regressions remain relevant.

Extracted the existing foreground driver behind a portable explicit-wake entry;
the public iOS wrapper retains its platform gate. This is resumed-application
execution, not browser background delivery. Session-owned delivery access binds
existing TKL/Studio ports privately to the accepted account. Application Bearer
credentials go only to the declared control service; the Google resumable
capability uses cookie-free CORS, no referrer/cache and rejected redirects.
Closing access/session retires pending dispatch without closing borrowed clients.

App namespaces include authority/profile/API/user. This separates legitimate
client compositions, not malicious same-origin scripts. Quota/denial/clear/close
remain observable; browser local storage is neither server registration nor a
backup or device-encryption claim. Native original and recognition semantics
are unchanged. No new server/provider API or second delivery algorithm is added.

Actual platform/HTTPS/provider/CORS and joined acceptance stay open under the
existing media-input plan. Controlled tests use synthetic replies/content and
isolated test-owned browser storage; they perform no real Drive transfer.
Integrated independent review found two App presentation-state blockers, both
closed by App-scoped fixes and focused re-review; no Core blocker remained.
Execution output remains local; no logs or credential material are versioned.

Qualification: full Core regression 2593 passed; full static analysis clean.
Six real Chrome scenarios passed for actual DOM file selection/cancel,
IndexedDB persistence/atomicity and cookie-free control/capability transport.
The App's actual browser composition also verifies exact Book/original reopen,
separate-account storage, durable failure without false registration/ACK and
session-retirement fencing. No live provider or device success is inferred.

During ordinary client commit preparation, independent review identified
CB-7CLIENT-01 in App's foreground composition: run retirement was not connected
to session delivery access, so pending HTTP could wait for its deadline before
cleanup. The session factory now optionally borrows the existing
SubmissionRunLifetime. It fences dispatch immediately and retires pending IO
through the existing cancellation port; neither access nor run retirement logs
the account out. App binds only batch access to that lifetime. Default session
access and native transport/wire contracts retain their existing semantics.

The new held-request scenario plus four existing session scenarios pass;
the complete Core suite now passes 2594 and full static analysis is clean.
App Chrome qualification observes held-body cancellation and retained saved
intent/original. Focused independent M2 re-review resolved CB-7CLIENT-01 with
no remaining blocker, Hygiene or Development Candidate. This does not close
Phase 7 or any physical-device/provider acceptance.
