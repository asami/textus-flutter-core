# Mobile photo acquisition and recognition

Current status: E selected Dart validation passed230 cases; Core/TFAF analysis and all App Dart source analysis passed. Native unit tests passed22 cases and the real App debug APK built. Actual private built-in consumer compilation passed. Complete ESA6-02 and physical-device acceptance remain pending.
Owner: Textus Flutter Core maintainer, coordinated by App PHASE-6 / ESA6-02.
Update rule: Preserve the frozen public contracts; append parent evidence separately from authoring and device observations.

This note describes the authored reusable runtime. It is navigation and usage
guidance; it does not promote this slice to a normative specification or claim
Core Phase closure. The [journal](../journal/2026/10/2026-10-06-esa6-camera-and-recognition-services.md)
records the same authoring boundary. The preceding
[original storage note](local-capture-material-and-storage.md) and
[settings note](settings-runtime-and-recognition-configurations.md) explain the
durable original and desired preference used here.

## Public usage and caller ownership

```dart
import 'package:textus_flutter_core/textus_flutter_core.dart';

Future<RecognitionComparison?> acquire(SettingsService settings) async {
  final desired = settings.snapshot.value(RecognitionSettings.configuration);
  final photos = await openDefaultPhotoCaptureService();
  final report = await photos.capture(desiredConfigurationId: desired);
  if (report != null) {
    final comparison = await photos.compare(report.material);
    final history = await photos.reports.listForMaterial(report.material.id);
    // Render comparison.runs and history using the reusable consumer UI.
    // App maps raw proposals to book fields and owns human corrections.
    return comparison;
  }
  return null;
}
```

The factory opens the same default local store used by originals unless the caller
injects one. It registers real `ImagePickerCameraProvider` and
`MlKitImageRecognitionProvider` and `GeminiNanoImageRecognitionProvider`.
`additionalProviders` is materialized once; one explicitly supplied `geminiNano`
replaces the default Nano. Two supplied Nano providers and every other true ID
collision still reject. Caller-owned services/providers have no runtime singleton
or global registration. Missing native companion registration is a truthful
unavailable snapshot, so Core-only standard consumers remain usable.

`CameraService` rejects unsupported and overlapping capture/recovery. The photo
service rejects overlap across capture, recovery, saved-original reads, recognition, comparison,
availability and explicit preparation. Its immutable `configurations` getter,
`availability()` and `prepareProvider(id)` are the reusable UI facade entry points.
Recognition service likewise permits one active probe, preparation or inference.
All guards release after cancellation, failure or successful completion. Invalid
selection is rejected before camera/import/read. Cancellation and empty recovery
return null without storage or inference.

## Original ownership and acquisition

`CapturedPhoto` snapshots positive image bytes and returns fresh byte copies.
MIME token, original name and UTC completion time describe the unchanged image;
plugin cache paths never enter public values or reports. One common camera route
serves both presets: rear camera, no quality/size/compression request, and
`requestFullMetadata: false`. Acquisition uses a valid supplied image MIME or the
finite jpg/jpeg/png/heic/heif/webp/gif filename fallback. Unknown or empty images
fail observably.

