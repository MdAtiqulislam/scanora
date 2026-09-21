# M05 Implementation Report

## 1. Executive Summary

M05 introduces a provider-neutral capture contract, native scanner adapter, capture orchestration service, lifecycle controller, and raw persistence boundary through M03 `AssetStore`.

The new service is independently testable with fake providers and preserves provider page order. It maps cancellation and provider errors into Scanora results, persists provider output as canonical raw assets, creates document/page metadata, and cleans newly created assets on repository failure.

M05 is locked after migrating active native scanner acquisition in `ScannerController`, `HomeController`, and `EditorController` behind `CaptureService`. The existing ID-card front/back sequence is preserved and both acquisitions use the same service.

## 2. Existing Capture Forensics

Before integration, direct `cunning_document_scanner` use existed in:

- `lib/app/modules/scanner/controllers/scanner_controller.dart`
- `lib/app/modules/home/controllers/home_controller.dart`
- `lib/app/modules/editor/controllers/editor_controller.dart`
- `lib/app/core/services/native_document_scanner_service.dart` (removed after migration)

The scanner returns `List<String>` paths. The scanner controller opens the editor with those paths, while the editor later performs existing processing and saves legacy metadata. ID-card flow captures front/back separately and uses the existing merge controller.

## 3. Current Native Scanner Behavior

The native scanner uses `CunningDocumentScanner.getPictures`. It may return provider-cropped/perspective-corrected images. M05 treats these outputs as provider capture artifacts and stores their bytes as Scanora raw assets without attempting to undo provider behavior.

Empty/null output is treated as cancellation. Plugin exceptions are mapped to `CaptureProviderFailure` by the new adapter.

## 4. Capture Architecture

```text
CaptureController
  -> CaptureService
  -> CaptureProvider
  -> CapturedPage/CaptureSessionResult
  -> AssetStore.saveRawImage
  -> DocumentRepository.saveDocument
```

## 5. CaptureProvider Contract

The domain contract includes:

- `capture(CaptureRequest)`.
- `isAvailable()`.
- `CaptureSource`.
- `CaptureProviderCapabilities`.

No provider-specific types leak upward.

## 6. CaptureRequest

`CaptureRequest` contains the current intent fields:

- `CaptureMode`.
- `maxPages`.
- `allowMultiple`.

No speculative modes or configuration framework was added.

## 7. CaptureResult

`CaptureSessionResult` contains ordered `CapturedPage` values, cancellation state, source, and optional dimensions/rotation fields.

## 8. Provider Capabilities

The capability model exposes only current application-relevant concepts:

- document detection.
- multi-page.
- flash.
- ID card.
- manual capture.

## 9. NativeScannerCaptureProvider

The adapter is the only new M05 class importing `cunning_document_scanner`. It validates returned paths and produces provider-neutral results.

## 10. CaptureService

`CaptureService`:

1. Rejects duplicate active sessions.
2. Calls the provider.
3. Treats cancelled/empty sessions as no-document results.
4. Validates source existence and non-zero length.
5. Persists each source sequentially through M03 `AssetStore.saveRawImage`.
6. Preserves provider ordering.
7. Creates one document with ordered pages.
8. Cleans the newly created canonical document asset tree if repository persistence fails.

## 11. Raw Asset Persistence

Provider temporary files are read and copied into canonical M03 raw assets. The service never writes directly to canonical paths and never processes a provider source before raw persistence.

## 12. Temporary File Ownership

Provider-returned paths are temporary/provider-owned inputs. M05 does not delete them because ownership is not guaranteed by the current plugin contract. M03 canonical `raw.jpg` files are Scanora-owned.

## 13. Capture State Machine

The controller exposes:

```text
idle → capturing → completed
idle → capturing → cancelled
idle → capturing → failed
```

`persisting` is part of the documented lifecycle but currently internal to `CaptureService`.

## 14. Cancellation

