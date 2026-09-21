# M06 Implementation Report

## 1. Executive Summary

Implemented a plain-Dart geometry engine for normalized document quads, deterministic ordering, validation, pixel conversion, destination sizing, rotation-aware calculations, and homography coefficients.

No image processing, rendering, OpenCV, capture, OCR, PDF, or M07+ functionality was added.

## 2. Existing Geometry Architecture Before M06

M04 provided `Point2D`, `PageCorners`, `PageTransform`, and normalized edit metadata. The existing `PerspectiveService` is Flutter/GetX/image-package coupled and performs legacy pixel warping. M06 does not replace it; the new engine is a provider-independent mathematical boundary for future processors.

## 3. New Geometry Architecture

```text
PageEditState/PageCorners
        ↓
PlainGeometryEngine
        ↓
GeometryResult
  ├── canonical corners
  ├── pixel corners
  ├── destination size
  └── perspective transform
```

## 4. Files Created

- `lib/app/core/errors/geometry_failure.dart`
- `lib/app/domain/geometry/geometry_models.dart`
- `lib/app/domain/contracts/geometry_engine.dart`
- `lib/app/infrastructure/processing/plain_geometry_engine.dart`
- `test/m06_geometry_test.dart`
- `docs/architecture/SCANORA_GEOMETRY_ENGINE_V6.md`
- `docs/reports/M06_IMPLEMENTATION_REPORT.md`

## 5. Files Modified

None outside the new M06 files.

## 6. Geometry Model

Added `PixelSize`, `PixelQuad`, `PerspectiveTransform`, and `GeometryResult`. Existing M04 `Point2D` and `PageCorners` are reused.

## 7. Corner Ordering Strategy

Four arbitrary points are ordered deterministically using minimum/maximum coordinate sums for TL/BR and coordinate difference for TR/BL. The resulting `PageCorners` uses the locked TL/TR/BR/BL representation.

## 8. Validation Strategy

Validation checks finite normalized coordinates, duplicates, convexity, self-intersection, non-zero area, and edge length thresholds. Invalid geometry returns typed failures rather than identity fallback.

## 9. Homography Strategy

The engine builds an 8x8 projective system and solves it with deterministic partial-pivot Gaussian elimination. Singular systems, non-finite values, and unstable coefficients fail safely.

## 10. Destination-Size Strategy

Width uses the larger horizontal edge and height uses the larger vertical edge after pixel conversion. No arbitrary fixed dimensions are introduced.

## 11. Rotation Handling

Rotation is normalized modulo 360 and applied to normalized geometry for calculation only. Raw images remain untouched.

## 12. Numerical Tolerance Strategy

Centralized tolerances are documented in `SCANORA_GEOMETRY_ENGINE_V6.md`: coordinate, area, edge, determinant, and coefficient limits.

## 13. Error Mapping

M06 uses M01 `Result<T>` and adds geometry-specific `AppFailure` subclasses.

## 14. Integration Points

`GeometryEngine` is an additive domain contract. No existing processing implementation was rewritten and no UI/controller dependency was added.

## 15. Backward Compatibility

M01–M05 APIs, database, assets, capture, editor, ID-card, and legacy perspective behavior remain unchanged.

## 16. Test Breakdown

M06 tests: 6 passed.

Covered:

- Identity rectangle.
- Deterministic permutation ordering.
- Mild and strong perspective.
- Rotation metadata.
- Duplicate/concave/degenerate geometry.
- Determinism and dimension calculation.

## 17. Full Regression Result

Final full suite:

```text
Test files: 7
Test cases: 42
Passed: 42
Failed: 0
Skipped: 0
Errors: 0
```

M01 regression: PASS

M02 regression: PASS

M03 regression: PASS

M04 regression: PASS

M05 regression: PASS

M06 tests: PASS

## 18. `flutter analyze` Result

`flutter analyze` reports 7 pre-existing informational diagnostics in legacy files and 0 M06-specific diagnostics.

## 19. Android Build Result

`flutter build apk --debug`: PASS.

Artifact:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

## 20. iOS Build Result

BLOCKED by the pre-existing issue:

```text
```

No deployment target change was made.

## 21. Scope Audit

Verified M06 introduced no OpenCV, FFI, image enhancement, illumination/shadow processing, thresholding, OCR, PDF, scanner UI, camera, cloud, or M07+ functionality.

## 22. Known Limitations

- The existing legacy `PerspectiveService` remains separate and pixel-processing capable; M06 does not replace it.
- No production resampler is implemented.
- Physical-device validation was not performed.
- iOS build remains blocked by the existing deployment target mismatch.

## 23. Acceptance Criteria

| Criterion | Status |
|---|---|
| Geometry contract exists | PASS |
| Core geometry provider-independent | PASS |
| M04 corner representation reused | PASS |
| Deterministic canonical ordering | PASS |
| Convexity validation | PASS |
| Self-intersection validation | PASS |
| Area validation | PASS |
| Edge-length validation | PASS |
| Normalized-to-pixel conversion | PASS |
| Homography calculation | PASS |
| Singular transform detection | PASS |
| Geometry-derived destination dimensions | PASS |
| Rotation metadata respected | PASS |
| Raw assets untouched | PASS |
| Typed invalid geometry failure | PASS |
| No NaN/Infinity escapes | PASS |
| Deterministic identity geometry | PASS |
| Existing capture behavior intact | PASS |
| Existing ID-card flow intact | PASS |
| M01–M05 tests green | PASS |
| Comprehensive M06 tests | PASS |
| No M06-specific analyzer issue | PASS |
| Android debug build | PASS |
| iOS status documented | PASS |
| Documentation created | PASS |
| Report created | PASS |
| No M07+ functionality | PASS |

## 24. Final Verdict

M06 — PASS — LOCKED
