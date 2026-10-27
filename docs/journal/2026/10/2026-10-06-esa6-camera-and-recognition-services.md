# ESA6-02-A — Camera and recognition comparison services

Current status: E selected Dart validation passed230 cases; Core/TFAF analysis and all App Dart source analysis passed. Native unit tests passed22 cases and the real App debug APK built. Actual private built-in consumer compilation passed. Complete ESA6-02 and physical-device acceptance remain pending.
Owner: Textus Flutter Core maintainer, coordinated by App PHASE-6 / ESA6-02 / ESA6-02-A.
Update rule: Preserve the frozen acquisition/provider/report contracts; append actual parent validation and independent acceptance evidence separately.

The dedicated Core checkout now authors the twenty-one manifest-owned source,
specification and documentation paths for common mobile acquisition, standard
recognition and durable comparison. The preceding
[settings migration](2026-10-06-esa6-settings-runtime-and-recognition-configurations.md)
supplies independent desired configuration intent. The
[public usage note](../../../notes/mobile-photo-acquisition-and-recognition.md)
explains caller-owned service composition through
`package:textus_flutter_core/textus_flutter_core.dart` and links primary adapters.

`CameraService` wraps a real injected image_picker route shared by both presets.
Captured bytes are defensive unchanged images without cache paths. Cancellation
and empty recovery do no storage/inference; native errors remain visible.
Android lost-data recovery accepts exactly one image and retains cache files;
iOS avoids its Android API. The
[image_picker cache/recovery guidance](https://pub.dev/packages/image_picker)
continues to apply: durable import follows acquisition, and no process-death
transaction is promised.

Provider/configuration catalogs are immutable and constructor-injected. Desired
`androidStandard`/`pixelEnhanced`, historical model/capability availability and
actual route remain separate. Explicit preparation downloads only when requested
for a downloadable provider, then reprobes. Inference never implicitly prepares.
Missing Nano registration is an explicit interim unavailable state in the standard
factory; no saved enhanced intent is downgraded.

One saved original feeds every provider. Standard prefix work is shared as the
identical immutable attempt object in both requested row orders. Enhancement gets
defensive original bytes and earlier raw results. Row elapsed time includes shared
standard processing plus executed enhancement, even when enhancement fails;
probe time is excluded. These cumulative route times do not represent independent
repeated benchmarks. Actual fallback retains failed/skipped enhancement and an
explicit reason; unavailable standard produces no false actual route.

F-ESA6-02-A-CACHE-01 is corrected within the authored A boundary: each occurrence
checks its required capabilities against the operation's historical availability
and frozen registration descriptor before cache access. Only an available
occurrence in a row that has not stopped can reuse work. The cache retains only
executed attempts, including executed failures with their raw result and measured
duration, keyed by provider and ordered prior attempt IDs. Each ineligible
occurrence retains a distinct nonexecuted identity, zero duration and truthful
readiness/dependency failures. Missing capabilities preserve the actually offered
capabilities and model name; skipped work cannot poison another compatible row.
Q1–Q4 are authored with both row orders for descriptor/readiness capability gaps,
compatible successful sharing, compatible executed failure sharing and independent
unavailable records. The parent still owns validation; no pass is recorded here.

Raw OCR, verbatim barcodes, interpretation and opaque generated candidates retain
per-provider provenance. Empty completed stages differ from failed/unexecuted
ones. App owns book mapping, accepted human edits and independent correction
history. No original or human field is replaced by generated suggestions.
Stage-coded failures retain real native descriptions, including cleanup errors.

Version1 `recognition_comparisons_v1` documents durably retain the original logical
reference, desired/actual configuration, historical availability/model snapshot,
attempt/source IDs and processing durations. Exact decoding rejects unsupported
versions, malformed keys/types/calendar values and contradictory shared IDs;
finite opaque JSON extensions remain deeply immutable. Restart restores shared
identity and sorted per-material history. Saves read the original first, reject
same-ID material/time conflicts, run in order and recover after failure. Storage
errors propagate while accepted report bytes and original files are preserved.
No automatic migration, deletion or cross-process transaction is introduced.

The real conditional ML Kit IO adapter owns temporary bytes and fresh native
handles per call, runs Japanese OCR and all-format barcodes independently and
attempts both closes plus only its own directory removal. Primary sources are
[TextRecognizer](https://raw.githubusercontent.com/flutter-ml/google_ml_kit_flutter/master/packages/google_mlkit_text_recognition/lib/src/text_recognizer.dart)
and [BarcodeScanner](https://raw.githubusercontent.com/flutter-ml/google_ml_kit_flutter/master/packages/google_mlkit_barcode_scanning/lib/src/barcode_scanner.dart).
Non-Web Android/iOS support is conditional; desktop/Web never fabricate successful
recognition. Availability establishes no host registration/model-wiring/accuracy
claim. Android Japanese `text-recognition-japanese:16.0.1`, iOS Japanese ML Kit
9.0.0 and iOS 15.5 minimum belong later E/B host wiring.

Executable specifications are authored in the five manifest-selected capture
files, with adjacent Given/When/Then and public package imports. They cover raw
immutability, durable originals/reports, restart, registry readiness/preparation,
shared-prefix comparison/fallback, strict codec/provenance and actual plugin
channel/resource shapes. The parent owns all dependency resolution, formatting or
analysis as admitted, selected test execution, compatibility accumulators,
diff/link/GWT verification and review transitions. This journal records no passed
tests, acceptance commit or physical-device/accuracy evidence.

Real Gemini Nano execution via the
[Google Prompt Android API](https://developers.google.com/ml-kit/genai/prompt/android),
TFAF/App UI and correction integration, native host configuration and physical
Android/Pixel acceptance remain E/B work. Complete independent ESA6-02 acceptance
waits for S+A+E+B/device evidence; neither Core Phase closure nor enhanced native
execution is claimed by this authored A slice.

## Parent-provided selected A evidence — 2026-10-06

The preceding A authoring statements record the state before parent validation.
Actual parent receipts now record Core 48 representative + Core 41 accumulator +
TFAF 140 + App 59 = 288 unique selected cases passed. Core 48 representative
was also rerun; that does not add unique cases. All three final analyzes passed
and A pre-review lint went 15 -> 2 -> 0. No Step review or acceptance is recorded.

## ESA6-02-E authored optional native provider — 2026-10-06

E is authored with selected Dart validation passed, native unit tests passed22
cases and the real App debug APK built; actual private built-in consumer compilation passed. The Core-owned
`packages/textus_flutter_core_android_genai` optional Flutter plugin registers
the real official beta4 AICore/Gemini Nano Android implementation. Base Core
remains platform-independent with its public provider/services in the existing
barrel and no dependency back to the companion. Only opted-in consumers require
Android 26. App canonical/local companion paths are authored, with the local
override ignored; App also bundles Japanese ML Kit 16.0.1. iOS Japanese host
wiring remains B. The companion uses AGP9.1.0/SDK36/Java-JVM17 and follows the consumer's Kotlin setting.
With android.builtInKotlin=false it explicitly applies Kotlin Android2.4.0; with
built-in Kotlin enabled or its AGP9 default it uses AGP's compiler. The current App
retains its global opt-out; its native unit tests and real debug APK build passed.
Actual private built-in host compilation passed. Current Flutter3.47.4
built-in consumers retain the template settings Kotlin2.4.0 applyfalse declaration
for runtime version selection and use android.builtInKotlin=true with
android.newDsl=false. The declaration does not apply the legacy Kotlin Android
plugin; do not apply that plugin in consumer modules. This recipe passed actual
private built-in consumer compilation and makes no default-version compatibility claim.
The companion's
[README](../../../../packages/textus_flutter_core_android_genai/README.md)
and [canonical Core note](../../../notes/mobile-photo-acquisition-and-recognition.md)
describe installation and the frozen ownership/error contract.

Nano is the default alongside ML Kit, with a single explicit Nano extension
replacing the default and true duplicate IDs still rejecting. Missing companion
is truthful unavailable; Web/iOS/desktop never call the bridge. Direct provider
availability/preparation/inference and photo facade readiness operations share
their existing guards. Native foreground admission requires this engine's attached
resumed Activity. Explicit completed-only preparation reprobes; probing and
inference never download. Cancellation preserves current AICore download truth.

One native request owns one real default stable model, unchanged original image
snapshot and Bitmap allocation/cleanup block. Token count plus 512 output tokens
must fit the actual limit; generation uses temperature0/candidateCount1/maxOutputTokens512.
Actual available model metadata is retained and rechecked; a changed known model
fails observably before inference. Native deadlines are 20/600/90 seconds for
probe/preparation/inference. Pause/configuration/engine detach cancels; cleanup
finishes before guard release and one callback, even if a scheduled body never
began. Close/Bitmap cleanup errors retain primary native evidence and successful
generated data; probe/preparation close errors cannot report success.

Exact immutable generic instructions and the `textus-image-recognition-v1`
template delimit ordered prior raw JSON as data. Strict whole-response decoding
accepts a single complete JSON/untagged fence and exactly interpretation/candidates.
Stages validate independently; opaque kinds, verbatim strings, duplicates, order
and completed empty candidates remain raw proposals. Invalid arrays supply no
partial prefix. Whole invalid output retains raw failed text and falls back to
standard with executed time and source IDs. Standard raw output and human edits
are never replaced. Native primary/cleanup/model/token errors remain descriptive.

Optional generic provider provenance is deep-frozen before native work using
existing finite JSON extension validation and persisted under providerProvenance.
Nano records exact instructions/template only, including when unavailable.
Old providers retain empty extensions and their old interface. Wire version1/key
set, repository, cache sharing/eligibility/key, original/result ownership and
identity/timing/fallback contracts are unchanged; no codec edit or migration.

N1–N9 Dart specifications and pure Kotlin runner/session matrices are authored
with adjacent scenario Given/When/Then. Selected Dart validation and Core/TFAF
analysis passed; native tests passed22 cases and the real App debug APK built.
Actual private built-in consumer compilation passed. These finite
fakes establish no actual Nano execution. Complete independent ESA6-02 and
physical Android/Pixel comparison remain pending. Pixel 11 Pro Fold is connected
device inventory only, not requested Pixel 11 Pro acceptance. Core/TFAF full
release validation remains due; App full driver is deferred-not-run to Phase 6.1.
No new Hygiene/Development Candidate item or empty follow-up is created.

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

## Independent Step acceptance and commit preparation — 2026-10-09

Current status: ESA6-02 complete Step and its affected ESA6-01/03/05 contracts
are independently accepted. Separate repository acceptance commits, upstream
final validation, the sole epoch1 full Phase review and Phase release remain
pending. Phase 6.1 is not started; App aggregate validation remains assigned to it.
Owner: Phase6 parent /root for evidence admission and transitions, with the
repository maintainer retaining the recorded domain responsibility.
Update rule: retain earlier dated failures, pending observations, review findings
and manual values; append actual later acceptance and commit evidence separately.

The original complete reviewer /root/esa6_02_complete_acceptance_20261009 reviewed
283 paths and 123 whole target programs across App/Core/TFAF. It found the sole
P2 CPB-ESA6-02-COMPLETE-STALE-EDITOR-DIALOG-001. Registered independent focused
reviewer /root/esa6_02_dialog_cycle1_rereview_20261009 then sealed PASS on
esa6-02-dialog-cycle1-focused-20261009@1 and explicitly resolved that blocker.
The parent admitted closure esa6-02-dialog-cycle1-closure-20261009@1 into the
retained Phase review ledger revision16 and verified save/read-back and the
complete chain. Two repaired App programs now bind dialogs and asynchronous
pending/completion callbacks to the exact controller and ownership generation,
detach only their owned routes, and preserve current-owner recording/cancellation.

Actual post-repair validation passed27 focused widget cases and128 affected
cases, including those27; selected lib/test/integration_test/test_driver analysis
reported zero issues. The retained pre-repair611-case affected App accumulator,
Core188-case and TFAF87-case selected accumulators, native22-unit and consumer
build evidence retain their exact original scope. These counts are not summed
and are not a full-App-suite or renewed physical-validation claim.

The complete Step reviewer found original P1-P8 and supplemental five-field,
seven-photo-viewpoint Fold and Sony observations sufficient with recorded limits.
Actual standard/Nano results, unavailable enhancement, source selection, explicit
manual correction/Apply/Save and same-install COLD restoration remain distinct.
Incorrect generated title/author/volume, differing human publication entries and
the historical Sony SIGKILL remain recorded; automatic bibliographic accuracy,
physical no-photo/corruption injection or model-download preparation is not claimed.

Separate accepted Step histories remain: esa6-01-material-acceptance-20261007@1,
esa6-03-material-editor-step1-closure-20261007@1 and
esa6-05-material-workspace-gwt-m0-closure-20261008@1, with their earlier Step
reviews. The complete02 review reconciled their affected current contracts.
All five existing OPEN Hygiene records remain in the canonical App Phase6
Hygiene journal. No new Hygiene or Development Candidate is admitted here.
Core retains generic storage/settings/providers/context; TFAF retains common
facades/widgets and opaque context forwarding; App retains Book Material policy,
mapping, explicit review and navigation. Original bases, Goal, authority, epoch1,
Step02repair1/Step03repair1/Step05repair0/Phase repair0 and prereview54 remain.

Commit preparation preserves separate repository journals and dependency order
Core -> TFAF -> App. Shared whole-file dependencies require a coherent accepted
accumulator covering02/03/05 and supplemental01 in each participating repository;
each Step keeps its own acceptance and eventual native commit attribution.
No commit or Phase completion is claimed by this documentary append.

## Phase 6 final acceptance — 2026-10-09

Phase 6 accepts local Book Material editing for ESA6-01/02/03/05: durable originals,
derived recognition proposals, independently editable representative attributes,
photo roles, direct text, local Draft save/reload and List/Detail/Edit navigation.
Core owns storage, settings, provider capability and standard/enhanced processing;
TFAF owns reusable interaction and presentation; App owns Book mapping and flow.
Opaque recognition/presentation context is carried through the common boundaries.

The original ESA6-01 commits and separate ESA6-02/03/05 review histories remain.
The coherent accepted Step commits are Core `5282639`, TFAF `d0d9ab0`, App `59d8468`.
Shared whole-file dependencies are attributed to every included accepted Step;
these are three actual Git events, not invented separate commits for each Step.
The sole comprehensive Phase review passed: `esa6-phase-full-acceptance-20261009@1`,
177 whole target programs and 18 affected programs, no Current Boundary Blockers.
Its single filename transcription correction is retained with the original result.

Final upstream validation used each committed `scripts/validate-full.sh`:
Core complete analyze passed and all 470 tests passed (native terminal `36b4c7`, exit0);
TFAF complete analyze passed and all 485 tests passed (`0ad093`, exit0).
Both ran through registered `cncf_runtime_runner`, GPT-6 Luna / low, exact scoped
escalation for normal Flutter/Dart caches. Console output was truncated; no complete
log is claimed. Retained App focused checks include 611 affected cases, post-repair
128 affected cases, source analysis and native Kotlin 22 cases; overlapping checks
are not summed or represented as an App full suite.

Actual Fold and Sony observations cover photo-role capture, standard recognition,
editable corrections, Save Draft, cold restart and List/Detail/Edit reload. Fold
also covers local Nano comparison; Sony covers unavailable enhanced processing and
explicit standard fallback. Requested and actual configurations remain distinct.
The book was 窯変源氏物語 第7巻, ISBN 9784122025660. Raw inaccurate Nano proposals,
original photos and human corrections are retained separately. These observations
do not establish general recognition accuracy or unobserved physical exceptional
cases; controlled software cases retain their separate evidence.

The five accepted OPEN Hygiene records remain in the App's canonical
`2026-10-06-phase-6-hygiene-follow-up.md`; they are nonblocking follow-up, not fixed
or discarded by release. No Development Candidate was admitted in the full review.
Versions remain App 1.0.0+1, Core/TFAF 0.0.1: no version-update rule or release
coordinate conversion is selected for this local Phase acceptance.

App aggregate full validation is `deferred-not-run`, owned by PHASE-6.1 under the
retained final-only local-driver declaration. Phase 6.1 remains planned and unstarted.
It consumes stable identity/media/persistence, original/derived/human separation and
Book Commit eligibility (`ISBN present OR title present`); incomplete Draft saving
needs neither. Actual Commit, durable enqueue/background transmission, audio and
transcription belong to Phase 6.1. Fixture Reference Workspace is accepted here;
real-server browsing remains the Phase 5 integration line. No push or publication
is performed by this local release. This section records the final release boundary;
the distinct release commit and its verified native closure receipt persist it.

Earlier pending, failed and precommit statements below/above remain dated history.
This final acceptance supersedes their current-status projections without rewriting
their actual observations, test results or repair accounting.
