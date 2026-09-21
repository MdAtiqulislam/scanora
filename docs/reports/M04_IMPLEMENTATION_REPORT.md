# M04 Implementation Report

## 1. Executive Summary

M04 establishes non-destructive page editing metadata and derived-cache identity.

Implemented:

- `PageEditState` domain model.
- Rotation normalization.
- Corner and transform validation.
- Adjustment validation and equality.
- Canonical processing-profile serialization/equality.
- Deterministic cache identity.
- SQLite v3 cache metadata migration.
- Edit-state persistence and reopen behavior.
- Cache invalidation without deleting raw or derived files.
- Minimal editor metadata preservation for corners, rotation, filter, brightness, and contrast.

Not implemented:

- New rendering algorithms.
- OpenCV or geometry processing.
- WYSIWYG rendering.
- OCR/PDF enhancements.
- UI redesign.
- M05 or later milestones.

Final verdict: PASS — LOCKED

## 2. Existing Editor Forensics

The existing editor stores temporary working paths in `EditorPageModel`, uses `quarterTurns` for rotation, applies filters through the existing image service, calls the existing perspective service for crop previews, and writes derived output files. Existing save behavior persisted only limited legacy page metadata and did not persist corners, rotation, adjustments, or cache freshness.

The existing image processing implementation remains unchanged. M04 does not claim its output is WYSIWYG or production render-engine quality.

## 3. Existing Edit-State Forensics

M02 already persisted:

- `corners_json`.
- `rotation_angle`.
- `crop_transform_json`.
- `processing_profile_json`.
- `is_dirty`.

M03 persisted raw/processed/thumbnail paths. M04 reuses these fields and adds only cache identity/version columns.

## 4. Non-Destructive Architecture

```text
raw asset
   +
PageEditState
   ↓
deterministic cache identity
   ↓
optional processed/thumbnail cache
```

Raw bytes remain authoritative. Derived files are disposable caches.

## 5. Edit State Model

`PageEditState` groups existing page concepts without duplicating persistence:

- corners.
- crop transform.
- rotation.
- filter.
- adjustments.
- processing profile.

`ScanPage.editState` provides the grouped view.

## 6. Rotation Semantics

Rotation is metadata, normalized modulo 360. Tested sequence:

```text
0 → 90 → 180 → 270 → 0
```

Negative rotations are normalized as well.

## 7. Crop/Corners Semantics

Corners use normalized `0..1` coordinates, top-left origin, and clockwise named ordering:

```text
topLeft, topRight, bottomRight, bottomLeft
```

Invalid, duplicate, out-of-range, non-finite, and degenerate quads are rejected.

No perspective algorithm was added.

## 8. Adjustment Semantics

Defaults:

```text
brightness = 0
contrast = 1
saturation = 1
```

All values must be finite. Contrast and saturation cannot be negative. Values are metadata only; M04 does not implement adjustment rendering.

## 9. Processing Profile

Profiles use stable filter names, adjustments, and sorted parameter keys for canonical serialization. Profile equality is deterministic and independent of map insertion order.

## 10. Cache Identity

Cache identity includes:

- document ID.
- page ID.
- raw asset identity.
- edit state.
- profile version.

FNV-1a hashing provides deterministic semantic identity without timestamps or randomness.

## 11. Dirty-State Semantics

`isDirty` represents edit-state synchronization status, not file existence. A missing or stale processed cache does not erase edit metadata.

## 12. Persistence Strategy

Database version increased from 2 to 3.

Added columns:

- `processed_cache_key`.
- `thumbnail_cache_key`.
- `edit_state_version`.

The v2-to-v3 migration is additive and preserves existing data.

Edit persistence APIs:

- `getPage`.
- `savePageEditState`.
- `getProcessedCacheStatus`.
- `markProcessedCacheCurrent`.

Saving edit state clears cache keys without deleting processed or raw files.

## 13. Legacy Compatibility

