# ESA6-02-S — Core settings runtime and desired recognition configuration

Current status: Authored; validation and independent acceptance pending.
Owner: textus-flutter-core maintainer, coordinated by the Phase 6 parent.
Update rule: Preserve the migration decision and append parent validation or
independent acceptance evidence when available; do not imply provider/device execution.

## Authored responsibility relocation

Before this migration, generic definitions, registry, snapshot, record, service,
storage, asynchronous controller and local adapters lived in TFAF's
`lib/src/settings/`. Core now owns those reusable contracts and adapters. Core's
`SettingsLifecycleController` owns the same explicit read barrier, intent revisions,
serialized durable write pump, observable failures, unsupported-envelope recovery,
notification and disposal behavior. Its nonempty `resetDefinitions` list is copied
immutably; duplicate IDs and definitions that are not identically registered reject.
`resetCommon()` retains its protocol name and resets exactly the supplied subset.
Other registered values and unknown keys remain intact. A failed/unread record
requires explicit `retryLoad()`; an unsupported integer envelope remains protected
until explicit reset authorizes version recovery. A failed save remains unsaved
until explicit `retrySave()` acknowledges the latest intent.

Wire envelope version1, strict frozen JSON, unknown values and nested envelope
fields remain preserved. Native adapters retain `textus-settings/<namespace>.json`
in application support and flushed temporary-file replacement; browser adapters
retain `textus.settings.<namespace>` localStorage. Construction performs no I/O.
One owner serializes writes for a namespace; no additional cache, lock, migration
or preference copy is introduced. The portable Core barrel exports the generic
runtime; `settings_io.dart` is the explicit public IO adapter entry point.

TFAF's existing import paths re-export the same Core type identities.
`SettingsController({SettingsRegistry? registry, required SettingsStorage storage})`
remains the caller entry point and delegates lifecycle work to Core, requiring the
same three actual CommonSettings definitions. CommonSettings, pane/hinge enums,
text scaling, defaults and reset subset stay owned by TFAF. The legacy IO path
re-exports Core's public IO library. Core has no TFAF dependency.

`RecognitionSettings.configuration` is the independent finite String preference
`textus.capture.recognitionConfiguration`: inherited default `androidStandard`,
optional `pixelEnhanced`. Both choices are always selectable without device/model
checks. SettingsService/SettingsSnapshot remain the authority for validation,
intent, load and durability. Saving enhanced desired intent makes no availability
or model-readiness claim, and a later fallback must preserve the saved choice.
Desired, available and actual configurations are separate concerns; only desired
preference is implemented by this slice.

Later ESA6-02 slices supply common image_picker acquisition plus ML Kit OCR/barcodes
for androidStandard, and standard recognition plus AICore/Gemini Nano interpretation
and candidate organizing for pixelEnhanced. Capability/provider-based presets and
model readiness must drive selection without a hardcoded Pixel branch in
BookCaptureProfile; lens/macro/exposure acquisition is a separate later provider.
Both configurations use one saved original, preserving independent results,
timing, failure and provenance. Original bytes, OCR, enhanced editable candidates
and human correction history remain separate with source lineage. Explicit standard
fallback and TFAF unavailable/preparing/fallback/comparison UI are future scope.
The App maps book fields and confirms/corrects ISBN/title, comparing candidates,
elapsed time and independently changed ISBN/title field count (explicit clearing
counts as a change) against each selected provider proposal. Each configuration
retains its own review branch and correction history. Standard-only devices must
capture/recognize/edit/save; durable settings/results must reload. Physical Pixel
comparison evidence is separate from controllable fake specifications. This slice
claims no camera, ML Kit, AICore, model download or physical-device execution.

## Implemented public usage

```dart
import 'package:textus_flutter_core/textus_flutter_core.dart';

final settings = SettingsLifecycleController(
  registry: RecognitionSettings.registry(),
  storage: createLocalSettingsStorage(namespace: 'example.capture'),
  resetDefinitions: RecognitionSettings.definitions,
);
await settings.load();
final desired = settings.snapshot.value(RecognitionSettings.configuration);
settings.setValue(
  RecognitionSettings.configuration.id,
  RecognitionSettings.pixelEnhanced,
);
// Observe snapshot.saveState, saveError and unsavedIds for acknowledgement.
// resetCommon() resets exactly the constructor's resetDefinitions.
// The owner calls settings.dispose() when the settings lifecycle ends.
```

```dart
import 'package:textus_flutter_application_framework/textus_flutter_application_framework.dart';

final settings = SettingsController(
  registry: CommonSettings.registry(
    extensionGroups: RecognitionSettings.groups,
    extensions: RecognitionSettings.definitions,
  ),
  storage: createLocalSettingsStorage(namespace: 'example.application'),
);
await settings.load();
settings.setValue(
  RecognitionSettings.configuration.id,
  RecognitionSettings.pixelEnhanced,
);
final desired = settings.snapshot.value(RecognitionSettings.configuration);
// resetCommon() resets the three CommonSettings definitions only.
// The owner calls settings.dispose() when the settings lifecycle ends.
```

## Evidence status

Initial settings-foundation implementation and observable executable specifications
are authored. The parent owns dependency resolution, analyzer/selected tests,
affected TFAF/App consumers, independent review and acceptance transitions.
No runtime camera/recognition, physical Pixel comparison, validation, acceptance
commit or Phase completion is claimed. Remaining provider and UI work is later
ESA6-02 slices in the same Step. See [the public note](../../../notes/settings-runtime-and-recognition-configurations.md).
