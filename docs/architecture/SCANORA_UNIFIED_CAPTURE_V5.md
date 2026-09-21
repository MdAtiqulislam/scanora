# Scanora Unified Capture v5

## Architecture

```text
Presentation
  -> CaptureController
  -> CaptureService
  -> CaptureProvider
  -> CaptureSessionResult
  -> M03 AssetStore
  -> DocumentRepository
```

M05 introduces provider-neutral capture intent/results and a testable application orchestration service. `NativeScannerCaptureProvider` is the adapter for `cunning_document_scanner`.

## Provider Contract

`CaptureProvider` exposes:

- `capture(CaptureRequest)`.
- `isAvailable()`.
- `source`.
- `capabilities`.

The contract exposes no Flutter, GetX, scanner plugin, Android, or iOS types.

## Request and Result

`CaptureRequest` currently supports the existing single-page, multi-page, and ID-card intents through `CaptureMode`, plus page limits and multi-page intent.

`CaptureSessionResult` contains ordered provider-neutral `CapturedPage` values and cancellation state. Provider output paths are temporary provider files, not Scanora-owned source-of-truth assets.

## Native Adapter

`NativeScannerCaptureProvider` is the only M05 adapter that imports `cunning_document_scanner`. It maps plugin output into `CapturedPage`, validates file existence/non-empty content, and maps empty results to cancellation.

The native scanner may return provider-cropped/perspective-corrected artifacts. M05 stores those artifacts as the current raw source and does not attempt to reverse or replace the provider’s processing.

## Raw Persistence and Ownership

`CaptureService` validates each provider source, reads it, persists it through M03 `AssetStore.saveRawImage`, then creates ordered page/document metadata through the existing repository facade. Provider temporary files remain provider-owned; canonical `raw.jpg` files are Scanora-owned.

If metadata persistence fails, the newly created document asset tree is removed. Empty and cancelled sessions create no document.

## State and Failure Semantics

The application controller exposes `idle`, `starting`, `capturing`, `persisting`, `completed`, `cancelled`, and `failed` states. Duplicate starts are rejected. Cancellation is represented as a capture failure result using `CaptureCancelledFailure`, without creating an empty document.

Provider failures, invalid captures, and storage failures are mapped to M01 `AppFailure`/`Result` types.

## Multi-page and ID Card Boundaries

M05 preserves provider output order. The generic service persists a multi-page session as one document. Existing ID-card front/back flow remains in its legacy controller path and is not rewritten into a new capture UI or merge algorithm in M05; this is an explicit remaining integration boundary.

## GetX and Legacy Compatibility

GetX remains at the application/presentation boundary. The new `CaptureController` depends on `CaptureService`, not on scanner APIs or filesystem writes. Existing legacy scanner/editor controllers remain operational for compatibility, but their direct plugin imports are identified in the M05 report as incomplete migration work.

## Performance and M06 Boundary

Raw persistence is sequential and does not decode/process image bitmaps. M05 adds no edge detection, geometry, perspective, illumination, shadow, OCR, or rendering algorithm. M06 owns future geometry/capture-engine evolution.
