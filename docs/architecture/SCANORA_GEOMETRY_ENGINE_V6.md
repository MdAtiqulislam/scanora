# Scanora Geometry Engine v6

## Purpose and Position

M06 provides a provider-independent, plain-Dart geometry boundary between edit metadata and future processing engines. It calculates validated quadrilateral geometry, destination size, and homography coefficients. It does not render images.

## Coordinate System

- Origin is top-left.
- X increases right; Y increases down.
- `PageCorners` use normalized coordinates in `[0, 1]`.
- Pixel conversion occurs once at the geometry boundary using source dimensions.
- Canonical order is `topLeft`, `topRight`, `bottomRight`, `bottomLeft`.

## Ordering and Validation

Arbitrary four-point inputs are deterministically ordered using coordinate sums/differences. Geometry validation rejects non-finite/out-of-range points, duplicates, degenerate edges, non-convex quads, self-intersections, and insufficient area.

Tolerances are centralized:

```text
coordinate = 1e-9
area = 1e-8 normalized units
edge = 1e-7 normalized units
determinant = 1e-12
coefficient = 1e12
```

## Homography

The engine solves the eight-unknown projective mapping with deterministic Gaussian elimination and appends the normalized ninth coefficient. Singular systems and non-finite/unstable coefficients return typed `PerspectiveTransformFailure` results.

## Destination Size

Destination width is the maximum of top/bottom pixel edge lengths. Destination height is the maximum of left/right pixel edge lengths. No fixed output size or image downscaling is applied.

## Rotation

M04 rotation metadata is normalized modulo 360 and applied to geometry coordinates for the calculation only. Raw assets and edit metadata are not mutated.

## Failure Handling

Geometry errors use M01 `Result<T>` with `InvalidGeometryFailure`, `DegenerateQuadrilateralFailure`, and `PerspectiveTransformFailure`.

## Scope Boundary

M06 does not use OpenCV/FFI/GPU, detect documents, render pixels, enhance images, process OCR/PDF, modify capture, or replace the existing legacy `PerspectiveService`. Those responsibilities belong to later milestones or existing compatibility paths.
