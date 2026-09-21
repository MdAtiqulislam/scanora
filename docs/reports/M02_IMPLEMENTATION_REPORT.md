# Scanora M02 Implementation Report

## 1. Executive Summary

M02 adds a versioned SQLite v2 persistence foundation with normalized `documents` and `pages` tables, a v1-to-v2 migration path, deterministic domain/database mapping, repository transactions, page-count synchronization, and a compatibility facade for existing GetX controllers.

Intentionally not implemented:

- M03 asset relocation or filesystem lifecycle migration.
- Image-processing changes.
- Non-destructive editor behavior.
- OCR processing or Bengali OCR.
- Searchable PDF.
- Folders, tags behavior, favorites UI, trash, sync, authentication, or UI redesign.
- New dependencies or package upgrades.

## 2. Existing Database Forensics

The previous repository opened `scanora.db` using sqflite version `1`. It created one table:

```sql
documents(
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  pages TEXT NOT NULL,
  pdfPath TEXT,
  createdAt TEXT NOT NULL,
  updatedAt TEXT NOT NULL
)
```

Pages were nested JSON serialized from `ScannedPage`. There was no `onUpgrade`, no normalized page table, no foreign key, no index, and no raw SQL outside `DocumentRepository`.

Existing controllers use the GetX facade's `documents`, `saveDocument`, and `deleteDocument` methods.

## 3. New Database v2 Schema

The full schema, columns, constraints, indexes, and serialization formats are documented in `docs/architecture/SCANORA_DATABASE_V2.md`.

The schema contains:

- `documents`: document metadata and synchronized `page_count`.
- `pages`: normalized page metadata ordered by `(document_id, page_index)`.

`pages.document_id` references `documents.id` with cascade deletion. No image bytes are loaded or migrated.

## 4. Migration Design

```text
legacy v1 documents with nested pages JSON
       ↓ sqflite onUpgrade transaction
v2 documents + normalized pages
```

Migration steps:

1. Add v2 document metadata columns to the existing table.
2. Create the normalized `pages` table.
3. Validate each legacy document ID and timestamp.
4. Decode each legacy page list in its existing order.
5. Preserve IDs and paths.
6. Generate deterministic page IDs only for empty legacy IDs.
7. Map existing filter values to stable v2 enum names.
8. Apply safe defaults for unavailable v2 fields.
9. Set `page_count` to the number of migrated pages.

The migration does not drop tables or delete existing data.

## 5. Legacy to V2 Mapping

| Legacy | V2 | Decision |
|---|---|---|
| `documents.id` | `documents.id` | Preserved |
| `documents.title` | `documents.title` | Preserved |
| `documents.createdAt` | `documents.created_at` | ISO string preserved/normalized |
| `documents.updatedAt` | `documents.updated_at` | ISO string preserved/normalized |
| `documents.pdfPath` | `documents.pdf_path` | Preserved exactly |
| nested page array position | `pages.page_index` | Preserved exactly |
| `ScannedPage.id` | `pages.id` | Preserved where valid |
| empty page ID | `documentId-page-index` | Deterministic fallback |
| `ScannedPage.imagePath` | `pages.processed_image_path` | Preserved |
| `ScannedPage.rawImagePath` | `pages.raw_image_path` | Preserved |
| `ScannedPage.filter` | `processing_profile_json.filterType` | Stable name mapping |
| unavailable favorite | `documents.favorite` | `0` |
| unavailable tags | `documents.tags_json` | `[]` |
| unavailable thumbnail | `pages.thumbnail_path` | `NULL` |
| unavailable OCR | `pages.ocr_result` | `NULL` |
| unavailable dirty state | `pages.is_dirty` | `0` |
| unavailable rotation | `pages.rotation_angle` | `0` |
| unavailable corners | `pages.corners_json` | `NULL` |
| unavailable transform | `pages.crop_transform_json` | `{}` |

## 6. Files Created

