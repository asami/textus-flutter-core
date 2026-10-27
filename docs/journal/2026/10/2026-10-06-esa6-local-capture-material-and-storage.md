# ESA6-01-A — Core local material and document storage

Date: 2026-10-06.
Current status: Independently accepted for ESA6-01; local Step commit pending.
Owner: Textus Flutter Core under App PHASE-6 / ESA6-01 / ESA6-01-A.
Update rule: Preserve this authoring record; record parent validation, independent acceptance and actual commits separately. Public contract changes require the parent plan.

The original body below records the authoring checkpoint. Its pending-validation
statements are historical; the dated acceptance addendum records the current status.

The frozen Core slice adds an immutable descriptive logical material
reference, generic local store interface, conditional IO/stub implementation
and default application-support factory. IO saves retain complete original
bytes at independent random identities and save opaque JSON documents through
flushed temporary files and atomic rename. Input snapshots precede IO and a
serialized per-instance write queue recovers after failed operations.

References deep-freeze nested JSON and use ordinary Dart value semantics.
Safe logical collection/id tokens reject traversal. Missing/length-inconsistent
materials, corrupt/nonobject documents and permission/path/IO failures are
observable. Reads detach JSON, absent documents return null, and listing
sorts only final valid JSON file ids without parsing/migrating candidates.
Failed document saves preserve accepted data and all original material;
cleanup is restricted to the current write's temporary file.

Core owns the storage public contract and `path_provider` dependency. TFAF's
next slice owns consumer capture facade and reusable integration. App owns
Annotation schema, domain workflows and consumer repository composition.
The [capability note](../../../notes/local-capture-material-and-storage.md)
contains public-import usage, IO/error details and the future App Phase 6.1
logical-reference/extension handoff. Existing capture and provisional
development Display semantics retain their existing responsibilities.

Unsupported web/non-IO storage keeps the same API and throws `UnsupportedError`
for every operation and default opening; no memory durability, successful web
storage, native camera/audio or physical camera behavior is claimed. No
Phase 6.1 implementation starts. Core Phase 1.1 / 1.2 / 1.3 histories are
preserved without any completion claim.

Thirteen public-entry-point executable scenarios are authored with adjacent
Given/When/Then clauses: immutable reference/roundtrip; invalid reference/JSON;
durable originals/restart; independent imports/input snapshot; missing/length
failures; opaque nested documents/restart/absence; durable corrections/detached
reads/empty objects; sorted listing/ignored entries; token traversal rejection;
observable corruption; invalid replacement preservation; queued order/failure
recovery; and path/rename failure preservation/owned temporary cleanup.
Each filesystem group owns a `Directory.systemTemp.createTemp` directory
removed only by its own teardown.

Only the ten manifest-owned paths are authored. Effective Dart naming,
private underscores, public API documentation and grouped public exports are
used; no Scala headers, analyzer suppressions, lockfile or unrelated cleanup
are added. Parent-selected `flutter pub get`, `flutter analyze`, focused new
and existing capture tests, and `git diff --check` have not been executed by
this worker. Edit completion provides no independent review or acceptance,
whole-Step/Phase closure, tests-passed or release claim.

## 2026-10-06 — ESA6-01 acceptance

Parent-recorded Core validation completed with the following results:

| Command | Result |
| --- | --- |
| `flutter pub get` | Success. |
| `flutter analyze` | No issues. |
| `flutter test test/capture/local_capture_store_test.dart` | 13 passed. |
| `flutter test test/capture/capture_model_test.dart test/capture/capture_profile_test.dart test/repository/capture_repository_test.dart` | 11 passed. |
| `git diff --check` | Passed. |

Independent protected-focused complete A+B acceptance returned PASS, reference
`esa6-01-acceptance-20261006` revision1, reviewer
`/root/esa6_01_acceptance_review`, with zero CPB/HYG/DEV.

The parent local Step commit is still pending; its actual commit identity will
be recorded after execution. This addendum asserts no current commit or
whole-Phase closure. Core/TFAF full suites remain pending Phase6 release; the
App aggregate driver is deferred-not-run to Phase6.1. This Step establishes no
physical-device or default-directory acceptance, nor camera, recognition, UI,
audio or submission acceptance.