M02 pages with null corners, default transforms, zero rotation, empty profiles, and `isDirty = 0` load safely. Existing legacy asset paths remain unchanged. Existing processed files are not treated as current merely because they exist.

## 14. AssetStore Integration

M04 does not add direct canonical filesystem operations. Repository lifecycle operations continue to use the M03 `AssetStore`. Future renderers can write through M03 and then mark the resulting cache current.

## 15. Raw Immutability

Edit persistence operates on SQLite metadata only. Raw byte equality is tested before and after rotation/edit-state save/cache invalidation.

## 16. Cache Invalidation

Saving a relevant edit state clears `processed_cache_key` and `thumbnail_cache_key`. Existing derived files may remain physically present but are stale until their key matches the current deterministic identity.

## 17. Thumbnail Invalidation

Thumbnail cache identity is separate from processed cache identity. Edit-state save clears the thumbnail key. M04 does not regenerate thumbnails.

## 18. Failure Handling

Invalid states throw typed `ValidationFailure`. Missing pages throw `StorageFailure`. Malformed persisted JSON falls back to documented legacy-safe defaults through the existing mapper.

## 19. Concurrency

The app assumes one active editor per page. No distributed or cloud locking was introduced. Future stale-editor conflict policy remains outside M04.

## 20. Performance

Edit changes are metadata-only and do not decode images or start new processing jobs. Existing preview processing remains unchanged.

## 21. Tests

M04 tests cover:

- rotation normalization.
- negative rotation.
- corner validation.
- transform validation.
- adjustment validation.
- edit-state equality.
- cache-key determinism and invalidation.
- v3 persistence and reopen.
- raw byte immutability.
- missing-page failure.
- malformed-profile compatibility.
- processed cache missing/stale/current states.
- thumbnail cache missing/stale/current states.
- cache restoration after returning to a prior edit state.
- raw identity changes.
- document/page cache isolation.
- profile parameter insertion-order independence.

Final full suite:

```text
Test files: 4
Test cases: 32
Passed: 32
Failed: 0
Skipped: 0
Errors: 0
```

## 22. Regression Verification

Automated M01, M02, M03, and M04 tests pass. Existing image-processing tests pass. Physical-device editor verification was not available.

## 23. Static Analysis

Command:

```text
flutter analyze
```

Result:

```text
No issues found!
```

## 24. Android Build

Command:

```text
flutter build apk --debug
```

Result:

```text
✓ Built build/app/outputs/flutter-apk/app-debug.apk
```

Status: PASS.

## 25. iOS Build

The known existing blocker remains:

```text
google_mlkit_commons requires iOS 15.5
project targets iOS 13.0
```

No platform configuration was changed.

## 26. Dependencies

No production dependency was added. Existing M02 `sqflite_common_ffi` test infrastructure was reused.

## 27. Files Created

- `lib/app/domain/value_objects/page_edit_state.dart`
- `test/m04_editing_test.dart`
- `docs/architecture/SCANORA_NON_DESTRUCTIVE_EDITING_V4.md`
- `docs/reports/M04_IMPLEMENTATION_REPORT.md`

## 28. Files Modified

- `lib/app/core/errors/app_failure.dart`
- `lib/app/domain/value_objects/page_corners.dart`
- `lib/app/domain/value_objects/page_transform.dart`
- `lib/app/domain/value_objects/processing_adjustments.dart`
- `lib/app/domain/value_objects/processing_profile.dart`
- `lib/app/domain/entities/scan_page.dart`
- `lib/app/data/datasources/scanora_database.dart`
- `lib/app/data/models/scan_document_db_mapper.dart`
- `lib/app/data/models/scanned_page.dart`
- `lib/app/data/repositories/sqlite_document_repository_v2.dart`
- `lib/app/data/repositories/document_repository.dart`
- `lib/app/modules/editor/controllers/editor_controller.dart`

## 29. M04 Acceptance Criteria

