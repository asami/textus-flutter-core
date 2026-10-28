# Source-bound image regions and quotation histories

This reusable Core boundary supports Editing Studio App Phase 6.5, ESA65-02A.
Implementation and authored host specifications do not establish native OCR,
provider readiness, Android recording/reopen qualification, or Step/Phase
acceptance. Those gates remain pending actual validation. Core's existing
Phase 3 SensitiveInteraction history and state are unchanged.

## Frame and exact derivation

`ImageRegionService` accepts an existing `LocalCaptureStore` and
`ImageRecognitionService`; its constructor performs no IO or native work.
`openDefaultImageRegionService` supplies existing ML Kit and Gemini Nano
providers, allows the same caller Nano replacement as the photo service, and
does not acquire a camera image. Availability and preparation remain explicit
forwarding operations. The service rejects overlapping operations and releases
its guard after failures.

Production decoding uses pinned `image: 4.3.0` on Flutter `compute`, with plain
transferable request/result values. Only static, single-frame `image/jpeg` and
`image/png` are supported. Default limits are 33,554,432 encoded bytes and
32,000,000 source pixels; positive caller limits can be supplied. Encoded length
is checked against the retained reference. Decoder header dimensions and frame
count are checked before full raster decoding. Corrupt input fails explicitly;
unsupported formats, animation and resource limits expose `UnsupportedError`
with a manual-route reason, without resizing or rewriting the original.

`loadFrame(source)` returns a trusted immutable `ImageRegionFrame` with defensive
canonical PNG bytes, upright width/height, the original reference and
`frameVersion == 'exifUprightV1'`. image 4.3's JPEG decoder already rotates and
mirrors EXIF and clears orientation. `bakeOrientation` honors only remaining
orientation; it does not invent or apply JPEG orientation twice. Fresh display
and derived rasters carry no original orientation metadata. Original stored
bytes are never resaved.

`ImageRegionGeometry` describes an axis-aligned rectangle or ellipse in finite
normalized source coordinates, inside `[0,1]`, with positive extents. A physical
circle is an ellipse with equal raster-pixel axes; normalized equal axes on a
nonsquare image do not describe a circle. Coordinates are independent of UI
contain-fit, letterbox, pan and zoom transforms, which remain caller concerns.

`boundsFor(pixelWidth: W, pixelHeight: H)` rounds left/top down and right/bottom
up, clamps to the raster, and uses exclusive right/bottom edges. `derive(snapshot)`
re-reads and normalizes the same original and rejects changed frame dimensions.
A rectangle retains all rounded bounding pixels. An ellipse tests each original
frame pixel center using `((px-cx)/rx)^2 + ((py-cy)/ry)^2 <= 1`, replacing outside
pixels with opaque white. No resizing or additional context is added.

The result is saved as a distinct PNG through the same store, with the actual
returned reference, its own length and a capture time at least the snapshot
time. The service validates returned provenance. `ImageRegionDerivation`
retains the exact snapshot, bounds, input and versioned `rectangleBoundsV1` or
`ellipsePixelCenterWhiteV1` mask method. `readDerived` returns the exact retained
input and rejects inconsistent length. Derived input never replaces original
evidence or travels under an original's reference.

Before `derive` returns, it also durably saves the exact existing
`ImageRegionDerivation.toJson()` record in
`ImageRegionService.derivationsCollection == 'image_region_derivations_v1'`,
keyed by the actual derived `input.id`. This retains the complete original
reference, region revision, upright frame dimensions/version, geometry, bounds,
mask method and exact input reference independently of UI or workspace adoption.
Canceled or retired outputs therefore retain their origin after route or process
state is lost. No model or workspace wire fields change.

`findDerivation(inputId)` resolves only that record through the same service busy
guard. For a retained raw comparison, pass `comparison.material.id`; no current
selection is supplied or rebound. A fresh `FileCaptureStore` and service can
resolve the same provenance without reading source or crop bytes, running
recognition, probing readiness or preparing a provider. Input ids follow the
store's safe-token convention. Absence alone returns null. Strict current-key,
frame and mask decoding, stored input-id mismatches, corruption and actual store
errors remain observable; failures release the guard.

PNG storage precedes the provenance write. A metadata write failure makes
`derive` fail and never reports an incomplete derivation as success. The exact
original and already saved crop bytes remain retained; there is no rollback,
deletion or automatic cleanup. A later actual derive creates a fresh input
reference and can succeed after persistence recovers. Workspace adoption is
still an explicit caller action.

## Explicit OCR and human text

