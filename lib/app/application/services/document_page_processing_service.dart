import 'dart:io';
import 'dart:typed_data';

import 'package:get/get.dart';
import 'package:image/image.dart' as img;

import '../../core/errors/processing_failure.dart';
import '../../core/result/result.dart';
import '../../core/utils/file_utils.dart';
import '../../data/models/document_corners.dart';
import '../../data/models/scanned_page.dart';
import '../../data/repositories/document_repository.dart';
import '../../domain/contracts/asset_store.dart';
import '../../domain/contracts/processing_engine.dart';
import '../../domain/entities/scan_document.dart' as domain;
import '../../domain/entities/scan_page.dart' as domain_page;
import '../../domain/enums/scan_enums.dart';
import '../../domain/geometry/geometry_models.dart';
import '../../domain/processing/processing_models.dart';
import '../../domain/value_objects/page_corners.dart';
import '../../domain/value_objects/point.dart';
import '../../domain/value_objects/processing_profile.dart';
import '../../infrastructure/processing/m07_processing_engine.dart';
import '../../modules/editor/controllers/editor_controller.dart';

/// Application service orchestrating document page raster processing through M07.
/// Coordinates between presentation controllers, AssetStore, and ProcessingEngine.
/// Does NOT perform raster algorithms directly.
class DocumentPageProcessingService extends GetxService {
  final ProcessingEngine processingEngine;
  final AssetStore assetStore;
  final DocumentRepository repository;
  final _dbDocLock = AsyncProcessingLock(maxConcurrency: 1);

  DocumentPageProcessingService({
    required this.processingEngine,
    required this.assetStore,
    required this.repository,
  });

  /// Processes all pages of an editor document sequentially through M07.
  /// Guarantees raw immutability, bounded concurrency, cache reuse, and failure propagation.
  Future<Result<List<ScannedPage>>> processEditorPages({
    required String documentId,
    required List<EditorPageModel> pages,
    bool Function()? isCancelled,
    bool forceReprocess = false,
  }) async {
    final processedPages = <ScannedPage>[];

    for (var i = 0; i < pages.length; i++) {
      if (isCancelled?.call() == true) {
        return const Failure(ProcessingCancelledFailure());
      }

      final pageModel = pages[i];
      final pageId = 'p_${documentId}_$i';

      final filterResult = filterFromLegacy(pageModel.filter.name);
      if (filterResult case Failure<ScanFilterType>(:final error)) {
        return Failure(error);
      }
      final filter = (filterResult as Success<ScanFilterType>).value;

      final pageResult = await processSinglePage(
        documentId: documentId,
        pageId: pageId,
        pageIndex: i,
        rawSourcePath: pageModel.rawImagePath,
        corners: pageModel.corners,
        quarterTurns: pageModel.quarterTurns,
        filter: filter,
        isCancelled: isCancelled,
        forceReprocess: forceReprocess,
      );

      if (pageResult case Failure<ScannedPage>(:final error)) {
        return Failure(error);
      }

      processedPages.add((pageResult as Success<ScannedPage>).value);
    }

    return Success(processedPages);
  }

