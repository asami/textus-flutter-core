# Core source-bound image region implementation

Date: 2026-10-28
Related work: Editing Studio App Phase 6.5 / ESA65-02 / ESA65-02A
Authority: esa65-phase-authority-20261028-001@1;
esa65-core-addition-20261028-001@1
Runtime acceptance: pending parent validation and review

The frozen Core addition introduces generic immutable region geometry,
source-bound snapshots, exact crop provenance, durable raw extraction and
append-only quotation/comment/audio-link histories. Public APIs and the pinned
`image: 4.3.0` dependency are documented in
[the runtime note](../../../notes/page-region-quotation-runtime.md).

The service uses the existing material store and recognition repository, keeps
original JPEG/PNG bytes unchanged, canonicalizes EXIF into `exifUprightV1`, and
saves a distinct PNG for exact rectangle or ellipse processing. Static format,
encoded size and header pixel limits remain explicit observable failures.
Standard OCR runs first; local AI requires an explicit supplement request. Raw
provider output never automatically becomes a human quotation or comment.

Same-Step repair `durable-lineage-repair-001` addresses
`CPB-ESA65-02-PROVENANCE-001`. Every successful derive now saves the complete
existing derivation JSON in `image_region_derivations_v1` under its actual PNG
input id before returning. `findDerivation(rawComparison.material.id)` resolves
the exact original, snapshot/frame/geometry, bounds, mask and input independently
of UI/workspace adoption, including after a fresh file-store/service reopen.
It reads only the selected metadata, validates safe ids and strict provenance,
and returns null only for absence. Store/decode errors propagate and release
the service guard. Original and crop bytes remain retained if metadata storage
fails; the failure propagates without rollback or deletion. Later actual derive
uses a fresh reference. No Core model/workspace wire, operation-context, TFAF or
App change is part of this repair.

Adjacent Given/When/Then specifications additionally cover exact independently
reloadable derivation metadata, lookup without readable material bytes,
absent/unsafe/corrupt/mismatched lookup, metadata IO failure and busy-guard
recovery, failed provenance writes with unchanged retained bytes, fresh derive
recovery, and raw-comparison origin resolution after file-store reopen without
workspace adoption. Existing OCR report-write failure expectations remain.
These authored scenarios await parent validation and independent review.

The workspace has strict versioned detached JSON, validates exact region and
source links, and rejects retained-history deletion, reorder or mutation.
Existing caller-owned audio reviews remain authoritative and are validated by
reference rather than serialized twice. Book namespace persistence and exact
Book photo/audio association belong to the App integration; reusable UI belongs
to TFAF.

Flutter specifications are authored with adjacent Given/When/Then scenarios for
orientation including mirrors, pixel-level crop/masking, unchanged originals,
resource failures, actual recognition orchestration with controlled providers,
durable raw comparisons, guard recovery, append-only histories, strict codecs,
audio report/index resolution and independent file-store reopening.

No test execution or native/provider qualification is recorded here. Host
validation, actual Android OCR/record/reopen evidence and owning workflow gates
remain pending; this entry does not close a Step or Phase. Existing Core Phase 3
SensitiveInteraction history and state are unchanged.

## Shared Step acceptance

ESA65-02 completed its shared host boundary on 2026-10-28 under Editing Studio App Phase 6.5. Independent Step conformance and focused closure accepted the current common contract. Earlier implementation-stage qualifications above remain historical. Book integration, native provider/device qualification, owning full validation and complete Phase acceptance remain separate pending gates. No existing Core/TFAF Phase is reopened or closed by this delivery.
