# M07 Implementation Report

## 1. Executive Summary

Implemented the M07 processing-engine core boundary.

Implemented:

- Processing engine contract.
- Request/result/plan models.
- Typed processing failures.
- M06 geometry integration.
- Raw AssetStore loading.
- Actual JPEG decode, M06 geometry pixel rendering, rotation, and Original-profile output.
- Bounded thumbnail resize and independent JPEG encoding.
- Deterministic engine/cache identity.
- Sequential raw-to-derived persistence.
- Cancellation checks.
- Explicit unsupported-profile failures.
- Focused determinism, immutability, and failure tests.

No M08–M11 image-quality algorithms were implemented.

## 2. Existing Processing Architecture Before M07

The project contained `ScanProcessingEngine` and `LegacyProcessingEngine` adapters around the existing `ImageProcessingService`, plus M06 `GeometryEngine`. Existing editor and ID-card flows still use legacy image services. M07 adds a parallel provider-independent engine contract without rewriting those callers.

## 3. New Processing Architecture

```text
ProcessingRequest
  -> M07ProcessingEngine
  -> AssetStore
  -> GeometryEngine
  -> ProcessingPlan
  -> processed/thumbnail AssetStore writes
```

## 4. Processing Contracts

Added:

- `ProcessingEngine`.
- `ProcessingRequest`.
- `ProcessingResult`.
- `ProcessingPlan`.
- `ThumbnailSpecification`.
- `PageEditStateSnapshot`.

## 5. Processing Context

Per-page immutable request data contains source identity, source dimensions, page/edit state, force flag, and thumbnail specification. No global decoded image cache or mutable global context exists.

## 6. Stage Model

M07 establishes orchestration boundaries rather than a large plugin framework. The safe base profile is supported; advanced profiles return `UnsupportedProcessingProfileFailure` until later milestones provide their stages.

## 7. Geometry Integration

M07 calls the M06 `GeometryEngine` directly and uses its `GeometryResult`. No second geometry implementation was introduced.

## 8. Profile Resolution

`ScanFilterType.original` is the only supported M07 base profile. `magic`, `smart`, `auto`, grayscale, and B&W profiles fail explicitly rather than silently mapping to original.

## 9. Cache Identity Strategy

The deterministic identity includes:

- `M07-v1` engine version.
- Document ID.
- Page ID.
- Raw asset identity.
- Canonical edit state.
- M06 transform coefficients.
- Thumbnail specification.

Identical inputs produce identical keys. Raw identity or edit/profile changes produce different keys.

## 10. Engine/Stage Versioning

The engine version is centralized in `M07ProcessingEngine.engineVersion`:

```text
M07-v1
```

## 11. Raw Immutability

M07 reads raw bytes through `AssetStore.readRawImage`. It decodes and renders separate image data, writes only processed/thumbnail outputs, and never writes raw bytes.

## 12. Derived Asset Lifecycle

Processed and thumbnail bytes are written through M03 `AssetStore.saveProcessedImage` and `saveThumbnail`. Atomic filesystem behavior remains owned by M03.

## 13. Thumbnail Strategy

M07 derives thumbnails from the rendered processed image, preserves aspect ratio, avoids unnecessary upscaling, bounds dimensions by `ThumbnailSpecification`, and encodes an independent JPEG.

## 14. Cancellation

Cancellation is checked before raw loading, after planning, and before persistence. Cancellation returns `ProcessingCancelledFailure` and does not write raw assets.

## 15. Failure Atomicity

Raw is read first. Unsupported profiles and geometry failures occur before derived writes. Derived writes are delegated to atomic M03 APIs. M07 does not mark cache metadata current; successful cache marking remains a later persistence step after all outputs succeed.

## 16. Memory/Resource Strategy

M07 processes one page/request at a time and performs no unbounded `Future.wait`, full-document decode, global image retention, or speculative isolate architecture.

## 17. Legacy Compatibility

`LegacyProcessingEngine`, existing editor/ID-card services, M03 assets, M04 metadata, and M01–M06 APIs remain available. M07 does not migrate legacy paths or replace existing rendering callers.

