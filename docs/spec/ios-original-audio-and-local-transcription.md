# iOS original audio and local saved-audio transcription

This contract adds the iOS implementation behind the existing
`AudioRuntimeProvider` and `AudioTranscriptionProvider` interfaces. The default
factory selects `IosAudioProvider` on non-web iOS and preserves the existing
Android adapter elsewhere. The service owns that shared adapter once and borrows
the caller's capture store. OriginalAudio, persisted PCM, transcript codec v1,
and consumer controller/panel APIs keep their existing meanings.

## Registration and explicit authority

The optional iOS registration package is a local Core path dependency. It
registers `TextusFlutterCoreIosAudioPlugin` through CocoaPods, with iOS 15.5,
Swift 5, AVFoundation and Speech. The package-root SwiftPM manifest originally
provided Foundation-only helper tests. It now also links Apple's AVFoundation
on macOS to exercise production CAF extraction with real files; Flutter/iOS
registration code remains outside that host target. It is not an iOS SwiftPM
registration route.
Registration observes lifecycle notifications and does no capture, playback,
recognition, preparation or permission request.

The consuming application supplies meaningful `NSMicrophoneUsageDescription`
and `NSSpeechRecognitionUsageDescription` entries. A missing entry is an
observable configuration failure before a permission request. Recording
requests microphone permission only on explicit start. Preparation and saved
transcription request speech authorization on explicit use. Permission denial
does not authorize a fallback or a download.

Availability inspects the exact locale recognizer, supported locales,
`supportsOnDeviceRecognition`, `isAvailable` and current speech authorization.
It requests no permission, inference or download. Denied/restricted, unsupported
or unavailable local capability reports unavailable with its actual reason.
Not-determined authorization can report available only if the inspected local
capability is ready, with reason "Speech permission is requested on explicit
use". This describes potential explicit use, not an already granted permission.
Preparation rechecks capability after authorization. It never advertises
downloadable/downloading states as permission states.

## Exact bridge and ownership

Channel: `org.textus.flutter.core/ios_audio`.
Actual provider identity: `ios-on-device-speech`.
Every request contains one safe logical `sessionId` matching
`^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$`. No material storage path crosses the bridge.

| Method | Additional exact argument keys |
| --- | --- |
| availability, prepare | locale |
| startRecording | maxDurationSeconds |
| play | bytes |
| transcribe | bytes, locale |
| stopRecording, cancelRecording, stopPlayback, cancelTranscription, dispose | none |

Locales retain the exact validated language tag. Duration is an integer 1..120,
with booleans and fractional/floating values rejected. Saved bytes use the
Flutter Uint8List typed-data representation and must satisfy the canonical WAV
contract before native replay/inference. Unknown methods are not implemented;
unknown/missing keys or wrong types are observable failures.

Capability response keys are exactly providerId, locale, state, reason.
Captured response keys are exactly bytes, capturedAt, originalName. Transcript
response keys are exactly text, extensions. Dart checks types, exact provider
and locale, canonical capture time and WAV, nonblank exact text, and JSON
extensions with providerId, exact locale and onDevice:true. Additional valid
JSON extension values are preserved. Native diagnostics become
`AudioProviderException`; missing registration reports unavailable capability
and fails explicit native work. Unsupported hosts do not synthesize audio/text.

Every ordinary operation is exclusive within a logical session. The production
`AudioOperationOwner` also grants one plugin-wide media lease, so different
sessions cannot concurrently own recorder, player or saved-audio recognizer.
Availability does not take a media lease. The portable helper is consumed by
the plugin for all callback fences, rather than existing only in tests.

Recording holds its generation through explicit stop/cancel, including after
the configured automatic duration ends. Stop is allowed after start has been
accepted. Cancel can interrupt pending permission/start immediately: retire
the token first, settle its pending FlutterResult as cancelled, clean up only
its resources and audio session, then settle cleanup. An OS prompt need not
dismiss before that old future settles. A late grant/completion cannot reacquire
or publish, including after a successor starts. Results settle at most once.
Cleanup from alive idle sessions is idempotent; disposal keeps terminal
session tombstones and repeated disposal is idempotent.

All mutable native state and callback publication use the main queue.
Permission grants can start work only for a live token in a foreground-active
application. Transient inactivity defers the same token until didBecomeActive.
didEnterBackground cancels pending and active work without autoresume;
interruption cancels the current physical owner. willResignActive does not
cancel native permission prompts. Cancel, dispose, background and detach
permanently fence deferred starts. Engine detach retires outstanding work,
settles pending results, releases resources and removes observers.

The Dart adapter retains the existing independent Android lifecycle semantics:
exclusive operations, stale-generation rejection, shared recording/playback
cleanup, joined transcription cancellation, terminal idempotent disposal that
awaits old futures/cleanup, and first cleanup failure preservation.

## Canonical original, replay and saved-input speech

