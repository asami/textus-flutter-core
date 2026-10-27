# Original audio and editable transcript review

- Current status: ESA6-04 connected Core/TFAF/App Step independently accepted; exact local Step commits pending. Separate repository Phases and App Phase 6.1 remain open.
- Owner: textus-flutter-core maintainer.
- Update rule: append actual parent-owned validation and acceptance evidence;
  preserve separate Core Phase histories.

This is the bounded Core delivery for App Phase 6.1, ESA6-04-A. Core owns
domain-independent recording, exact original storage/replay, saved-input
recognition, and immutable transcript provenance. TFAF owns presentation and
controllers; the admitted `nict-editing-studio-app` consumer owns Book Material
meaning and document composition. Consumers import
`package:textus_flutter_core/textus_flutter_core.dart`. This delivery does not
close Core's separately planned device-runtime Phases.

## Original and runtime contracts

`AudioRecordingConfiguration(maxDurationSeconds: 120)` accepts integer limits
from 1 through 120 seconds. `CapturedAudio(bytes, capturedAt, originalName)`
snapshots original WAV bytes; reads return detached copies, timestamps normalize
to UTC, and the optional name is descriptive. `OriginalAudio(material,
durationMilliseconds)` contains an existing `CaptureMaterialReference` and a
positive sample-derived duration of at most 120000 ms. The material must have an
audio media type. Safe logical IDs never become caller-selected filesystem paths.

The bounded native format is canonical RIFF/WAVE: a 44-byte header, `RIFF`, exact
file-minus-eight size, `WAVE`, `fmt ` size 16, format 1, mono channel 1, 16000 Hz,
32000 bytes/second, alignment 2, 16 bits, and `data` with an exact positive even
payload of at most 3840000 bytes. Duration is
`floor(sampleCount * 1000 / 16000)` and must be positive. Both Dart and Kotlin
helpers reject unsupported, extra, truncated or inconsistent chunks. Original
bytes are preserved, with detached headerless PCM available for the native
saved-input recognizer. There is no implicit transcoding.

`AudioRuntimeProvider` exposes `isSupported`, `startRecording(configuration)`,
`stopRecording()`, `cancelRecording()`, `play(bytes)`, `stopPlayback()`, and
`dispose()`. `AudioTranscriptionProvider` exposes `id`, `availability(locale)`,
explicit `prepare(locale)`, `transcribe(input)`, `cancel()`, and `dispose()`.
`AudioTranscriptionInput(bytes, original, locale)` is a defensive saved-input
snapshot and rejects inconsistent lengths or invalid locales. Provider results
are `AudioProviderTranscript(text, extensions)` with exact nonblank final text
and deeply immutable JSON. `AudioProviderException(code, message)` retains actual
platform diagnostics. Availability has `providerId`, exact `locale`, `state`
(`available`, `downloadable`, `downloading`, `unavailable`), and nullable `reason`.

## Service state, storage and ownership

`AudioCaptureService(runtime: ..., transcription: ..., store: ..., now: ...,
ownsProviders: false)` borrows dependencies by default and creates no native
work. `openDefaultAudioCaptureService(store: ...)` owns one shared
`AndroidAudioProvider` exactly once. The existing `LocalCaptureStore` persists
the unchanged original; no audio report repository or queue is introduced.

The public states are `idle`, `recording`, `saving`, `playing`, `preparing`,
`transcribing`, and terminal `disposed`. `state`, `isSupported`, and
`pendingOriginal` are inert getters. `availability(locale: 'ja-JP')`,
`prepareTranscription(locale: 'ja-JP')`, `startRecording(configuration: ...)`,
`stopRecording()`, `retryPendingOriginal()`, `playOriginal(original)`, and
`transcribe(original, locale: 'ja-JP')` share one operation guard. Recording holds
the guard after the start future completes. Explicit `cancelRecording()`,
`stopPlayback()`, and `dispose()` interrupt the matching operation and await
cleanup. Overlap and callback reentrancy fail observably.

