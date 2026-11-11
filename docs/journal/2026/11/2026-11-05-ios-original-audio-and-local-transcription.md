# iOS original audio and local transcription implementation

Date: 2026-11-05
Identity: ESA610-IOS-AUDIO-001, original Phase 6.10

The frozen parent manifest extends Core's iOS purpose to recording, saved-original
replay and on-device Japanese saved-audio transcription under the existing audio
interfaces and unchanged PCM/transcript persistence. This note records initial
source authoring and the bounded PCM-read repair following the physical failure
described below. Validation, independent review, device acceptance and local
acceptance commits remain pending with the parent.

## Initial authored changes

- Added the inert IosAudioProvider with independent channel/session lifecycle,
  strict exact locale/provenance/type/WAV checks and cancellation/disposal
  joining. The default factory selects it on non-web iOS and owns the shared
  runtime/transcription instance once; other hosts retain Android behavior.
- Added the iOS-only CocoaPods registration package using AVFoundation and
  Speech, with iOS 15.5 minimum and no third-party dependency. Registration
  observes lifecycle only; permissions require explicit use.
- Added actual production ownership/generation fencing for delayed permission,
  inactive-to-active start, media completion and timeout. Background,
  interruption, cancellation and detach retire work without autoresume.
  Cleanup releases only its token's media resources and owned UUID temporary files.
- Added actual bounded CAF sample extraction into the exact Core 44-byte
  16 kHz mono PCM16 WAV; saved replay and recognition validate the same format.
  Automatic recording duration completion retains the buffer for explicit stop.
- Added saved-WAV URL recognition constrained to on-device execution, honest
  local capability/authorization responses, exact final text and provenance,
  observable failures and timeout, with no microphone recognition or cloud fallback.
- Added channel scenarios, factory/storage-ownership scenarios and a portable
  zero-dependency Foundation SwiftPM test harness using the production helpers.

The full setup/action/expectation map is in
[the iOS audio specification](../../../spec/ios-original-audio-and-local-transcription.md#executable-scenario-authoring-map).
The memory-store pattern in the factory spec is adapted from the existing
private image-region-processing fixture within the owned test file.

## Bounded PCM-read repair authoring

Identity: ESA610-IOS-AUDIO-PCM-READ-001, same original Phase 6.10 and repair
cycle 10. The human iPhone recording-stop attempt, with Device Hub stopped,
returned `recordingFailed` / "Recorded PCM could not be read completely" and
created no saved original. The parent reproduced the cause with real synthetic
CAF files: a single large AVAudioFile read can return a positive short buffer.
The original strict one-read equality incorrectly rejected that valid capture.

The frozen repair extracts CAF decoding into production `PcmAudioFileReader`,
consumed by synchronous recording stop and the native regression target. It
retains actual source/processing format and 16..1920000-frame validation, reads
successively through one buffer of at most 8192 frames and appends exactly the
actual returned samples. Every read must progress and agree with the initial
expected length and file position. Complete accumulation is required before
the existing canonical WAV encoder runs. No padding, suffix omission, extra
EOF read, resampling, mono mixing or duration-based success is introduced.
The reader's internal errors map in stop to the existing native error codes;
raw AVAudioFile I/O errors propagate through the existing bridge. Recorder
lifecycle, permissions, cancellation and temporary-file ownership are retained.

The initial Foundation-only SwiftPM harness is extended with Apple's
AVFoundation on macOS and the production reader. Authored real-file scenarios
cover varying known samples at 320001, 329937 and 1920000 frames with exact
decoded PCM bytes including the tail, plus a 320-frame control. Real mismatched
sample-rate, stereo and float CAFs, and actual submillisecond/over-120-second
CAFs, must fail with invalidAudio. Writers have scoped lifetimes before reads;
each test cleans up its own UUID temporary file. The existing eight Foundation
scenarios are retained. This adds no microphone simulation or mocked
AVAudioFile evidence.

Revision 2 records the parent-frozen reader-local error adaptation after the
first worker returned a zero-edit scope mismatch for the excluded plugin's
failure type. It retains the same six owned paths and repair cycle. This
authoring record claims no test pass, recovered physical recording, native
success, independent review acceptance or Phase closure.

## Validation and native acceptance pending

No tests, builds, formatters, project scripts, native UI operations or
self-review were run by the implementation worker. The parent owns dependency
resolution, focused Dart regression tests, static analysis, portable Swift
tests, iOS Release build, preserved-data physical recording/replay/Japanese
saved-audio recognition/save/restart readback, independent conformance review
and exact local commits. Channel mocks and on-device request flags are not
microphone/model/SDK-egress acceptance evidence. The bounded repair editor also
ran no tests, builds, formatter, project scripts, native UI or self-review.
For the repair the parent owns the changed SwiftPM host target, the same iOS
Release build, normal signature check and preserved-data same-device
record/replay/transcribe/save/restart verification, followed by independent
protected integrated Step review and scoped commits. Earlier Dart and App
regression evidence remains relevant unless actual new evidence warrants a
rerun.

The consuming application must supply microphone and speech usage descriptions.
Device local Japanese capability, authorization, actual saved-audio recognition,
permission-prompt cancellation and lifecycle behavior still require native
verification. No Phase acceptance or completion is asserted.

## Scope and debt

Initial authoring used only its manifest's nineteen Core paths. The bounded
PCM-read repair uses its six enumerated Core source/test/documentation paths.
Existing Android
implementation, common interfaces, service lifecycle, persisted identities and
codec v1 remain outside the editing boundary. No App/TFAF edits, generated
registration/lock changes, authentication/submission changes, publication or push
were performed.

Same-file obligations completed during authoring: new Dart public API docs,
plugin metadata, production helper consumption, exact wire and PCM validation,
cleanup/generation fencing, observable diagnostics, and behavioral specifications.
No separate cleanup or redesign was added. Parent-owned acceptance and generated
consumer integration are the remaining follow-ups; any discovered repairs require
their own admitted Fix Manifest.

Same-file repair obligations completed during authoring: production helper
consumption, preserved native error adaptation, bounded actual-sample
accumulation, real-CAF behavioral scenarios and aligned specification/journal
responsibility. No separate existing debt was repaired or admitted.