Android lost-data recovery consumes exactly one image, preserves native exceptions
and rejects ambiguous responses. iOS recovery returns null without calling the
Android API. [image_picker](https://pub.dev/packages/image_picker) documents its
cache and process-death caveats: the plugin file is temporary, the application must
recover lost data, and durable import is a separate step. Core never deletes
plugin-owned cache. Acquisition support is conditional on non-Web Android/iOS;
desktop/Web have no successful native fallback.

The photo service durably imports unchanged original bytes before recognition,
then reads that saved original once for inference. All providers receive defensive
copies with the same material ID. `recognize` and `compare` reuse the saved
reference without calling camera or reimporting. Repository save may read the
original again solely to verify durable ownership. A report is returned only after
its durable save. Import/read/report-save errors propagate and preserve any saved
original; they do not fabricate references or imply an acquisition/report
transaction across process death.

## Desired, available and actual recognition

Desired preference remains `RecognitionSettings.androidStandard` or
`RecognitionSettings.pixelEnhanced`. Saving enhanced intent makes no readiness
claim. The immutable presets require `mlkitStandard` OCR/barcodes, followed for
enhanced by `geminiNano` interpretation/candidate organization. Providers and real
capabilities determine routes; no Pixel brand branch is present in presets or
App capture profiles.

Availability is a historical snapshot of available, unavailable, downloadable or
preparing state, provider capabilities, optional reason and optional model name.
Unknown model names remain null. Missing registration and required capabilities
are explicit unavailable outcomes. Probes have no download/inference side effects.
Only explicit `prepareProvider` prepares downloadable providers and then reprobes.
Available/preparing providers return their current snapshot, unavailable providers
throw their reason, and native preparation failures remain visible. Inference never
implicitly prepares a model.

One comparison snapshots availability once and evaluates rows in requested order.
Each provider occurrence checks its required capabilities against that historical
snapshot and the frozen registration descriptor before sharing work. A stopped
row or a checked snapshot that is not available is ineligible for execution or
cache reuse. Missing capabilities retain the offered capabilities and model name
with the explicit `missingCapabilities` reason.

Common prefixes share the identical immutable provider attempt, even when the
enhanced row is requested first. Standard executes once; enhancement receives the
same original plus earlier executed raw outputs. Different ordered prior attempt
IDs produce different work, preserving ordinary logical provenance.
Only executed attempts enter this shared work cache, including executed failures
with their original raw result and measured duration. Eligible occurrences with
different capability requirements can share the same performed work. Every
ineligible occurrence instead gets a distinct nonexecuted attempt ID, zero
duration and its own historical readiness/dependency failure record; it neither
supplies missing capabilities nor blocks a compatible row.

An unavailable provider stops later inference and retains skipped records. A
failed enhancement remains executed, timed and visible. Enhanced desire falls back
to the longest fully executed declared standard prefix when the last stage has no
successful output or readiness stopped the chain. Fallback records its reason and
preserves desired preference. If standard never executed, actual configuration is
null, with no false standard route or fallback reason. An executed standard route
may still have failed recognition: route selection and accuracy are separate.

Per-row elapsed time sums executed processing attempts, including failed
enhancement overhead. Both rows include the shared standard time. These are
cumulative route processing times over shared work; availability probe time is
excluded, and the rows are not independent repeated benchmarks. No timing
threshold or synthetic duration is used.

## Raw stages and durable provenance

Raw OCR, barcodes, interpretation and generated candidates stay separate in each
attempt. Empty successful OCR, completed empty barcode and completed empty
candidate stages differ from not-executed/failed stages. Barcode strings and
opaque candidate kinds are preserved without ISBN/title interpretation. App owns
book mapping, confirmed human edits and correction history; generated suggestions
never overwrite original bytes or imply accepted human fields.

Failures retain stage, code and descriptive native message; arbitrary exception
objects/native handles are never serialized. Unexpected native inference failure
becomes an executed provider failure. A provider returning no completed stage or
failure gets `emptyResult`. Selected successful stages with incomplete output or
failures are partial; no selected success is failed. Failed enhancement outside
the actual standard fallback remains visible without making completed standard
recognition fail.

`RecognitionReportCodec` owns exact version1 schema and
`LocalRecognitionRepository.collection` is `recognition_comparisons_v1`.
The report records original material, configuration intent/actual route, attempt
IDs, earlier executed source IDs, historical availability and processing timing.
Shared attempts serialize by value per row; decoding structurally equal repeated
IDs restores identical objects. Contradictory IDs, unknown keys outside finite
JSON extensions, invalid calendar/timezone values or unsupported versions throw
`FormatException`. There is no automatic migration/rewrite or integrity hash.
Extensions are deeply frozen snapshots; encoded JSON is detached.

The repository serializes saves on one instance and recovers after a failure. It
reads the original before checking an existing report; same-ID writes cannot
change material or creation time. Absence alone returns null. Corruption, listed
disappearance and IO/unsupported errors remain visible. Material history sorts
creation time descending then ID ascending and reloads after restart without
rewriting/deleting originals. Cross-process transactions, orphan collection,
backup and deletion are separate responsibilities.

## Standard native adapter and remaining acceptance

The conditional ML Kit IO adapter owns a unique temporary directory and fresh
Japanese `TextRecognizer` plus all-format `BarcodeScanner` for each call. Both
stages run independently against unchanged temp bytes. It always attempts both
close operations and removal of only its own temp directory; cleanup errors are
visible while other cleanup still proceeds. The non-IO implementation truthfully
reports unavailable and throws for preparation/inference. Platform availability
does not prove plugin registration, native host wiring, model setup or accuracy.

Primary adapter guidance and the parent-inspected API sources:

- [image_picker package](https://pub.dev/packages/image_picker) and [public source](https://raw.githubusercontent.com/flutter/packages/main/packages/image_picker/image_picker/lib/image_picker.dart).
- [ML Kit text recognition package](https://pub.dev/packages/google_mlkit_text_recognition) and [TextRecognizer source](https://raw.githubusercontent.com/flutter-ml/google_ml_kit_flutter/master/packages/google_mlkit_text_recognition/lib/src/text_recognizer.dart).
- [ML Kit barcode scanning package](https://pub.dev/packages/google_mlkit_barcode_scanning) and [BarcodeScanner source](https://raw.githubusercontent.com/flutter-ml/google_ml_kit_flutter/master/packages/google_mlkit_barcode_scanning/lib/src/barcode_scanner.dart).
- [Google Prompt Android API](https://developers.google.com/ml-kit/genai/prompt/android) for the later real Nano adapter.

Japanese host dependencies Android `text-recognition-japanese:16.0.1` and iOS
`MLKitTextRecognitionJapanese` 9.0.0, with iOS 15.5 minimum, belong E/B native host
wiring. No native host file is edited by A. Real Nano execution, reusable comparison
UI, App book correction branches and physical Android/Pixel comparison remain
pending E/B and device acceptance.

Five public behavior groups are authored for photo service, registry, repository,
image_picker and real ML Kit channel/resource behavior.
The registry specifications also author Q1–Q4 for per-occurrence eligibility,
successful and failed executed sharing, and distinct unavailable records in both
row orders. This original A authoring record preceded parent validation. The
dated evidence below records selected A and E Dart validation, passed22 native
unit cases and the real App debug APK build. Actual private built-in consumer
compilation passed; independent complete ESA6-02 acceptance remains pending. Controlled channel responses
establish no physical-device, model-download, OCR accuracy or enhanced native
execution claim. Whole Core Phase closure is not asserted.

## ESA6-02-E optional Android AICore / Gemini Nano — 2026-10-06

E is authored with selected Dart validation passed, native unit tests passed22
cases and the real App debug APK built; actual private built-in consumer compilation passed.
Install the Core-owned companion
[textus_flutter_core_android_genai](../../packages/textus_flutter_core_android_genai/README.md)
in an Android consumer alongside base Core. Base Core remains a platform-independent
library and has no dependency back on this optional plugin. The companion registers
`org.textus.flutter.core/genai.v1` through official
`com.google.mlkit:genai-prompt:1.0.0-beta4`. Only consumers opting into the companion
require Android 26; Core-only standard consumers retain their existing floor.
The App bundles Japanese `text-recognition-japanese:16.0.1`; iOS Japanese wiring
remains B. The companion uses AGP9.1.0/SDK36/Java-JVM17 and follows the consumer's Kotlin setting.
With android.builtInKotlin=false it explicitly applies Kotlin Android2.4.0; with
built-in Kotlin enabled or its AGP9 default it uses AGP's compiler. The current App
retains its global opt-out; its native unit tests and real debug APK build passed.
Actual private built-in host compilation passed. Current Flutter3.47.4
built-in consumers retain the template settings Kotlin2.4.0 applyfalse declaration
for runtime version selection and use android.builtInKotlin=true with
android.newDsl=false. The declaration does not apply the legacy Kotlin Android
plugin; do not apply that plugin in consumer modules. This recipe passed actual
private built-in consumer compilation and makes no default-version compatibility claim.

All application-facing APIs remain in base Core. Nano reports unsupported on
Web/iOS/desktop and never invokes a native channel there. Missing Android bridge
is `nativeBridgeUnavailable`; malformed replies and probe exceptions retain real
failure descriptions. Probes never download or infer. The native session initially
has foreground=false and admits only the attached resumed Activity. Initial
window-focus observation can establish an already resumed attachment; subsequent
resume/pause callbacks control it. Other activities cannot admit this engine's work.
Explicit foreground preparation awaits a real DownloadCompleted and the Core
service reprobes. Actual download failure, incomplete download, unavailable or
already downloading state remain observable. Cancellation claims no rollback of
AICore-managed downloading; a later explicit probe reports current truth.

`GeminiNanoImageRecognitionProvider(instructions: ...)` preserves a nonblank exact
String. The default describes visible content, entities and text/codes without
domain truth. App B can supply book instructions and map opaque generated kinds.
The deterministic `textus-image-recognition-v1` prompt contains exact instructions,
the strict interpretation/candidates schema and clearly delimited JSON prior raw
source data in execution order. Original bytes and source strings are never
truncated, normalized, rewritten or treated as commands. Native checks actual
request tokens plus 512 output tokens against the actual token limit and rejects
oversized input as `inputTooLarge`. ImagePart/TextPart inference uses temperature 0,
one candidate and 512 output tokens, requiring exactly one nonblank candidate text.

Each operation owns one actual default stable model and always attempts close.
Decode/inference and Bitmap cleanup share a Dispatchers.Default ownership block,
so cancellation cannot discard an unowned allocation. No image file, shared native
handle or executor is added. Probe/preparation/inference deadlines are 20/600/90
seconds without retry. Pause, configuration detach and engine detach cancel owned
work. Cleanup finishes before the guard clears and its at-most-once callback
delivers, including a scheduled body canceled before it starts. Successful inference
retains cleanup failures without erasing raw data; probe/preparation close failure
is an error. Native quota, initialization, token and download descriptions remain
visible in the error envelope.

Available probes retain the actual base model name; unknown names remain null.
Inference rechecks AVAILABLE and rejects a changed known model as `modelChanged`
before generation. Dart also strictly checks the returned model. Report availability
retains the historical probe snapshot. Executed failures and standard fallback
preserve desired configuration, real processing duration, earlier source attempt
IDs and standard raw results. Neither probing nor inference implicitly prepares.

Decoding accepts a whole JSON object optionally inside one complete JSON or
untagged fence, with exactly interpretation and candidates. No partial JSON is
salvaged. Interpretation and candidate organization validate independently: a valid
stage stays enhanced partial output with an explicit failed other stage. Candidates
have exactly nonblank String kind/value; opaque kinds, whitespace, duplicates and
order remain verbatim. Empty valid arrays are completed. Invalid arrays supply no
valid prefix. Invalid whole output supplies no success, retains the actual text
in descriptive failure and permits standard fallback. Cleanup never erases a
successful generated stage. Original OCR/barcodes and human corrections stay separate.

Optional `ImageRecognitionProviderProvenance` provides finite generic JSON;
old providers remain compatible. The service validates and deeply freezes participating
metadata before native work using existing material JSON-extension validation.
Nano supplies only exact instructions and promptTemplate under
`RecognitionComparison.extensions.providerProvenance.geminiNano`. This records
configuration even when Nano did not run; it adds no guessed model, native path,
handle, bytes or hash. Providers without metadata retain extensions:{}.
Report wire version1/key set, repository, cache eligibility/key and durable identity
remain unchanged; no migration is required.

N1–N9 are authored in public Dart Nano, photo facade and registry behavior files.
Pure Kotlin runner/session cases use finite injectable models and virtual time
without Android runtime mocks. Selected E Dart cases and22 native unit cases
passed. The real App debug APK built and
provides native compile/link evidence separately from physical inference,
which remains B/device acceptance.

## Parent-provided A evidence — 2026-10-06

Core 48 representative + Core 41 accumulator + TFAF 140 + App 59 = 288 unique
selected cases passed. Core 48 representative was additionally rerun, adding no
unique cases. All three final analyzes passed; the A pre-review lint sequence was
15 -> 2 -> 0. These selected A receipts recorded no E pass at initial authoring
on 2026-10-06 and claim no Step review or acceptance. Complete independent ESA6-02 and physical provider/device
acceptance remain pending. Connected Pixel 11 Pro Fold is inventory only and
distinct from requested Pixel 11 Pro acceptance; no real inference is claimed.
Core/TFAF release full suites remain obligations, and the App aggregate driver
stays deferred-not-run to Phase 6.1. No new Hygiene or Development Candidate
follow-up was identified in this slice.

## Compiler-integration correction and parent evidence — 2026-10-06

Actual E parent receipts record Core88 representative + Core62 accumulator +
TFAF56 + App24 = 230 unique selected Dart cases passed; Core/TFAF final analyzes
passed and the three original pubgets passed. Native configuration failed before
Kotlin tests: the gradle-kotlin lookup was fixed, then Flutter's legacy Kotlin
auto-application conflicted with the explicit built-in plugin. Prior units1–4
and both native failures remain recorded. At this earlier compiler-integration
correction on 2026-10-06, parent-selected validation in both host modes was still
pending and no native unit/APK success or physical inference was claimed. The
subsequent native build evidence below records the later passes without changing
these failed receipts. Initial "no E passes" wording records initial-authoring history;
A's 288 selected passed cases remain historical evidence.


## Native build evidence and built-in consumer preparation — 2026-10-06

Actual parent terminal receipts record22 native unit cases (runner13 + session9)
passed with failures/errors/skips0, all App Dart source analysis
`flutter analyze lib test integration_test` passed, and the real App debug APK
built. Reuse the existing230 selected E Dart passes and Core/TFAF analysis passes;
these receipts consume the dedicated Core/TFAF/companion overrides and all42 App
Dart files across lib/test/integration_test (three source directories), with
actual native App companion consumption. The sole
canonical companion pubspec-path warning and earlier whole-root App analyze
failure remain historical evidence; no whole-root App analyze pass is claimed.
All three private built-in consumer attempts failed before companion Kotlin
compilation: newDsl=true was incompatible with Flutter's legacy extension;
newDsl=false exposed actual default Kotlin2.2.10 below Flutter's actual minimum
2.2.20; the later root buildscript Kotlin2.4.0 override did not change that
observed version. The frozen successor restores template settings Kotlin2.4.0
applyfalse and removes that failed root override, retaining
android.builtInKotlin=true and Flutter-compatible android.newDsl=false. The
settings declaration does not apply the legacy Kotlin Android plugin in modules.
At this preparation stage on 2026-10-06, actual built-in consumer compilation
was still pending; the later parent compile result below records its pass. Prior
units1–5, native configuration failures and all three failed fixture receipts
remain recorded. No physical inference, complete ESA6-02, Step or release
acceptance is claimed. B/iOS/book/comparison and physical acceptance, Core/TFAF
full release suites and App aggregate validation in Phase6.1 remain pending.


## Built-in consumer compile result — 2026-10-06

Actual parent terminal0 receipt records `BUILD SUCCESSFUL in7s`: the same
companion's four native production sources compiled through compileDebugKotlin
with output under built_in_kotlinc. Kotlin2.4.0 applyfalse resolved, and actual
App and companion runtime diagnostics both showed builtIn=true/newDsl=false,
legacyApplied=false and KotlinBaseApiPlugin. No dependency-check bypass was used.
The first unit6 diagnostic attempt failed because the parent's init callback
also ran in included Flutter :gradle, which lacks :app. The parent then guarded
only builds without the companion; the retry passed. All earlier native,
fixture and diagnostic failure receipts and units remain retained. This proves
compiler consumption only; it establishes no real Nano inference, physical Pixel
identity, model readiness or image quality. B comparison UI/book mapping/iOS and
physical acceptance, ESA6-03/05, independent Step/Phase acceptance, Core/TFAF full
release suites and App aggregate validation in Phase6.1 remain pending. Existing
230 selected Dart cases,22 native unit cases and App source analysis/debug APK
evidence are reused; no new behavior scenario or acceptance is claimed.

## Original-only acquisition authored — 2026-10-06 / ESA6-03-A

`PhotoCaptureService.captureOriginal()` and `recoverOriginal()` return a
`Future<CaptureMaterialReference?>` after importing the unchanged image into the
same caller-owned local store. They require no desired configuration or settings.
Use the returned reference for a later explicit recognition operation:

```dart
final original = await photos.captureOriginal();
// Or: final original = await photos.recoverOriginal();
if (original != null) {
  final bytes = await photos.readOriginal(original);
  final report = await photos.recognize(
    original,
    desiredConfigurationId: RecognitionSettings.androidStandard,
  );
  // App owns page attachment and presentation of bytes/report.
}
```

Here `photos` is constructed with `store: sharedStore`. Each operation invokes
the existing camera capture or lost-photo recovery exactly once and awaits the
actual `saveMaterial` reference with exact bytes, media type, UTC capture time and
original name. It does not read the saved image, select a configuration, probe or
prepare a provider, infer, or write a recognition report. Null acquisition or
recovery returns null without storage work. Actual camera, permission and import
exceptions propagate unchanged, including CameraService's UnsupportedError.
There is no implicit retry, rollback or deletion of accepted originals.

Both methods share the same service guard with capture, recovery, recognition,
comparison, availability and preparation, including while import is pending.
Success, error and cancellation release that guard. Existing recognition APIs
retain selection-before-camera, import-before-inference and report durability.
Applications may explicitly recognize or compare the saved original later.
Page-specific Add page photo composition belongs to App ESA6-03-B.

The [original-acquisition journal](../journal/2026/10/2026-10-06-esa6-original-photo-acquisition.md)
maps authored A1–A5 executable scenarios. Parent focused validation and independent
complete-Step review/acceptance remain pending. Injected camera/provider cases
with real FileCaptureStore establish authored software behavior only; they do not
establish physical device acceptance or Core/TFAF full release validation. All
earlier native/device receipts and pending obligations retain their stated scope.

## Parent preflight and approval-review stop — 2026-10-06 / ESA6-03-A

Parent exact10paths preflight, all three repository `git diff --check` results,
owned-file whitespace/final-newline checks and48 relative-link checks passed.
The first selected Core `flutter analyze` request used `require_escalated`, but
CreateProcess rejected it before execution because automatic approval review
could not complete: the selected review model was at capacity. The platform
identified this as a review failure, not a determination that the action was
unsafe, and directed that the approval check must not be bypassed.

No selected analysis or test process started; there is no exit status, pass,
test count or runtime session. The remaining four selected jobs were not
submitted. No automatic retry, alternate execution route or repair was consumed.
The parent retained the raw request/result in
`.codex-workflow/phases/PHASE-6/platform-review-failure-esa6-03-a-core-analyze-20261006.json`
under the App root. Compiler compatibility of the observed pre-existing private
constructor parameter spelling remains unverified; no constructor repair or
design change is admitted. Prior passing receipts retain only their recorded
historical scope. Focused validation, independent complete-Step review/acceptance,
physical acceptance and full release obligations remain pending.

## Shared original-read correction authored — 2026-10-06 / ESA6-03-B-R

Parent-selected F-ESA6-03-B-01 adds `Future<Uint8List> readOriginal(material)` to
the existing photo service. It forwards the exact reference once to its borrowed
store inside the same `_operate` guard, holding ownership through actual read
success or error and releasing in `finally`. Saved bytes remain readable when
camera support or model readiness is unavailable. Reading performs no camera,
import, settings selection, probe, preparation, inference or report work.
Caller-owned returned bytes may be changed without rewriting the stored source.
The existing recognition implementation retains its internal store read while it
already owns the guard; it does not recursively call the public read operation.

Capture/import and read are successive explicit operations. An intervening
competitor may cause a shared-busy read failure; App retains its pending reference
for explicit retry/discard. This does not establish a continuous transaction.
Independent low-level storage reads retain their existing contract.

R1 saved/read/reopen/mutation, R2 observed held-read exclusion and injected,
missing and inconsistent-length errors, and R3 reciprocal acquisition/import/
probe/preparation/inference/report exclusion are authored in the existing public
photo-service specifications with adjacent Given/When/Then. TFAF forwards this
operation and App uses it for every existing original-validation helper caller.
Authoring is pending actual parent validation and M2 independent complete-Step03
protected focused conformance; it establishes no runtime closure or acceptance.
The retained pre-start platform failure and unverified constructor spelling above
remain unchanged, with no retry or execution by this repair editor.