Explicit stop validates WAV and durably saves exact bytes before returning an
`OriginalAudio`. Import failure retains immutable `pendingOriginal` bytes for
`retryPendingOriginal()` without re-recording. A new operation or recording
cancel cannot silently erase those bytes. Reads fail before runtime playback or
inference when the original is missing or inconsistent. Recognition reuses the
same saved original and never reimports it. The returned report belongs to the
caller for document composition. Provider failures become typed nonsuccess
reports; storage/input/programming failures remain exceptions. Report IDs are
random safe tokens, UTC clocks cannot regress past capture or prior completion,
and elapsed time comes from a nonnegative monotonic stopwatch.

Disposal is idempotent, makes the service terminal immediately, cancels native
work, awaits outstanding operations, and disposes providers only when owned.
Identical runtime/transcriber instances close once. Interrupted or disposed
operations cannot publish late success. Explicit playback stop completes native
cleanup and is observable to pending callers as interruption.

The default adapter treats recording/playback cleanup from alive idle state as
inert and joins equivalent pending cleanup calls. Recording cancellation can
interrupt a pending native recording stop, rejects its stale captured success
and waits for its completion. Disposal waits for that cleanup before terminal
native disposal. The service's ordinary operation guard remains exclusive, and
disposal during durable save or original read still waits for IO and prevents
late reference/playback success.

## Append-only transcript provenance

`AudioTranscriptReport` has `id`, `original`, `providerId`, `locale`, UTC
`startedAt`, UTC `completedAt`, nonnegative `elapsedMilliseconds`, `status`,
nullable `text`, nullable `errorCode`, nullable `errorMessage`, and immutable JSON
`extensions`. Status is exactly `success`, `failed`, `unavailable`, or
`cancelled`. Success requires exact nonblank text and null errors. Every
nonsuccess requires null text and a nonblank error code. Start cannot precede
original capture and completion cannot precede start.

`TranscriptRevision` has exact `text` (including an intentional empty clear),
UTC `recordedAt`, `source` (`manual` or `generated`), and nullable `reportId`.
Generated selection requires an earlier successful report and exactly its text.
Manual edits may retain that selected source identity. `AudioTranscriptReview`
has `original`, ordered immutable `reports`, and ordered immutable `revisions`.
Reports use the exact original with unique identities and ordered clocks;
revisions have nondecreasing times and valid successful source links.

`appendReport(report)` always retains prior entries and only prefills the first
successful exact text while revisions are empty. Once there is a user revision,
including a manual clear, later recognition cannot overwrite current text.
`correct(text, recordedAt: ...)` appends a manual revision;
`useReport(id, recordedAt: ...)` explicitly appends a generated selection.
Failures never select text. Manual entry works without recognition availability.
`AudioTranscriptReview.requireRetainedPrefix(old, next)` rejects original
replacement and dropped or rewritten report/revision prefixes. Values implement
exact equality and detached/deeply immutable snapshots.

## Frozen JSON version 1

`AudioTranscriptCodec` encodes detached JSON and strictly decodes exact keys,
types, enums, identities, provenance and canonical UTC timestamps, using
`DateTime.toIso8601String()` form such as `2026-10-09T00:00:00.000Z`. Unknown,
missing and unsupported fields throw `FormatException`. No migration, silent
repair or automatic write occurs. Extension Unicode, whitespace, nulls, lists,
objects and finite numbers roundtrip exactly.

| Encoded value | Exact keys |
| --- | --- |
| Original (`encodeOriginal` / `decodeOriginal`) | `version: 1`, `material`, `durationMilliseconds` |
| Material (existing `CaptureMaterialReference` schema) | `id`, `mediaType`, `byteLength`, `capturedAt`, `originalName`, `extensions` |
| Report (`encodeReport` / `decodeReport`) | `version: 1`, `id`, `original`, `providerId`, `locale`, `startedAt`, `completedAt`, `elapsedMilliseconds`, `status`, `text`, `errorCode`, `errorMessage`, `extensions` |
| Review (`encode` / `decode`) | `version: 1`, `original`, `reports`, `revisions` |
| Revision within review | `text`, `recordedAt`, `source`, `reportId` |

Nested `original` and report objects use the same versioned value schemas.
Nullable fields remain present with null; revisions are exact strings, including
empty strings. The caller may store this opaque review document using the
existing local capture store, enforcing retained prefixes before replacement.

## Android implementation and honest support status

Core depends on the optional registration plugin
`textus_flutter_core_android_audio` through its package path. The plugin depends
only on Flutter in Dart and has no circular Core dependency. Existing photo,
settings, recognition and generic storage contracts stay compatible.