- `lib/app/data/datasources/scanora_database.dart`
- `lib/app/data/models/scan_document_db_mapper.dart`
- `lib/app/data/repositories/sqlite_document_repository_v2.dart`
- `docs/architecture/SCANORA_DATABASE_V2.md`
- `docs/reports/M02_IMPLEMENTATION_REPORT.md`
- `test/m02_database_test.dart`

## 7. Files Modified

- `lib/app/data/repositories/document_repository.dart`

The file is now a compatibility facade over the v2 repository. Existing controllers retain their API, but writes delegate to v2 SQLite.

## 8. Repository Architecture

```text
Existing GetX controllers
        ↓
DocumentRepository compatibility facade
        ↓
SqliteDocumentRepositoryV2
        ↓
ScanoraDatabase
        ↓
SQLite v2
```

There are no two independently writable document databases.

Repository document saves and page mutations use transactions. Page insertion/deletion synchronizes `page_count` from actual normalized rows.

## 9. Serialization

- Enums use stable names rather than indexes.
- Dates use ISO-8601 strings.
- Booleans use SQLite `0`/`1`.
- Corners, transforms, profiles, and tags use deterministic JSON.
- OCR text is stored in `ocr_result`.
- Malformed optional JSON restores safe defaults; malformed required migration data fails migration.

## 10. Data Preservation

Automated mapper tests verify preservation of:

- IDs.
- Titles.
- Creation/update timestamps.
- PDF paths.
- Raw, processed, and thumbnail paths.
- Page ordering.
- Rotation.
- Corners.
- Crop transform.
- Processing profile.
- OCR text.
- Dirty state.

The existing test environment does not initialize a sqflite test platform factory. Direct repository/migration integration tests therefore cannot execute under `flutter test` without adding `sqflite_common_ffi`, which is an unnecessary new dependency prohibited by M02. The production sqflite path remains implemented for Android/iOS.

## 11. Migration Safety

- sqflite schema upgrades run through the database upgrade transaction.
- A thrown migration failure prevents a successful commit.
- Migration is version-gated and runs only from version 1 to version 2.
- IDs and ordering are deterministic.
- Null optional values receive documented defaults.
- Invalid required IDs, timestamps, page-list shapes, or page rows throw `StorageFailure`.
- No destructive reset or `DROP TABLE` is used.

## 12. Tests

Command:

```text
flutter test
```

Result:

```text
00:02 +10: All tests passed!
```

Exact result:

```text
Test files: 3
Test cases: 15
Passed: 15
Failed: 0
Skipped: 0
Errors: 0
```

The three test files are the two M01 test files plus `test/m02_database_test.dart`. The M02 test file now executes the real SQLite v1-to-v2 upgrade path using isolated temporary databases and verifies migration, schema, repository, rollback, retry, and collision behavior.

The initial direct sqflite test attempt failed before test execution because the project has no initialized test database factory:

```text
Bad state: databaseFactory not initialized
```

No FFI dependency was added to avoid violating the dependency restrictions.

## 13. Static Analysis

Command:

```text
flutter analyze
```

Result:

```text
flutter analyze
No issues found!
```

Status: PASS.

## 14. Android Build

Command:

```text
flutter build apk --debug
```

Result:

```text
✓ Built build/app/outputs/flutter-apk/app-debug.apk
```

Status: PASS.

## 15. iOS Build

Command:

```text
flutter build ios --no-codesign
```

Result: BLOCKED by the existing platform configuration:

```text
The plugin "google_mlkit_commons" requires a higher minimum iOS deployment version than your application is targeting.
```

The project targets iOS 13.0; the existing plugin requires iOS 15.5. No iOS configuration or dependency version was changed.

## 16. Regression Verification

Automated:

- Domain/database mapping tests.
- Existing M01 tests.
- Existing image-processing test.
- Static analysis and Android build after final verification.

Manual/device:

- Not performed in the current environment.

Not tested:

- Physical scanner flow against an upgraded installed database.
- Physical device document rename/delete/open flow.