Recording owns a UUID-named temporary CAF. AVAudioRecorder requests linear
PCM, 16 kHz, mono, signed integer 16-bit, little-endian and nonfloat; the
playAndRecord/default audio session uses defaultToSpeaker and is activated
only for actual media. record(forDuration:) applies the 1..120 second limit.
Normal automatic completion keeps the buffer for explicit stop and creates no
unsolicited original or event.

Explicit stop stops the recorder, preserves any recorder failure, then calls
the production `PcmAudioFileReader`. The reader opens the actual file through
AVAudioFile with int16 interleaved processing and checks both actual source
and processing formats for 16 kHz mono PCM16, plus interleaved processing and
an initial actual length of 16..1920000 frames. It retains that expected length
and reuses one buffer holding at most 8192 frames. Each read requests at most
the remaining expected frames, advances from the current file position and
appends only the returned `frameLength` samples in little-endian order. A
positive short read continues until the accumulated count equals the initial
length. Zero progress, premature EOF, missing sample data, inconsistent file
position/length or a read error fails; there is no padding, missing suffix
acceptance or extra EOF read. Only the complete samples enter the existing
encoder for one exact common 44-byte WAV. Actual format/bounds failures retain
`invalidAudio`; allocation/incomplete/contradictory read failures retain
`recordingFailed`. Stop translates only the reader's internal failure to the
existing native failure type; AVAudioFile I/O errors propagate unchanged.
It performs no resampling, mono mixing, arbitrary WAV chunk pass-through or
silent fallback. capturedAt is the original start time
in POSIX/Gregorian UTC `yyyy-MM-dd'T'HH:mm:ss.SSS'Z'`;
originalName is `recording.wav`.

The physical iPhone recording-stop attempt reported `recordingFailed` with
"Recorded PCM could not be read completely" and produced no saved original.
The parent's real synthetic CAF reproduction established that a single large
AVAudioFile read can return fewer frames than requested even with sample data
present. This bounded source repair replaces the original one-read equality
assumption. Its authored regressions and physical recovery remain to be
validated by the parent; no successful recording or Phase closure is asserted.

Canonical WAV has RIFF/WAVE, fmt length 16, integer PCM tag 1, mono 16 kHz,
32000 bytes/second, block align 2, 16 bits/sample, and one data payload.
Lengths must agree exactly with the fixed 44-byte header and actual bytes.
Payload is even, 32..3840000 bytes (16..1920000 samples; 1 ms..120 s).
No extra chunks, padding or trailing bytes are accepted. Bounds precede
allocation and length conversion. Swift and Dart enforce the same persisted
format without migration.

Replay passes the exact validated saved WAV to AVAudioPlayer, holds its future
until actual completion, and reports decode/finish errors. Explicit stop
cancels the pending playback result. Replay does not request microphone access.

Transcription rechecks authorization and exact local capability, writes only
the exact saved original to an owned UUID temporary WAV, and uses
SFSpeechURLRecognitionRequest with requiresOnDeviceRecognition=true and
shouldReportPartialResults=false. It never starts microphone capture. It
preserves the actual final bestTranscription.formattedString unchanged and
returns provenance JSON without a filesystem path or credentials. Error,
missing/blank final result, and a 60-second timeout fail observably. No cloud
fallback, automatic model download or OS 26 SpeechAnalyzer path is present.

Completion, cancel, background, dispose, detach and error paths stop the owned
recognition task/timer/player/recorder and remove only their UUID temporary
files. A different session's cleanup cannot stop or deactivate the active
owner. No directory scan or session-data deletion is part of this implementation.

## Executable scenario authoring map

The following specifications are authored with adjacent Given/When/Then
comments and observable matchers/assertions. Execution and acceptance are
pending. Channel mocks prove protocol behavior only.

Source: `test/audio/ios_audio_provider_test.dart`.

| Scenario | Given / When / Then |
| --- | --- |
| Inert construction and input validation | Construct an iOS adapter with malformed saved WAV / replay and transcribe / reject before any native call. |
| Transcript provenance and model-download states | Exact ja-JP input / foreign provider, locale, onDevice value, nonfinite JSON, nonstring key or permission-as-download response / FormatException without accepted output. |
| Repeated transcription cancellation | Pending recognition plus independently gated cancel / cancel twice then dispose / same cleanup future, one native cancellation/disposal, rejected stale result. |
| Failed recording cleanup | Pending stop plus gated failing cancel / cancel and repeat dispose / keep exact first failure, reject old capture, still dispose once. |
| Failed playback cleanup | Pending playback plus gated failing stop / stop and repeat dispose / keep exact first failure, reject old playback, still dispose once. |
| Idle cleanup | Alive idle adapter / repeated cancel/stop then dispose / no cleanup channel calls while idle; terminal calls reject. |
| Cancel delayed recording stop | Started recording with held stop result / cancel, release delayed capture and start anew / old capture rejects and fresh recording is possible. |
| Joined recording cancels | Held recording stop and gated cancellation / equivalent cancels overlap disposal / shared future, one cleanup, disposal waits for old work. |
| Joined playback stops | Held playback and gated stop / equivalent stops overlap disposal / shared future, one stop, disposal waits. |
| Exact method protocol | Valid captured/saved audio / all methods explicitly invoked / exact argument keys, stable safe session, exact bytes/time/name/text/JSON, no original path. |
| Per-instance isolation | Two adapters sharing channel / probe both and dispose one / unique stable sessions and second remains usable. |
| Unsupported/absent plugin | Unsupported host then unregistered iOS channel / availability, prepare, recording and dispose / honest unavailable, runtime failure, no fake audio. |
| Native diagnostics | Mock permission/preparation failures / explicit start and prepare / preserve exact error code/message without capture or inference. |
| Strict captured response | Valid capture with independent malformed keys/types/time/WAV / start and stop / each malformed capture rejects. |
| Strict capability/transcript response | Exact saved input / contradictory identity, locale, state, reason, blank/type/extra-key transcript / reject malformed result. |
| Exclusive inference and cancellation | Held transcription / attempt overlapping work then cancel / busy rejects, late success rejects, idle becomes usable. |
| Dispose pending preparation | Held prepare / repeated terminal dispose / one native disposal, late readiness rejects, later work rejects. |
| Cancel pending permission-like start | Held native start / cancel before response, then new recording / stale start rejects and fresh start succeeds. |
| Explicit playback stop | Held saved playback / stop and delayed completion / old playback rejects, exact owner/bytes preserved, idle reusable. |

