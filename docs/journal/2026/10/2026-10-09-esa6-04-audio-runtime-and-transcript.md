# 2026-10-09 — ESA6-04-A original audio runtime and transcript

- Current status: ESA6-04 connected Core/TFAF/App Step independently accepted; exact local Step commits pending. Separate repository Phases and App Phase 6.1 remain open.
- Owner: textus-flutter-core maintainer.
- Update rule: append actual parent-owned validation and acceptance evidence;
  preserve separate Core Phase histories.

Implemented the frozen App Phase 6.1 / ESA6-04 / ESA6-04-A Core participant
manifest in its task-private `codex/esa6-local-capture` checkout. This is bounded
connected App delivery; no Core Phase, App Step or Phase acceptance is claimed.
Existing photo/settings/recognition/storage contracts are retained.

The public audio runtime borrows providers by default, uses one exclusive
record/save/play/prepare/transcribe guard, durably saves exact WAV before
returning provenance, and retains failed-import originals for explicit retry.
Repeated recognition reads the same saved material without microphone work or
reimport. Provider diagnostics become typed nonsuccess reports; storage/input
errors stay observable. Disposal prevents stale success, awaits cleanup and
disposes identical owned providers once.

Immutable reports retain actual provider, exact locale, original reference,
ordered UTC times, monotonic elapsed time, status and diagnostics. Manual and
generated revisions are append-only; first success prefills only before any
revision, later success preserves manual corrections and intentional clears,
and explicit report selection appends provenance. Strict version 1 JSON rejects
missing/extra keys, wrong types/enums, clocks and source-link corruption without
migration. Exact fields are frozen in the
[public audio note](../../../notes/original-audio-and-transcript-review.md).

The optional Android plugin uses explicit Activity microphone permission,
AudioRecord PCM16LE mono 16 kHz, and a canonical 44-byte RIFF/WAVE with at most
3840000 PCM bytes (120 seconds). Capture stops at the limit but returns bytes only
on explicit stop. MediaPlayer replay owns only a private temporary WAV.
Session-specific guards and once-only results make cancellation/pause/detach
observable and release recording, playback and model resources.
Ordinary Activity pause keeps sessions reusable after cleanup; the pending
explicit microphone permission request survives pause without acquiring MIC.
A granted request launches only after the same attached Activity resumes and
only while its request/generation remains current. Detach, destroy, engine
detach and explicit disposal remain terminal.

MLKit `genai-speech-recognition:1.0.0-alpha1` uses Basic only. API 31 and actual
runtime feature status govern exact-locale availability. Model preparation is
explicit; saved-input local inference feeds headerless PCM through a PFD pipe
in 640-byte chunks paced by cumulative monotonic sample time, never `fromMic`
or a full-speed file descriptor. Exact final text concatenates in response
order, partial text is ignored, completion is required, and timeout is audio
duration plus 30 seconds. Cancel/error/timeout close pipe ends, join the feeder,
and stop/close the client. Replaceable Core interfaces keep provider choice
outside App domain logic.

Executable specifications authored with adjacent Given/When/Then clauses cover
actual WAV helpers, exact values/codec/provenance, retained history, real durable
storage/restart, retry, unchanged saved-input ASR, playback read failures,
operation overlap/reentrancy, diagnostics, session separation and disposal.
Initial parent-owned checks passed 14 of 15 representative service tests; the
remaining case failed at uninitialized Flutter test binding setup. All 93
related accumulator tests passed, and analysis reported 10 info diagnostics.
These are historical results from before the bounded readiness repair.

The readiness repair keeps ordinary pause nonterminal, defers permission grants
to foreground, makes idle/equivalent adapter cleanup idempotent, and permits
cancellation during pending native recording stop. New actual-adapter/channel
specs cover those branches and service disposal during delayed durable save and
original read; five pure permission lifecycle specs retain the four WAV specs.
Binding setup, the 10 lint diagnostics, Dart formatting and truthful status docs
are addressed within the frozen paths. Parent revalidation and subsequent
closure evidence are recorded by the Phase orchestrator before independent Step
acceptance. App Android Kotlin/MLKit compilation, native helper validation,
actual device/model acceptance and independent Step review remain pending.
No queue/server/Drive implementation,
commit, publication, deployment or control-data transition is part of this slice.


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