## 17. M02 Acceptance Criteria

| Criterion | Status | Evidence |
|---|---|---|
| AC-01 | PASS | `ScanoraDatabase.createV2Schema`; fresh-schema mapper/schema tests |
| AC-02 | PASS | Real v1 fixture opened through production `onUpgrade(1, 2)` path |
| AC-03 | PASS | Real migrated document rows verified through SQL and repository |
| AC-04 | PASS | Real normalized page rows verified through SQL and repository |
| AC-05 | PASS | Legacy list index maps to `page_index`; repository orders ascending |
| AC-06 | PASS | Existing IDs preserved; deterministic fallback documented |
| AC-07 | PASS | Raw/processed paths mapped and mapper-tested |
| AC-08 | PASS | PDF path mapped and mapper-tested |
| AC-09 | PASS | Legacy filter mapping implemented and tested; rotation supported by v2 mapper |
| AC-10 | PASS | Documented defaults and mapper defaults |
| AC-11 | PASS | `PageCorners` JSON mapper round trip tested |
| AC-12 | PASS | `PageTransform` JSON mapper round trip tested |
| AC-13 | PASS | `ProcessingProfile` JSON mapper round trip tested |
| AC-14 | PASS | `ocr_result` mapper persistence tested |
| AC-15 | PASS | `SqliteDocumentRepositoryV2` implements M01 contract |
| AC-16 | PASS | Legacy facade delegates to v2; no second writable store |
| AC-17 | PASS | Malformed timestamp fixture rolled back schema/data; retry succeeded after repair |
| AC-18 | PASS | Real reopen kept version 2, IDs, ordering, and row counts unchanged |
| AC-19 | PASS | Page count written/synchronized from normalized page rows |
| AC-20 | PASS | Production repository read verified after real migration; physical device workflow not claimed |
| AC-21 | PASS | No M03+ functionality added |
| AC-22 | PASS | Only test-scoped `sqflite_common_ffi` added; no production dependency change |
| AC-23 | PASS | `flutter test`: 15 passed, 0 failed |
| AC-24 | PASS | `flutter analyze`: no issues found |
| AC-25 | PASS | Android debug APK generated |
| AC-26 | PASS | `SCANORA_DATABASE_V2.md` exists |

## 18. Known Issues

### Non-blocking notes

- Physical-device migration and workflow verification were unavailable.
- iOS build remains blocked by the pre-existing iOS 13.0 versus ML Kit iOS 15.5 requirement.
- `sqflite_common_ffi` is used only by the M02 integration test target; it is not a production runtime dependency.

### Deferred M03+ items

- Filesystem asset migration and orphan cleanup.
- Non-destructive editor state.
- New image-processing algorithms.
- OCR expansion and searchable PDF.

## 19. Final Verdict

The original implementation report remained `PASS WITH NOTES` pending integration evidence. The verification in section 20 closes that gap.

## 20. Migration Integration Verification

### Test Database Strategy

The test creates real legacy v1 SQLite files directly using the legacy schema and inserts rows directly into `documents`. Each test uses an isolated temporary database path. The production `ScanoraDatabase` is then instantiated with that path and opened through the normal `version: 2` and `onUpgrade: migrate` flow.

The test backend is `sqflite_common_ffi`, initialized with:

```dart
sqfliteFfiInit();
databaseFactory = databaseFactoryFfi;
```

This does not mock or manually invoke migration. The test executes the actual sqflite upgrade callback.

### Dependency Changes

Added only as a `dev_dependency`:

```text
sqflite_common_ffi: ^2.4.0
```

Reason: the project’s existing host Flutter test environment had no initialized sqflite database factory, making actual SQLite integration impossible. The dependency is test-only and does not affect Android/iOS production runtime dependencies.

### Real v1 Fixture

Fixtures are created directly with:

```sql
documents(
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  pages TEXT NOT NULL,
  pdfPath TEXT,
  createdAt TEXT NOT NULL,
  updatedAt TEXT NOT NULL
)
```

