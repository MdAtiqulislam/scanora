import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:sqflite/sqflite.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../core/utils/jpeg_utils.dart';
import '../../domain/contracts/document_repository.dart' as contract;
import '../../domain/contracts/asset_store.dart';
import '../../domain/contracts/geometry_engine.dart';
import '../../domain/entities/scan_document.dart';
import '../../domain/entities/scan_page.dart';
import '../../domain/enums/scan_enums.dart';
import '../../domain/geometry/geometry_models.dart';
import '../../domain/processing/processing_models.dart';
import '../../domain/value_objects/page_corners.dart';
import '../../domain/value_objects/page_edit_state.dart';
import '../../domain/value_objects/point.dart';
import '../../domain/value_objects/cache_status.dart';
import '../../infrastructure/processing/plain_geometry_engine.dart';
import '../datasources/scanora_database.dart';
import '../models/scan_document_db_mapper.dart';

class SqliteDocumentRepositoryV2 implements contract.DocumentRepository {
  final ScanoraDatabase database;
  final ScanDocumentDbMapper mapper;
  final AssetStore assetStore;
  final GeometryEngine geometryEngine;
  final String engineVersion;

  const SqliteDocumentRepositoryV2({
    required this.database,
    this.mapper = const ScanDocumentDbMapper(),
    required this.assetStore,
    this.geometryEngine = const PlainGeometryEngine(),
    this.engineVersion = 'M07-v1',
  });

  Future<Database> _db() => database.open();

