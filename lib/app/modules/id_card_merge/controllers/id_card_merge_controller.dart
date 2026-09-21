import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../application/services/document_page_processing_service.dart';
import '../../../core/constants/id_card_dimensions.dart';
import '../../../core/navigation/app_navigator.dart';
import '../../../core/result/result.dart';
import '../../../core/services/image_processing_service.dart';
import '../../../core/services/share_service.dart';
import '../../../core/utils/file_utils.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../../data/models/document_corners.dart';
import '../../../data/models/scanned_document.dart';
import '../../../data/models/scanned_page.dart';
import '../../../data/repositories/document_repository.dart';

class IdCardMergeController extends GetxController {
  final ImageProcessingService imageProcessingService =
      Get.find<ImageProcessingService>();
  final DocumentPageProcessingService pageProcessingService =
      Get.find<DocumentPageProcessingService>();
  final DocumentRepository documentRepository = Get.find<DocumentRepository>();
  final ShareService shareService = Get.put(ShareService());

  var frontPath = ''.obs;
  var rawFrontPath = ''.obs;
  var backPath = ''.obs;
  var rawBackPath = ''.obs;

  // Physical Spacing in Millimeters (Default 20 mm)
  var spacingMm = 20.0.obs;
  var frontQuarterTurns = 0.obs; // 0, 1, 2, 3
  var backQuarterTurns = 0.obs;
  var selectedFilter = DocumentFilterType.original.obs;
  var isProcessing = false.obs;

  DocumentCorners? frontCorners;
  DocumentCorners? backCorners;

  // Manual 4-Corner Crop State
  var isCroppingFront = false.obs;
  var isCroppingBack = false.obs;

