# Local original material and document storage

Current status: Independently accepted for ESA6-01; local Step commit pending.
Owner: Textus Flutter Core; App PHASE-6 / ESA6-01 / ESA6-01-A.
Update rule: Change the public contract only through the parent plan; record validation and independent acceptance separately.

The original body below records the authoring checkpoint. Its pending-validation
statements are historical; the dated acceptance addendum records the current status.

## Capability and responsibilities

Core provides `CaptureMaterialReference`, `LocalCaptureStore`,
`FileCaptureStore`, and `openDefaultCaptureStore` through the public package
import. Original bytes are stored unchanged and opaque JSON objects are saved
durably. This addition leaves the existing capture-session/profile/repository
and development Display semantics in their existing scope.

| Repository | Responsibility |
| --- | --- |
| Core | Immutable logical original-material references, unchanged original bytes, generic JSON document storage, filesystem persistence, default application-support root and observable storage errors. |
| TFAF | Consumer capture facade, acquisition/import orchestration and reusable presentation integration in the next slice; no Core-owned application schema or policy. |
| App | Annotation/document schema, domain identifiers and workflows, composing TFAF with the Core store, and consumer repository integration in the next slice. |

The new generic store is distinct from the existing consumer-supplied
`CaptureLocalRepository` capture-session contract. It injects no domain,
schema, lifecycle, Drive, remote identity, submission or synchronization keys.
No native camera/audio provider or physical camera acceptance is established
by this storage work. Core's own Phase 1.1 / 1.2 / 1.3 history and acceptance
remain governed by their respective Phase records.

## Public usage

```dart
import 'dart:typed_data';
import 'package:textus_flutter_core/textus_flutter_core.dart';

Future<CaptureMaterialReference> importOriginal(Uint8List bytes) async {
  final LocalCaptureStore store = await openDefaultCaptureStore();
  final reference = await store.saveMaterial(
    bytes: bytes,
    mediaType: 'image/jpeg',
    capturedAt: DateTime.now(),
    originalName: 'cover.jpg',
  );
  await store.saveDocument('drafts', 'draft-1', <String, Object?>{
    'material': reference.toJson(),
    'text': '',
    'extensions': <String, Object?>{},
  });
  return reference;
}
```

Consumers may instead configure `FileCaptureStore(directoryPath)` and reopen
another instance with that root. On IO platforms the default root is
`getApplicationSupportDirectory()` / `textus_capture`; Core owns the
`path_provider: ^2.1.6` dependency. Provider failures propagate.

## Logical reference and original ownership

The reference contains exactly `id`, `mediaType`, `byteLength`, `capturedAt`,
`originalName` and `extensions`. Identity is a safe logical token matching
`^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$`. Each import receives an independent secure
random identity, even when two originals have identical bytes. The identifier
is neither a content hash nor an absolute path. The optional original name is
descriptive and is never resolved as a path.

The reference requires a MIME-like type and positive byte length, normalizes
time to UTC, and emits UTC ISO time. The decoder rejects missing/unknown keys,
wrong types, invalid field values and malformed ISO date/time. Explicit
timezones normalize to UTC on decoding. Nested
extension maps and lists are defensively copied and immutable; empty
collections and nulls remain intact. Cycles, non-JSON values and nonfinite
numbers are rejected. Deep equality and normal Dart hashing include all
fields without claiming an integrity or workflow-control hash.

`saveMaterial` snapshots caller bytes before IO, never scales/compresses or
replaces them, and stores `materials/<id>.bin`. The returned reference follows
successful flushed temporary-file write and rename. Reads resolve only the
logical id within the configured root, return caller-owned bytes and fail for
missing files or length inconsistency. A document failure never removes the
original; orphan collection, uninstall and backup behavior are outside scope.

## Opaque documents and failures