  /// Processes a single page through the M07 processing pipeline.
  Future<Result<ScannedPage>> processSinglePage({
    required String documentId,
    required String pageId,
    required int pageIndex,
    required String rawSourcePath,
    DocumentCorners? corners,
    int quarterTurns = 0,
    ScanFilterType filter = ScanFilterType.original,
    bool Function()? isCancelled,
    bool forceReprocess = false,
    ThumbnailSpecification thumbnail = const ThumbnailSpecification(),
  }) async {
    try {
      if (isCancelled?.call() == true) {
        return const Failure(ProcessingCancelledFailure());
      }

      if (filter != ScanFilterType.original) {
        return Failure(
          UnsupportedProcessingProfileFailure(
            'M07 only supports original filter, but got ${filter.name}',
          ),
        );
      }

      // Step 1: Ensure raw image is safely persisted in AssetStore
      final rawExistsResult = await assetStore.exists(
        documentId,
        pageId,
        AssetKind.raw,
      );
      if (rawExistsResult case Failure<bool>(:final error)) {
        return Failure(error);
      }
      final rawExists = (rawExistsResult as Success<bool>).value;

      String rawAssetPath;
      if (!rawExists) {
        final rawFile = File(rawSourcePath);
        if (!await rawFile.exists()) {
          return Failure(
            ProcessingInputFailure('Raw source file does not exist: $rawSourcePath'),
          );
        }
        final rawBytes = await rawFile.readAsBytes();
        if (rawBytes.isEmpty) {
          return const Failure(ProcessingInputFailure('Raw source file is empty'));
        }
        final saveRawResult = await assetStore.saveRawImage(
          documentId,
          pageId,
          rawBytes,
        );
        if (saveRawResult case Failure<String>(:final error)) {
          return Failure(error);
        }
        rawAssetPath = (saveRawResult as Success<String>).value;
      } else {
        final pathResult = await assetStore.pathFor(
          documentId,
          pageId,
          AssetKind.raw,
        );
        if (pathResult case Failure<String>(:final error)) {
          return Failure(error);
        }
        rawAssetPath = (pathResult as Success<String>).value;
      }

      if (isCancelled?.call() == true) {
        return const Failure(ProcessingCancelledFailure());
      }

      // Step 2: Determine source image dimensions
      final rawBytesResult = await assetStore.readRawImage(documentId, pageId);
      if (rawBytesResult case Failure<List<int>>(:final error)) {
        return Failure(error);
      }
      final rawBytes = (rawBytesResult as Success<List<int>>).value;
      final rawUint8 =
          rawBytes is Uint8List ? rawBytes : Uint8List.fromList(rawBytes);

      final fastSize = parseJpegDimensions(rawUint8);
      final PixelSize sourceSize;
      if (fastSize != null) {
        sourceSize = fastSize;
      } else {
        final decodedHeader = img.decodeImage(rawUint8);
        if (decodedHeader == null) {
          return const Failure(
            ProcessingInputFailure('Could not decode raw image header'),
          );
        }
        sourceSize = PixelSize(decodedHeader.width, decodedHeader.height);
      }

      // Step 3: Build Domain ScanPage and PageEditStateSnapshot
      final domainCorners = _cornersToDomain(corners);
      final now = DateTime.now();

      final domainPage = domain_page.ScanPage(
        id: pageId,
        documentId: documentId,
        pageIndex: pageIndex,
        rawImagePath: rawAssetPath,
        corners: domainCorners,
        rotationAngle: (quarterTurns * 90.0) % 360.0,
        processingProfile: ProcessingProfile(filterType: filter),
        createdAt: now,
        updatedAt: now,
      );

      // Ensure page row exists in SQLite repository before M07 processing begins
      await _dbDocLock.acquire();
      final domain_page.ScanPage domainPageToUse;
      try {
        final existingDoc = await repository.v2Repository.getById(documentId);
        if (existingDoc != null) {
          final duplicateIndexPage = existingDoc.pages
              .where((p) => p.pageIndex == pageIndex && p.id != pageId)
              .firstOrNull;
          if (duplicateIndexPage != null) {
            return Failure(
              ProcessingInputFailure(
                'Conflicting pageIndex $pageIndex for distinct pageId: ${duplicateIndexPage.id} vs $pageId',
              ),
            );
          }
        }

        final existingPage = existingDoc?.pages
            .where((p) => p.id == pageId)
            .firstOrNull;

        final isSameEdit = existingPage != null &&
            existingPage.id == pageId &&
            existingPage.editState == domainPage.editState &&
            existingPage.rawImagePath == domainPage.rawImagePath;

        domainPageToUse = isSameEdit ? existingPage : domainPage;

        if (existingDoc == null) {
          final draftDoc = domain.ScanDocument(
            id: documentId,
            title: 'Document',
            createdAt: now,
            updatedAt: now,
            pages: [domainPageToUse],
          );
          await repository.v2Repository.save(draftDoc);
        } else {
          final hasPage = existingDoc.pages.any((p) => p.id == pageId);
          if (!hasPage) {
            final updatedPages = [...existingDoc.pages, domainPageToUse];
            await repository.v2Repository.save(
              domain.ScanDocument(
                id: existingDoc.id,
                title: existingDoc.title,
                createdAt: existingDoc.createdAt,
                updatedAt: now,
                favorite: existingDoc.favorite,
                tags: existingDoc.tags,
                pdfPath: existingDoc.pdfPath,
                pages: updatedPages,
              ),
            );
          } else if (!isSameEdit) {
            final updatedPages =
                existingDoc.pages
                    .map((p) => (p.id == pageId) ? domainPageToUse : p)
                    .toList();
            await repository.v2Repository.save(
              domain.ScanDocument(
                id: existingDoc.id,
                title: existingDoc.title,
                createdAt: existingDoc.createdAt,
                updatedAt: now,
                favorite: existingDoc.favorite,
                tags: existingDoc.tags,
                pdfPath: existingDoc.pdfPath,
                pages: updatedPages,
              ),
            );
          }
        }
      } finally {
        _dbDocLock.release();
      }

      final request = ProcessingRequest(
        documentId: documentId,
        pageId: pageId,
        rawAssetIdentity: 'raw-v1',
        editState: PageEditStateSnapshot(domainPageToUse),
        sourceSize: sourceSize,
        forceReprocess: forceReprocess,
        thumbnail: thumbnail,
        isCancelled: isCancelled,
      );

      // Step 4: Authoritative M07 Execution
      final result = await processingEngine.process(request);
      if (result case Failure<ProcessingResult>(:final error)) {
        return Failure(error);
      }

      final processingResult = (result as Success<ProcessingResult>).value;

      return Success(
        ScannedPage(
          id: pageId,
          imagePath: processingResult.processedPath,
          rawImagePath: rawAssetPath,
          corners: corners,
          rotationAngle: (quarterTurns * 90) % 360,
          filter: filter.name,
          processedCacheKey: processingResult.plan.processedCacheKey,
          thumbnailCacheKey: processingResult.plan.thumbnailCacheKey,
          createdAt: now,
        ),
      );
    } catch (cause, stackTrace) {
      return Failure(
        ProcessingStageFailure(
          'Page processing failed',
          cause: cause,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Warps a temporary preview image using canonical M06 homography math for live UI editing.
  Future<File> warpPreview({
    required String rawImagePath,
    required DocumentCorners corners,
    int quarterTurns = 0,
  }) async {
    final rawFile = File(rawImagePath);
    if (!await rawFile.exists()) return rawFile;
    final rawBytes = await rawFile.readAsBytes();
    if (rawBytes.isEmpty) return rawFile;

    final domainCorners = _cornersToDomain(corners);
    final previewResult = await processingEngine.renderPreview(
      sourceBytes: rawBytes,
      corners: domainCorners,
      quarterTurns: quarterTurns,
    );

    if (previewResult case Success<List<int>>(:final value)) {
      final outPath = await FileUtils.createTimestampedFilePath(
        prefix: 'crop_preview',
        extension: 'jpg',
      );
      final outFile = File(outPath);
      await outFile.writeAsBytes(value);
      return outFile;
    }
    return rawFile;
  }

  static PixelSize? parseJpegDimensions(Uint8List bytes) {
    if (bytes.length < 4) return null;
    if (bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
    var offset = 2;
    while (offset < bytes.length - 1) {
      if (bytes[offset] != 0xFF) {
        offset++;
        continue;
      }
      final marker = bytes[offset + 1];
      offset += 2;
      if (marker == 0xD8 ||
          marker == 0xD9 ||
          marker == 0x00 ||
          (marker >= 0xD0 && marker <= 0xD7)) {
        continue;
      }
      if (offset + 2 > bytes.length) break;
      final length = (bytes[offset] << 8) | bytes[offset + 1];
      if (length < 2 || offset + length > bytes.length) break;

      if ((marker >= 0xC0 && marker <= 0xC3) ||
          (marker >= 0xC5 && marker <= 0xC7) ||
          (marker >= 0xC9 && marker <= 0xCB) ||
          (marker >= 0xCD && marker <= 0xCF)) {
        if (length >= 7) {
          final height = (bytes[offset + 3] << 8) | bytes[offset + 4];
          final width = (bytes[offset + 5] << 8) | bytes[offset + 6];
          return PixelSize(width, height);
        }
      }
      offset += length;
    }
    return null;
  }

  static PageCorners _cornersToDomain(DocumentCorners? corners) {
    if (corners == null) {
      return PageCorners(
        topLeft: const Point2D(0, 0),
        topRight: const Point2D(1, 0),
        bottomRight: const Point2D(1, 1),
        bottomLeft: const Point2D(0, 1),
      );
    }
    return PageCorners(
      topLeft: Point2D(corners.topLeft.dx, corners.topLeft.dy),
      topRight: Point2D(corners.topRight.dx, corners.topRight.dy),
      bottomRight: Point2D(corners.bottomRight.dx, corners.bottomRight.dy),
      bottomLeft: Point2D(corners.bottomLeft.dx, corners.bottomLeft.dy),
    );
  }

  static Result<ScanFilterType> filterFromLegacy(String value) => switch (value) {
    'original' => const Success(ScanFilterType.original),
    'auto' => const Success(ScanFilterType.auto),
    'magic' => const Success(ScanFilterType.magic),
    'gray' => const Success(ScanFilterType.gray),
    'blackAndWhite' => const Success(ScanFilterType.blackAndWhite),
    'smart' => const Success(ScanFilterType.smart),
    'color' => const Success(ScanFilterType.color),
    _ => Failure(ProcessingInputFailure('Unknown filter profile: $value')),
  };
}
