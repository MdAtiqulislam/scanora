# Scanora Architecture v2.0

## M01 Scope

M01 establishes contracts and boundaries; image-processing algorithms and database migration belong to later milestones. Existing GetX controllers and services remain the runtime path so the current scanning behavior is not rewritten during this foundation milestone.

## Layers

`Presentation -> Application -> Domain` is the intended dependency direction. Infrastructure implements domain contracts and may depend on Flutter plugins and package APIs. Domain contains plain Dart entities, value objects, enums, and contracts; it does not import Flutter, GetX, scanner, database, image, PDF, or OCR packages.

- **Presentation:** existing Flutter module views and widgets.
- **Application:** GetX controllers and future use cases/state. GetX is retained for reactive state, dependency injection, and navigation support.
- **Domain:** `ScanDocument`, `ScanPage`, `PageCorners`, `PageTransform`, `ProcessingProfile`, repository contracts, and subsystem contracts.
- **Infrastructure:** adapters around the existing native scanner, image service, OCR service, PDF service, and filesystem asset operations.
- **Data:** existing legacy models and sqflite repository remain in place until the storage migration milestones.

## CaptureProvider

`CaptureProvider` returns package-independent `CapturedAsset` values and identifies its `CaptureSource`. `NativeScannerCaptureProvider` wraps the current `NativeDocumentScannerService`, while gallery and camera providers establish the same seam without changing the existing scanner UI or camera flow.

## ScanProcessingEngine

`ScanProcessingEngine` accepts a `ProcessingRequest` and returns a `Result<ProcessingOutput>`. Processing stages are represented as an architectural enum only. `LegacyProcessingEngine` bridges the existing image service; M01 does not add OpenCV, new document detection, homography, illumination correction, shadow removal, or adaptive binarization.

## ProcessingProfile

`ProcessingProfile` is a plain Dart value object containing filter type, adjustments, and extensible numeric parameters. It is independent of rendered images and is intended to become the shared source of truth for editor preview and export in later milestones.

## Repositories and Assets

`DocumentRepository` and `AssetStore` define persistence and asset lifecycle responsibilities without exposing `File`, `Directory`, SQLite, or SharedPreferences to domain/application code. `FileAssetStore` is a minimal future-facing adapter; the existing sqflite repository and storage service are deliberately not migrated in M01.

## OCR and PDF

`OcrEngine`/`OcrProvider` and `PdfRenderer` isolate the current Latin OCR and PDF packages. `LegacyOcrEngine` and `LegacyPdfRenderer` adapt existing services. Bengali OCR and searchable PDF are explicitly deferred.

## Errors and Results

`AppFailure` provides a small typed error family for capture, processing, storage, OCR, PDF, and validation failures while retaining an optional original cause and stack trace. `Result<T>` provides an explicit success/failure boundary for new application contracts.

## Future Milestone Boundaries

M02/M03 own storage and database migration. Later processing milestones own real algorithms and WYSIWYG rendering. Later product milestones own folders, tags, favorites, sync, Bengali OCR, searchable PDF, and other product expansion. M01 adds no such functionality.
