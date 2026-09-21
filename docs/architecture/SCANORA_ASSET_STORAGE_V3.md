# Scanora Asset Storage v3

## Asset Root

M03-managed assets are rooted at the application documents directory under:

```text
<application documents directory>/scanora-assets/documents/
```

The root is resolved once during application startup and injected into `FileSystemAssetStore`. The root is not persisted redundantly in SQLite.

## Directory Structure

```text
scanora-assets/
└── documents/
    └── {documentId}/
        ├── pages/
        │   └── {pageId}/
        │       ├── raw.jpg
        │       ├── processed.jpg
        │       └── thumbnail.jpg
        └── exports/
```

Directories are created lazily and recursively. Repeated creation is safe.

## Ownership and Naming

- A document owns `documents/{documentId}/`.
- A page owns `documents/{documentId}/pages/{pageId}/`.
- Raw, processed, and thumbnail files have fixed canonical names.
- Canonical paths are derived only from validated IDs.
- No timestamps, random names, counters, or global path state are used for canonical assets.

## Identifier Safety

Document and page IDs reject empty/whitespace values, `.`, `..`, path separators, absolute paths, and values containing `..`. Invalid values produce `InvalidAssetIdentifierFailure`. IDs are not silently normalized.

## Raw, Processed, and Thumbnail Semantics

- `raw.jpg` is the source-of-truth capture and is never targeted by derived writes.
- `processed.jpg` is independently replaceable and deletable.
- `thumbnail.jpg` is independently replaceable and deletable.
- Reads do not silently substitute one asset kind for another.

M03 does not decode or transform images.

## Atomic Writes

Writes create a temporary sibling file, write with `flush: true`, then rename it to the canonical destination. Temporary files are removed after failures. A replacement rename occurs only after the temporary write succeeds, preserving the previous final file as far as the platform rename semantics allow.

## Database and Filesystem Consistency

M03 does not attempt a filesystem/SQLite cross-system transaction. The chosen deletion order is:

1. Delete the owned canonical asset directory.
2. Delete the corresponding database metadata.

This prioritizes avoiding orphaned canonical files. If the database deletion fails after asset deletion, the operation returns a storage failure and the metadata remains recoverable for retry, but its canonical asset references will be missing and are detectable by the integrity scanner.

New canonical paths are persisted by the caller in the v2 page metadata in the same repository save operation. Asset writes must succeed before a caller commits those paths. Existing legacy paths are not rewritten by M03.

## Delete Operations

Page deletion is scoped to one document/page directory and is idempotent. Document deletion is scoped to one document directory and is idempotent. The v2 repository invokes the asset store before deleting corresponding database rows when an asset store is injected.

## Legacy Compatibility

M02 paths such as timestamped `imagePath`, `rawImagePath`, and `pdfPath` remain readable as persisted paths. M03 does not move, reinterpret, or delete those files merely because they are outside `scanora-assets`. Canonical storage is additive until a later migration explicitly moves legacy assets.

PDF paths remain outside the canonical page asset tree. M03 does not migrate or redesign PDF generation.

## Integrity Scanner

`FileSystemAssetStore.inspectIntegrity` compares managed directories and canonical asset references against database-provided document/page identifiers. It reports:

- Orphan document directories.
- Orphan page directories.
- Missing raw assets.
- Missing processed assets.
- Missing thumbnails.
- Unknown files under managed page directories.

The scanner is report-only and never deletes findings.

## Concurrency and Performance

Operations are asynchronous and scoped to individual paths. M03 does not introduce a global locking system. Callers should serialize conflicting save/delete operations for the same page. Writes do not load whole documents or decode image contents. Deletes and integrity scans operate on filesystem entries.

## Error Handling and Future Boundary

Operations return M01 `Result<T>` values with `StorageFailure`, `AssetNotFoundFailure`, or `InvalidAssetIdentifierFailure`. No filesystem exception is exposed as an uncontrolled domain error. Automatic orphan cleanup, legacy asset relocation, retry queues, and richer consistency state remain future lifecycle-hardening work; M03 only establishes safe storage and detection primitives.