The tests cover one-page, five-page, three-document, null/default, filter, collision, and malformed-timestamp fixtures.

### Actual Migration Execution

Verified path:

```text
real v1 SQLite file
  -> ScanoraDatabase.open()
  -> openDatabase(version: 2)
  -> onUpgrade(db, 1, 2)
  -> normalized v2 schema
  -> SqliteDocumentRepositoryV2
  -> domain ScanDocument/ScanPage
```

The migration was not called directly by the tests.

### Test Cases

1. Single document/single page: IDs, title, timestamps, PDF path, image paths, filter, index, and page count.
2. Five-page document: exact ordering, IDs, paths, indexes, and page count.
3. Three documents: isolation and independent page counts/order.
4. Empty IDs: deterministic fallback and collision handling.
5. Null PDF and empty raw path: documented defaults.
6. Legacy filters: `auto`, `magic`, `original`, `smart`, `gray`, and `bw`.
7. Raw SQL preservation: all required document/page columns and defaults.
8. Schema metadata: primary keys, indexes, foreign key, cascade, and `PRAGMA foreign_keys`.
9. Transaction rollback: invalid timestamp leaves version 1/schema/data intact; repair and retry succeeds.
10. Version retry: reopening v2 does not duplicate documents/pages or rerun migration.

### Schema Verification

Direct SQLite inspection verified:

- `PRAGMA foreign_keys` is enabled.
- `pages.document_id` references `documents.id`.
- Foreign key delete action is `CASCADE`.
- `idx_documents_updated_at` exists.
- `idx_pages_document_index` exists.
- Unique `(document_id, page_index)` index exists and contains both columns.
- Deleting a document deletes its pages.

### Data Preservation Verification

Direct SQL and repository assertions verified:

- Document IDs and page IDs.
- Titles and timestamps.
- PDF paths.
- Raw and processed image paths.
- Page ordering and indexes.
- Filters without enum ordinal dependence.
- `page_count` against `SELECT COUNT(*)`.
- Favorite and tags defaults.
- Thumbnail, corners, OCR, rotation, transform, and dirty-state defaults.

### Repository Verification

All migrated documents are read through `SqliteDocumentRepositoryV2`, not only raw SQL. The repository returns normalized pages in `page_index ASC` order and maps the rows into domain entities.

### Rollback Verification

A fixture with one malformed required timestamp triggers `StorageFailure` during the real upgrade. After the failed open:

- `PRAGMA user_version` remains `1`.
- The `pages` table does not exist.
- Both original v1 document rows remain.
- No partial page rows remain.

After repairing the timestamp, reopening the same database completes migration successfully.

### Retry/Version Verification

After successful migration, closing and reopening the database confirms:

- Version remains `2`.
- One document remains one document.
- One page remains one page.
- IDs and ordering remain unchanged.
- No second migration is executed.

### Collision Verification

When an empty page ID would resolve to an ID already reserved by another legacy page, migration generates:

```text
<documentId>-page-<pageIndex>-migrated-1
```

The resulting IDs are unique, deterministic, stable after reopen, and remain associated with the correct document.

### OCR Field Check

The M01 OCR domain contract contains plain text only:

```dart
OcrDocument(documentId, text)
```

`pages.ocr_result TEXT` is sufficient for the current M01 contract. Structured OCR blocks, lines, words, bounding boxes, confidence, language, and provider metadata remain deferred to later OCR milestones.

### Final Verification Results

```text
flutter test: 15 passed, 0 failed, 0 skipped, 0 errors
flutter analyze: No issues found!
flutter build apk --debug: PASS
flutter build ios --no-codesign: BLOCKED by existing ML Kit iOS 15.5 requirement vs project iOS 13.0 target
```

No filesystem assets were moved, read for image processing, deleted, or migrated. No M03 functionality was introduced.

### Integration Verification Verdict

```text
PASS — LOCKED
```