Null/empty native output and explicit fake cancellation produce `CaptureCancelledFailure`. No empty document is created.

## 15. Multi-Page Semantics

The service persists all provider pages in returned order as one logical document. Persistence is sequential for bounded memory use.

## 16. Partial Failure Policy

The logical capture operation is atomic at the application boundary: if raw persistence or database persistence fails, the service attempts to delete the newly created canonical document asset tree and returns a typed failure. Existing documents are not modified.

## 17. ID Card Compatibility

Existing ID-card merge/handling behavior remains unchanged, but both front and back scanner acquisitions now use `CaptureService`.

## 18. Error Mapping

Mapped failures include:

- `CaptureCancelledFailure`.
- `CaptureProviderFailure`.
- `InvalidCaptureFailure`.
- `StorageFailure`.

## 19. DB/Filesystem Consistency

Raw asset writes occur before repository metadata persistence. Repository failure triggers cleanup of the new document asset tree. Cleanup failure is surfaced by the asset store and remains detectable by M03 integrity tooling.

## 20. GetX Integration

`CaptureController` uses GetX only for lifecycle state and dependency injection. It does not import scanner plugins, write files, or write SQLite rows.

## 21. Legacy Compatibility

Existing legacy documents and asset paths are untouched. All active native scanner acquisition paths now route through `CaptureService -> CaptureProvider -> NativeScannerCaptureProvider`.

## 22. Performance

Raw persistence is sequential. No full-resolution bitmap decoding, processing, or unbounded page concurrency was added.

## 23. Tests

M05 tests cover:

- Provider-neutral fake provider.
- Single/multi-page ordered persistence.
- Cancellation/empty result.
- Provider failure.
- Duplicate-start service guard.
- Database failure cleanup.

Final full suite result:

```text
Test files: 5
Test cases: 36
Passed: 36
Failed: 0
Skipped: 0
Errors: 0
```

## 24. Regression Verification

M01, M02, M03, and M04 tests pass as part of the full suite. Physical-device scanner verification was not available.

## 25. Static Analysis

`flutter analyze` reports 7 pre-existing informational lint diagnostics in legacy files and 0 M05-specific diagnostics.

## 26. Android Build

`flutter build apk --debug` succeeds:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

## 27. iOS Build

Still blocked by the pre-existing configuration:

```text
google_mlkit_commons requires iOS 15.5
project targets iOS 13.0
```

## 28. Dependencies

No dependency was added or upgraded.

## 29. Files Created

- `lib/app/application/services/capture_service.dart`
- `lib/app/application/controllers/capture_controller.dart`
- `test/m05_capture_test.dart`
- `docs/architecture/SCANORA_UNIFIED_CAPTURE_V5.md`
- `docs/reports/M05_IMPLEMENTATION_REPORT.md`

## 30. Files Modified

- `lib/app/domain/contracts/capture_provider.dart`
- `lib/app/core/errors/app_failure.dart`
- `lib/app/infrastructure/capture/native_scanner_capture_provider.dart`
- `lib/app/infrastructure/capture/camera_capture_provider.dart`
- `lib/main.dart`

## 31. Acceptance Criteria