Documents use `documents/<collection>/<id>.json`; both path tokens follow the
same safe-token rule. The entire JSON object is validated and encoded before
IO, preserving nested application fields/extensions, empty objects and nulls.
Input mutation after invocation cannot change the encoded snapshot. Values
with custom `toJson`, cycles, nonstring map keys or nonfinite numbers are not
accepted as JSON.

Every write creates a unique temporary file in the destination directory,
flushes it and renames into place. Accepted files are never truncated/deleted
first. One store serializes writes in invocation order; a failed write does
not poison later writes. Other store instances use ordinary atomic filesystem
replacement. No interprocess lock, transaction engine, crash-recovery cleanup
or additional platform durability guarantee is promised. Cleanup on failure
is confined to the current write's temporary file.

Reads return a fresh detached object or null only for absence. Malformed JSON
and nonobject JSON throw `FormatException` and preserve the existing file.
Permission, path and IO errors propagate. Listing returns sorted safe ids
from final regular `.json` files only: absent collections are empty,
temporary/nonfile entries are ignored, and candidate documents are never
eagerly parsed, migrated or deleted.

## Unsupported platform and future handoff

The conditional public export selects IO storage using `dart.library.io`.
Web and other unsupported platforms retain the same constructor and method
API. Every stub operation and `openDefaultCaptureStore` throws a clear
`UnsupportedError`. This is not a durable browser or memory backend, and no
successful web persistence or physical-camera claim is made.

Future App Phase 6.1 may extend acquisition and consumer schema/integration
using logical local references and opaque extension JSON under its own
authority. No Phase 6.1 work starts here. Core continues to own generic
storage; TFAF owns its reusable integration and App owns domain decisions.
Remote/Drive references, synchronization, orphan cleanup, backup and native
device providers require separate future decisions rather than interpretation
of the current reference.

The thirteen behavior specifications are authored in
`test/capture/local_capture_store_test.dart`. Parent dependency resolution,
analysis, selected tests, diff checks and independent review are pending;
this note records edit completion only, with no tests-passed, Step/Phase
closure or physical-device observation claim.

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

## 2026-10-10 — FIX23 operation-time absence correction

Frozen repair `esa61-submission-core-readiness-fix23-20261010@1` preserves the
historical ESA6-01 acceptance above. Its Core correction
`VF-ESA61-CORE-MISSING-LIST-001` treats null/empty as the missing-path observation
from the actual document read or collection listing. It removes the later stat
that could see a concurrent creation and spuriously rethrow the earlier ENOENT.
A subsequent read/list can see that new final document. Reads and listings remain
free of writes, retries and eager directory creation. Original bytes, safe sorted
listing, strict JSON/corruption checks, atomic flushed replacement and propagation
of nonmissing errors retain their contracts.

The new [absence race specifications](../../test/capture/file_capture_store_absence_race_test.dart)
use scoped IOOverrides and real temporary native files. F1 creates a real
collection and final JSON file after its actual ENOENT listing, then rethrows
that same error: the first public listing is empty, the next returns the retained
id. F2 creates a valid final object after its actual ENOENT read and rethrows the
same error: the first public read is null, the next returns the exact object.
F3 exposes the same nonmissing permission errors from selected reads/listings
while retaining accepted document contents and original bytes. File-system type
checks remain native; no successful disk result is synthesized. Each scenario,
callback, wrapper and setup/teardown carries adjacent Given/When/Then clauses.

The companion `VF-ESA61-CORE-SQLITE-OPEN-001` correction configures SQLite's
unchanged 5000ms busy wait before the initial FULL synchronous pragma, with the
real independent-open Q4 regression in the queue specification. Parent-selected
coverage includes Core submission/capture/audio consumers and App BU7 queue
acquisition plus W5 held-camera exit while its writer settles. Parent validation
and fresh independent protected source conformance review are pending; existing
source acceptance remains historical. No command pass, commit, native/Drive
acceptance, whole-Step acceptance or Phase closure is asserted by this authoring.