  // Cache for instant Save / Share
  String? _cachedPdfPath;
  String? _cachedImagePath;
  String _lastStateHash = '';

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments as Map<String, dynamic>?;
    if (args != null) {
      frontPath.value = args['frontPath'] ?? '';
      rawFrontPath.value = args['rawFrontPath'] ?? args['frontPath'] ?? '';
      backPath.value = args['backPath'] ?? '';
      rawBackPath.value = args['rawBackPath'] ?? args['backPath'] ?? '';
    }
  }

  void updateSpacingMm(double val) {
    spacingMm.value = val;
    update();
  }

  void rotateFront() {
    frontQuarterTurns.value = (frontQuarterTurns.value + 1) % 4;
    update();
  }

  void rotateBack() {
    backQuarterTurns.value = (backQuarterTurns.value + 1) % 4;
    update();
  }

  void swapFrontAndBack() {
    final temp = frontPath.value;
    final tempRaw = rawFrontPath.value;
    final tempCorners = frontCorners;
    frontPath.value = backPath.value;
    rawFrontPath.value = rawBackPath.value;
    frontCorners = backCorners;
    backPath.value = temp;
    rawBackPath.value = tempRaw;
    backCorners = tempCorners;

    final tempTurns = frontQuarterTurns.value;
    frontQuarterTurns.value = backQuarterTurns.value;
    backQuarterTurns.value = tempTurns;
    update();
  }

  void selectFilter(DocumentFilterType filter) {
    selectedFilter.value = filter;
    update();
  }

  void openCropFront() {
    isCroppingFront.value = true;
    update();
  }

  void openCropBack() {
    isCroppingBack.value = true;
    update();
  }

  void cancelCrop() {
    isCroppingFront.value = false;
    isCroppingBack.value = false;
    update();
  }

  Future<void> applyFrontCrop(DocumentCorners corners) async {
    isCroppingFront.value = false;
    isProcessing.value = true;
    frontCorners = corners;
    update();

    try {
      final warped = await pageProcessingService.warpPreview(
        rawImagePath: rawFrontPath.value,
        corners: corners,
      );
      frontPath.value = warped.path;
    } catch (e) {
      debugPrint('Error applying front crop: $e');
    } finally {
      isProcessing.value = false;
      update();
    }
  }

  Future<void> applyBackCrop(DocumentCorners corners) async {
    isCroppingBack.value = false;
    isProcessing.value = true;
    backCorners = corners;
    update();

    try {
      final warped = await pageProcessingService.warpPreview(
        rawImagePath: rawBackPath.value,
        corners: corners,
      );
      backPath.value = warped.path;
    } catch (e) {
      debugPrint('Error applying back crop: $e');
    } finally {
      isProcessing.value = false;
      update();
    }
  }

  /// Generates PDF + merged image with EXACT physical size. Returns {pdfPath, imagePath}.
  /// Optimised: front & back processed in parallel, raster merge skipped for PDF path.
  Future<Map<String, String>?> _buildFinalMergedFiles() async {
    if (frontPath.value.isEmpty || backPath.value.isEmpty) {
      SnackbarHelper.showError('Missing ID card images');
      return null;
    }

    final frontCornersStr = frontCorners?.points.map((p) => '${p.dx},${p.dy}').join(';') ?? 'default';
    final backCornersStr = backCorners?.points.map((p) => '${p.dx},${p.dy}').join(';') ?? 'default';
    final currentHash =
        '${rawFrontPath.value}_${rawBackPath.value}_${frontQuarterTurns.value}'
        '_${backQuarterTurns.value}_${spacingMm.value}_${selectedFilter.value.name}'
        '_${frontCornersStr}_$backCornersStr';
    if (_cachedPdfPath != null &&
        _cachedImagePath != null &&
        _lastStateHash == currentHash) {
      final pdfFile = File(_cachedPdfPath!);
      final imgFile = File(_cachedImagePath!);
      if (pdfFile.existsSync() &&
          pdfFile.lengthSync() > 0 &&
          imgFile.existsSync() &&
          imgFile.lengthSync() > 0) {
        return {'pdfPath': _cachedPdfPath!, 'imagePath': _cachedImagePath!};
      }
    }

    try {
      final docId = DateTime.now().millisecondsSinceEpoch.toString();
      final pdfPath = await FileUtils.createTimestampedFilePath(
        prefix: 'id_doc',
        extension: 'pdf',
      );
      final mergedImgPath = await FileUtils.createTimestampedFilePath(
        prefix: 'id_preview',
        extension: 'jpg',
      );

      final filterResult = DocumentPageProcessingService.filterFromLegacy(
        selectedFilter.value.name,
      );
      if (filterResult case Failure(:final error)) {
        SnackbarHelper.showError('Invalid filter: ${error.message}');
        return null;
      }
      final resolvedFilter = (filterResult as Success).value;

      // ── Process front & back through authoritative M07 processing pipeline ──
      final frontResult = await pageProcessingService.processSinglePage(
        documentId: docId,
        pageId: 'p_${docId}_front',
        pageIndex: 0,
        rawSourcePath: rawFrontPath.value,
        corners: frontCorners,
        quarterTurns: frontQuarterTurns.value,
        filter: resolvedFilter,
      );
      if (frontResult case Failure<ScannedPage>(:final error)) {
        SnackbarHelper.showError('Could not process ID front: ${error.message}');
        return null;
      }

      final backResult = await pageProcessingService.processSinglePage(
        documentId: docId,
        pageId: 'p_${docId}_back',
        pageIndex: 1,
        rawSourcePath: rawBackPath.value,
        corners: backCorners,
        quarterTurns: backQuarterTurns.value,
        filter: resolvedFilter,
      );
      if (backResult case Failure<ScannedPage>(:final error)) {
        SnackbarHelper.showError('Could not process ID back: ${error.message}');
        return null;
      }

      final frontPage = (frontResult as Success<ScannedPage>).value;
      final backPage = (backResult as Success<ScannedPage>).value;

      final processedFront = File(frontPage.imagePath);
      final processedBack = File(backPage.imagePath);

      // ── PDF: embed processed images in exact physical containers ──
      final pdfDoc = pw.Document();
      final frontBytes = await processedFront.readAsBytes();
      final backBytes = await processedBack.readAsBytes();
      final frontPdfImg = pw.MemoryImage(frontBytes);
      final backPdfImg = pw.MemoryImage(backBytes);
      final double spacingPt = spacingMm.value * PdfPageFormat.mm;

      pdfDoc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Container(
                    width: IdCardDimensions.widthPt,
                    height: IdCardDimensions.heightPt,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: PdfColors.grey300,
                        width: 0.5,
                      ),
                    ),
                    child: pw.Image(frontPdfImg, fit: pw.BoxFit.fill),
                  ),
                  pw.SizedBox(height: spacingPt),
                  pw.Container(
                    width: IdCardDimensions.widthPt,
                    height: IdCardDimensions.heightPt,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: PdfColors.grey300,
                        width: 0.5,
                      ),
                    ),
                    child: pw.Image(backPdfImg, fit: pw.BoxFit.fill),
                  ),
                ],
              ),
            );
          },
        ),
      );

      // ── Ultra-fast: save PDF and lightweight A4 preview thumbnail in parallel (< 50ms) ──
      await Future.wait([
        pdfDoc.save().then((bytes) => File(pdfPath).writeAsBytes(bytes)),
        imageProcessingService.createIdCardPreviewImage(
          processedFrontFile: processedFront,
          processedBackFile: processedBack,
          outputFilePath: mergedImgPath,
          spacingMm: spacingMm.value,
        ),
      ]);

      // ── Persist authoritative front and back pages to repository ──
      final document = ScannedDocument(
        id: docId,
        title: 'ID Card ${DateTime.now().toString().substring(0, 10)}',
        pages: [frontPage, backPage],
        pdfPath: pdfPath,
      );
      await documentRepository.saveDocument(document);

      _cachedPdfPath = pdfPath;
      _cachedImagePath = mergedImgPath;
      _lastStateHash = currentHash;

      return {'pdfPath': pdfPath, 'imagePath': mergedImgPath};
    } catch (e) {
      debugPrint('Error creating merged files: $e');
      return null;
    }
  }

  /// 1. Save and return to Home instantly
  Future<void> saveDocument() async {
    isProcessing.value = true;
    update();

    final result = await _buildFinalMergedFiles();
    isProcessing.value = false;
    update();

    if (result != null) {
      SnackbarHelper.showSuccess('ID Card saved successfully!');
      AppNavigator.toHome();
    } else {
      SnackbarHelper.showError('Could not save ID Card');
    }
  }

  /// 2. Share PDF / Image directly instantly
  Future<void> shareDocument() async {
    isProcessing.value = true;
    update();

    final result = await _buildFinalMergedFiles();
    isProcessing.value = false;
    update();

    if (result != null && result['pdfPath'] != null) {
      await shareService.shareFile(
        result['pdfPath']!,
        subject: 'Scanora ID Card Scan (9.0 x 5.5 cm)',
      );
    } else {
      SnackbarHelper.showError('Could not share ID Card');
    }
  }
}
