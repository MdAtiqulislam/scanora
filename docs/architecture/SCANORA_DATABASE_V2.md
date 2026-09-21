# Scanora Database v2

## Version and Ownership

- Database filename: `scanora.db`
- Current schema version: `2`
- Database implementation: `ScanoraDatabase`
- Repository implementation: `SqliteDocumentRepositoryV2`
- Compatibility facade: `DocumentRepository`

The v2 database is the only writable document/page store. The legacy GetX-facing repository API delegates to v2 and does not maintain a second database.

## Tables

### `documents`

| Column | SQLite type | Rules |
|---|---|---|
| `id` | `TEXT` | Primary key |
| `title` | `TEXT` | Not null |
| `created_at` | `TEXT` | Not null, ISO-8601 UTC-compatible representation |
| `updated_at` | `TEXT` | Not null, ISO-8601 UTC-compatible representation |
| `favorite` | `INTEGER` | Not null, default `0`, constrained to `0` or `1` |
| `tags_json` | `TEXT` | Not null, default `[]` |
| `pdf_path` | `TEXT` | Nullable, preserved exactly |
| `page_count` | `INTEGER` | Not null, default `0`, non-negative |

Indexes:

- `idx_documents_updated_at` on `updated_at DESC`

### `pages`

| Column | SQLite type | Rules |
|---|---|---|
| `id` | `TEXT` | Primary key |
| `document_id` | `TEXT` | Not null, FK to `documents.id`, cascade delete |
| `page_index` | `INTEGER` | Not null, non-negative |
| `raw_image_path` | `TEXT` | Nullable |
| `processed_image_path` | `TEXT` | Nullable |
| `thumbnail_path` | `TEXT` | Nullable |
| `corners_json` | `TEXT` | Nullable JSON |
| `rotation_angle` | `REAL` | Not null, default `0` |
| `crop_transform_json` | `TEXT` | Not null, default `{}` JSON |
| `processing_profile_json` | `TEXT` | Not null, default `{}` JSON |
| `ocr_result` | `TEXT` | Nullable |
| `is_dirty` | `INTEGER` | Not null, default `0`, constrained to `0` or `1` |
| `created_at` | `TEXT` | Not null, ISO-8601 representation |
| `updated_at` | `TEXT` | Not null, ISO-8601 representation |

Constraints and indexes:

- Foreign key `pages.document_id -> documents.id ON DELETE CASCADE`.
- Unique `(document_id, page_index)` preserves one ordered page per position.
- `idx_pages_document_index` on `(document_id, page_index)`.

## Serialization

- `DateTime`: ISO-8601 string from `toIso8601String()`.
- Boolean values: SQLite integer `0` or `1`.
- `ScanFilterType`: stable enum name, never enum ordinal.
- Tags: JSON string array.
- `PageCorners`: JSON object containing `topLeft`, `topRight`, `bottomRight`, and `bottomLeft`, each with `x` and `y`.
- `PageTransform`: JSON object containing scale, translation, and rotation values.
- `ProcessingProfile`: JSON object containing `filterType`, `adjustments`, and numeric `parameters`.
- OCR: current domain-supported OCR text is persisted in `ocr_result`; no OCR processing is performed by M02.

## Migration

The shipped legacy schema is version 1:

```text
documents(id, title, pages, pdfPath, createdAt, updatedAt)
```

On upgrade from version 1, the database:

1. Adds v2 document metadata columns.
2. Creates normalized `pages`.
3. Reads each legacy nested page list in stored order.
4. Preserves valid document/page IDs and paths.
5. Uses deterministic `documentId-page-index` IDs only when a legacy page ID is empty.
6. Maps legacy filters to stable v2 filter names.
7. Initializes unavailable fields to safe defaults.
8. Sets `page_count` from inserted page rows.

The sqflite `onUpgrade` callback runs within SQLite's upgrade transaction. A malformed row or timestamp throws a `StorageFailure`, preventing a successful commit. No `DROP TABLE` or data deletion is used.

For isolated integration verification, `ScanoraDatabase` accepts an optional database path. Production callers continue to use the platform database path; tests use temporary files with `sqflite_common_ffi` and still open the production `version: 2`/`onUpgrade` path.

Empty legacy page IDs use the deterministic base `$documentId-page-$pageIndex`. If another legacy page already reserves that ID, the migration appends `-migrated-N`, preserving primary-key uniqueness and stable retry behavior.

## Page Count

`page_count` is persisted for query/display efficiency. Repository document saves write it from the supplied page collection, while page insert/delete methods recalculate it from the normalized `pages` table in the same transaction.

## Scope Boundary

M02 persists metadata and relationships only. It does not relocate files, delete filesystem assets, process images, add OCR languages, create searchable PDFs, or implement editor behavior.
