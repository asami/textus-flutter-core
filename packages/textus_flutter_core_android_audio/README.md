# Textus Flutter Core Android audio registration

- Current status: Implemented; independent Step acceptance pending.
- Owner: textus-flutter-core maintainer.
- Update rule: append actual parent-owned validation and acceptance evidence;
  preserve separate Core Phase histories.

This optional Flutter registration plugin provides original Android audio
capture, exact WAV replay and saved-input MLKit Basic speech recognition. Its
Dart dependency is Flutter only. Core exposes services and values from
`package:textus_flutter_core/textus_flutter_core.dart` and depends on this
package by path, so Android consumer plugin registration is transitive.

The admitted real consumer example is `nict-editing-studio-app` Phase 6.1,
ESA6-04. Its TFAF controller and App workspace integrate the Core public service
in subsequent slices. This package introduces no application scaffold.

## Setup and explicit use

Use the Core package in the consumer and resolve its dependency closure. Android
uses compileSdk 36, minSdk 26 and Java 17, following the existing AGP 9.1.0 and
Kotlin 2.4.0 plugin convention. Native dependencies are MLKit
`genai-speech-recognition:1.0.0-alpha1` and coroutines-android 1.7.3. The manifest
declares `RECORD_AUDIO`; the runtime prompt occurs only on explicit
`startRecording`, through an attached Flutter Activity. Denial and missing
Activity are observable errors. No external storage permission is needed.

Core's default factory owns one shared native provider. Recording retains up to
120 seconds of MIC PCM16LE mono 16 kHz and returns canonical WAV only on explicit
stop. The service durably stores the unchanged original before returning its
reference. Failed import bytes can be retried. A cancelled recording is unsaved.
Ordinary pause cancels active recording, playback, preparation and recognition,
awaits resource cleanup and keeps the session reusable. A pending explicit
permission request owns no microphone and survives ordinary pause; a grant
starts capture only after the same attached Activity resumes. Already granted
capture requested while paused fails observably. Detach, destroy and explicit
disposal remain terminal.

Playback accepts exact saved WAV bytes and ends on completion, explicit stop or
error. It uses an owned private cache file, releases MediaPlayer and deletes only
that file. Caller original paths never enter native arguments.

## Recognition limitations and status

Basic ASR requires API 31, an eligible device and actual readiness for the exact
locale (default `ja-JP`). `availability` inspects runtime status without a
download. Only explicit `prepareTranscription` prepares/downloads a model.
Available recognition reads the same saved original, validates canonical WAV,
and feeds headerless PCM through a pipe in paced 20 ms chunks. It never acquires
a live microphone, never chooses Advanced/Nano, and never creates fallback text.
Final texts concatenate in order; partial text is not persisted. Completed
response and nonblank final text are required. Timeout, cancellation and errors
close descriptors, feeder and recognizer. Unavailable recognition preserves
record, playback and manual transcript editing.

This dependency is alpha. Dart channel mocks and Kotlin WAV/permission lifecycle
tests specify protocol/helper behavior only. Initial parent-owned Dart checks
passed 14 of 15 representative service cases (one binding setup failure), all 93
related accumulator cases, and reported 10 analyzer info diagnostics. The bounded
repair adds lifecycle and actual-adapter cleanup regressions, fixes the fixture
and mechanical conformance, and awaits parent revalidation. Android consumer
compilation, native helper validation and actual device/permission/model
acceptance remain pending. The Phase orchestrator records subsequent closure
evidence before independent Step acceptance. See the
[Core audio contract](../../docs/notes/original-audio-and-transcript-review.md).
