# Scanora Non-Destructive Editing v4

## Raw Source of Truth

Raw capture bytes remain the editor source of truth. M04 edit operations persist metadata only and do not overwrite or replace raw assets.

## Edit State

`PageEditState` contains:

- Optional normalized `PageCorners`.
- `PageTransform`.
- Normalized 0/90/180/270 rotation.
- Stable `ScanFilterType`.
- Brightness, contrast, and saturation adjustments.
- Versioned `ProcessingProfile`.

The existing `ScanPage` fields remain the persistence representation; `editState` exposes the grouped domain view without creating a second database model.

## Coordinates and Validation

Corners use normalized source-image coordinates with origin at the top-left, range `0..1`, and ordering:

```text
topLeft, topRight, bottomRight, bottomLeft
```

All points must be finite, in range, distinct, and form a non-degenerate quad. M04 stores geometry only; it does not implement perspective correction.

## Rotation and Adjustments

Rotation is metadata and normalized modulo 360. Negative rotations are normalized deterministically. Adjustments default to brightness `0`, contrast `1`, saturation `1`; contrast and saturation cannot be negative and all values must be finite.

## Profile and Cache Identity

`ProcessingProfile` uses stable enum names and canonical JSON ordering for numeric parameters. `PageCacheIdentity` combines document ID, page ID, raw asset identity, profile version, and canonical edit state using deterministic FNV-1a hashing.

Same raw identity plus same edit state produces the same key. Any relevant change produces a different key.

## Dirty and Cache Semantics

`isDirty` means the persisted page edit state is not considered synchronized with a completed render. A missing or stale processed asset does not invalidate metadata. Saving edit metadata clears processed and thumbnail cache keys but does not delete derived files. A future renderer may call `markProcessedCacheCurrent` after writing a matching derived asset.

Processed file existence alone never indicates freshness.

Freshness uses both managed asset existence and stored identity:

```text
asset missing                      -> MISSING
asset exists + key null            -> STALE
asset exists + key differs         -> STALE
asset exists + key matches         -> CURRENT
```

The algorithm is identical for processed and thumbnail caches. Cache-marking APIs refuse to mark a cache current unless the corresponding M03 asset exists.

State transitions are:

```text
CLEAN + CURRENT
  -> edit change  -> DIRTY + STALE
  -> save         -> CLEAN + STALE
  -> matching render -> CLEAN + CURRENT
```

Dirty state and cache freshness are independent; clean metadata may have a stale or missing derived cache.

## Thumbnail Semantics

Thumbnail cache identity is persisted separately. M04 invalidates its key when edit state changes but does not regenerate thumbnails or add a rendering pipeline.

## Persistence and Migration

M04 increments SQLite v2 to v3 and adds:

- `processed_cache_key TEXT`.
- `thumbnail_cache_key TEXT`.
- `edit_state_version INTEGER NOT NULL DEFAULT 1`.

The migration preserves all M02 data and is exercised with the existing FFI SQLite test infrastructure.

## Legacy Compatibility

Legacy paths and legacy processed files remain untouched. Missing M04 metadata uses M02 defaults. Legacy rendered pixels are not treated as proof of current cache freshness.

Malformed M04 JSON, unknown filters, invalid corners, invalid transforms, and invalid numeric values raise typed `StorageFailure` during strict repository reads. They are never silently repaired and committed. Low-level legacy mapper reads remain permissive only for M02 compatibility.

## AssetStore Integration

M04 does not perform canonical filesystem operations directly. It uses the M03 `AssetStore` through repository injection for lifecycle operations. Rendering remains deferred.

## Boundaries

- M03 owns asset storage and lifecycle.
- M06 owns geometry algorithms.
- M07+ own production processing engines.
- M11 owns WYSIWYG preview/export equivalence.

M04 establishes state and cache identity only.
