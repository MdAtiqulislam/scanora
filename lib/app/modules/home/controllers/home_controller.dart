import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/document_detection_service.dart';
import '../../../core/services/image_processing_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/utils/file_utils.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../../data/models/document_corners.dart';
import '../../../data/models/scanned_document.dart';
import '../../../data/repositories/document_repository.dart';
import '../../../application/services/capture_service.dart';
import '../../../domain/contracts/capture_provider.dart';
import '../../../core/result/result.dart';
import '../../../routes/app_pages.dart';

class HomeController extends GetxController {
  final DocumentRepository repository = Get.find<DocumentRepository>();
  final StorageService storageService = Get.find<StorageService>();
  final ImageProcessingService imageProcessingService =
      Get.find<ImageProcessingService>();
  final ImagePicker _picker = ImagePicker();
  final CaptureService captureService = Get.find<CaptureService>();

  var currentNavIndex = 0.obs;
  var isScanning = false.obs;
  RxList<ScannedDocument> get recentDocuments => repository.documents;

  void changeNavIndex(int index) {
    currentNavIndex.value = index;
  }

  void startDefaultScan() {
    final defaultMode =
        storageService.getString(AppConstants.keyDefaultScanMode) ?? 'document';
    if (defaultMode == 'id_card') {
      startIdCardScan();
    } else if (defaultMode == 'passport') {
      startPassportScan();
    } else {
      startDocumentScan();
    }
  }

  /// 1. General Document Scanning
  Future<void> startDocumentScan() async {
    try {
      final captured = await captureService.acquire(
        const CaptureRequest(maxPages: 50),
      );
      if (captured case Success<CaptureSessionResult>(:final value)) {
        final pictures = value.pages.map((page) => page.sourcePath).toList();
        Get.toNamed(
          Routes.editor,
          arguments: {
            'images': pictures,
            'imagePath': pictures.first,
            'mode': ScannerScanMode.document,
            'corners': DocumentCorners.defaultGuide(),
            'alreadyCropped': true,
          },
        );
        return;
      }
    } catch (_) {
      try {
        final XFile? photo = await _picker.pickImage(
          source: ImageSource.camera,
        );
        if (photo != null) {
          Get.toNamed(
            Routes.editor,
            arguments: {
              'images': [photo.path],
              'imagePath': photo.path,
              'mode': ScannerScanMode.document,
              'corners': DocumentCorners.defaultGuide(),
              'alreadyCropped': false,
            },
          );
        }
      } catch (err) {
        SnackbarHelper.showError('Failed to capture photo: $err');
      }
    }
  }

  /// 2. ID Card Dual-Side Scanning (Step 1: Front ➔ Step 2: Back ➔ Merge Studio)
  Future<void> startIdCardScan() async {
    try {
      // Step 1: Scan Front Side
      String? frontPath;
      String? backPath;

      final step1Result = await captureService.acquire(
        const CaptureRequest(
          mode: CaptureMode.idCard,
          maxPages: 1,
          allowMultiple: false,
        ),
      );
      if (step1Result case Failure()) {
        return;
      }
      // Guarantee distinct, persistent file storage for Front
      final persistentFrontPath = await FileUtils.createTimestampedFilePath(
        prefix: 'id_front',
        extension: 'jpg',
      );
      await File(
        (step1Result as Success<CaptureSessionResult>)
            .value
            .pages
            .first
            .sourcePath,
      ).copy(persistentFrontPath);
      frontPath = persistentFrontPath;

      // Step 2: Prompt user to flip card and scan Back side
      final shouldScanBack = await Get.bottomSheet<bool>(
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Get.theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: AppColors.primary,
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Front Side Captured ✓',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Now turn your ID card over and scan the Back Side.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => Get.back(result: true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text(
                  'Scan Back Side',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        isDismissible: false,
      );

      if (shouldScanBack != true) {
        return;
      }

      // Step 3: Scan Back Side
      final step2Result = await captureService.acquire(
        const CaptureRequest(
          mode: CaptureMode.idCard,
          maxPages: 1,
          allowMultiple: false,
        ),
      );
      if (step2Result case Failure()) {
        return;
      }
      // Guarantee distinct, persistent file storage for Back
      final persistentBackPath = await FileUtils.createTimestampedFilePath(
        prefix: 'id_back',
        extension: 'jpg',
      );
      await File(
        (step2Result as Success<CaptureSessionResult>)
            .value
            .pages
            .first
            .sourcePath,
      ).copy(persistentBackPath);
      backPath = persistentBackPath;

      // Step 4: Normalize landscape & Open Merge Studio
      final frontFile = await imageProcessingService.normalizeLandscapeImage(
        File(frontPath),
      );
      final backFile = await imageProcessingService.normalizeLandscapeImage(
        File(backPath),
      );

      Get.toNamed(
        Routes.idCardMerge,
        arguments: {
          'frontPath': frontFile.path,
          'rawFrontPath': frontFile.path,
          'backPath': backFile.path,
          'rawBackPath': backFile.path,
        },
      );
    } catch (e) {
      debugPrint('Error in ID card scanning flow: $e');
      SnackbarHelper.showError('Could not complete ID card scan');
    }
  }

  /// 3. Passport Scanning
  Future<void> startPassportScan() async {
    try {
      final captured = await captureService.acquire(
        const CaptureRequest(
          mode: CaptureMode.singlePage,
          maxPages: 1,
          allowMultiple: false,
        ),
      );
      if (captured case Success<CaptureSessionResult>(:final value)) {
        final pictures = value.pages.map((page) => page.sourcePath).toList();
        Get.toNamed(
          Routes.editor,
          arguments: {
            'images': pictures,
            'imagePath': pictures.first,
            'mode': ScannerScanMode.passport,
            'corners': DocumentCorners.passportGuide(),
          },
        );
        return;
      }
    } catch (_) {
      try {
        final XFile? photo = await _picker.pickImage(
          source: ImageSource.camera,
        );
        if (photo != null) {
          Get.toNamed(
            Routes.editor,
            arguments: {
              'images': [photo.path],
              'imagePath': photo.path,
              'mode': ScannerScanMode.passport,
              'corners': DocumentCorners.passportGuide(),
            },
          );
        }
      } catch (err) {
        SnackbarHelper.showError('Failed to capture passport: $err');
      }
    }
  }

  /// 4. Gallery Multi-Image Import (Exact from pdf_tool)
  Future<void> startGalleryImport() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage();
      if (images.isNotEmpty) {
        final paths = images.map((e) => e.path).toList();
        Get.toNamed(
          Routes.editor,
          arguments: {
            'images': paths,
            'imagePath': paths.first,
            'mode': ScannerScanMode.document,
            'corners': DocumentCorners.defaultGuide(),
          },
        );
      }
    } catch (e) {
      SnackbarHelper.showError('Could not import from gallery: $e');
    }
  }

  void goToDocuments() {
    currentNavIndex.value = 1;
  }

  void goToSettings() {
    currentNavIndex.value = 2;
  }
}