Source: `test/audio/default_audio_provider_selection_test.dart`.
The existing private in-memory LocalCaptureStore fixture pattern is adapted
inside this owned test file; it opens no file store.

| Scenario | Given / When / Then |
| --- | --- |
| iOS default | iOS platform override and memory store / default factory, probe, capture, replay, dispose twice / iOS identity/channel only, one owned adapter disposal, unchanged borrowed bytes/document. |
| Android default | Android platform override and same store pattern / same sequence / existing Android identity/channel only and unchanged ownership/storage. |
| Unsupported fallback | macOS override and memory store / probe and dispose / existing Android unavailable fallback with no native calls. |

Source: `packages/textus_flutter_core_ios_audio/Tests/AudioContractTests.swift`.

| Scenario | Given / When / Then |
| --- | --- |
| Exact minimum/maximum samples | Varying real PCM at 16 and 1920000 samples / production encode and validate / exact samples and 44-byte header roundtrip. |
| Invalid PCM encoding | Empty, submillisecond, odd and oversized PCM / encode / reject before successful canonical allocation. |
| Malformed WAV structure | Valid saved WAV independently corrupted/truncated/extra-chunk/trailing / validate / reject every inconsistency. |
| Invalid payload bounds | Matching size headers with zero, odd, short and oversized payload / validate / lengths cannot legitimize invalid PCM. |
| Cancel before grant | Pending generation / retire then delayed media acquisition / no current token or media acquisition. |
| Old completion versus successor | Retired owner followed by active successor / old retire/reacquire / successor remains current and owns media. |
| Terminal disposal | Active owner / dispose repeatedly then delayed callback/new acquire / terminal tombstone and no reacquisition. |
| Other-session isolation and busy | Active owner plus separate logical token / competing media, cleanup and dispose / busy observable and only actual owner can release. |

Source: `packages/textus_flutter_core_ios_audio/Tests/PcmAudioFileReaderTests.swift`.
These native host scenarios write real UUID-owned temporary CAF files with
AVAudioFile and varying known samples, finish the scoped writer before reading,
and clean up their own files. They use no microphone or mocked file reader.
The production extraction helper is the same one called by recording stop.

| Scenario | Given / When / Then |
| --- | --- |
| Complete long CAF samples | Actual 320001, 329937 and 1920000-frame 16 kHz mono PCM16 CAFs / production extraction and canonical WAV decoding / exact original byte sequence, complete tail and 44-byte header length. |
| Short CAF control | Actual 320-frame CAF with the same varying sample pattern / production extraction and WAV decoding / every original sample and exact canonical length. |
| Foreign actual source formats | Real 44.1 kHz, stereo and float CAFs / production extraction / invalidAudio without resampling, mixing or accepting converted originals. |
| Actual length bounds | Real 15 and 1920001-frame PCM16 CAFs / production extraction / invalidAudio without padding, truncation or duration estimation. |

## Pending acceptance and limits

No authored test or request flag establishes physical microphone behavior,
Japanese model availability, native speech accuracy or SDK egress guarantees.
The parent must run dependency resolution, focused iOS and existing
Android/service/transcript tests, static analysis, SwiftPM host tests covering
the existing Foundation contracts and native AVFoundation CAF scenarios, and
a real iOS Release build. For this bounded PCM-read repair, the parent owns
the changed SwiftPM target, the same iOS Release build and normal signature
check; earlier Dart and App regression evidence remains relevant unless new
evidence warrants rerunning it. Preserved-data device acceptance must record, replay,
recognize saved Japanese audio, save, restart and read back unchanged originals
and transcript provenance, including permission/cancel/background/interruption
behavior. Independent protected conformance review and local acceptance commits
follow actual results. This document makes no passed-test or Phase-acceptance claim.
