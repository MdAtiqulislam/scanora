import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:scanora/initial_buinding.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app/core/constants/app_constants.dart';
import 'app/core/services/camera_service.dart';
import 'app/core/services/document_detection_service.dart';
import 'app/core/services/image_processing_service.dart';
import 'app/core/services/ocr_service.dart';
import 'app/core/services/pdf_service.dart';
import 'app/core/services/perspective_service.dart';
import 'app/core/services/share_service.dart';
import 'app/core/services/storage_service.dart';
import 'app/data/repositories/document_repository.dart';
import 'app/data/repositories/sqlite_document_repository_v2.dart';
import 'app/data/datasources/scanora_database.dart';
import 'app/infrastructure/storage/file_system_asset_store.dart';
import 'app/infrastructure/capture/native_scanner_capture_provider.dart';
import 'app/application/controllers/capture_controller.dart';
import 'app/application/services/capture_service.dart';
import 'app/application/services/document_page_processing_service.dart';
import 'app/core/errors/app_failure.dart';
import 'app/core/result/result.dart';
import 'app/domain/contracts/asset_store.dart';
import 'app/domain/contracts/processing_engine.dart';
import 'app/infrastructure/processing/m07_processing_engine.dart';
import 'app/infrastructure/processing/plain_geometry_engine.dart';
import 'app/routes/app_pages.dart';
import 'app/theme/app_theme.dart';
import 'app/theme/theme_controller.dart';
import 'app/translations/app_translations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Core Services initialization
  await Get.putAsync(() => StorageService().init());
  Get.put(ThemeController());
  await Get.putAsync(() => CameraService().init());
  Get.put(DocumentDetectionService());
  Get.put(PerspectiveService());
  Get.put(ImageProcessingService());
  Get.put(PdfService());
  Get.put(OcrService());
  Get.put(ShareService());
  final docsDir = await getApplicationDocumentsDirectory();
  final assetStore = FileSystemAssetStore(
    Directory(p.join(docsDir.path, 'scanora_assets')),
  );
  Get.put<AssetStore>(assetStore, permanent: true);
  Get.put<FileSystemAssetStore>(assetStore, permanent: true);

  final documentRepository = DocumentRepository(
    repository: SqliteDocumentRepositoryV2(
      database: ScanoraDatabase(),
      assetStore: assetStore,
    ),
  );
  Get.put(
    CaptureService(
      provider: const NativeScannerCaptureProvider(),
      assetStore: assetStore,
      repository: documentRepository,
    ),
  );
  Get.put(CaptureController(Get.find<CaptureService>()));
  await Get.putAsync(() => documentRepository.init());

  final processingEngine = M07ProcessingEngine(
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
        await documentRepository.v2Repository.markCacheCurrent(
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
  Get.put<ProcessingEngine>(processingEngine, permanent: true);
  Get.put<M07ProcessingEngine>(processingEngine, permanent: true);

  final pageProcessingService = DocumentPageProcessingService(
    processingEngine: processingEngine,
    assetStore: assetStore,
    repository: documentRepository,
  );
  Get.put(pageProcessingService, permanent: true);

  final themeController = Get.find<ThemeController>();

  runApp(
    GetMaterialApp(
      title: AppConstants.appName,
      initialRoute: AppPages.initial,
      initialBinding: InitialBinding(),
      getPages: AppPages.routes,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeController.themeMode.value,
      translations: AppTranslations(),
      locale: const Locale('en', 'US'),
      fallbackLocale: const Locale('en', 'US'),
    ),
  );
}