```dart
final frame = await regions.loadFrame(source);
final snapshot = ImageRegionSnapshot(
  regionId: 'region1', revision: 1, source: source,
  pixelWidth: frame.pixelWidth, pixelHeight: frame.pixelHeight,
  geometry: ImageRegionGeometry(
    shape: ImageRegionShape.rectangle, x: .1, y: .2, width: .5, height: .3),
  recordedAt: DateTime.now().toUtc(),
);
final derived = await regions.derive(snapshot);
final previewPng = await regions.readDerived(derived);
final extraction = await regions.recognize(derived);
```

The caller presents `previewPng` and original source inspection. Recognition uses
the exact derived bytes and reference with `androidStandard` first and alone by
default. Explicit `supplementWithLocalAi: true` adds the ordered `pixelEnhanced`
route. Existing orchestration retains shared standard work, fallback, unavailable
and failed attempts, completed-empty text, actual providers and raw metadata.
Caller operation context is forwarded unchanged; default intent requests
verbatim visible quotation text and forbids paraphrase. The actual raw comparison
is durably saved through `LocalRecognitionRepository` before extraction returns.
Provider preparation, audio recording and text adoption are never automatic.

Raw `ImageRegionExtraction` is independent of corrected verbatim quotations,
human comments and existing audio transcript reviews. A `RegionTextRevision`
retains exact text including an empty clear. Every quotation requires explicit
`sourceConfirmed: true`, recording a human's source-inspection intent without
claiming proof of semantic correctness. Manual text has no source fields.
OCR/AI text references an extraction with executed matching-kind output for the
same region revision. AI suggestions remain separate raw output. Transcript text
identifies one same-region original audio link and exactly one source: successful
audio report id or a stable retained correction-history index. No correction,
comment or quotation operation overwrites another history or raw report.

## Workspace, append-only retention and codecs

`ImageRegionEntry` freezes contiguous snapshot revisions `1..N` with the same
region id, exact original reference, dimensions and frame version. Revision times
are nondecreasing. Extractions resolve exact snapshots; quotation/comment ids
are unique across both histories, with ordered times and valid source links.
Audio originals are unique within and across entries.

```dart
final next = ImageRegionWorkspace(regions: [
  ImageRegionEntry(snapshots: [snapshot], extractions: [extraction]),
]);
ImageRegionWorkspace.requireRetainedPrefix(previous, next);
next.validateAudioReviews(callerOwnedAudioReviews);
await store.saveDocument('region_workspaces', 'draft',
  ImageRegionWorkspaceCodec.encode(next));
```

The prefix guard rejects deletion, reorder, original rebinding and mutation of
retained snapshots, extraction reports, text or audio links. It uses ordinary
recursive JSON/value comparison, without content/integrity hashes. Appending
valid revisions or entries preserves all previous exact associations.
`validateAudioReviews` resolves each original id against the existing
caller-owned `AudioTranscriptReview`, and checks transcript report/correction
existence and timing. Reviews and audio bytes are not duplicated in workspace
serialization.

`ImageRegionWorkspaceCodec` emits detached maps/lists with exact root keys
`schemaVersion: 1` and `regions`. Every new nested model enforces exact keys and
types; nullable source fields are emitted explicitly. Existing material and raw
recognition codecs retain their strict schemas. Timestamps are canonical UTC ISO
on encode; decoding requires a timezone and rejects invalid dates and calendar
rollover. Malformed current data throws `FormatException`. Future integer schema
versions throw `UnsupportedError` so a caller can preserve opaque draft data and
block namespace editing. Decode errors never become an empty workspace. An
explicit empty constructor is available when the caller determines old-draft
namespace absence.

The App later owns `BookMaterial.extensions.bookRegionAnnotations`, exact photo
and audio-workspace validation and atomic save. Existing
`BookAudioAnnotation.linkedElementId` remains the image element id, while the
generic link supplies region/revision/audio detail. Quotations remain authoritative
in the common workspace; no `MaterialTextElement` mirror or server wire schema
is introduced. TFAF owns reusable selection, preview and editing controls.

The authored Flutter scenarios cover all eight EXIF outcomes with independent
color-block expectations, crop pixels, resource/decode failures, raw OCR routing
and persistence, source/retention checks, exact codecs and file-backed reopen.
Their existence is not an execution receipt or native/provider qualification.

## Shared Step acceptance

ESA65-02 completed its shared host boundary on 2026-10-28 under Editing Studio App Phase 6.5. Independent Step conformance and focused closure accepted the current common contract. Earlier implementation-stage qualifications above remain historical. Book integration, native provider/device qualification, owning full validation and complete Phase acceptance remain separate pending gates. No existing Core/TFAF Phase is reopened or closed by this delivery.