The Android adapter uses per-instance safe session IDs on
`org.textus.flutter.core/audio`. Native mutable operations are confined to the
main dispatcher; AudioRecord reads and paced PCM feeding use cancellable IO
workers. Recording uses MIC PCM16 mono 16 kHz, requests `RECORD_AUDIO` only on
explicit start through an attached Activity, captures at most the requested
limit, and retains that buffer until explicit stop. Denial, missing Activity,
initialization/read failure and empty audio are observable. No external storage
permission or background microphone is used. Ordinary Activity pause cancels
active session work and outstanding results, releases resources and keeps the
session reusable after cleanup. It preserves the single explicit pending
permission request, which owns no microphone. A grant while paused is deferred
until the same attached Activity resumes; cancelled or terminal requests cannot
launch. Already granted capture can start only in foreground. Detach, destroy,
engine detach and explicit disposal remain terminal.

Playback uses supplied exact WAV bytes in an owned application-private temporary
file, `MediaPlayer.prepareAsync`, and completion/error callbacks. Explicit stop
and lifecycle cleanup release the player and only its owned temporary file.
Durable original paths never cross the channel.

Recognition uses `com.google.mlkit:genai-speech-recognition:1.0.0-alpha1` and only
`MODE_BASIC`, requiring API 31 and actual per-locale `FeatureStatus.AVAILABLE`.
The feature status is authoritative on eligible devices; unsupported platforms
and absent plugin registration report unavailable truthfully. No Advanced/Nano
selection, live microphone ASR fallback or synthetic transcript is supplied.
Only explicit preparation collects `download()`. Model preparation can require
network; available saved-input inference is local.

Each recognition rechecks status, validates saved WAV, and supplies headerless
PCM through `AudioSource.fromPfd` using a pipe. The IO feeder writes 640-byte
(20 ms) chunks paced by cumulative monotonic sample time, closes EOF after the
last sample, and never passes a full-speed file descriptor or uses `fromMic`.
Final response texts concatenate in exact response order; partials are ignored,
`CompletedResponse` is required, explicit errors retain diagnostics, and missing
final text is `noSpeech`. Timeout is audio duration plus 30 seconds. Cancellation,
error and timeout close both pipe ends, cancel/join the feeder, stop/close the
client, and complete each Flutter result once. Preparation also closes clients.

The provider interfaces permit explicit replacement. A future provider may
support other formats through an admitted contract; this native adapter remains
bounded to its own canonical recordings.

## Validation attribution

New Dart behavioral specs cover PCM, strict codec/provenance, editable history,
durable originals, import retry, replay/read failures, saved-input ASR, operation
guards, session isolation and disposal using real storage and controlled
providers/channels. Every behavioral test and async fixture/action helper has
adjacent Given/When/Then clauses with observable assertions. Kotlin JUnit specs
exercise the actual canonical WAV helper and malformed/limit rejection, plus
the same pure permission lifecycle helper used by the plugin for paused grants,
foreground resume, cancellation and once-only deferred launch. Actual adapter
regressions cover idle/equivalent cleanup, delayed stop cancellation and service
disposal during delayed durable save/read.

Initial parent-owned validation passed 14 of 15 representative service tests;
the remaining case failed because the Flutter test binding was not initialized.
All 93 related accumulator tests passed, and analysis reported 10 info
diagnostics. Those results describe the initial implementation before this
bounded lifecycle, cleanup, fixture, lint, formatting and documentation repair.
Parent revalidation and independent Step acceptance remain pending. The Phase
orchestrator records subsequent closure evidence before Step acceptance. Actual
Android Kotlin/MLKit linkage, App plugin build, permission/device playback,
model download/availability and saved-input recognition acceptance are required
separately; mocks and pure helper tests do not prove microphone or model success.


## ESA6-04-B additive nonterminal cancellation

Core source Slice A has parent-recorded focused closure
`esa61-audio-core-focused-closure-1-20261009@1`, including the accepted playback
and lifecycle repair. That historical focused source acceptance covers Slice A;
it does not accept the new Slice B cancellation, Android/model behavior, the
complete ESA6-04 Step, or any separately owned Core Phase.

