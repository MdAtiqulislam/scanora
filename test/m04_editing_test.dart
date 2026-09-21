import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:scanora/app/core/errors/app_failure.dart';
import 'package:scanora/app/data/datasources/scanora_database.dart';
import 'package:scanora/app/data/repositories/sqlite_document_repository_v2.dart';
import 'package:scanora/app/domain/entities/scan_document.dart';
import 'package:scanora/app/domain/entities/scan_page.dart';
import 'package:scanora/app/domain/enums/scan_enums.dart';
import 'package:scanora/app/domain/value_objects/page_corners.dart';
import 'package:scanora/app/domain/value_objects/page_edit_state.dart';
import 'package:scanora/app/domain/value_objects/page_transform.dart';
import 'package:scanora/app/domain/value_objects/processing_adjustments.dart';
import 'package:scanora/app/domain/value_objects/processing_profile.dart';
import 'package:scanora/app/domain/value_objects/point.dart';
import 'package:scanora/app/domain/value_objects/cache_status.dart';
import 'package:scanora/app/infrastructure/storage/file_system_asset_store.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  final corners = PageCorners(
    topLeft: const Point2D(0, 0),
    topRight: const Point2D(1, 0),
    bottomRight: const Point2D(1, 1),
    bottomLeft: const Point2D(0, 1),
  );

  PageEditState state({int rotation = 0}) {
    const adjustments = ProcessingAdjustments(
      brightness: 0.1,
      contrast: 1.2,
      saturation: 0.8,
    );
    const profile = ProcessingProfile(
      filterType: ScanFilterType.magic,
      adjustments: adjustments,
      parameters: {'profileVersion': 1},
    );
    return PageEditState(
      corners: corners,
      cropTransform: const PageTransform(translationX: 0.25),
      rotationAngle: rotation,
      filterType: ScanFilterType.magic,
      adjustments: adjustments,
      processingProfile: profile,
    );
  }

  test('rotation normalizes positive and negative turns', () {
    expect(PageEditState().rotateBy(90).normalizedRotation, 90);
    expect(
      PageEditState(rotationAngle: 90).rotateBy(90).normalizedRotation,
      180,
    );
    expect(
      PageEditState(rotationAngle: 180).rotateBy(90).normalizedRotation,
      270,
    );
    expect(
      PageEditState(rotationAngle: 270).rotateBy(90).normalizedRotation,
      0,
    );
    expect(PageEditState().rotateBy(-90).normalizedRotation, 270);
    expect(PageEditState(rotationAngle: 360).normalizedRotation, 0);
  });

  test('corners, transforms, and adjustments reject invalid edit state', () {
    expect(
      () => PageCorners(
        topLeft: const Point2D(0, 0),
        topRight: const Point2D(0, 0),
        bottomRight: const Point2D(1, 1),
        bottomLeft: const Point2D(0, 1),
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => PageCorners(
        topLeft: const Point2D(-0.1, 0),
        topRight: const Point2D(1, 0),
        bottomRight: const Point2D(1, 1),
        bottomLeft: const Point2D(0, 1),
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => const PageTransform(scaleX: 0).validate(),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => const ProcessingAdjustments(contrast: -1).validate(),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('edit state equality and cache identity are deterministic', () {
    final first = state();
    final second = state();
    final keyA = PageCacheIdentity.forState(
      documentId: 'doc-1',
      pageId: 'page-1',
      rawAssetIdentity: 'raw-v1',
      state: first,
    );
    final keyB = PageCacheIdentity.forState(
      documentId: 'doc-1',
      pageId: 'page-1',
      rawAssetIdentity: 'raw-v1',
      state: second,
    );
    final changed = PageCacheIdentity.forState(
      documentId: 'doc-1',
      pageId: 'page-1',
      rawAssetIdentity: 'raw-v1',
      state: state(rotation: 90),
    );
    expect(first, second);
    expect(keyA, keyB);
    expect(changed, isNot(keyA));
    expect(
      PageCacheIdentity.forState(
        documentId: 'doc-1',
        pageId: 'page-1',
        rawAssetIdentity: 'raw-v2',
        state: first,
      ),
      isNot(keyA),
    );
    final orderedA = const ProcessingProfile(parameters: {'a': 1, 'b': 2});
    final orderedB = const ProcessingProfile(parameters: {'b': 2, 'a': 1});
    expect(orderedA, orderedB);
    expect(
      PageCacheIdentity.forState(
        documentId: 'doc-1',
        pageId: 'page-1',
        rawAssetIdentity: 'raw-v1',
        state: PageEditState(processingProfile: orderedA),
      ),
      PageCacheIdentity.forState(
        documentId: 'doc-1',
        pageId: 'page-1',
        rawAssetIdentity: 'raw-v1',
        state: PageEditState(processingProfile: orderedB),
      ),
    );
  });

  test(
    'processed and thumbnail cache statuses distinguish missing, stale, and current',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'scanora-m04-cache-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final assets = FileSystemAssetStore(
        Directory(path.join(directory.path, 'assets')),
      );
      final database = ScanoraDatabase(
        databasePath: path.join(directory.path, 'cache.db'),
      );
      final repository = SqliteDocumentRepositoryV2(
        database: database,
        assetStore: assets,
      );
      addTearDown(database.close);
      final now = DateTime.utc(2026);
      await repository.save(
        ScanDocument(
          id: 'doc-1',
          title: 'Cache',
          createdAt: now,
          updatedAt: now,
          pages: [
            ScanPage(
              id: 'page-1',
              documentId: 'doc-1',
              pageIndex: 0,
              createdAt: now,
              updatedAt: now,
            ),
          ],
        ),
      );
      await repository.savePageEditState(
        pageId: 'page-1',
        state: state(),
        rawAssetIdentity: 'raw-a',
      );
      expect(
        await repository.getProcessedCacheStatus(
          pageId: 'page-1',
          rawAssetIdentity: 'raw-a',
        ),
        CacheStatus.missing,
      );
      expect(
        await repository.getThumbnailCacheStatus(
          pageId: 'page-1',
          rawAssetIdentity: 'raw-a',
        ),
        CacheStatus.missing,
      );
      await assets.saveProcessedImage('doc-1', 'page-1', [1]);
      await assets.saveThumbnail('doc-1', 'page-1', [2]);
      expect(
        await repository.getProcessedCacheStatus(
          pageId: 'page-1',
          rawAssetIdentity: 'raw-a',
        ),
        CacheStatus.stale,
      );
      expect(
        await repository.getThumbnailCacheStatus(
          pageId: 'page-1',
          rawAssetIdentity: 'raw-a',
        ),
        CacheStatus.stale,
      );
      await repository.markProcessedCacheCurrent(
        pageId: 'page-1',
        rawAssetIdentity: 'raw-a',
      );
      await repository.markThumbnailCacheCurrent(
        pageId: 'page-1',
        rawAssetIdentity: 'raw-a',
      );
      expect(
        await repository.getProcessedCacheStatus(
          pageId: 'page-1',
          rawAssetIdentity: 'raw-a',
        ),
        CacheStatus.current,
      );
      expect(
        await repository.getThumbnailCacheStatus(
          pageId: 'page-1',
          rawAssetIdentity: 'raw-a',
        ),
        CacheStatus.current,
      );
      await repository.savePageEditState(
        pageId: 'page-1',
        state: state(rotation: 90),
        rawAssetIdentity: 'raw-a',
      );
      expect(
        await repository.getProcessedCacheStatus(
          pageId: 'page-1',
          rawAssetIdentity: 'raw-a',
        ),
        CacheStatus.stale,
      );
      expect(
        await repository.getThumbnailCacheStatus(
          pageId: 'page-1',
          rawAssetIdentity: 'raw-a',
        ),
        CacheStatus.stale,
      );
      await repository.savePageEditState(
        pageId: 'page-1',
        state: state(),
        rawAssetIdentity: 'raw-a',
      );
      expect(
        await repository.getProcessedCacheStatus(
          pageId: 'page-1',
          rawAssetIdentity: 'raw-a',
        ),
        CacheStatus.current,
      );
      expect(
        await repository.getThumbnailCacheStatus(
          pageId: 'page-1',
          rawAssetIdentity: 'raw-a',
        ),
        CacheStatus.current,
      );
    },
  );

  test(
    'clean metadata can remain stale and raw identity changes the key',
    () async {
      final first = PageCacheIdentity.forState(
        documentId: 'doc',
        pageId: 'page',
        rawAssetIdentity: 'raw-a',
        state: state(),
      );
      final second = PageCacheIdentity.forState(
        documentId: 'doc',
        pageId: 'page',
        rawAssetIdentity: 'raw-b',
        state: state(),
      );
      expect(second, isNot(first));
    },
  );

  test(
    'page edit/cache state is isolated by document and page identity',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'scanora-m04-isolation-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final assets = FileSystemAssetStore(
        Directory(path.join(directory.path, 'assets')),
      );
      final database = ScanoraDatabase(
        databasePath: path.join(directory.path, 'isolation.db'),
      );
      final repository = SqliteDocumentRepositoryV2(
        database: database,
        assetStore: assets,
      );
      addTearDown(database.close);
      final now = DateTime.utc(2026);
      await repository.save(
        ScanDocument(
          id: 'doc-a',
          title: 'A',
          createdAt: now,
          updatedAt: now,
          pages: [
            ScanPage(
              id: 'same-page-a',
              documentId: 'doc-a',
              pageIndex: 0,
              createdAt: now,
              updatedAt: now,
            ),
            ScanPage(
              id: 'page-2',
              documentId: 'doc-a',
              pageIndex: 1,
              createdAt: now,
              updatedAt: now,
            ),
          ],
        ),
      );
      await repository.save(
        ScanDocument(
          id: 'doc-b',
          title: 'B',
          createdAt: now,
          updatedAt: now,
          pages: [
            ScanPage(
              id: 'same-page-b',
              documentId: 'doc-b',
              pageIndex: 0,
              createdAt: now,
              updatedAt: now,
            ),
          ],
        ),
      );
      final before = await repository.getPage('page-2');
      await repository.savePageEditState(
        pageId: 'same-page-b',
        state: state(rotation: 90),
        rawAssetIdentity: 'raw-a',
      );
      expect(
        (await repository.getPage('page-2'))!.editState,
        before!.editState,
      );
      expect((await repository.getPage('same-page-b'))!.documentId, 'doc-b');
      expect((await repository.getPage('page-2'))!.rotationAngle, 0);
      expect(
        PageCacheIdentity.forState(
          documentId: 'doc-a',
          pageId: 'same-page',
          rawAssetIdentity: 'raw',
          state: state(),
        ),
        isNot(
          PageCacheIdentity.forState(
            documentId: 'doc-b',
            pageId: 'same-page',
            rawAssetIdentity: 'raw',
            state: state(),
          ),
        ),
      );
    },
  );

  test(
    'v2 database upgrades to v3 and edit metadata survives reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp('scanora-m04-');
      final databasePath = path.join(directory.path, 'editing.db');
      addTearDown(() => directory.delete(recursive: true));
      final assets = FileSystemAssetStore(
        Directory(path.join(directory.path, 'assets')),
      );
      final database = ScanoraDatabase(databasePath: databasePath);
      final repository = SqliteDocumentRepositoryV2(
        database: database,
        assetStore: assets,
      );
      addTearDown(database.close);
      final now = DateTime.utc(2026);
      await repository.save(
        ScanDocument(
          id: 'doc-1',
          title: 'Editing',
          createdAt: now,
          updatedAt: now,
          pages: [
            ScanPage(
              id: 'page-1',
              documentId: 'doc-1',
              pageIndex: 0,
              rawImagePath: '/legacy/raw.jpg',
              processedImagePath: '/legacy/processed.jpg',
              createdAt: now,
              updatedAt: now,
            ),
          ],
        ),
      );
      await repository.savePageEditState(
        pageId: 'page-1',
        state: state(rotation: 90),
        rawAssetIdentity: 'raw-v1',
      );
      await database.close();

      final reopened = ScanoraDatabase(databasePath: databasePath);
      addTearDown(reopened.close);
      final reopenedRepository = SqliteDocumentRepositoryV2(
        database: reopened,
        assetStore: assets,
      );
      final page = await reopenedRepository.getPage('page-1');
      final db = await reopened.open();
      expect(await db.getVersion(), 3);
      expect(page!.editState.normalizedRotation, 90);
      expect(page.editState.filterType, ScanFilterType.magic);
      expect(page.editState.corners, corners);
      expect(page.rawImagePath, '/legacy/raw.jpg');
      expect(page.processedCacheKey, isNull);
      expect(
        await reopenedRepository.getProcessedCacheStatus(
          pageId: 'page-1',
          rawAssetIdentity: 'raw-v1',
        ),
        CacheStatus.missing,
      );
    },
  );

  test(
    'edit save invalidates cache metadata but leaves raw bytes unchanged',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'scanora-m04-raw-',
      );
      final databasePath = path.join(directory.path, 'editing.db');
      addTearDown(() => directory.delete(recursive: true));
      final assets = FileSystemAssetStore(
        Directory(path.join(directory.path, 'assets')),
      );
      final rawFile = File(path.join(directory.path, 'raw.jpg'))
        ..writeAsBytesSync([1, 2, 3, 4]);
      final before = rawFile.readAsBytesSync();
      final database = ScanoraDatabase(databasePath: databasePath);
      final repository = SqliteDocumentRepositoryV2(
        database: database,
        assetStore: assets,
      );
      addTearDown(database.close);
      final now = DateTime.utc(2026);
      await repository.save(
        ScanDocument(
          id: 'doc-1',
          title: 'Raw',
          createdAt: now,
          updatedAt: now,
          pages: [
            ScanPage(
              id: 'page-1',
              documentId: 'doc-1',
              pageIndex: 0,
              rawImagePath: rawFile.path,
              createdAt: now,
              updatedAt: now,
            ),
          ],
        ),
      );
      await repository.savePageEditState(
        pageId: 'page-1',
        state: state(rotation: 180),
        rawAssetIdentity: 'raw-v1',
      );
      expect(rawFile.readAsBytesSync(), before);
      expect(
        await repository.getProcessedCacheStatus(
          pageId: 'page-1',
          rawAssetIdentity: 'raw-v1',
        ),
        CacheStatus.missing,
      );
    },
  );

  test('missing page and malformed persisted profile fail safely', () async {
    final directory = await Directory.systemTemp.createTemp(
      'scanora-m04-failure-',
    );
    final databasePath = path.join(directory.path, 'editing.db');
    addTearDown(() => directory.delete(recursive: true));
    final database = ScanoraDatabase(databasePath: databasePath);
    final repository = SqliteDocumentRepositoryV2(database: database);
    addTearDown(database.close);
    expect(
      () => repository.savePageEditState(
        pageId: 'missing',
        state: PageEditState(),
        rawAssetIdentity: 'raw',
      ),
      throwsA(isA<StorageFailure>()),
    );
    final db = await database.open();
    await db.insert('documents', {
      'id': 'doc',
      'title': 'Doc',
      'created_at': DateTime.utc(2026).toIso8601String(),
      'updated_at': DateTime.utc(2026).toIso8601String(),
      'favorite': 0,
      'tags_json': '[]',
      'page_count': 1,
    });
    await db.insert('pages', {
      'id': 'page',
      'document_id': 'doc',
      'page_index': 0,
      'processing_profile_json': '{bad',
      'crop_transform_json': '{}',
      'is_dirty': 0,
      'created_at': DateTime.utc(2026).toIso8601String(),
      'updated_at': DateTime.utc(2026).toIso8601String(),
    });
    expect(() => repository.getPage('page'), throwsA(isA<StorageFailure>()));
  });
}