| ID | Status | Evidence |
|---|---|---|
| AC-01 | PASS | Provider-neutral `CaptureProvider` exists |
| AC-02 | PASS | Direct plugin audit leaves only `NativeScannerCaptureProvider` |
| AC-03 | PASS | Native provider adapter exists |
| AC-04 | PASS | `CaptureRequest` |
| AC-05 | PASS | `CaptureSessionResult` and `CapturedPage` |
| AC-06 | PASS | Capability model |
| AC-07 | PASS | New application contract has no plugin types |
| AC-08 | PASS | Temporary provider paths distinguished from canonical raw paths |
| AC-09 | PASS | `CaptureService` uses M03 `AssetStore` |
| AC-10 | PASS | Raw is copied before metadata persistence; no raw overwrite |
| AC-11 | PASS | Fake single-page path through service |
| AC-12 | PASS | Fake multi-page path |
| AC-13 | PASS | Provider order preserved |
| AC-14 | PASS | Empty capture creates no document |
| AC-15 | PASS | Cancellation creates no document |
| AC-16 | PASS | Provider failures mapped to `AppFailure` |
| AC-17 | PASS | Storage failures returned |
| AC-18 | PASS | Repository failures returned |
| AC-19 | PASS | New asset tree cleanup attempted |
| AC-20 | PASS | Atomic partial-failure policy documented |
| AC-21 | PASS | Existing ID-card front/back acquisition uses `CaptureService`; merge behavior unchanged |
| AC-22 | PASS | Legacy documents untouched |
| AC-23 | PASS | New service uses canonical AssetStore paths |
| AC-24 | PASS | No image algorithm added |
| AC-25 | PASS | No M06+ functionality |
| AC-26 | PASS | Fake provider accepted by CaptureService |
| AC-27 | PASS | Fake provider tests exist |
| AC-28 | PASS | Asset/DB cleanup test exists |
| AC-29 | PASS | Multi-page test exists |
| AC-30 | PASS | Active-session guard exists |
| AC-31 | PASS | Lifecycle documented |
| AC-32 | PASS | GetX controller is application boundary |
| AC-33 | PASS | Domain contract is plugin-independent |
| AC-34 | PASS | Sequential raw persistence |
| AC-35 | PASS | `flutter test` |
| AC-36 | PASS | 0 M05-specific diagnostics; 7 pre-existing informational diagnostics documented |
| AC-37 | PASS | Android APK builds |
| AC-38 | PASS | Architecture document exists |
| AC-39 | PASS | Implementation report exists |
| AC-40 | PASS | M01–M04 regression tests pass |

## 32. Known Issues

- Native scanner temporary-file cleanup is not performed because plugin ownership semantics are not exposed.
- Physical-device capture testing was unavailable.
- iOS remains blocked by the pre-existing deployment-target mismatch.

## M05 Final Verification

### Direct Plugin Usage Before

Direct usage was found in the scanner, home, and editor controllers and in `NativeDocumentScannerService`.

### Migration Performed

- Scanner document/passport acquisition uses `CaptureService.acquire`.
- Scanner ID-card front and back acquisition uses `CaptureService.acquire`.
- Home document/passport acquisition uses `CaptureService.acquire`.
- Home ID-card front and back acquisition uses `CaptureService.acquire`.
- Editor add-page native acquisition uses `CaptureService.acquire`.
- Existing navigation, editor, and ID-card merge behavior remains unchanged.
- Redundant `NativeDocumentScannerService` was removed.

### Direct Plugin Usage After

The only executable plugin usage remaining is:

```text
lib/app/infrastructure/capture/native_scanner_capture_provider.dart
```

The remaining scanner-controller match is a comment only.

### ID-Card Integration

```text
front capture -> CaptureService -> CaptureProvider -> NativeScannerCaptureProvider
back capture  -> CaptureService -> CaptureProvider -> NativeScannerCaptureProvider
existing merge/handling behavior
```

No new ID-card algorithm or UI was added.

### Speculative Providers

The unused `gallery_capture_provider.dart` implementation was removed because M05 does not add gallery-import functionality. `camera_capture_provider.dart` remains as a minimal unavailable-provider contract placeholder for future extensibility; it does not capture images or introduce camera UI.

### Tests

```text
flutter test: 36 passed, 0 failed, 0 skipped, 0 errors
```

### Analyze

```text
M05-specific issues: 0
Pre-existing informational issues: 7
```

### Android

```text
PASS
```

### iOS

```text
BLOCKED
```

Existing blocker: ML Kit requires iOS 15.5 while the project targets iOS 13.0.

### M01–M04 Regression

```text
M01 PASS
M02 PASS
M03 PASS
M04 PASS
```

### Final Integration Verdict

PASS — LOCKED
