import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../../../core/navigation/app_navigator.dart';
import '../../../core/services/document_detection_service.dart';
import '../../../core/services/image_processing_service.dart';
import '../../../core/services/pdf_service.dart';
import '../../../core/utils/file_utils.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../../data/models/document_corners.dart';
import '../../../data/models/scanned_document.dart';
import '../../../data/models/scanned_page.dart';
import '../../../data/repositories/document_repository.dart';
import '../../../application/services/capture_service.dart';
import '../../../application/services/document_page_processing_service.dart';
import '../../../domain/contracts/capture_provider.dart';
import '../../../core/result/result.dart';
import '../../../routes/app_pages.dart';

class EditorPageModel {
  String imagePath;
  String rawImagePath;
  DocumentFilterType filter;
  int quarterTurns; // 0, 1, 2, 3
  DocumentCorners? corners;

  EditorPageModel({
    required this.imagePath,
    required this.rawImagePath,
    this.filter = DocumentFilterType.original,
    this.quarterTurns = 0,
    this.corners,
  });

  String get fileName => imagePath.split(Platform.pathSeparator).last;
  int get sizeInBytes {
    try {
      return File(imagePath).lengthSync();
    } catch (_) {
      return 0;
    }
  }
}

class EditorController extends GetxController {
  final DocumentPageProcessingService pageProcessingService =
      Get.find<DocumentPageProcessingService>();
  final DocumentRepository documentRepository = Get.find<DocumentRepository>();
  final PdfService pdfService = Get.find<PdfService>();
  final CaptureService captureService = Get.find<CaptureService>();

  bool _isCancelled = false;

  var editorPages = <EditorPageModel>[].obs;
  var currentPageIndex = 0.obs;
  var isListViewMode = false.obs;

  late String rawImagePath;
  late DocumentCorners initialCorners;
  var isPassport = false.obs;
  var isIdCard = false.obs;

  var selectedFilter = DocumentFilterType.original.obs;
  var isProcessing = false.obs;
  var isCropMode = false.obs;
  var alreadyCropped =
      false.obs; // true when ML Kit already cropped (no re-warp needed)

  var brightness = 0.0.obs;
  var contrast = 1.0.obs;

  EditorPageModel? get currentPage =>
      editorPages.isNotEmpty && currentPageIndex.value < editorPages.length
          ? editorPages[currentPageIndex.value]
          : null;

  @override
  void onInit() {
    super.onInit();
    _setupInitialData();
  }

