import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/app_lock_service.dart';
import '../../../core/services/pdf_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../theme/theme_controller.dart';

import '../../scanner/controllers/scanner_controller.dart';

class SettingsController extends GetxController {
  final ThemeController themeController = Get.find<ThemeController>();
  final StorageService storageService = Get.find<StorageService>();
  final AppLockService appLockService = Get.find<AppLockService>();

  // Scanner settings
  final autoCapture = true.obs;
  final defaultScanMode = 'document'.obs; // 'document', 'id_card', 'passport'
  final autoEnhancement = true.obs;

  // Document settings
  final pdfQuality = PdfQuality.high.obs;
  final defaultPageSize = PdfPageFormatType.original.obs;

  // Privacy & Security
  final appLockEnabled = false.obs;

  @override
  void onInit() {
    super.onInit();
    _loadSettings();
  }

  void _loadSettings() {
    // 1. Auto Capture
    autoCapture.value = storageService.getBool(
      AppConstants.keyAutoCapture,
      defaultValue: true,
    );

    // 2. Default Scan Mode
    defaultScanMode.value =
        storageService.getString(AppConstants.keyDefaultScanMode) ?? 'document';

    // 3. Auto Enhancement
    autoEnhancement.value = storageService.getBool(
      AppConstants.keyAutoEnhancement,
      defaultValue: true,
    );

    // 4. PDF Quality
    final savedQuality = storageService.getString(AppConstants.keyPdfQuality);
    if (savedQuality == 'low') {
      pdfQuality.value = PdfQuality.low;
    } else if (savedQuality == 'medium') {
      pdfQuality.value = PdfQuality.medium;
    } else {
      pdfQuality.value = PdfQuality.high;
    }

    // 5. Default Page Size
    final savedPageSize = storageService.getString(
      AppConstants.keyDefaultPageSize,
    );
    if (savedPageSize == 'a4') {
      defaultPageSize.value = PdfPageFormatType.a4;
    } else if (savedPageSize == 'letter') {
      defaultPageSize.value = PdfPageFormatType.letter;
    } else {
      defaultPageSize.value = PdfPageFormatType.original;
    }

    // 6. App Lock
    appLockEnabled.value = storageService.getBool(
      AppConstants.keyAppLockEnabled,
      defaultValue: false,
    );
  }

  void toggleAutoCapture(bool val) {
    autoCapture.value = val;
    storageService.setBool(AppConstants.keyAutoCapture, val);
    if (Get.isRegistered<ScannerController>()) {
      Get.find<ScannerController>().autoCapture.value = val;
    }
  }

  void setDefaultScanMode(String mode) {
    defaultScanMode.value = mode;
    storageService.setString(AppConstants.keyDefaultScanMode, mode);
  }

  void toggleAutoEnhancement(bool val) {
    autoEnhancement.value = val;
    storageService.setBool(AppConstants.keyAutoEnhancement, val);
  }

  void setPdfQuality(PdfQuality quality) {
    pdfQuality.value = quality;
    String qualityStr = 'high';
    if (quality == PdfQuality.low) qualityStr = 'low';
    if (quality == PdfQuality.medium) qualityStr = 'medium';
    storageService.setString(AppConstants.keyPdfQuality, qualityStr);
  }

  void setDefaultPageSize(PdfPageFormatType size) {
    defaultPageSize.value = size;
    String sizeStr = 'original';
    if (size == PdfPageFormatType.a4) sizeStr = 'a4';
    if (size == PdfPageFormatType.letter) sizeStr = 'letter';
    storageService.setString(AppConstants.keyDefaultPageSize, sizeStr);
  }

  Future<void> toggleAppLock(bool val) async {
    if (val) {
      final success = await appLockService.enableAppLock();
      if (success) {
        appLockEnabled.value = true;
        Get.snackbar(
          'App Lock Enabled',
          'Your documents are now protected.',
          snackPosition: SnackPosition.BOTTOM,
        );
      } else {
        appLockEnabled.value = false;
        Get.snackbar(
          'Could not enable App Lock',
          'Please set up fingerprint, Face ID, or device security first.',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } else {
      await appLockService.disableAppLock();
      appLockEnabled.value = false;
      Get.snackbar(
        'App Lock Disabled',
        'Your documents are no longer protected by App Lock.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  void setThemeMode(ThemeMode mode) {
    themeController.setThemeMode(mode);
  }

  // UI Helpers
  String getScanModeName(String mode) {
    switch (mode) {
      case 'id_card':
        return 'ID Card';
      case 'passport':
        return 'Passport';
      case 'document':
      default:
        return 'Document';
    }
  }

  String getPdfQualityName(PdfQuality quality) {
    switch (quality) {
      case PdfQuality.low:
        return 'Low quality (Smaller size)';
      case PdfQuality.medium:
        return 'Medium quality (Balanced)';
      case PdfQuality.high:
        return 'High quality (Crisp details)';
    }
  }

  String getPageSizeName(PdfPageFormatType size) {
    switch (size) {
      case PdfPageFormatType.a4:
        return 'A4 (210 × 297 mm)';
      case PdfPageFormatType.letter:
        return 'Letter (8.5 × 11 in)';
      case PdfPageFormatType.original:
        return 'Original (Auto-fit)';
    }
  }
}
