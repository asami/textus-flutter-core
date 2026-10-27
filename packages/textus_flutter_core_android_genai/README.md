# Textus Flutter Core Android GenAI

Current status: E selected Dart validation passed230 cases; Core/TFAF analysis and all App Dart source analysis passed. Native unit tests passed22 cases and the real App debug APK built. Actual private built-in consumer compilation passed. Complete ESA6-02 and physical-device acceptance remain pending.
Owner: Textus Flutter Core maintainer, coordinated by App PHASE-6 / ESA6-02.
Update rule: Preserve the frozen Core provider/native ownership contract; append actual validation separately from device evidence.

This optional Core-owned Flutter plugin registers Android AICore/Gemini Nano for
`GeminiNanoImageRecognitionProvider`. Application services and providers remain
in base Core, imported from `package:textus_flutter_core/textus_flutter_core.dart`.
This Dart library is a registration marker, with no application business API.
See the [canonical Core usage and ownership guidance](../../docs/notes/mobile-photo-acquisition-and-recognition.md)
and [authoring journal](../../docs/journal/2026/10/2026-10-06-esa6-camera-and-recognition-services.md).

## Consumer installation

```yaml
dependencies:
  textus_flutter_core:
    path: ../textus-flutter-core
  textus_flutter_core_android_genai:
    path: ../textus-flutter-core/packages/textus_flutter_core_android_genai
```

Opting into this package requires Android minSdk 26. Base Core does not depend
back on it, and Core-only standard consumers retain their existing floor.
The companion uses AGP9.1.0/SDK36/Java-JVM17 and follows the consumer's Kotlin setting.
With android.builtInKotlin=false it explicitly applies Kotlin Android2.4.0; with
built-in Kotlin enabled or its AGP9 default it uses AGP's compiler. The current App
retains its global opt-out; its native unit tests and real debug APK build passed.
Actual private built-in host compilation passed. Current Flutter3.47.4
built-in consumers retain the template settings Kotlin2.4.0 applyfalse declaration
for runtime version selection and use android.builtInKotlin=true with
android.newDsl=false. The declaration does not apply the legacy Kotlin Android
plugin; do not apply that plugin in consumer modules. This recipe passed actual
private built-in consumer compilation and makes no default-version compatibility claim.
See [Gradle plugin declarations shared with subprojects](https://docs.gradle.org/current/userguide/plugins_intermediate.html#sec:subprojects_plugins_dsl)
for the applyfalse declaration pattern.
Ordinary consumers use the companion with their matching host Kotlin setting.
Google's real `genai-prompt:1.0.0-beta4` dependency supplies AICore binding/query
manifest entries; this plugin does not override Google's Android minimum.
App consumers of Core's Japanese standard OCR also configure Japanese ML Kit;
this App authors bundled Android `text-recognition-japanese:16.0.1`.

## Readiness and explicit foreground preparation

The factory registers both standard ML Kit and Nano. Missing native registration
remains unavailable/nativeBridgeUnavailable. Unsupported Web/iOS/desktop reports
unsupportedPlatform and invokes no channel; direct preparation/inference throws
UnsupportedError. No iOS native registration is supplied by this companion.

`PhotoCaptureService.configurations`, `availability()` and `prepareProvider(id)`
are the reusable facade. Probe/preparation cannot overlap any photo operation.
Native session starts foreground=false and admits only this engine's attached
resumed Activity. A probe obtains actual readiness without downloading/inference.
Explicit preparation alone collects an actual DownloadCompleted and then Core
reprobes. Downloading/unavailable/incomplete/error truth remains visible.
Pause/detach cancels; it does not claim AICore-managed download rollback.

## Inference and durable raw results

One request owns one real default stable model and closes it on every outcome.
The original bytes are copied, decoded inside one Dispatchers.Default Bitmap
ownership block and used with ImagePart/TextPart. Actual token count plus 512
output tokens must fit the real model limit; input is never silently truncated.
Generation uses temperature0, one candidate and maxOutputTokens512, requiring
one nonblank candidate text. Inference rechecks availability and actual model;
model change from known probe identity is modelChanged and permits standard fallback.

Native deadlines are probe20s/preparation600s/inference90s, without retry.
Foreground loss/configuration detach/engine detach cancels owned work. Native
cleanup completes before busy releases and the one callback delivers, including
cancellation before the scheduled body starts. Primary failure and every cleanup
description survive; close failure cannot turn a probe/preparation into success.

Core preserves exact generic instructions and ordered prior raw source JSON in
`textus-image-recognition-v1`. Whole JSON/fenced responses are strict; interpretation
and candidate stages validate independently. Opaque kinds, verbatim strings,
duplicates/order and valid empty candidate arrays remain proposals. Invalid whole
responses retain failed raw text and select standard fallback. Cleanup errors
retain successful raw data. App owns book mapping and human corrections.

Finite optional configuration provenance snapshots instructions/template before
native work and persists through existing report extensions, even if Nano did not
run. Actual model identity remains the historical availability snapshot. No report
wire version1/key change, image rewriting, cache-key change or schema migration.

## Evidence boundary

N1–N9 public Dart cases and pure Kotlin model/session cases are authored; selected
Dart execution has passed and native unit execution passed22 cases. Native unit cases use finite injectable models and
virtual time; they do not prove real Nano. App APK build is native compile/link
evidence. Actual physical provider execution remains B/device acceptance.
The parent supplied A's 288 unique selected passed cases and final Core/TFAF/App
analyzes. At initial E authoring on 2026-10-06, E had no passed validation receipt;
the dated correction below records the subsequent selected E evidence. Connected Pixel 11 Pro Fold
is inventory, distinct from requested Pixel 11 Pro acceptance.

Primary API linkage guidance: [Google Prompt API](https://developers.google.com/ml-kit/genai/prompt/android/get-started),
[model selection](https://developers.google.com/ml-kit/genai/prompt/android/select-model)
and [Android built-in Kotlin](https://developer.android.com/build/migrate-to-built-in-kotlin#module-by-module-migration).

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

Connected development selects dedicated Core/TFAF/companion overrides. The
original App whole-root analyze failed with the sole pubspec.yaml38 warning
because canonical main lacks the companion; that receipt is retained, with no
whole-root analyze pass claimed. The parent validates all current App Dart roots
`lib/test/integration_test`, actual resolved package/plugin roots and the real
native APK. Canonical installation assumes the accepted Core tree at the
documented layout. This is branch-consumption evidence, with no publication,
remote integration or reduced runtime acceptance claim.


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