Authored `AudioCaptureService.cancelTranscription()` interrupts only active
readiness inspection, explicit preparation or saved-input recognition. It rejects
idle, recording, saving, playing, disposed, pending-original and duplicate
interruption contexts before provider work. It reserves interruption and a new
generation, snapshots prior settlement futures before registering its own task,
then invokes the existing provider cancellation exactly once. Prior IO/provider
work is always awaited even when cleanup fails. The first actual cleanup error
and stack survive; late prior success cannot escape generation checks. Only its
own current token can restore idle, so terminal disposal stays authoritative.
The service and borrowed provider remain reusable after nonterminal cancellation.
Original bytes, import counts, reports, schemas and provider lifetime are retained.

Adjacent Given/When/Then specifications CANCEL-1 through CANCEL-6 cover invalid
and duplicate contexts, delayed probe/preparation, held saved-input recognition,
held original read, actual cleanup failure/stack with delayed settlement, and
terminal disposal during pending cancellation. These additions are authored;
parent-selected execution and independent conformance are pending. Android
linkage, physical permission/record/replay, actual model readiness/preparation and
saved-input recognition remain owed by connected App integration before complete
Step acceptance. No new native or whole-Step acceptance is claimed.

## 2026-10-10 — Parent software validation

The selected ESA6-04-B software checks passed. Core service cancellation and
existing audio behavior: 23 tests; transcript/codec/Android adapter/photo-service
consumer accumulator: 82 tests. Shared audio panel representative: 6 tests;
facade/controller/transcript editor and existing photo/text-scaling accumulator:
104 tests. Both selected static analyses reported no issues. Canonical dry
formatting covered 11 owned Dart files with zero changes; both Git diff checks
passed.

Earlier W1 runs timed out during test-fixture teardown after the user workflow
completed. Fixed observation traces located a cached detachment future created
in Flutter fake async; creating both W1 detach futures through tester.runAsync
resolved the cross-zone cleanup wait. The isolated W1 then passed, followed by
all six representative cases. Temporary diagnostic traces were removed; no
product lifecycle or behavioral assertion changed. Earlier failures remain
historical evidence.

These are parent-executed software results. Independent shared conformance,
connected App integration, Android build and plugin tests, physical-device
permission/recording/replay/model checks, complete ESA6-04 acceptance and
Phase 6.1 release remain pending.

Core commands: `flutter test --no-pub test/audio/audio_capture_service_test.dart`;
`flutter test --no-pub test/audio/audio_transcript_test.dart test/audio/audio_transcript_codec_test.dart test/audio/android_audio_provider_test.dart test/capture/photo_capture_service_test.dart`;
`dart analyze lib/src/audio test/audio`.

## ESA6-04 whole-Step acceptance — 2026-10-10

Current status: ESA6-04 complete Core/TFAF/App Step accepted by independent
review `esa61-audio-whole-step-review-20261010@1` (PASS, no blockers,
new Hygiene or Development Candidates). Exact dependency-ordered local Step
commits are pending. Phase 6.1 remains open.
Owner: nict-editing-studio-app Phase 6.1 parent task.
Update rule: retain historical source/validation/failure receipts; record
actual commits separately and preserve remaining Phase validation/release gates.

This receipt supersedes earlier pending independent/native/whole-Step
acceptance descriptions for this delivery; those descriptions retain their
historical meaning. The connected review covered 65 owned paths and 92
selected contract/source/specification paths, including APP-AUDIO-OWNER-001.
Actual retained Core 23+82, TFAF 34+91, App 363 passed with one optional saved
photo replay skip, and 20 native helper tests passed. Fold native write5 and
distinct restore1 both passed: the same 656680-byte, 20.519-second original,
Japanese saved-input ASR, manual corrections/history, save/reopen and replay
were retained. The model was already available; preparation was not executed.
Japanese ASR success does not establish exact title accuracy: 窯変 was
recognized as 傭兵 and manual review remains necessary.

This is ESA6-04 Step acceptance only. It closes no separate Core/TFAF Phase.
ESA6-06 Commit/durable background submission and Core Drive/KTL integration,
ESA6-07 fake success/failure/retry/offline, ESA6-08 server handoff, the one
comprehensive Phase review, final full validation and distinct Phase release
remain required.
