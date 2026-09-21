# Scanora M03 Implementation Report

## 1. Executive Summary

M03 establishes the canonical asset storage and lifecycle subsystem for raw, processed, and thumbnail assets.

Implemented:

- Deterministic document/page path resolver.
- Strict identifier validation.
- Application-documents asset root.
- Atomic byte writes.
- Typed asset reads and missing-asset failures.
- Scoped and idempotent page/document deletion.
- Integrity scanner for orphan, missing, and unknown managed assets.
- v2 repository integration for canonical asset deletion.
- Canonical path persistence through existing v2 page metadata.
- Filesystem and SQLite synchronization tests.

Not implemented:

- Legacy file relocation.
- Orphan automatic cleanup.
- M04 editor behavior.
- New image processing.
- OCR/PDF feature changes.
- UI redesign.

Final verdict: PASS — LOCKED

## 2. Existing Asset Forensics

The existing application creates legacy timestamped files through `FileUtils.createTimestampedFilePath`, using the application documents directory and names such as `scan_...jpg`, `proc_...jpg`, `id_front_...jpg`, and generated PDFs. Controllers and services also directly use `File`, `copy`, `writeAsBytes`, and `delete`.

Existing M02 database paths are legacy paths such as `imagePath`, `rawImagePath`, and `pdfPath`. Existing editor, scanner, ID card, OCR, PDF, and presentation code consumes those paths directly.

M03 does not rewrite these flows or move existing files.

## 3. Asset Architecture

```text
Application/repository
        ↓
AssetStore contract
        ↓
FileSystemAssetStore
        ↓
application documents/scanora-assets/documents
```

The domain contract contains no filesystem, Flutter, GetX, or plugin imports.

## 4. Path Strategy

`DocumentAssetPathResolver` centralizes:

- Document directory.
- Pages directory.
- Page directory.
- Raw path.
- Processed path.
- Thumbnail path.
- Exports directory.

Canonical names are deterministic:

```text
raw.jpg
processed.jpg
thumbnail.jpg
```

## 5. Identifier Safety

Rejected identifiers include:

- Empty strings.
- Whitespace-only strings.
- `.` and `..`.
- Values containing `/` or `\\`.
- Absolute paths.
- Values containing `..`.

Failures use `InvalidAssetIdentifierFailure`.

## 6. Directory Lifecycle

Document storage creates:

```text
documents/{documentId}/
documents/{documentId}/pages/
```

Page storage creates:

```text

Creation is lazy, recursive, and idempotent.

## 7. Atomic Write Strategy

Asset bytes are written to a unique temporary sibling file with `flush: true`, then renamed to the final path. Temporary files are removed after failures. Raw, processed, and thumbnail destinations are separate.

## 8. Raw Asset Lifecycle

Raw assets use `raw.jpg`. They are independently written, read, and deleted. Processed and thumbnail writes never target or delete raw assets.

## 9. Processed Asset Lifecycle

Processed assets use `processed.jpg`. They can be replaced or deleted independently while preserving raw and thumbnail assets.

## 10. Thumbnail Lifecycle

Thumbnail assets use `thumbnail.jpg`. They can be replaced or deleted independently while preserving raw and processed assets.

## 11. Database/Filesystem Consistency Strategy

M03 does not claim a cross-system transaction between SQLite and the filesystem.

For repository deletion, the chosen order is:

1. Delete owned canonical assets.
2. Delete database metadata.

This avoids knowingly leaving canonical assets after successful metadata deletion. If metadata deletion fails after asset deletion, the operation returns a failure and the database remains retryable; the integrity scanner reports missing referenced assets.

New canonical paths are supplied to the v2 domain page and persisted by `SqliteDocumentRepositoryV2.save`. Existing legacy paths are not rewritten.

## 12. Document Delete Lifecycle

`SqliteDocumentRepositoryV2.delete` invokes `AssetStore.deleteDocumentAssets` before deleting the document row. Deletion is scoped by validated document ID and is idempotent.

## 13. Page Delete Lifecycle

`SqliteDocumentRepositoryV2.deletePage` obtains the owning document ID, deletes that page’s canonical asset directory, then deletes the database page row and synchronizes page count. Sibling pages and document exports are not touched.

## 14. Legacy Asset Compatibility

Legacy timestamped files and persisted paths remain untouched and readable by existing application code. M03 does not reinterpret legacy paths as canonical paths and does not delete them during canonical cleanup.

## 15. Orphan Detection

The integrity scanner detects document directories and page directories that are absent from supplied database ownership records. It does not delete them.

## 16. Integrity Scanner

The typed `AssetIntegrityReport` contains:

- `orphanDocuments`.
- `orphanPages`.
- `missingRawAssets`.
- `missingProcessedAssets`.
- `missingThumbnails`.
- `unknownFiles`.

## 17. Failure Recovery

- Invalid IDs fail before path operations.
- Missing reads return `AssetNotFoundFailure`.
- Temporary write files are cleaned after failures.
- Previous final assets are not removed before replacement bytes are successfully written.
- Delete operations are idempotent.
- Database/filesystem cross-system failures are surfaced as typed failures rather than swallowed.

## 18. Concurrency Strategy

M03 uses asynchronous scoped operations and no global lock. Callers must avoid concurrent destructive operations against the same page. Canonical path ownership prevents cross-document deletion.

## 19. Performance Considerations

M03 manages metadata and filesystem entries only. It does not decode images, load complete documents, relocate legacy files, or process image bytes beyond writing/reading requested byte arrays.

## 20. Tests

### M03 Test File

`test/m03_asset_test.dart` contains 8 tests covering:

- Deterministic paths and identifier safety.
- Idempotent directory creation.
- Independent raw/processed/thumbnail writes and reads.
- Typed missing-asset failures.
- Isolated/idempotent page and document deletion.
- Integrity findings.
- SQLite v2 path persistence and repository deletion integration.
- Cleanup of canonical assets for pages removed during repository save.

### Full Test Result

Command:

```text
flutter test
```

Result:

```text
23 tests passed
0 failed
0 skipped
0 errors
```

## 21. Regression Verification

Automated:

- Existing M01 tests pass.
- Existing M02 migration tests pass.
- Existing image-processing test passes.
- M03 filesystem tests pass.
- M03 SQLite path/deletion integration test passes.

Manual/device:

- Not performed in the available environment.

M03 does not change existing scanner/editor/PDF processing algorithms or UI flows.

## 22. Static Analysis

Command:

```text
flutter analyze
```

Result:

```text
No issues found!
```

## 23. Android Build

Command:

```text
flutter build apk --debug
```

Result:

```text
Built build/app/outputs/flutter-apk/app-debug.apk
```

## 24. iOS Build

The existing iOS validation remains blocked by:

```text
google_mlkit_commons requires iOS 15.5
project targets iOS 13.0
```

No iOS deployment target or dependency version was changed.

## 25. Dependencies

No production dependency was added. Existing `path`, `path_provider`, and `sqflite_common_ffi` test infrastructure were reused. No image-processing or cloud dependency was introduced.

## 26. Files Created

- `lib/app/infrastructure/storage/document_asset_path_resolver.dart`
- `lib/app/infrastructure/storage/file_system_asset_store.dart`
- `test/m03_asset_test.dart`
- `docs/architecture/SCANORA_ASSET_STORAGE_V3.md`
- `docs/reports/M03_IMPLEMENTATION_REPORT.md`

## 27. Files Modified

- `lib/app/core/errors/app_failure.dart`
- `lib/app/domain/contracts/asset_store.dart`
- `lib/app/infrastructure/storage/file_asset_store.dart`
- `lib/app/data/repositories/sqlite_document_repository_v2.dart`
- `lib/app/data/repositories/document_repository.dart`
- `lib/main.dart`

## 28. M03 Acceptance Criteria

| Criterion | Status |
|---|---|
| AC-01 Centralized asset root exists | PASS |
| AC-02 Deterministic canonical paths | PASS |
| AC-03 Path traversal IDs rejected | PASS |
| AC-04 Idempotent directory creation | PASS |
| AC-05 Independent raw storage | PASS |
| AC-06 Independent processed storage | PASS |
| AC-07 Independent thumbnail storage | PASS |
| AC-08 Derived assets cannot overwrite raw | PASS |
| AC-09 Atomic writes | PASS |
| AC-10 Temporary failure cleanup and prior-file preservation | PASS |
| AC-11 Typed read failures | PASS |
| AC-12 Page deletion isolation | PASS |
| AC-13 Document deletion isolation | PASS |
| AC-14 Idempotent deletion | PASS |
| AC-15 DB/filesystem consistency strategy | PASS |
| AC-16 Canonical paths persist in v2 metadata | PASS |
| AC-17 Legacy paths remain untouched/readable | PASS |
| AC-18 Orphan detection | PASS |
| AC-19 Missing asset detection | PASS |
| AC-20 Unknown file detection | PASS |
| AC-21 Typed integrity report | PASS |
| AC-22 M02 compatibility | PASS |
| AC-23 Document deletion strategy explicit and recoverable | PASS |
| AC-24 Page deletion cleans owned assets | PASS |
| AC-25 No M04 functionality | PASS |
| AC-26 No M05+ functionality | PASS |
| AC-27 Path/ID unit tests | PASS |
| AC-28 Filesystem integration tests | PASS |
| AC-29 Integrity scanner tests | PASS |
| AC-30 Real SQLite path synchronization | PASS |
| AC-31 Failed writes do not silently persist nonexistent paths | PASS |
| AC-32 `flutter test` | PASS |
| AC-33 `flutter analyze` | PASS |
| AC-34 Android debug build | PASS |
| AC-35 Architecture documentation | PASS |
| AC-36 Implementation report | PASS |

## 29. Known Issues

- Physical-device scanner/editor regression testing was unavailable.
- Existing legacy files are not migrated; they remain outside the canonical M03 root by design.
- Cross-system SQLite/filesystem operations cannot be one atomic transaction. The chosen deletion order and integrity scanner are documented recovery mechanisms.
- Automatic orphan cleanup is intentionally deferred.
- Existing direct controller/service file operations remain for legacy runtime compatibility and were not rewritten in M03.
- iOS build remains blocked by the pre-existing ML Kit deployment target mismatch.

## 30. Final Verdict

PASS — LOCKED