  void _setupInitialData() {
    final args = Get.arguments as Map<String, dynamic>?;
    if (args != null) {
      final imagePath = args['imagePath'] as String? ?? '';
      final imagesList =
          (args['images'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      rawImagePath = args['rawImagePath'] as String? ?? imagePath;
      alreadyCropped.value =
          args['alreadyCropped'] == true; // ML Kit images need no re-warp
      initialCorners = args['corners'] ??
          (alreadyCropped.value
              ? DocumentCorners.fullFrame()
              : DocumentCorners.defaultGuide());
      final mode = args['mode'] as ScannerScanMode? ?? ScannerScanMode.document;
      isPassport.value = mode == ScannerScanMode.passport;
      isIdCard.value = mode == ScannerScanMode.idCard;

      if (imagesList.isNotEmpty) {
        for (int i = 0; i < imagesList.length; i++) {
          editorPages.add(
            EditorPageModel(
              imagePath: imagesList[i],
              rawImagePath: imagesList[i],
              filter: DocumentFilterType.original,
              quarterTurns: 0,
              corners: initialCorners,
            ),
          );
        }
      } else if (imagePath.isNotEmpty) {
        editorPages.add(
          EditorPageModel(
            imagePath: imagePath,
            rawImagePath: rawImagePath,
            filter: DocumentFilterType.original,
            quarterTurns: 0,
            corners: initialCorners,
          ),
        );
      }

      if (editorPages.isNotEmpty) {
        currentPageIndex.value = 0;
        selectedFilter.value = editorPages[0].filter;
      }
    }
  }

  void toggleViewMode() {
    isListViewMode.value = !isListViewMode.value;
    update();
  }

  void selectPage(int index) {
    if (index >= 0 && index < editorPages.length) {
      currentPageIndex.value = index;
      selectedFilter.value = editorPages[index].filter;
      update();
    }
  }

  void updatePageAt(int index, EditorPageModel updated) {
    if (index >= 0 && index < editorPages.length) {
      editorPages[index] = updated;
      editorPages.refresh();
      update();
    }
  }

  void reorderPages(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = editorPages.removeAt(oldIndex);
    editorPages.insert(newIndex, item);
    if (currentPageIndex.value == oldIndex) {
      currentPageIndex.value = newIndex;
    }
    editorPages.refresh();
    update();
  }

  Future<void> addPage() async {
    try {
      final captured = await captureService.acquire(
        const CaptureRequest(maxPages: 50),
      );
      if (captured case Success<CaptureSessionResult>(:final value)) {
        for (final capturedPage in value.pages) {
          final path = capturedPage.sourcePath;
          editorPages.add(
            EditorPageModel(
              imagePath: path,
              rawImagePath: path,
              filter: DocumentFilterType.original,
              quarterTurns: 0,
              corners: DocumentCorners.fullFrame(),
            ),
          );
        }
        currentPageIndex.value = editorPages.length - 1;
        editorPages.refresh();
        update();
      } else if (captured case Failure(:final error)) {
        SnackbarHelper.showError('Could not capture page: ${error.message}');
      }
    } catch (e) {
      debugPrint('Error adding page: $e');
      SnackbarHelper.showError('Could not add page');
    }
  }

  void deletePage(int index) {
    if (editorPages.length <= 1) {
      SnackbarHelper.showError('Document must have at least 1 page');
      return;
    }
    editorPages.removeAt(index);
    if (currentPageIndex.value >= editorPages.length) {
      currentPageIndex.value = editorPages.length - 1;
    }
    editorPages.refresh();
    update();
  }

  /// Instant GPU Filter Selection (0 ms)
  void applyFilter(DocumentFilterType filter) {
    if (currentPage == null) return;
    if (filter != DocumentFilterType.original) {
      SnackbarHelper.showInfo('Filters other than Original are coming in a future update');
      return;
    }
    selectedFilter.value = filter;
    currentPage!.filter = filter;
    editorPages.refresh();
    update();
  }

  /// Apply Filter to All Pages (pdf_tool feature)
  void applyFilterToAll(DocumentFilterType filter) {
    if (filter != DocumentFilterType.original) {
      SnackbarHelper.showInfo('Filters other than Original are coming in a future update');
      return;
    }
    selectedFilter.value = filter;
    for (final page in editorPages) {
      page.filter = filter;
    }
    editorPages.refresh();
    update();
    SnackbarHelper.showSuccess('Applied ${filter.name} filter to all pages');
  }

  /// Instant Rotation (0 ms)
  void rotateImage() {
    if (currentPage == null) return;
    currentPage!.quarterTurns = (currentPage!.quarterTurns + 1) % 4;
    editorPages.refresh();
    update();
  }

  void toggleCropMode() {
    isCropMode.value = !isCropMode.value;
    update();
  }

  Future<void> applyNewCrop(DocumentCorners newCorners) async {
    if (currentPage == null) return;
    isProcessing.value = true;
    isCropMode.value = false;
    update();

    try {
      final warped = await pageProcessingService.warpPreview(
        rawImagePath: currentPage!.rawImagePath,
        corners: newCorners,
      );
      currentPage!.imagePath = warped.path;
      currentPage!.corners = newCorners;
      editorPages.refresh();
    } catch (e) {
      debugPrint('Error applying new crop: $e');
    } finally {
      isProcessing.value = false;
      update();
    }
  }

  void openOcr() {
    if (currentPage == null) return;
    Get.toNamed(
      Routes.ocr,
      arguments: {
        'imagePath': currentPage!.imagePath,
        'isPassport': isPassport.value,
      },
    );
  }

  Future<void> saveAndFinish() async {
    if (editorPages.isEmpty) return;
    isProcessing.value = true;
    update();

    try {
      final docId = DateTime.now().millisecondsSinceEpoch.toString();
      final pdfPath = await FileUtils.createTimestampedFilePath(
        extension: 'pdf',
      );

      final result = await pageProcessingService.processEditorPages(
        documentId: docId,
        pages: editorPages,
        isCancelled: () => _isCancelled,
      );

      if (result case Failure<List<ScannedPage>>(:final error)) {
        SnackbarHelper.showError('Could not process document: ${error.message}');
        return;
      }

      final processedPages = (result as Success<List<ScannedPage>>).value;

      // Generate PDF
      await pdfService.generatePdf(
        imagePaths: processedPages.map((p) => p.imagePath).toList(),
        outputFilePath: pdfPath,
      );

      final title =
          isPassport.value
              ? 'Passport ${DateTime.now().toString().substring(0, 10)}'
              : isIdCard.value
              ? 'ID Card (Merged) ${DateTime.now().toString().substring(0, 10)}'
              : 'Scan ${DateTime.now().toString().substring(0, 16)}';

      final document = ScannedDocument(
        id: docId,
        title: title,
        pages: processedPages,
        pdfPath: pdfPath,
      );

      await documentRepository.saveDocument(document);
      SnackbarHelper.showSuccess('Document saved successfully!');
      AppNavigator.toHome();
    } catch (e) {
      debugPrint('Error saving document: $e');
      SnackbarHelper.showError('Could not save document');
    } finally {
      isProcessing.value = false;
      update();
    }
  }

  void retake() {
    _isCancelled = true;
    AppNavigator.back();
  }

  @override
  void onClose() {
    _isCancelled = true;
    super.onClose();
  }
}