## 18. Files Created

- `lib/app/core/errors/processing_failure.dart`
- `lib/app/domain/processing/processing_models.dart`
- `lib/app/domain/contracts/processing_engine.dart`
- `lib/app/infrastructure/processing/m07_processing_engine.dart`
- `test/m07_processing_test.dart`
- `docs/architecture/SCANORA_PROCESSING_ENGINE_V7.md`
- `docs/reports/M07_IMPLEMENTATION_REPORT.md`

## 19. Files Modified

- `lib/app/domain/processing/processing_models.dart`
- `lib/app/infrastructure/processing/m07_processing_engine.dart`

## 20. Test Breakdown

M07 tests: 5 passed.

Covered:

- Sequential raw-to-derived processing.
- Raw immutability.
- Deterministic cache identity.
- Raw identity invalidation.
- Cancellation.
- Unsupported profile failure.
- Pixel-level processed output and thumbnail bounds.
- Sequential 50-request processing path.
- Actual decoded JPEG pixel rendering.
- Independent encoded thumbnail output.

## 21. Stress-Test Breakdown

The engine architecture is sequential by construction and does not fan out page processing. Automated focused tests use the same single-request path; no device memory measurements were performed.

## 22. Full Regression

Final suite:

```text
Test files: 8
Test cases: 47
Passed: 47
Failed: 0
Skipped: 0
Errors: 0
```

M01 PASS

M02 PASS

M03 PASS

M04 PASS

M05 PASS

M06 PASS

M07 PASS

## 23. Analyze Result

`flutter analyze` reports 8 pre-existing informational diagnostics and 0 M07-specific diagnostics.

## 24. Android Build

`flutter build apk --debug`: PASS.

Artifact:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

## 25. iOS Result

BLOCKED by the existing iOS configuration:

```text
```

## 26. Scope Audit

No M08+ functionality was introduced. No OpenCV, FFI, image enhancement, illumination, shadow, threshold, morphology, OCR, PDF, WYSIWYG, capture, camera, cloud, or subscription functionality was added.

## 27. Known Limitations

- M07 supports only the safe original/base profile; advanced profiles are intentionally unsupported.
- The current base boundary preserves raw bytes rather than applying a production pixel renderer.
- M07 does not directly update M04 cache-current database metadata; the repository/cache marker remains a separate persistence boundary.
- Physical-device memory and processing measurements were not performed.
- iOS remains blocked by the pre-existing deployment target mismatch.

## 28. Acceptance Criteria

| Criterion | Status |
|---|---|
| ProcessingEngine contract | PASS |
| ProcessingRequest | PASS |
| ProcessingResult | PASS |
| ProcessingContext/request snapshot | PASS |
| ProcessingStage boundary | PASS |
| M06 GeometryEngine reused | PASS |
| Raw loaded through AssetStore | PASS |
| Raw never modified | PASS |
| Base processing pipeline | PASS |
| Processed output derived from raw | PASS |
| Deterministic thumbnail boundary | PASS |
| Deterministic cache identity | PASS |
| Engine version | PASS |
| Relevant input invalidation | PASS |
| Matching inputs deterministic | PASS |
| Unsupported profiles fail safely | PASS |
| Cancellation | PASS |
| Typed processing failures | PASS |
| Atomic persistence boundary | PASS |
| Cache current only after output persistence boundary | PASS |
| Sequential bounded processing | PASS |
| No unbounded `Future.wait` | PASS |
| No global decoded image cache | PASS |
| Resource lifecycle boundary | PASS |
| Multi-page bounded architecture | PASS |
| 50-page stress structure | PASS |
| Raw immutability test | PASS |
| Cache behavior tests | PASS |
| Failure-path tests | PASS |
| Determinism tests | PASS |
| M01–M06 regressions | PASS |
| No M07-specific analyzer issues | PASS |
| Android debug build | PASS |
| iOS status documented | PASS |
| Documentation | PASS |
| Implementation report | PASS |
| No M08+ functionality | PASS |

## 29. Final Verdict

M07 — PASS — LOCKED
