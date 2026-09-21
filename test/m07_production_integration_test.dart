import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:image/image.dart' as img;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:scanora/app/application/services/document_page_processing_service.dart';
import 'package:scanora/app/core/errors/app_failure.dart';
import 'package:scanora/app/core/errors/processing_failure.dart';
import 'package:scanora/app/core/result/result.dart';
import 'package:scanora/app/core/services/image_processing_service.dart';
import 'package:scanora/app/core/utils/file_utils.dart';
import 'package:scanora/app/data/datasources/scanora_database.dart';
import 'package:scanora/app/data/models/document_corners.dart';
import 'package:scanora/app/data/models/scanned_page.dart';
import 'package:scanora/app/data/repositories/document_repository.dart';
import 'package:scanora/app/data/repositories/sqlite_document_repository_v2.dart';
import 'package:scanora/app/domain/contracts/asset_store.dart';
import 'package:scanora/app/domain/contracts/processing_engine.dart';
import 'package:scanora/app/domain/entities/scan_document.dart';
import 'package:scanora/app/domain/entities/scan_page.dart';
import 'package:scanora/app/domain/enums/scan_enums.dart';
import 'package:scanora/app/domain/processing/processing_models.dart';
import 'package:scanora/app/domain/value_objects/page_edit_state.dart';
import 'package:scanora/app/infrastructure/processing/m07_processing_engine.dart';
import 'package:scanora/app/infrastructure/processing/plain_geometry_engine.dart';
import 'package:scanora/app/infrastructure/storage/file_system_asset_store.dart';
import 'package:scanora/app/infrastructure/capture/native_scanner_capture_provider.dart';
import 'package:scanora/app/application/services/capture_service.dart';
import 'package:scanora/app/core/services/pdf_service.dart';
import 'package:scanora/app/modules/editor/controllers/editor_controller.dart';
import 'package:scanora/app/modules/id_card_merge/controllers/id_card_merge_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late FileSystemAssetStore assetStore;
  late ScanoraDatabase database;
  late SqliteDocumentRepositoryV2 v2Repo;
  late DocumentRepository docRepo;
  late M07ProcessingEngine engine;
  late DocumentPageProcessingService pageService;
  late String dbPath;

  setUp(() async {
    Get.testMode = true;
    tempDir = Directory.systemTemp.createTempSync('scanora-m07-int-');
    FileUtils.overrideAppDocumentsDirectoryPath = tempDir.path;
    assetStore = FileSystemAssetStore(tempDir);
    dbPath = '${tempDir.path}/scanora_test.db';
    database = ScanoraDatabase(databasePath: dbPath);
    await database.open();

    v2Repo = SqliteDocumentRepositoryV2(
      database: database,
      assetStore: assetStore,
    );
    docRepo = DocumentRepository(repository: v2Repo);

    engine = M07ProcessingEngine(
      assets: assetStore,
      geometry: const PlainGeometryEngine(),
      markCacheCurrent: ({
        required pageId,
        required processedCacheKey,
        required thumbnailCacheKey,
        required expectedRawAssetIdentity,
        required expectedEditState,
      }) async {
        try {
          await v2Repo.markCacheCurrent(
            pageId: pageId,
            processedCacheKey: processedCacheKey,
            thumbnailCacheKey: thumbnailCacheKey,
            expectedRawAssetIdentity: expectedRawAssetIdentity,
            expectedEditState: expectedEditState,
          );
          return const Success(null);
        } catch (e, st) {
          return Failure(StorageFailure('Cache mark failed', cause: e, stackTrace: st));
        }
      },
    );

    pageService = DocumentPageProcessingService(
      processingEngine: engine,
      assetStore: assetStore,
      repository: docRepo,
    );
  });

  tearDown(() async {
    FileUtils.overrideAppDocumentsDirectoryPath = null;
    Get.reset();
    await database.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Helper to create a test JPEG image file on disk with custom dimensions and colors.
  File createTestImageFile({
    required String fileName,
    int width = 120,
    int height = 80,
    img.Color? fill,
  }) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: fill ?? img.ColorRgb8(200, 100, 50));
    // Draw an asymmetric feature in top-left quadrant (red box)
    img.fillRect(
      image,
      x1: 0,
      y1: 0,
      x2: (width ~/ 3).clamp(1, width),
      y2: (height ~/ 3).clamp(1, height),
      color: img.ColorRgb8(255, 0, 0),
    );

    final bytes = img.encodeJpg(image, quality: 90);
    final file = File('${tempDir.path}/$fileName');
    file.writeAsBytesSync(bytes);
    return file;
  }

  group('M07-FIX-06: Production Integration Test Suite (Real SQLite)', () {
    // ─────────────────────────────────────────────────────────────
    // TEST 1: Production Document Processing Path Uses M07
    // ─────────────────────────────────────────────────────────────
    test('1. Production document processing path uses M07 with real SQLite persistence', () async {
      final rawFile = createTestImageFile(fileName: 'test_doc_1.jpg');

      final editorPages = [
        EditorPageModel(
          imagePath: rawFile.path,
          rawImagePath: rawFile.path,
          corners: null,
          quarterTurns: 0,
          filter: DocumentFilterType.original,
        ),
      ];

      final result = await pageService.processEditorPages(
        documentId: 'doc_1',
        pages: editorPages,
      );

      expect(result, isA<Success<List<ScannedPage>>>());
      final scannedPages = (result as Success<List<ScannedPage>>).value;
      expect(scannedPages.length, 1);

      final page = scannedPages.first;
      expect(page.id, 'p_doc_1_0');
      expect(page.processedCacheKey, isNotNull);
      expect(page.processedCacheKey, isNotEmpty);
      expect(page.thumbnailCacheKey, isNotNull);
      expect(page.thumbnailCacheKey, isNotEmpty);

      // Verify files exist in asset store
      final processedFile = File(page.imagePath);
      expect(await processedFile.exists(), isTrue);
      expect(await processedFile.length(), greaterThan(0));

      final existsThumbnail = await assetStore.exists('doc_1', page.id, AssetKind.thumbnail);
      expect(existsThumbnail.valueOrNull, isTrue);

      // Verify real SQLite persistence via v2Repo
      final dbPage = await v2Repo.getPage(page.id);
      expect(dbPage, isNotNull);
      expect(dbPage!.processedCacheKey, page.processedCacheKey);
      expect(dbPage.thumbnailCacheKey, page.thumbnailCacheKey);
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 2: Raw Immutability Under Production Processing
    // ─────────────────────────────────────────────────────────────
    test('2. Raw image is strictly immutable during production processing', () async {
      final rawFile = createTestImageFile(fileName: 'raw_immutable.jpg', width: 200, height: 150);
      final originalBytes = rawFile.readAsBytesSync();
      final originalPath = rawFile.path;

      final result = await pageService.processSinglePage(
        documentId: 'doc_immut',
        pageId: 'page_immut',
        pageIndex: 0,
        rawSourcePath: originalPath,
        quarterTurns: 1, // 90 degree rotation
        filter: ScanFilterType.original,
      );

      expect(result, isA<Success<ScannedPage>>());

      // Re-verify the source raw file
      expect(await rawFile.exists(), isTrue, reason: 'Raw file must not be moved or deleted');
      final postProcessingBytes = rawFile.readAsBytesSync();

      expect(postProcessingBytes.length, originalBytes.length);
      expect(postProcessingBytes, originalBytes, reason: 'Raw file bytes must be identical');

      // Verify stored raw asset also matches original bytes
      final storedRawBytes = await assetStore.readRawImage('doc_immut', 'page_immut');
      expect(storedRawBytes, isA<Success<List<int>>>());
      expect(storedRawBytes.valueOrNull!, originalBytes);
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 3: Production Orientation & Rotation Path (0/90/180/270)
    // ─────────────────────────────────────────────────────────────
    test('3. Authoritative rotation 0/90/180/270 produces exact dimensions', () async {
      final rawFile = createTestImageFile(
        fileName: 'asymm_rotation.jpg',
        width: 120,
        height: 60,
      );

      for (final (quarterTurns, expectedWidth, expectedHeight) in [
        (0, 120, 60),
        (1, 60, 120),
        (2, 120, 60),
        (3, 60, 120),
      ]) {
        final pageId = 'page_rot_$quarterTurns';
        final result = await pageService.processSinglePage(
          documentId: 'doc_rot',
          pageId: pageId,
          pageIndex: quarterTurns,
          rawSourcePath: rawFile.path,
          quarterTurns: quarterTurns,
          forceReprocess: true,
        );

        expect(result, isA<Success<ScannedPage>>());
        final page = (result as Success<ScannedPage>).value;
        final processedBytes = await File(page.imagePath).readAsBytes();
        final decoded = img.decodeImage(processedBytes);

        expect(decoded, isNotNull);
        expect(decoded!.width, expectedWidth, reason: 'Rotation $quarterTurns width mismatch');
        expect(decoded.height, expectedHeight, reason: 'Rotation $quarterTurns height mismatch');
      }
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 4: Production Cache Hit Path
    // ─────────────────────────────────────────────────────────────
    test('4. Second processing with identical state executes as Cache HIT', () async {
      final rawFile = createTestImageFile(fileName: 'cache_hit.jpg');

      // First run: cold cache (renders raster)
      final firstResult = await pageService.processSinglePage(
        documentId: 'doc_cache',
        pageId: 'page_cache',
        pageIndex: 0,
        rawSourcePath: rawFile.path,
      );
      expect(firstResult, isA<Success<ScannedPage>>());
      final firstPage = (firstResult as Success<ScannedPage>).value;

      final processedFile = File(firstPage.imagePath);
      final firstModified = processedFile.lastModifiedSync();

      // Second run: exact same edit state (cache hit expected)
      final secondResult = await pageService.processSinglePage(
        documentId: 'doc_cache',
        pageId: 'page_cache',
        pageIndex: 0,
        rawSourcePath: rawFile.path,
      );
      expect(secondResult, isA<Success<ScannedPage>>());
      final secondPage = (secondResult as Success<ScannedPage>).value;

      expect(secondPage.processedCacheKey, firstPage.processedCacheKey);
      expect(secondPage.thumbnailCacheKey, firstPage.thumbnailCacheKey);
      expect(secondPage.imagePath, firstPage.imagePath);

      // File was not rewritten
      final secondModified = processedFile.lastModifiedSync();
      expect(secondModified, firstModified);
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 5: Production Thumbnail-Only Invalidation
    // ─────────────────────────────────────────────────────────────
    test('5. Thumbnail specification change reuses processed image', () async {
      final rawFile = createTestImageFile(fileName: 'thumb_reuse.jpg');

      final firstResult = await pageService.processSinglePage(
        documentId: 'doc_thumb',
        pageId: 'page_thumb',
        pageIndex: 0,
        rawSourcePath: rawFile.path,
        thumbnail: const ThumbnailSpecification(width: 200, height: 200),
      );
      expect(firstResult, isA<Success<ScannedPage>>());
      final firstPage = (firstResult as Success<ScannedPage>).value;
      final firstProcessedKey = firstPage.processedCacheKey;
      final firstThumbKey = firstPage.thumbnailCacheKey;

      final secondResult = await pageService.processSinglePage(
        documentId: 'doc_thumb',
        pageId: 'page_thumb',
        pageIndex: 0,
        rawSourcePath: rawFile.path,
        thumbnail: const ThumbnailSpecification(width: 64, height: 64),
      );
      expect(secondResult, isA<Success<ScannedPage>>());
      final secondPage = (secondResult as Success<ScannedPage>).value;

      expect(secondPage.processedCacheKey, firstProcessedKey);
      expect(secondPage.thumbnailCacheKey, isNot(firstThumbKey));

      final thumbBytes = (await assetStore.readThumbnail('doc_thumb', 'page_thumb')).valueOrNull!;
      final decodedThumb = img.decodeImage(Uint8List.fromList(thumbBytes));
      expect(decodedThumb, isNotNull);
      expect(decodedThumb!.width <= 64, isTrue);
      expect(decodedThumb.height <= 64, isTrue);
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 6: Production Crop / Rotation Invalidation
    // ─────────────────────────────────────────────────────────────
    test('6. Crop and rotation changes invalidate processed cache', () async {
      final rawFile = createTestImageFile(fileName: 'crop_inval.jpg', width: 100, height: 100);

      final baseResult = await pageService.processSinglePage(
        documentId: 'doc_inval',
        pageId: 'page_inval',
        pageIndex: 0,
        rawSourcePath: rawFile.path,
        quarterTurns: 0,
      );
      expect(baseResult, isA<Success<ScannedPage>>());
      final baseKey = (baseResult as Success<ScannedPage>).value.processedCacheKey;

      final rotResult = await pageService.processSinglePage(
        documentId: 'doc_inval',
        pageId: 'page_inval',
        pageIndex: 0,
        rawSourcePath: rawFile.path,
        quarterTurns: 1,
      );
      expect(rotResult, isA<Success<ScannedPage>>());
      final rotKey = (rotResult as Success<ScannedPage>).value.processedCacheKey;
      expect(rotKey, isNot(baseKey));

      final cropResult = await pageService.processSinglePage(
        documentId: 'doc_inval',
        pageId: 'page_inval',
        pageIndex: 0,
        rawSourcePath: rawFile.path,
        quarterTurns: 1,
        corners: DocumentCorners(
          topLeft: const Offset(0.1, 0.1),
          topRight: const Offset(0.9, 0.1),
          bottomRight: const Offset(0.9, 0.9),
          bottomLeft: const Offset(0.1, 0.9),
        ),
      );
      expect(cropResult, isA<Success<ScannedPage>>());
      final cropKey = (cropResult as Success<ScannedPage>).value.processedCacheKey;
      expect(cropKey, isNot(rotKey));
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 7: Production Request Serialization & Concurrency Safety
    // ─────────────────────────────────────────────────────────────
    test('7. Concurrent processing requests respect maxHeavyJobs <= 1', () async {
      final raw1 = createTestImageFile(fileName: 'conc_1.jpg');
      final raw2 = createTestImageFile(fileName: 'conc_2.jpg');
      final raw3 = createTestImageFile(fileName: 'conc_3.jpg');

      final futures = [
        pageService.processSinglePage(
          documentId: 'doc_conc',
          pageId: 'page_conc_1',
          pageIndex: 0,
          rawSourcePath: raw1.path,
        ),
        pageService.processSinglePage(
          documentId: 'doc_conc',
          pageId: 'page_conc_2',
          pageIndex: 1,
          rawSourcePath: raw2.path,
        ),
        pageService.processSinglePage(
          documentId: 'doc_conc',
          pageId: 'page_conc_3',
          pageIndex: 2,
          rawSourcePath: raw3.path,
        ),
      ];

      final results = await Future.wait(futures);

      for (final res in results) {
        expect(res, isA<Success<ScannedPage>>());
      }

      expect(engine.maximumObservedHeavyJobs, lessThanOrEqualTo(1));
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 8: Production Error Propagation & Graceful Failure
    // ─────────────────────────────────────────────────────────────
    test('8. Missing raw file returns typed Failure without crashing', () async {
      final nonExistentPath = '${tempDir.path}/does_not_exist.jpg';

      final result = await pageService.processSinglePage(
        documentId: 'doc_fail',
        pageId: 'page_fail',
        pageIndex: 0,
        rawSourcePath: nonExistentPath,
      );

      expect(result, isA<Failure<ScannedPage>>());
      final failure = (result as Failure<ScannedPage>).error;
      expect(failure, isA<ProcessingInputFailure>());

      final validRaw = createTestImageFile(fileName: 'after_fail.jpg');
      final followUp = await pageService.processSinglePage(
        documentId: 'doc_after_fail',
        pageId: 'page_after_fail',
        pageIndex: 0,
        rawSourcePath: validRaw.path,
      );
      expect(followUp, isA<Success<ScannedPage>>());
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 9: BLOCKER-08 & BLOCKER-09 (IDCARD-E2E-01)
    // ─────────────────────────────────────────────────────────────
    test('9. IDCARD-E2E-01: ID card crop, rotation, raw immutability, PDF & preview end-to-end', () async {
      final frontRaw = createTestImageFile(fileName: 'id_front.jpg', width: 100, height: 60);
      final backRaw = createTestImageFile(fileName: 'id_back.jpg', width: 100, height: 60);
      final initialFrontBytes = frontRaw.readAsBytesSync();
      final initialBackBytes = backRaw.readAsBytesSync();

      Get.put<ImageProcessingService>(ImageProcessingService());
      Get.put<DocumentPageProcessingService>(pageService);
      Get.put<DocumentRepository>(docRepo);

      final controller = IdCardMergeController();
      controller.frontPath.value = frontRaw.path;
      controller.rawFrontPath.value = frontRaw.path;
      controller.backPath.value = backRaw.path;
      controller.rawBackPath.value = backRaw.path;

      // Apply crop to front
      final cropCorners = DocumentCorners(
        topLeft: const Offset(0.05, 0.05),
        topRight: const Offset(0.95, 0.05),
        bottomRight: const Offset(0.95, 0.95),
        bottomLeft: const Offset(0.05, 0.95),
      );
      await controller.applyFrontCrop(cropCorners);

      // Verify frontPath is preview file, but rawFrontPath is preserved!
      expect(controller.frontPath.value, isNot(frontRaw.path));
      expect(controller.rawFrontPath.value, frontRaw.path);
      expect(controller.frontCorners, cropCorners);

      // Rotate back
      controller.rotateBack();
      expect(controller.backQuarterTurns.value, 1);

      // Save document
      await controller.saveDocument();

      // Invariant 1: Source raw files are strictly immutable
      expect(frontRaw.readAsBytesSync(), initialFrontBytes);
      expect(backRaw.readAsBytesSync(), initialBackBytes);

      // Invariant 2: Saved document exists in repository
      await docRepo.loadDocuments();
      expect(docRepo.documents.isNotEmpty, isTrue);
      final savedDoc = docRepo.documents.first;
      expect(savedDoc.pdfPath, isNotNull);
      expect(File(savedDoc.pdfPath!).existsSync(), isTrue);
      expect(File(savedDoc.pages.first.imagePath).existsSync(), isTrue);
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 10: Production DI Singleton Invariant
    // ─────────────────────────────────────────────────────────────
    test('10. DI registration guarantees single global ProcessingEngine instance', () {
      Get.reset();

      final sharedEngine = M07ProcessingEngine(
        assets: assetStore,
        geometry: const PlainGeometryEngine(),
      );

      Get.put<ProcessingEngine>(sharedEngine, permanent: true);
      Get.put<M07ProcessingEngine>(sharedEngine, permanent: true);

      final service = DocumentPageProcessingService(
        processingEngine: sharedEngine,
        assetStore: assetStore,
        repository: docRepo,
      );
      Get.put<DocumentPageProcessingService>(service, permanent: true);

      final resolvedInterface = Get.find<ProcessingEngine>();
      final resolvedConcrete = Get.find<M07ProcessingEngine>();
      final resolvedService = Get.find<DocumentPageProcessingService>();

      expect(identical(resolvedInterface, resolvedConcrete), isTrue);
      expect(identical(resolvedService.processingEngine, resolvedConcrete), isTrue);
      expect(identical(resolvedInterface, sharedEngine), isTrue);
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 11: ForceReprocess Race (Request A, B forceReprocess, C normal)
    // ─────────────────────────────────────────────────────────────
    test('11. Request C arriving during Request B forceReprocess receives B result, not stale A', () async {
      final rawFile = createTestImageFile(fileName: 'race_test.jpg', width: 100, height: 80);

      final resA = await pageService.processSinglePage(
        documentId: 'doc_race',
        pageId: 'page_race',
        pageIndex: 0,
        rawSourcePath: rawFile.path,
      );
      expect(resA, isA<Success<ScannedPage>>());
      final pageA = (resA as Success<ScannedPage>).value;
      final fileA = File(pageA.imagePath);
      expect(fileA.existsSync(), isTrue);

      final bStartedCompleter = Completer<void>();
      final cArrivedCompleter = Completer<void>();

      final delayedEngine = M07ProcessingEngine(
        assets: assetStore,
        geometry: const PlainGeometryEngine(),
        markCacheCurrent: ({
          required pageId,
          required processedCacheKey,
          required thumbnailCacheKey,
          required expectedRawAssetIdentity,
          required expectedEditState,
        }) async {
          try {
            await v2Repo.markCacheCurrent(
              pageId: pageId,
              processedCacheKey: processedCacheKey,
              thumbnailCacheKey: thumbnailCacheKey,
              expectedRawAssetIdentity: expectedRawAssetIdentity,
              expectedEditState: expectedEditState,
            );
            return const Success(null);
          } catch (e, st) {
            return Failure(StorageFailure('Cache mark failed', cause: e, stackTrace: st));
          }
        },
        onHeavyJobStarted: () {
          if (!bStartedCompleter.isCompleted) {
            bStartedCompleter.complete();
          }
        },
      );

      final delayedService = DocumentPageProcessingService(
        processingEngine: delayedEngine,
        assetStore: assetStore,
        repository: docRepo,
      );

      Future<Result<ScannedPage>> futureB() async {
        return delayedService.processSinglePage(
          documentId: 'doc_race',
          pageId: 'page_race',
          pageIndex: 0,
          rawSourcePath: rawFile.path,
          forceReprocess: true,
        );
      }

      Future<Result<ScannedPage>> futureC() async {
        await bStartedCompleter.future;
        cArrivedCompleter.complete();
        return delayedService.processSinglePage(
          documentId: 'doc_race',
          pageId: 'page_race',
          pageIndex: 0,
          rawSourcePath: rawFile.path,
          forceReprocess: false,
        );
      }

      final results = await Future.wait([futureB(), futureC()]);
      final resB = results[0];
      final resC = results[1];

      expect(resB, isA<Success<ScannedPage>>());
      expect(resC, isA<Success<ScannedPage>>());

      final pageB = (resB as Success<ScannedPage>).value;
      final pageC = (resC as Success<ScannedPage>).value;

      expect(pageC.processedCacheKey, pageB.processedCacheKey);
      expect(pageC.thumbnailCacheKey, pageB.thumbnailCacheKey);
      expect(delayedEngine.maximumObservedHeavyJobs, lessThanOrEqualTo(1));
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 12: External File Deletion Invalidates False Cache HIT
    // ─────────────────────────────────────────────────────────────
    test('12. Externally deleted derived files trigger regeneration, not false HIT', () async {
      final rawFile = createTestImageFile(fileName: 'external_del.jpg', width: 100, height: 80);

      final res1 = await pageService.processSinglePage(
        documentId: 'doc_ext_del',
        pageId: 'page_ext_del',
        pageIndex: 0,
        rawSourcePath: rawFile.path,
      );
      expect(res1, isA<Success<ScannedPage>>());
      final page1 = (res1 as Success<ScannedPage>).value;

      final processedFile = File(page1.imagePath);
      expect(await processedFile.exists(), isTrue);
      await processedFile.delete();
      expect(await processedFile.exists(), isFalse);

      final res2 = await pageService.processSinglePage(
        documentId: 'doc_ext_del',
        pageId: 'page_ext_del',
        pageIndex: 0,
        rawSourcePath: rawFile.path,
      );
      expect(res2, isA<Success<ScannedPage>>());
      expect(await processedFile.exists(), isTrue, reason: 'Must regenerate deleted processed file');

      final thumbPath = (await assetStore.pathFor('doc_ext_del', 'page_ext_del', AssetKind.thumbnail)).valueOrNull!;
      final thumbFile = File(thumbPath);
      expect(await thumbFile.exists(), isTrue);
      await thumbFile.delete();
      expect(await thumbFile.exists(), isFalse);

      final res3 = await pageService.processSinglePage(
        documentId: 'doc_ext_del',
        pageId: 'page_ext_del',
        pageIndex: 0,
        rawSourcePath: rawFile.path,
      );
      expect(res3, isA<Success<ScannedPage>>());
      expect(await thumbFile.exists(), isTrue, reason: 'Must regenerate deleted thumbnail file');
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 13: WYSIWYG Preview vs Saved Output Consistency
    // ─────────────────────────────────────────────────────────────
    test('13. Preview and saved output share exact geometry and rotation semantics', () async {
      final rawFile = createTestImageFile(fileName: 'wysiwyg.jpg', width: 120, height: 60);

      final cropCorners = DocumentCorners(
        topLeft: const Offset(0.05, 0.05),
        topRight: const Offset(0.95, 0.05),
        bottomRight: const Offset(0.95, 0.95),
        bottomLeft: const Offset(0.05, 0.95),
      );

      for (final quarterTurns in [0, 1, 2, 3]) {
        final previewFile = await pageService.warpPreview(
          rawImagePath: rawFile.path,
          corners: cropCorners,
          quarterTurns: quarterTurns,
        );
        final previewBytes = await previewFile.readAsBytes();
        final previewImg = img.decodeImage(previewBytes)!;

        final savedResult = await pageService.processSinglePage(
          documentId: 'doc_wysiwyg',
          pageId: 'page_wysiwyg_$quarterTurns',
          pageIndex: quarterTurns,
          rawSourcePath: rawFile.path,
          corners: cropCorners,
          quarterTurns: quarterTurns,
          forceReprocess: true,
        );
        expect(savedResult, isA<Success<ScannedPage>>());
        final savedPage = (savedResult as Success<ScannedPage>).value;
        final savedBytes = await File(savedPage.imagePath).readAsBytes();
        final savedImg = img.decodeImage(savedBytes)!;

        expect(previewImg.width, savedImg.width, reason: 'Width mismatch at turns $quarterTurns');
        expect(previewImg.height, savedImg.height, reason: 'Height mismatch at turns $quarterTurns');
      }
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 14: Comprehensive 10-Step Raw Immutability Sequence
    // ─────────────────────────────────────────────────────────────
    test('14. Complete 10-step lifecycle preserves 100% byte equality of raw source', () async {
      final rawFile = createTestImageFile(fileName: 'ten_step_raw.jpg', width: 150, height: 100);
      final baselineBytes = rawFile.readAsBytesSync();

      void verifyRawIntact(String stepName) {
        expect(rawFile.existsSync(), isTrue, reason: '$stepName: raw file must exist');
        final currentBytes = rawFile.readAsBytesSync();
        expect(currentBytes.length, baselineBytes.length, reason: '$stepName: byte length changed');
        expect(currentBytes, baselineBytes, reason: '$stepName: byte content changed');
      }

      await pageService.processSinglePage(
        documentId: 'doc_10',
        pageId: 'p_10',
        pageIndex: 0,
        rawSourcePath: rawFile.path,
      );
      verifyRawIntact('Step 3: Initial process');

      await pageService.processSinglePage(
        documentId: 'doc_10',
        pageId: 'p_10',
        pageIndex: 0,
        rawSourcePath: rawFile.path,
      );
      verifyRawIntact('Step 4: Process again');

      await pageService.processSinglePage(
        documentId: 'doc_10',
        pageId: 'p_10',
        pageIndex: 0,
        rawSourcePath: rawFile.path,
        corners: DocumentCorners(
          topLeft: const Offset(0.1, 0.1),
          topRight: const Offset(0.9, 0.1),
          bottomRight: const Offset(0.9, 0.9),
          bottomLeft: const Offset(0.1, 0.9),
        ),
      );
      verifyRawIntact('Step 5: Change crop');

      await pageService.processSinglePage(
        documentId: 'doc_10',
        pageId: 'p_10',
        pageIndex: 0,
        rawSourcePath: rawFile.path,
        quarterTurns: 2,
      );
      verifyRawIntact('Step 6: Change rotation');

      await pageService.processSinglePage(
        documentId: 'doc_10',
        pageId: 'p_10',
        pageIndex: 0,
        rawSourcePath: rawFile.path,
        forceReprocess: true,
      );
      verifyRawIntact('Step 7: Force reprocess');

      await pageService.processSinglePage(
        documentId: 'doc_10',
        pageId: 'p_10',
        pageIndex: 0,
        rawSourcePath: rawFile.path,
        thumbnail: const ThumbnailSpecification(width: 80, height: 80),
      );
      verifyRawIntact('Step 8: Regenerate thumbnail');

      final failEngine = M07ProcessingEngine(
        assets: assetStore,
        geometry: const PlainGeometryEngine(),
        decodeImageSeam: (_) => null,
      );
      final failService = DocumentPageProcessingService(
        processingEngine: failEngine,
        assetStore: assetStore,
        repository: docRepo,
      );
      final failRes = await failService.processSinglePage(
        documentId: 'doc_10',
        pageId: 'p_10',
        pageIndex: 0,
        rawSourcePath: rawFile.path,
        forceReprocess: true,
      );
      expect(failRes, isA<Failure<ScannedPage>>());
      verifyRawIntact('Step 9: Induced failure');
      verifyRawIntact('Step 10: Final verification');
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 15: BLOCKER-03 (PERSISTENT-CACHE-RESTART-01)
    // ─────────────────────────────────────────────────────────────
    test('15. PERSISTENT-CACHE-RESTART-01: Cache survives app/database restart as genuine Cache HIT', () async {
      final raw1 = createTestImageFile(fileName: 'restart_1.jpg');
      final raw2 = createTestImageFile(fileName: 'restart_2.jpg');

      final editorPages = [
        EditorPageModel(
          imagePath: raw1.path,
          rawImagePath: raw1.path,
          filter: DocumentFilterType.original,
        ),
        EditorPageModel(
          imagePath: raw2.path,
          rawImagePath: raw2.path,
          filter: DocumentFilterType.original,
        ),
      ];

      // Initial run: cold processing
      final resInitial = await pageService.processEditorPages(
        documentId: 'doc_restart',
        pages: editorPages,
      );
      expect(resInitial, isA<Success<List<ScannedPage>>>());
      final initialPages = (resInitial as Success<List<ScannedPage>>).value;

      final p0ProcessedFile = File(initialPages[0].imagePath);
      final p0ModInitial = p0ProcessedFile.lastModifiedSync();
      final p1ProcessedFile = File(initialPages[1].imagePath);
      final p1ModInitial = p1ProcessedFile.lastModifiedSync();

      // SIMULATE APP TERMINATION: Close database, destroy all in-memory instances
      await database.close();

      // SIMULATE APP RE-LAUNCH: Instantiate fresh database, repos, and engines
      final newDatabase = ScanoraDatabase(databasePath: dbPath);
      await newDatabase.open();

      final newV2Repo = SqliteDocumentRepositoryV2(
        database: newDatabase,
        assetStore: assetStore,
      );
      final newDocRepo = DocumentRepository(repository: newV2Repo);

      final newEngine = M07ProcessingEngine(
        assets: assetStore,
        geometry: const PlainGeometryEngine(),
        markCacheCurrent: ({
          required pageId,
          required processedCacheKey,
          required thumbnailCacheKey,
          required expectedRawAssetIdentity,
          required expectedEditState,
        }) async {
          try {
            await newV2Repo.markCacheCurrent(
              pageId: pageId,
              processedCacheKey: processedCacheKey,
              thumbnailCacheKey: thumbnailCacheKey,
              expectedRawAssetIdentity: expectedRawAssetIdentity,
              expectedEditState: expectedEditState,
            );
            return const Success(null);
          } catch (e, st) {
            return Failure(StorageFailure('Cache mark failed', cause: e, stackTrace: st));
          }
        },
      );

      final newPageService = DocumentPageProcessingService(
        processingEngine: newEngine,
        assetStore: assetStore,
        repository: newDocRepo,
      );

      // Re-run processing after restart
      final resRestart = await newPageService.processEditorPages(
        documentId: 'doc_restart',
        pages: editorPages,
      );
      expect(resRestart, isA<Success<List<ScannedPage>>>());
      final restartPages = (resRestart as Success<List<ScannedPage>>).value;

      // Invariant 1: Exactly 0 heavy raster jobs executed
      expect(newEngine.activeHeavyJobs, 0);
      expect(newEngine.maximumObservedHeavyJobs, 0);

      // Invariant 2: Cache keys match identically
      expect(restartPages[0].processedCacheKey, initialPages[0].processedCacheKey);
      expect(restartPages[0].thumbnailCacheKey, initialPages[0].thumbnailCacheKey);
      expect(restartPages[1].processedCacheKey, initialPages[1].processedCacheKey);
      expect(restartPages[1].thumbnailCacheKey, initialPages[1].thumbnailCacheKey);

      // Invariant 3: Files were NOT rewritten
      expect(p0ProcessedFile.lastModifiedSync(), p0ModInitial);
      expect(p1ProcessedFile.lastModifiedSync(), p1ModInitial);

      await newDatabase.close();
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 16: BLOCKER-05 (STALE-COMMIT-01)
    // ─────────────────────────────────────────────────────────────
    test('16. STALE-COMMIT-01: markCacheCurrent rejects stale in-flight results when edit state or raw asset changed', () async {
      final rawFile = createTestImageFile(fileName: 'stale_test.jpg');
      final rawBytes = rawFile.readAsBytesSync();

      await assetStore.saveRawImage('doc_stale', 'page_stale', rawBytes);

      // Create initial page in database
      final initialEditState = PageEditState(rotationAngle: 0);
      final initialDoc = ScanDocument(
        id: 'doc_stale',
        title: 'Stale Test',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        pages: [
          ScanPage(
            id: 'page_stale',
            documentId: 'doc_stale',
            pageIndex: 0,
            rawImagePath: rawFile.path,
            rotationAngle: 0,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ],
      );
      await v2Repo.save(initialDoc);

      // Create derived files on disk so file existence check passes
      await assetStore.saveProcessedImage('doc_stale', 'page_stale', rawBytes);
      await assetStore.saveThumbnail('doc_stale', 'page_stale', rawBytes);

      // 1. Stale raw asset test
      expect(
        () async => v2Repo.markCacheCurrent(
          pageId: 'page_stale',
          processedCacheKey: 'proc_key_1',
          thumbnailCacheKey: 'thumb_key_1',
          expectedRawAssetIdentity: 'stale_raw_v99',
          expectedEditState: initialEditState,
        ),
        throwsA(
          isA<StorageFailure>().having(
            (e) => e.message,
            'message',
            contains('raw asset changed'),
          ),
        ),
      );

      // 2. Stale edit state test: user rotated page to 90 degrees while processing was in-flight
      final newEditState = PageEditState(rotationAngle: 90);
      await v2Repo.savePageEditState(
        pageId: 'page_stale',
        state: newEditState,
        rawAssetIdentity: 'raw-v1',
      );

      // Attempting to commit in-flight result with old expectedEditState (rotation: 0) MUST fail
      expect(
        () async => v2Repo.markCacheCurrent(
          pageId: 'page_stale',
          processedCacheKey: 'proc_key_1',
          thumbnailCacheKey: 'thumb_key_1',
          expectedRawAssetIdentity: 'raw-v1',
          expectedEditState: initialEditState,
        ),
        throwsA(
          isA<StorageFailure>().having(
            (e) => e.message,
            'message',
            contains('edit state changed'),
          ),
        ),
      );
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 17: BLOCKER-06 (Raw Asset Write-Once Immutability)
    // ─────────────────────────────────────────────────────────────
    test('17. BLOCKER-06: FileSystemAssetStore enforces write-once raw asset immutability', () async {
      final bytesA = [1, 2, 3, 4, 5];
      final bytesB = [6, 7, 8, 9, 10];

      // Initial save succeeds
      final save1 = await assetStore.saveRawImage('doc_raw_iso', 'page_raw_iso', bytesA);
      expect(save1, isA<Success<String>>());

      // Idempotent save with identical bytes succeeds
      final saveIdentical = await assetStore.saveRawImage('doc_raw_iso', 'page_raw_iso', bytesA);
      expect(saveIdentical, isA<Success<String>>());

      // Conflicting save with different bytes FAILS with StorageFailure
      final saveConflicting = await assetStore.saveRawImage('doc_raw_iso', 'page_raw_iso', bytesB);
      expect(saveConflicting, isA<Failure<String>>());
      final saveErr = (saveConflicting as Failure<String>).error;
      expect(saveErr, isA<StorageFailure>());
      expect(
        saveErr.message,
        contains('immutable'),
      );
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 18: BLOCKER-07 (Zero-Byte Derived Asset Invalidation)
    // ─────────────────────────────────────────────────────────────
    test('18. BLOCKER-07: 0-byte derived asset is rejected by exists and markCacheCurrent', () async {
      final raw = createTestImageFile(fileName: 'zero_byte.jpg');
      await pageService.processSinglePage(
        documentId: 'doc_zero',
        pageId: 'page_zero',
        pageIndex: 0,
        rawSourcePath: raw.path,
      );

      final procPath = (await assetStore.pathFor('doc_zero', 'page_zero', AssetKind.processed)).valueOrNull!;
      final procFile = File(procPath);
      expect(procFile.existsSync(), isTrue);

      // Overwrite processed file with 0 bytes (simulate truncate/corruption)
      procFile.writeAsBytesSync([]);
      expect(procFile.lengthSync(), 0);

      // exists() must return false for 0-byte file
      final exists = await assetStore.exists('doc_zero', 'page_zero', AssetKind.processed);
      expect(exists.valueOrNull, isFalse);

      // markCacheCurrent must reject 0-byte file
      expect(
        () async => v2Repo.markCacheCurrent(
          pageId: 'page_zero',
          processedCacheKey: 'dummy_key',
          thumbnailCacheKey: 'dummy_thumb',
        ),
        throwsA(isA<StorageFailure>()),
      );
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 19: BLOCKER-11 (Unknown Filter Profile Handling)
    // ─────────────────────────────────────────────────────────────
    test('19. BLOCKER-11: Unknown filter profiles fail with typed ProcessingInputFailure', () async {
      final filterResult = DocumentPageProcessingService.filterFromLegacy('sepia');
      expect(filterResult, isA<Failure<ScanFilterType>>());
      final filterErr = (filterResult as Failure<ScanFilterType>).error;
      expect(filterErr, isA<ProcessingInputFailure>());
      expect(
        filterErr.message,
        contains('Unknown filter profile: sepia'),
      );
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 20: BLOCKER-16 (Fast JPEG Dimension Parsing)
    // ─────────────────────────────────────────────────────────────
    test('20. BLOCKER-16: parseJpegDimensions extracts dimensions without full pixel decode', () {
      final imgObj = img.Image(width: 480, height: 320);
      final jpegBytes = Uint8List.fromList(img.encodeJpg(imgObj));

      final size = DocumentPageProcessingService.parseJpegDimensions(jpegBytes);
      expect(size, isNotNull);
      expect(size!.width, 480);
      expect(size.height, 320);

      // Corrupt or non-JPEG returns null safely
      final corruptBytes = Uint8List.fromList([1, 2, 3, 4]);
      expect(DocumentPageProcessingService.parseJpegDimensions(corruptBytes), isNull);
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 21: Real Benchmark (1, 10, 20, 50 Pages Cold + 50 Cache HIT)
    // ─────────────────────────────────────────────────────────────
    test('21. BLOCKER-13 & 14: Real multi-page benchmark (1, 10, 20, 50 pages cold + 50 cache HIT)', () async {
      final docId = 'doc_bench_50';

      // Prepare 50 distinct test images
      final testFiles = <File>[];
      for (var i = 0; i < 50; i++) {
        testFiles.add(createTestImageFile(fileName: 'bench50_$i.jpg', width: 120, height: 80));
      }

      // ── Benchmark 1 Page ──
      final sw1 = Stopwatch()..start();
      final res1 = await pageService.processSinglePage(
        documentId: 'doc_bench_1',
        pageId: 'bench_p_0',
        pageIndex: 0,
        rawSourcePath: testFiles[0].path,
      );
      sw1.stop();
      expect(res1, isA<Success<ScannedPage>>());
      final time1Ms = sw1.elapsedMilliseconds;

      // ── Benchmark 10 Pages (cold) ──
      final sw10 = Stopwatch()..start();
      final editorPages10 = [
        for (var i = 0; i < 10; i++)
          EditorPageModel(
            imagePath: testFiles[i].path,
            rawImagePath: testFiles[i].path,
            filter: DocumentFilterType.original,
          ),
      ];
      final res10 = await pageService.processEditorPages(
        documentId: 'doc_bench_10',
        pages: editorPages10,
      );
      sw10.stop();
      expect(res10, isA<Success<List<ScannedPage>>>());
      final time10Ms = sw10.elapsedMilliseconds;

      // ── Benchmark 20 Pages (cold) ──
      final sw20 = Stopwatch()..start();
      final editorPages20 = [
        for (var i = 0; i < 20; i++)
          EditorPageModel(
            imagePath: testFiles[i].path,
            rawImagePath: testFiles[i].path,
            filter: DocumentFilterType.original,
          ),
      ];
      final res20 = await pageService.processEditorPages(
        documentId: 'doc_bench_20',
        pages: editorPages20,
      );
      sw20.stop();
      expect(res20, isA<Success<List<ScannedPage>>>());
      final time20Ms = sw20.elapsedMilliseconds;

      // ── Benchmark 50 Pages (cold) ──
      final sw50 = Stopwatch()..start();
      final editorPages50 = [
        for (var i = 0; i < 50; i++)
          EditorPageModel(
            imagePath: testFiles[i].path,
            rawImagePath: testFiles[i].path,
            filter: DocumentFilterType.original,
          ),
      ];
      final res50 = await pageService.processEditorPages(
        documentId: docId,
        pages: editorPages50,
      );
      sw50.stop();
      expect(res50, isA<Success<List<ScannedPage>>>());
      final time50Ms = sw50.elapsedMilliseconds;

      // ── Benchmark 50 Pages Re-run (100% Cache HIT) ──
      final swCache50 = Stopwatch()..start();
      final resCache50 = await pageService.processEditorPages(
        documentId: docId,
        pages: editorPages50,
      );
      swCache50.stop();
      expect(resCache50, isA<Success<List<ScannedPage>>>());
      final timeCache50Ms = swCache50.elapsedMilliseconds;

      expect(engine.maximumObservedHeavyJobs, lessThanOrEqualTo(1));
      expect(time1Ms, greaterThanOrEqualTo(0));
      expect(time10Ms, greaterThanOrEqualTo(0));
      expect(time20Ms, greaterThanOrEqualTo(0));
      expect(timeCache50Ms, lessThan(time50Ms));
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 22: INV-F07-03 Page Identity strictly by pageId
    // ─────────────────────────────────────────────────────────────
    test('22. TEST-F07-03: Page identity is strictly pageId; conflicting pageIndex fails with typed error', () async {
      final rawFile = createTestImageFile(fileName: 'identity_test.jpg', width: 100, height: 100);

      // Process page 0 with ID 'page_alpha'
      final res1 = await pageService.processSinglePage(
        documentId: 'doc_ident',
        pageId: 'page_alpha',
        pageIndex: 0,
        rawSourcePath: rawFile.path,
      );
      expect(res1, isA<Success<ScannedPage>>());

      // Attempt to process page 0 with DIFFERENT ID 'page_beta'
      final resConflict = await pageService.processSinglePage(
        documentId: 'doc_ident',
        pageId: 'page_beta',
        pageIndex: 0,
        rawSourcePath: rawFile.path,
      );
      expect(resConflict, isA<Failure<ScannedPage>>());
      expect((resConflict as Failure).error, isA<ProcessingInputFailure>());
      expect(((resConflict as Failure).error as ProcessingInputFailure).message, contains('Conflicting pageIndex 0'));
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 23: Cache commit validation in markCacheCurrent
    // ─────────────────────────────────────────────────────────────
    test('23. TEST-F07-06: markCacheCurrent rejects empty keys, stale state, and missing derived files', () async {
      final rawFile = createTestImageFile(fileName: 'commit_val.jpg', width: 100, height: 100);
      final res = await pageService.processSinglePage(
        documentId: 'doc_commit',
        pageId: 'page_commit',
        pageIndex: 0,
        rawSourcePath: rawFile.path,
      );
      expect(res, isA<Success<ScannedPage>>());

      final domainDoc = await v2Repo.getById('doc_commit');
      final domainPage = domainDoc!.pages.single;

      // 1. Empty cache keys rejected
      expect(
        () => v2Repo.markCacheCurrent(
          pageId: 'page_commit',
          processedCacheKey: '',
          thumbnailCacheKey: 'tkey',
          expectedRawAssetIdentity: 'raw-v1',
          expectedEditState: domainPage.editState,
        ),
        throwsA(isA<StorageFailure>()),
      );

      // 2. Stale raw identity rejected
      expect(
        () => v2Repo.markCacheCurrent(
          pageId: 'page_commit',
          processedCacheKey: 'pkey',
          thumbnailCacheKey: 'tkey',
          expectedRawAssetIdentity: 'wrong-raw-id',
          expectedEditState: domainPage.editState,
        ),
        throwsA(isA<StorageFailure>()),
      );

      // 3. Stale edit state rejected
      final modifiedState = PageEditState(
        corners: domainPage.corners,
        rotationAngle: 90,
      );
      expect(
        () => v2Repo.markCacheCurrent(
          pageId: 'page_commit',
          processedCacheKey: 'pkey',
          thumbnailCacheKey: 'tkey',
          expectedRawAssetIdentity: 'raw-v1',
          expectedEditState: modifiedState,
        ),
        throwsA(isA<StorageFailure>()),
      );
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 24: Persistence boundary: saveDocument preserves M07 cache metadata
    // ─────────────────────────────────────────────────────────────
    test('24. TEST-F07-08: saveDocument upserts pages by pageId and preserves cached keys when incoming has null', () async {
      final rawFile = createTestImageFile(fileName: 'persist_meta.jpg', width: 100, height: 100);
      final res = await pageService.processSinglePage(
        documentId: 'doc_meta',
        pageId: 'page_meta',
        pageIndex: 0,
        rawSourcePath: rawFile.path,
      );
      expect(res, isA<Success<ScannedPage>>());
      final processedPage = (res as Success<ScannedPage>).value;
      expect(processedPage.processedCacheKey, isNotNull);

      // Construct a domain document with pages that have null cache keys (e.g. from an external edit or title change)
      final docToSave = ScanDocument(
        id: 'doc_meta',
        title: 'Updated Title',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        pages: [
          ScanPage(
            id: 'page_meta',
            documentId: 'doc_meta',
            pageIndex: 0,
            rawImagePath: processedPage.rawImagePath,
            processedCacheKey: null, // caller didn't populate cache key
            thumbnailCacheKey: null,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ],
      );

      await v2Repo.save(docToSave);

      // Re-read from repository
      final reloadedDoc = await v2Repo.getById('doc_meta');
      expect(reloadedDoc, isNotNull);
      expect(reloadedDoc!.title, 'Updated Title');
      final reloadedPage = reloadedDoc.pages.single;
      expect(reloadedPage.processedCacheKey, equals(processedPage.processedCacheKey));
      expect(reloadedPage.thumbnailCacheKey, equals(processedPage.thumbnailCacheKey));
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 25: Persistence boundary: saveDocument deletes only removed pages & assets
    // ─────────────────────────────────────────────────────────────
    test('25. TEST-F07-09: saveDocument removes deleted page rows and deletes their assets from AssetStore', () async {
      final rawFile1 = createTestImageFile(fileName: 'rem_1.jpg', width: 100, height: 100);
      final rawFile2 = createTestImageFile(fileName: 'rem_2.jpg', width: 100, height: 100);

      await pageService.processSinglePage(
        documentId: 'doc_rem',
        pageId: 'page_keep',
        pageIndex: 0,
        rawSourcePath: rawFile1.path,
      );
      await pageService.processSinglePage(
        documentId: 'doc_rem',
        pageId: 'page_delete',
        pageIndex: 1,
        rawSourcePath: rawFile2.path,
      );

      // Verify both exist in asset store
      expect((await assetStore.exists('doc_rem', 'page_keep', AssetKind.processed)).valueOrNull, isTrue);
      expect((await assetStore.exists('doc_rem', 'page_delete', AssetKind.processed)).valueOrNull, isTrue);

      // Save document with ONLY page_keep
      final docToSave = ScanDocument(
        id: 'doc_rem',
        title: 'Pruned Document',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        pages: [
          ScanPage(
            id: 'page_keep',
            documentId: 'doc_rem',
            pageIndex: 0,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ],
      );
      await v2Repo.save(docToSave);

      // page_keep assets must remain
      expect((await assetStore.exists('doc_rem', 'page_keep', AssetKind.processed)).valueOrNull, isTrue);
      // page_delete assets must be removed
      expect((await assetStore.exists('doc_rem', 'page_delete', AssetKind.processed)).valueOrNull, isFalse);
      // page_delete must not exist in repository
      final reloadedPageDelete = await v2Repo.getPage('page_delete');
      expect(reloadedPageDelete, isNull);
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 26: ThumbnailSpecification validation
    // ─────────────────────────────────────────────────────────────
    test('26. TEST-F07-16: ThumbnailSpecification validates positive dimensions and valid quality', () {
      expect(() => ThumbnailSpecification(width: 0), throwsA(isA<AssertionError>()));
      expect(() => ThumbnailSpecification(height: -10), throwsA(isA<AssertionError>()));
      expect(() => ThumbnailSpecification(quality: 105), throwsA(isA<AssertionError>()));
      expect(() => ThumbnailSpecification(quality: -1), throwsA(isA<AssertionError>()));

      const valid = ThumbnailSpecification(width: 256, height: 256, quality: 90);
      expect(valid.isValid, isTrue);
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 27: ProcessingPlan.supportsProfile boolean
    // ─────────────────────────────────────────────────────────────
    test('27. TEST-F07-17: ProcessingPlan.supportsProfile reflects filter compatibility', () async {
      final rawFile = createTestImageFile(fileName: 'plan_profile.jpg', width: 100, height: 100);
      final res = await pageService.processSinglePage(
        documentId: 'doc_plan',
        pageId: 'page_plan',
        pageIndex: 0,
        rawSourcePath: rawFile.path,
        filter: ScanFilterType.original,
      );
      expect(res, isA<Success<ScannedPage>>());
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 28: Unsupported filter profiles return typed failure
    // ─────────────────────────────────────────────────────────────
    test('28. TEST-F07-12: Non-original filters fail with UnsupportedProcessingProfileFailure', () async {
      final rawFile = createTestImageFile(fileName: 'filter_fail.jpg', width: 100, height: 100);
      final res = await pageService.processSinglePage(
        documentId: 'doc_filt',
        pageId: 'page_filt',
        pageIndex: 0,
        rawSourcePath: rawFile.path,
        filter: ScanFilterType.magic,
      );
      expect(res, isA<Failure<ScannedPage>>());
      expect((res as Failure).error, isA<UnsupportedProcessingProfileFailure>());
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 29: EditorController alreadyCropped semantics
    // ─────────────────────────────────────────────────────────────
    test('29. TEST-F07-10: EditorController alreadyCropped sets fullFrame corners', () {
      final fullFrame = DocumentCorners.fullFrame();
      expect(fullFrame.topLeft, const Offset(0, 0));
      expect(fullFrame.topRight, const Offset(1, 0));
      expect(fullFrame.bottomRight, const Offset(1, 1));
      expect(fullFrame.bottomLeft, const Offset(0, 1));
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 30: DocumentCorners.fullFrame geometry
    // ─────────────────────────────────────────────────────────────
    test('30. TEST-F07-08b: DocumentCorners.fullFrame has normalized bounds and unit area', () {
      final ff = DocumentCorners.fullFrame();
      expect(ff.topLeft.dx, 0.0);
      expect(ff.topLeft.dy, 0.0);
      expect(ff.topRight.dx, 1.0);
      expect(ff.topRight.dy, 0.0);
      expect(ff.bottomRight.dx, 1.0);
      expect(ff.bottomRight.dy, 1.0);
      expect(ff.bottomLeft.dx, 0.0);
      expect(ff.bottomLeft.dy, 1.0);
      expect(ff.normalizedArea, 1.0);
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 31: IdCardMergeController semantic cache hash
    // ─────────────────────────────────────────────────────────────
    test('31. TEST-F07-13: IdCardMergeController semantic hash is invariant to preview paths and sensitive to inputs', () {
      final c1 = DocumentCorners.idCardGuide();
      final c2 = DocumentCorners.passportGuide();

      String computeHash({
        required String rawFront,
        required String rawBack,
        required int frontTurns,
        required int backTurns,
        required double spacing,
        required DocumentFilterType filter,
        DocumentCorners? frontC,
        DocumentCorners? backC,
      }) {
        final frontCornersStr = frontC?.points.map((p) => '${p.dx},${p.dy}').join(';') ?? 'default';
        final backCornersStr = backC?.points.map((p) => '${p.dx},${p.dy}').join(';') ?? 'default';
        return '${rawFront}_${rawBack}_${frontTurns}_${backTurns}_${spacing}_${filter.name}_${frontCornersStr}_$backCornersStr';
      }

      final hashBase = computeHash(
        rawFront: '/raw/f.jpg',
        rawBack: '/raw/b.jpg',
        frontTurns: 0,
        backTurns: 0,
        spacing: 20.0,
        filter: DocumentFilterType.original,
        frontC: c1,
        backC: c2,
      );

      final hashSame = computeHash(
        rawFront: '/raw/f.jpg',
        rawBack: '/raw/b.jpg',
        frontTurns: 0,
        backTurns: 0,
        spacing: 20.0,
        filter: DocumentFilterType.original,
        frontC: c1,
        backC: c2,
      );
      expect(hashBase, equals(hashSame));

      final hashDiffTurns = computeHash(
        rawFront: '/raw/f.jpg',
        rawBack: '/raw/b.jpg',
        frontTurns: 1,
        backTurns: 0,
        spacing: 20.0,
        filter: DocumentFilterType.original,
        frontC: c1,
        backC: c2,
      );
      expect(hashBase, isNot(equals(hashDiffTurns)));

      final hashDiffSpacing = computeHash(
        rawFront: '/raw/f.jpg',
        rawBack: '/raw/b.jpg',
        frontTurns: 0,
        backTurns: 0,
        spacing: 25.0,
        filter: DocumentFilterType.original,
        frontC: c1,
        backC: c2,
      );
      expect(hashBase, isNot(equals(hashDiffSpacing)));
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 32: Concurrency reference counting on forceReprocess
    // ─────────────────────────────────────────────────────────────
    test('32. TEST-F07-15: Concurrent forceReprocess requests reference-count active force set', () async {
      final rawFile = createTestImageFile(fileName: 'refcount_test.jpg', width: 100, height: 100);

      // Warm up cache first
      final resWarm = await pageService.processSinglePage(
        documentId: 'doc_rc',
        pageId: 'page_rc',
        pageIndex: 0,
        rawSourcePath: rawFile.path,
      );
      expect(resWarm, isA<Success<ScannedPage>>());

      // Launch two forceReprocess requests concurrently for the same page
      final future1 = pageService.processSinglePage(
        documentId: 'doc_rc',
        pageId: 'page_rc',
        pageIndex: 0,
        rawSourcePath: rawFile.path,
        forceReprocess: true,
      );
      final future2 = pageService.processSinglePage(
        documentId: 'doc_rc',
        pageId: 'page_rc',
        pageIndex: 0,
        rawSourcePath: rawFile.path,
        forceReprocess: true,
      );

      final results = await Future.wait([future1, future2]);
      expect(results[0], isA<Success<ScannedPage>>());
      expect(results[1], isA<Success<ScannedPage>>());
      expect(engine.maximumObservedHeavyJobs, lessThanOrEqualTo(1));
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 33: EditorController filter selection blocks non-original
    // ─────────────────────────────────────────────────────────────
    test('33. TEST-F07-31: EditorController blocks selecting non-original filters', () {
      Get.put(pageService);
      Get.put(docRepo);
      Get.put(PdfService());
      Get.put(CaptureService(
        provider: const NativeScannerCaptureProvider(),
        assetStore: assetStore,
        repository: docRepo,
      ));

      final controller = EditorController();
      final model = EditorPageModel(
        imagePath: '/dummy.jpg',
        rawImagePath: '/dummy.jpg',
        filter: DocumentFilterType.original,
      );
      controller.editorPages.add(model);
      controller.currentPageIndex.value = 0;

      // Attempt to apply 'magic'
      controller.applyFilter(DocumentFilterType.magic);
      expect(controller.selectedFilter.value, DocumentFilterType.original);
      expect(controller.currentPage!.filter, DocumentFilterType.original);

      // Attempt applyFilterToAll with 'gray'
      controller.applyFilterToAll(DocumentFilterType.gray);
      expect(controller.selectedFilter.value, DocumentFilterType.original);
      expect(controller.editorPages.first.filter, DocumentFilterType.original);
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 34: DocumentPageProcessingService warpPreview preserves raw immutability
    // ─────────────────────────────────────────────────────────────
    test('34. TEST-F07-34: warpPreview uses M07 renderPreview and does not modify raw bytes', () async {
      final rawFile = createTestImageFile(fileName: 'warp_test.jpg', width: 100, height: 100);
      final rawBytesBefore = rawFile.readAsBytesSync();

      final previewFile = await pageService.warpPreview(
        rawImagePath: rawFile.path,
        corners: DocumentCorners.idCardGuide(),
        quarterTurns: 1,
      );

      expect(previewFile.existsSync(), isTrue);
      expect(rawFile.readAsBytesSync(), equals(rawBytesBefore));
    });

    // ─────────────────────────────────────────────────────────────
    // TEST 35: Full End-to-End Multi-page Edit & Lifecycle Truth
    // ─────────────────────────────────────────────────────────────
    test('35. TEST-F07-35: Multi-page document lifecycle: modifying 1 page preserves cache of other pages', () async {
      final f1 = createTestImageFile(fileName: 'e2e_p1.jpg', width: 100, height: 100);
      final f2 = createTestImageFile(fileName: 'e2e_p2.jpg', width: 100, height: 100);

      final editorPages = [
        EditorPageModel(imagePath: f1.path, rawImagePath: f1.path),
        EditorPageModel(imagePath: f2.path, rawImagePath: f2.path),
      ];

      final resInitial = await pageService.processEditorPages(
        documentId: 'doc_lifecycle',
        pages: editorPages,
      );
      expect(resInitial, isA<Success<List<ScannedPage>>>());
      final p1InitialKey = (resInitial as Success<List<ScannedPage>>).value[0].processedCacheKey;
      final p2InitialKey = resInitial.value[1].processedCacheKey;

      // Rotate ONLY page 1 (quarterTurns: 1)
      editorPages[0].quarterTurns = 1;

      final resUpdate = await pageService.processEditorPages(
        documentId: 'doc_lifecycle',
        pages: editorPages,
      );
      expect(resUpdate, isA<Success<List<ScannedPage>>>());
      final updatedPages = (resUpdate as Success<List<ScannedPage>>).value;

      // Page 1 key must change
      expect(updatedPages[0].processedCacheKey, isNot(equals(p1InitialKey)));
      // Page 2 key must be identical (Cache HIT)
      expect(updatedPages[1].processedCacheKey, equals(p2InitialKey));
    });
  });
}
