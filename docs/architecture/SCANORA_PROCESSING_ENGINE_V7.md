# Scanora Processing Engine v7

## Architecture

```text
ProcessingRequest
  -> M07ProcessingEngine
  -> AssetStore raw load
  -> input/profile validation
  -> M06 GeometryEngine
  -> deterministic ProcessingPlan
  -> derived AssetStore writes
```

The engine is plain Dart/provider-independent. It does not import GetX, Flutter widgets, SQLite, scanner, OCR, or PDF packages.

## Contracts and Context

`ProcessingEngine` accepts a provider-neutral `ProcessingRequest` containing document/page identity, raw identity, source dimensions, edit-state snapshot, force flag, and thumbnail specification. `ProcessingResult` returns derived paths and a deterministic plan. `PageEditStateSnapshot` keeps per-request state immutable by convention.

## Stage and Profile Boundary

M07 resolves only the safe original/base profile. Non-original filters return `UnsupportedProcessingProfileFailure`; M08–M10 provide future enhancement stages. The pipeline boundary is raw load, validation, profile resolution, geometry, derived output, and persistence.

## Geometry

M07 reuses the M06 `GeometryEngine` and `GeometryResult`. It does not duplicate ordering, validation, homography, or destination sizing.

## Cache Identity and Versioning

The engine version is centralized as `M07-v1`. Cache identity includes engine version, document/page identity, raw asset identity, canonical edit state, geometry coefficients, and thumbnail specification. It contains no timestamps or random values.

## Resource and Failure Semantics

The engine loads one raw asset per request, processes sequentially, writes processed and thumbnail assets through M03 `AssetStore`, and does not retain decoded bitmap state. Raw bytes are never written by M07. Cancellation is checked at safe boundaries. Unsupported profiles, missing raw assets, geometry failures, and persistence failures return typed `Result` failures.

M07 does not mark database cache metadata current directly; that remains the repository/cache metadata boundary established by M04. A later renderer can mark a successfully persisted matching cache current.

## Explicit Scope Boundary

M07 does not implement illumination normalization, shadow removal, adaptive thresholding, professional B&W, morphology, OCR, PDF, WYSIWYG, OpenCV, FFI, GPU, camera, or cloud behavior.