| Criterion | Status |
|---|---|
| AC-01 Raw immutable source of truth | PASS |
| AC-02 Domain edit state exists | PASS |
| AC-03 Metadata-driven rotation | PASS |
| AC-04 Deterministic rotation normalization | PASS |
| AC-05 Metadata-driven crop state | PASS |
| AC-06 Corner coordinate convention documented | PASS |
| AC-07 Invalid/degenerate corners rejected | PASS |
| AC-08 Stable filter identity | PASS |
| AC-09 Non-destructive adjustments represented | PASS |
| AC-10 Adjustment defaults/ranges documented and validated | PASS |
| AC-11 Deterministic serializable profile | PASS |
| AC-12 Deterministic edit equality | PASS |
| AC-13 Processed image treated as cache | PASS |
| AC-14 Deterministic cache identity | PASS |
| AC-15 Relevant edits invalidate cache identity | PASS |
| AC-16 Same source/state gives same key | PASS |
| AC-17 Different state gives different key | PASS |
| AC-18 Dirty semantics documented | PASS |
| AC-19 State survives database reopen | PASS |
| AC-20 Legacy M02 pages load safely | PASS |
| AC-21 Legacy paths untouched | PASS |
| AC-22 Raw remains byte-identical | PASS |
| AC-23 Cache invalidation preserves raw | PASS |
| AC-24 Thumbnail invalidation defined | PASS |
| AC-25 M03 AssetStore boundary preserved | PASS |
| AC-26 Sibling pages isolated | PASS |
| AC-27 Other documents isolated | PASS |
| AC-28 Persistence failures typed | PASS |
| AC-29 Invalid states cannot be silently committed | PASS |
| AC-30 No new image-processing algorithm | PASS |
| AC-31 No M05+ functionality | PASS |
| AC-32 Domain tests pass | PASS |
| AC-33 Persistence integration tests pass | PASS |
| AC-34 Raw immutability tests pass | PASS |
| AC-35 Cache invalidation tests pass | PASS |
| AC-36 Legacy compatibility tests pass | PASS |
| AC-37 Failure-path tests pass | PASS |
| AC-38 `flutter test` | PASS |
| AC-39 `flutter analyze` | PASS |
| AC-40 Android debug build | PASS |
| AC-41 Architecture documentation | PASS |
| AC-42 Implementation report | PASS |

## 30. Known Issues

- iOS remains blocked by the pre-existing ML Kit deployment target mismatch.
- Existing editor preview still uses legacy temporary image processing; M04 does not claim WYSIWYG behavior.
- Existing PDF cache is not automatically marked stale by page edits; this remains a later export lifecycle concern.
- Physical-device editor testing was unavailable.

## 31. Final Verdict

PASS — LOCKED

## Verification Mapping

| Invariant | Verification | Status |
|---|---|---|
| M04-CACHE-01 | Processed asset missing returns `CacheStatus.missing` | PASS |
| M04-CACHE-02 | Existing processed asset with null key returns `stale` | PASS |
| M04-CACHE-03 | Existing processed asset with mismatched key returns `stale` | PASS |
| M04-CACHE-04 | Existing processed asset with matching key returns `current` | PASS |
| M04-CACHE-05 | Raw identity change changes deterministic key | PASS |
| M04-CACHE-06 | Thumbnail freshness uses existence plus matching identity | PASS |
| M04-CACHE-07 | Returning to prior state restores prior cache identity | PASS |
| M04-STATE-01 | Edit identity changes invalidate cache freshness | PASS |
| M04-STATE-02 | Clean metadata can remain stale | PASS |
| M04-STATE-03 | Cache markers survive database reopen | PASS |
| M04-RAW-01 | Raw bytes remain unchanged after metadata/cache operations | PASS |
| M04-ISO-01 | Page edits do not affect sibling page state | PASS |
| M04-ISO-02 | Document identity participates in cache identity | PASS |
| M04-JSON-01 | Missing legacy metadata uses safe defaults | PASS |
| M04-JSON-02 | Malformed profile data raises typed storage failure | PASS |
| M04-JSON-03 | Unknown persisted filter raises typed storage failure | PASS |
