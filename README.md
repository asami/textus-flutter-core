# Textus Flutter Core

`textus_flutter_core` is a reusable Flutter package for domain-independent
capture-runtime contracts. It intentionally contains no Editing Studio, Book,
or KnowledgeHub domain types.

This repository is a Flutter **package**, not a Flutter application. It has no
`main.dart` or platform-app scaffold. Consumer applications own application
startup, navigation, and iOS/Android builds.

## Requirements

- Flutter 3.47.4 or later
- Dart 3.13.3 or later

## Install in a consumer during local development

```yaml
dependencies:
  textus_flutter_core:
    path: ../textus-flutter-core
```

Import only the package's public entry point:

```dart
import 'package:textus_flutter_core/textus_flutter_core.dart';
```

Do not import future `lib/src/` implementation files directly.

## Development

```sh
flutter pub get
flutter analyze
flutter test
```

Library-level validation runs in this repository. iOS/Android device and
consumer smoke tests run from an explicitly admitted Flutter consumer app.

## Delivery status

Phase 1 is complete: it provides the public capture model, profile, and
repository contracts described in [the Phase 1 record](docs/phase/phase-1.md).
The device-runtime successor programme is separately planned as
[Phase 1.1](docs/phase/phase-1.1.md) (foundation),
[Phase 1.2](docs/phase/phase-1.2.md) (capture providers and Reference
Application vertical slice), and [Phase 1.3](docs/phase/phase-1.3.md)
(workflow, consumer acceptance, and Phase 2 handoff). None is implemented by
this package release.

The package also exposes `SideBySideDisplayRegions` as a small, domain-neutral
fold/hinge geometry primitive consumed by TFAF. It interprets full-height
vertical display features from `MediaQueryData`; it does not implement the
planned device Service/Provider programme or close Phase 1.1.

The companion `SeparatedDisplayRegions` contract supports both full-height
vertical and full-width horizontal fold/hinge separators. It exposes leading,
separation, and trailing rectangles in Flutter-view logical coordinates and
can clip them to an actual content viewport. `Axis.horizontal` means left/right
panes; `Axis.vertical` means upper/lower panes. Positive separator thickness is
occlusion; a zero-thickness fold still identifies two adjoining regions.
The old side-by-side API remains unchanged. This is a first relevant full-span
separator contract, not a general partitioner for multiple or partial display
features. TFAF owns pane viability and presentation decisions.

## Original audio and editable transcript

- Current status: Implemented; independent Step acceptance pending.
- Owner: textus-flutter-core maintainer.
- Update rule: append actual parent-owned validation and acceptance evidence;
  preserve separate Core Phase histories.

The bounded App Phase 6.1 connected delivery adds public original audio capture,
durable exact-byte replay, saved-input Basic transcription and append-only
editable transcript provenance. See the
[audio API and strict version 1 schema](docs/notes/original-audio-and-transcript-review.md).
The optional Android registration package is included by Core's path dependency.
Recording requires explicit microphone permission; Basic ASR requires API 31
and actual exact-locale model readiness, with model preparation requested
explicitly. Unsupported/missing-plugin recognition stays unavailable while
manual transcript entry remains usable. Ordinary Activity pause cancels active
work without terminally disposing sessions; a pending microphone permission
grant waits for the same attached Activity to resume before capture starts.
Detach, destroy and explicit disposal remain terminal.

Initial parent-owned checks passed 14 of 15 representative service tests (the
remaining failure was missing test binding initialization), passed all 93 related
accumulator tests, and reported 10 analyzer info diagnostics. The bounded repair
addresses that fixture, lifecycle/cleanup behavior and mechanical conformance;
parent revalidation and independent Step acceptance remain pending. Android
consumer compilation, native helper validation and actual device/model acceptance
are also pending. The Phase orchestrator records subsequent closure evidence
before Step acceptance. This connected delivery does not close Core's own
planned Phases.

## Package layout

```text
lib/textus_flutter_core.dart  public API entry point
lib/src/                      internal implementation, added with the first API
test/                         package unit and widget tests
docs/                         Phase and architecture records
tool/verify_phase_1_release.sh Flutter package release-validation driver
```

If Textus Flutter Core later owns native platform code rather than depending on
an existing Flutter plugin, that capability should be introduced as a Flutter
plugin package with an example consumer—not as an application scaffold or an
SBT subproject.