  @override
  Future<List<ScanDocument>> getAll() async {
    try {
      final db = await _db();
      final rows = await db.query(
        ScanoraDatabase.documentsTable,
        orderBy: 'updated_at DESC',
      );
      return Future.wait(rows.map((row) => _readDocument(db, row)));
    } catch (cause, stackTrace) {
      throw StorageFailure(
        'Unable to load documents',
        cause: cause,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<ScanDocument?> getById(String id) async {
    try {
      final db = await _db();
      final rows = await db.query(
        'documents',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return _readDocument(db, rows.single);
    } catch (cause, stackTrace) {
      throw StorageFailure(
        'Unable to load document',
        cause: cause,
        stackTrace: stackTrace,
      );
    }
  }

  Future<ScanDocument> _readDocument(
    DatabaseExecutor db,
    Map<String, dynamic> row,
  ) async {
    final pages = await db.query(
      ScanoraDatabase.pagesTable,
      where: 'document_id = ?',
      whereArgs: [row['id']],
      orderBy: 'page_index ASC',
    );
    return mapper.documentFromRows(row, pages, strictEditMetadata: true);
  }

  @override
  Future<void> save(ScanDocument document) async {
    try {
      final db = await _db();
      final existingDocRows = await db.query(
        'documents',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [document.id],
      );
      final docExists = existingDocRows.isNotEmpty;

      final existingRows = await db.query(
        'pages',
        where: 'document_id = ?',
        whereArgs: [document.id],
      );
      final existingPageMap = {
        for (final row in existingRows) row['id'] as String: row,
      };
      final retainedPageIds = document.pages.map((page) => page.id).toSet();
      final removedPageIds =
          existingPageMap.keys.toSet().difference(retainedPageIds);

      await db.transaction((txn) async {
        if (docExists) {
          await txn.update(
            'documents',
            mapper.documentValues(document),
            where: 'id = ?',
            whereArgs: [document.id],
          );
        } else {
          await txn.insert(
            'documents',
            mapper.documentValues(document),
          );
        }

        for (final pageId in removedPageIds) {
          await txn.delete(
            'pages',
            where: 'id = ?',
            whereArgs: [pageId],
          );
        }

        for (final page in document.pages) {
          if (page.documentId != document.id) {
            throw const StorageFailure(
              'Page document id does not match parent document',
            );
          }

          final existingRow = existingPageMap[page.id];
          final newValues = mapper.pageValues(page);

          if (existingRow != null) {
            final existingCornersJson = existingRow['corners_json'];
            final existingRotation =
                (existingRow['rotation_angle'] as num?)?.toDouble() ?? 0.0;
            final existingProfileJson = existingRow['processing_profile_json'];

            // If incoming page does not specify corners, preserve existing DB corners
            if (page.corners == null && existingCornersJson != null) {
              newValues['corners_json'] = existingCornersJson;
            }

            final incomingCornersJson = newValues['corners_json'];
            final incomingRotation = page.rotationAngle;
            final incomingProfileJson =
                jsonEncode(page.processingProfile.toMap());

            final editChanged =
                (page.corners != null && existingCornersJson != incomingCornersJson) ||
                existingRotation != incomingRotation ||
                existingProfileJson != incomingProfileJson;

            if (editChanged) {
              // Semantic edit changed: incoming stale cache keys must be invalidated
              newValues['processed_cache_key'] = null;
              newValues['thumbnail_cache_key'] = null;
              newValues['edit_state_version'] =
                  ((existingRow['edit_state_version'] as int? ?? 1) + 1);
            } else {
              // Rule 5: Incoming NULL cache metadata preserves current DB metadata.
              // Stale NON-NULL cache metadata must NOT overwrite newer authoritative DB metadata.
              if (existingRow['processed_cache_key'] != null) {
                newValues['processed_cache_key'] =
                    existingRow['processed_cache_key'];
              }
              if (existingRow['thumbnail_cache_key'] != null) {
                newValues['thumbnail_cache_key'] =
                    existingRow['thumbnail_cache_key'];
              }
              newValues['edit_state_version'] =
                  existingRow['edit_state_version'] ?? 1;
            }

            // Preserve paths if incoming does not supply them
            if (page.processedImagePath == null &&
                existingRow['processed_image_path'] != null) {
              newValues['processed_image_path'] =
                  existingRow['processed_image_path'];
            }
            if (page.thumbnailPath == null &&
                existingRow['thumbnail_path'] != null) {
              newValues['thumbnail_path'] =
                  existingRow['thumbnail_path'];
            }
            if (page.rawImagePath == null &&
                existingRow['raw_image_path'] != null) {
              newValues['raw_image_path'] =
                  existingRow['raw_image_path'];
            }

            final count = await txn.update(
              'pages',
              newValues,
              where: 'id = ?',
              whereArgs: [page.id],
            );
            if (count == 0) {
              await txn.insert(
                'pages',
                newValues,
              );
            }
          } else {
            await txn.insert(
              'pages',
              newValues,
            );
          }
        }
      });

      for (final pageId in removedPageIds) {
        final assets = await assetStore.deletePageAssets(
          document.id,
          pageId,
        );
        if (assets case Failure<void>(:final error)) throw error;
      }
    } catch (error) {
      if (error is StorageFailure) rethrow;
      throw StorageFailure('Unable to save document', cause: error);
    }
  }

  @override
  Future<void> delete(String id) async {
    try {
      final assets = await assetStore.deleteDocumentAssets(id);
      if (assets case Failure<void>(:final error)) throw error;
      final db = await _db();
      await db.delete('documents', where: 'id = ?', whereArgs: [id]);
    } catch (cause, stackTrace) {
      throw StorageFailure(
        'Unable to delete document',
        cause: cause,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> savePage(ScanPage page) async {
    final db = await _db();
    await db.transaction((txn) async {
      final parent = await txn.query(
        'documents',
        where: 'id = ?',
        whereArgs: [page.documentId],
      );
      if (parent.isEmpty) {
        throw const StorageFailure('Page document does not exist');
      }
      await txn.insert(
        'pages',
        mapper.pageValues(page),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _syncPageCount(txn, page.documentId);
    });
  }

  Future<void> deletePage(String pageId) async {
    final db = await _db();
    final rows = await db.query(
      'pages',
      where: 'id = ?',
      whereArgs: [pageId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final documentId = rows.single['document_id'] as String;
    final assets = await assetStore.deletePageAssets(documentId, pageId);
    if (assets case Failure<void>(:final error)) throw error;
    await db.transaction((txn) async {
      await txn.delete('pages', where: 'id = ?', whereArgs: [pageId]);
      await _syncPageCount(txn, documentId);
    });
  }

  Future<ScanPage?> getPage(String pageId) async {
    final db = await _db();
    final rows = await db.query(
      'pages',
      where: 'id = ?',
      whereArgs: [pageId],
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : mapper.pageFromRow(rows.single, strictEditMetadata: true);
  }

  Future<void> savePageEditState({
    required String pageId,
    required PageEditState state,
    required String rawAssetIdentity,
    bool isDirty = false,
  }) async {
    state.toMap();
    final db = await _db();
    final rows = await db.query(
      'pages',
      where: 'id = ?',
      whereArgs: [pageId],
      limit: 1,
    );
    if (rows.isEmpty) throw const StorageFailure('Page does not exist');
    final oldPage = mapper.pageFromRow(rows.single, strictEditMetadata: true);
    final isSemanticEdit = state != oldPage.editState;
    final currentVersion = rows.single['edit_state_version'] as int? ?? 1;
    final nextVersion = isSemanticEdit ? currentVersion + 1 : currentVersion;

    await db.update(
      'pages',
      {
        'corners_json':
            state.corners == null ? null : jsonEncode(state.corners!.toMap()),
        'rotation_angle': state.normalizedRotation,
        'crop_transform_json': jsonEncode(state.cropTransform.toMap()),
        'processing_profile_json': jsonEncode(state.processingProfile.toMap()),
        'is_dirty': isDirty ? 1 : 0,
        // The stored key represents the identity of the physical asset currently on disk.
        // CacheStatus becomes stale whenever state != physical asset identity.
        // On semantic edit, invalidate cache keys so reprocessing is triggered.
        'processed_cache_key': isSemanticEdit ? null : oldPage.processedCacheKey,
        'thumbnail_cache_key': isSemanticEdit ? null : oldPage.thumbnailCacheKey,
        'edit_state_version': nextVersion,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [pageId],
    );
  }

  Future<({String processedKey, String thumbnailKey})> _computeCanonicalKeys({
    required ScanPage page,
    required String rawAssetIdentity,
    ThumbnailSpecification thumbnailSpec = const ThumbnailSpecification(),
  }) async {
    final rawRes = await assetStore.readRawImage(page.documentId, page.id);
    if (rawRes case Failure<List<int>>(:final error)) {
      throw StorageFailure(
        'Cannot compute canonical cache key: raw asset read failed',
        cause: error,
      );
    }
    final rawBytes = (rawRes as Success<List<int>>).value;
    final rawUint8 = rawBytes is Uint8List ? rawBytes : Uint8List.fromList(rawBytes);

    PixelSize? sourceSize = parseJpegDimensions(rawUint8);
    if (sourceSize == null) {
      final decoded = img.decodeImage(rawUint8);
      if (decoded != null) {
        sourceSize = PixelSize(decoded.width, decoded.height);
      }
    }
    if (sourceSize == null) {
      throw const StorageFailure(
        'Cannot compute canonical cache key: unable to determine image dimensions',
      );
    }

    final corners =
        page.corners ??
        PageCorners(
          topLeft: const Point2D(0, 0),
          topRight: const Point2D(1, 0),
          bottomRight: const Point2D(1, 1),
          bottomLeft: const Point2D(0, 1),
        );
    final geomResult = geometryEngine.calculate(
      corners: corners,
      sourceSize: sourceSize,
      rotationDegrees: 0,
    );
    if (geomResult case Failure<GeometryResult>(:final error)) {
      throw StorageFailure(
        'Cannot compute canonical cache key: geometry calculation failed',
        cause: error,
      );
    }
    final transform = (geomResult as Success<GeometryResult>).value.transform.coefficients;

    final processedKey = PageCacheIdentity.forProcessed(
      engineVersion: engineVersion,
      documentId: page.documentId,
      pageId: page.id,
      rawAssetIdentity: rawAssetIdentity,
      editState: page.editState,
      geometryTransform: transform,
    );

    final thumbnailKey = PageCacheIdentity.forThumbnail(
      processedCacheKey: processedKey,
      width: thumbnailSpec.width,
      height: thumbnailSpec.height,
      quality: thumbnailSpec.quality,
    );

    return (processedKey: processedKey, thumbnailKey: thumbnailKey);
  }

  Future<CacheStatus> getProcessedCacheStatus({
    required String pageId,
    required String rawAssetIdentity,
  }) async {
    final page = await getPage(pageId);
    if (page == null) throw const StorageFailure('Page does not exist');

    final existsResult = await assetStore.exists(
      page.documentId,
      page.id,
      AssetKind.processed,
    );
    if (existsResult case Failure<bool>(:final error)) throw error;
    final exists = (existsResult as Success<bool>).value;
    if (!exists) return CacheStatus.missing;

    final pathResult = await assetStore.pathFor(
      page.documentId,
      page.id,
      AssetKind.processed,
    );
    if (pathResult case Failure<String>(:final error)) throw error;
    final file = File((pathResult as Success<String>).value);
    if (!file.existsSync() || file.lengthSync() == 0) {
      return CacheStatus.missing;
    }

    final keys = await _computeCanonicalKeys(
      page: page,
      rawAssetIdentity: rawAssetIdentity,
    );

    return page.processedCacheKey == keys.processedKey
        ? CacheStatus.current
        : CacheStatus.stale;
  }

  Future<CacheStatus> getThumbnailCacheStatus({
    required String pageId,
    required String rawAssetIdentity,
  }) async {
    final page = await getPage(pageId);
    if (page == null) throw const StorageFailure('Page does not exist');

    final existsResult = await assetStore.exists(
      page.documentId,
      page.id,
      AssetKind.thumbnail,
    );
    if (existsResult case Failure<bool>(:final error)) throw error;
    final exists = (existsResult as Success<bool>).value;
    if (!exists) return CacheStatus.missing;

    final pathResult = await assetStore.pathFor(
      page.documentId,
      page.id,
      AssetKind.thumbnail,
    );
    if (pathResult case Failure<String>(:final error)) throw error;
    final file = File((pathResult as Success<String>).value);
    if (!file.existsSync() || file.lengthSync() == 0) {
      return CacheStatus.missing;
    }

    final keys = await _computeCanonicalKeys(
      page: page,
      rawAssetIdentity: rawAssetIdentity,
    );

    return page.thumbnailCacheKey == keys.thumbnailKey
        ? CacheStatus.current
        : CacheStatus.stale;
  }

  Future<void> markProcessedCacheCurrent({
    required String pageId,
    required String rawAssetIdentity,
  }) async {
    final page = await getPage(pageId);
    if (page == null) throw const StorageFailure('Page does not exist');

    final existsResult = await assetStore.exists(
      page.documentId,
      page.id,
      AssetKind.processed,
    );
    if (existsResult case Failure<bool>(:final error)) throw error;
    if (!(existsResult as Success<bool>).value) {
      throw const StorageFailure('Processed cache asset does not exist');
    }

    final keys = await _computeCanonicalKeys(
      page: page,
      rawAssetIdentity: rawAssetIdentity,
    );
    final db = await _db();
    await db.update(
      'pages',
      {'processed_cache_key': keys.processedKey},
      where: 'id = ?',
      whereArgs: [pageId],
    );
  }

  Future<void> markThumbnailCacheCurrent({
    required String pageId,
    required String rawAssetIdentity,
  }) async {
    final page = await getPage(pageId);
    if (page == null) throw const StorageFailure('Page does not exist');

    final existsResult = await assetStore.exists(
      page.documentId,
      page.id,
      AssetKind.thumbnail,
    );
    if (existsResult case Failure<bool>(:final error)) throw error;
    if (!(existsResult as Success<bool>).value) {
      throw const StorageFailure('Thumbnail cache asset does not exist');
    }

    final keys = await _computeCanonicalKeys(
      page: page,
      rawAssetIdentity: rawAssetIdentity,
    );
    final db = await _db();
    await db.update(
      'pages',
      {'thumbnail_cache_key': keys.thumbnailKey},
      where: 'id = ?',
      whereArgs: [pageId],
    );
  }

  Future<void> markCacheCurrent({
    required String pageId,
    required String processedCacheKey,
    required String thumbnailCacheKey,
    String? expectedRawAssetIdentity,
    PageEditState? expectedEditState,
  }) async {
    final page = await getPage(pageId);
    if (page == null) throw const StorageFailure('Page does not exist');

    if (processedCacheKey.isEmpty || thumbnailCacheKey.isEmpty) {
      throw const StorageFailure('Cache keys cannot be empty');
    }
    if (expectedRawAssetIdentity != null &&
        page.rawAssetIdentity != expectedRawAssetIdentity) {
      throw const StorageFailure(
        'Stale processing result cannot be marked current: raw asset changed',
      );
    }
    if (expectedEditState != null && page.editState != expectedEditState) {
      throw const StorageFailure(
        'Stale processing result cannot be marked current: edit state changed',
      );
    }

    final processedExistsRes = await assetStore.exists(
      page.documentId,
      page.id,
      AssetKind.processed,
    );
    if (processedExistsRes case Failure<bool>(:final error)) throw error;
    if (!(processedExistsRes as Success<bool>).value) {
      throw const StorageFailure('Processed cache asset does not exist or is invalid');
    }
    final processedPathRes = await assetStore.pathFor(
      page.documentId,
      page.id,
      AssetKind.processed,
    );
    if (processedPathRes case Failure<String>(:final error)) throw error;
    final processedFile = File((processedPathRes as Success<String>).value);
    if (!processedFile.existsSync() || processedFile.lengthSync() == 0) {
      throw const StorageFailure('Processed cache asset does not exist or is invalid');
    }

    final thumbnailExistsRes = await assetStore.exists(
      page.documentId,
      page.id,
      AssetKind.thumbnail,
    );
    if (thumbnailExistsRes case Failure<bool>(:final error)) throw error;
    if (!(thumbnailExistsRes as Success<bool>).value) {
      throw const StorageFailure('Thumbnail cache asset does not exist or is invalid');
    }
    final thumbnailPathRes = await assetStore.pathFor(
      page.documentId,
      page.id,
      AssetKind.thumbnail,
    );
    if (thumbnailPathRes case Failure<String>(:final error)) throw error;
    final thumbnailFile = File((thumbnailPathRes as Success<String>).value);
    if (!thumbnailFile.existsSync() || thumbnailFile.lengthSync() == 0) {
      throw const StorageFailure('Thumbnail cache asset does not exist or is invalid');
    }

    // Recompute canonical keys to validate against arbitrary keys
    final canonicalKeys = await _computeCanonicalKeys(
      page: page,
      rawAssetIdentity: expectedRawAssetIdentity ?? page.rawAssetIdentity,
    );

    if (processedCacheKey != canonicalKeys.processedKey) {
      throw const StorageFailure(
        'Supplied processed cache key does not match canonical identity',
      );
    }

    if (thumbnailCacheKey != canonicalKeys.thumbnailKey) {
      throw const StorageFailure(
        'Supplied thumbnail cache key does not match canonical identity',
      );
    }

    final db = await _db();
    final dbRow = (await db.query(
      'pages',
      columns: ['edit_state_version'],
      where: 'id = ?',
      whereArgs: [pageId],
    )).firstOrNull;
    final currentVersion = dbRow?['edit_state_version'] as int? ?? 1;

    final count = await db.update(
      'pages',
      {
        'processed_cache_key': processedCacheKey,
        'thumbnail_cache_key': thumbnailCacheKey,
        'is_dirty': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND edit_state_version = ?',
      whereArgs: [pageId, currentVersion],
    );
    if (count == 0) {
      throw const StorageFailure(
        'Stale processing result cannot overwrite newer state: edit state version mismatch',
      );
    }
  }

  Future<void> _syncPageCount(DatabaseExecutor db, String documentId) async {
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM pages WHERE document_id = ?',
      [documentId],
    );
    await db.update(
      'documents',
      {'page_count': result.single['count']},
      where: 'id = ?',
      whereArgs: [documentId],
    );
  }
}

extension ScanPageRawIdentityExtension on ScanPage {
  String get rawAssetIdentity => 'raw-v1';
}
