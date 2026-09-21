import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../constants/app_colors.dart';

class SnackbarHelper {
  SnackbarHelper._();

  static void showSuccess(String message, {String title = 'Success'}) {
    if (Get.overlayContext == null) return;
    Get.snackbar(
      title,
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColors.success,
      colorText: Colors.white,
      margin: const EdgeInsets.all(16),
      borderRadius: 12,
      duration: const Duration(seconds: 2),
    );
  }

  static void showError(String message, {String title = 'Error'}) {
    if (Get.overlayContext == null) return;
    Get.snackbar(
      title,
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColors.error,
      colorText: Colors.white,
      margin: const EdgeInsets.all(16),
      borderRadius: 12,
      duration: const Duration(seconds: 3),
    );
  }

  static void showInfo(String message, {String title = 'Notice'}) {
    if (Get.overlayContext == null) return;
    Get.snackbar(
      title,
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColors.primary,
      colorText: Colors.white,
      margin: const EdgeInsets.all(16),
      borderRadius: 12,
      duration: const Duration(seconds: 2),
    );
  }
}
