import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/services/document_detection_service.dart';
import '../../../core/widgets/document_overlay.dart';
import '../controllers/scanner_controller.dart';

class ScannerView extends GetView<ScannerController> {
  const ScannerView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Obx(() {
        if (!controller.hasPermission) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.camera_alt_outlined,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Scanora needs camera access\nto scan your documents.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    AppStrings.privacyNotice,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () => controller.onInit(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    child: const Text(
                      'Allow Camera',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (!controller.isInitialized || controller.cameraController == null) {
          return const Center(
            child: CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2.5,
            ),
          );
        }

        final stabilityScore =
            controller.detectionResult.value?.stabilityScore ?? 0;
        final isStable = controller.detectionResult.value?.isStable ?? false;

        return Stack(
          fit: StackFit.expand,
          children: [
            // 1. Live Camera Preview
            CameraPreview(controller.cameraController!),

            // 2. Real-time Document Detection Overlay with Laser Scan & Guidance
            DocumentOverlayWidget(
              corners: controller.currentCorners.value,
              detectionResult: controller.detectionResult.value,
              mode: controller.scanMode.value,
              isAutoCapture: controller.autoCapture.value,
            ),

            // 3. ID Card Guidance Banner
            if (controller.scanMode.value == ScannerScanMode.idCard)
              Positioned(
                top: MediaQuery.of(context).padding.top + 56,
                left: 32,
                right: 32,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.badge_outlined,
                        color: AppColors.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        controller.idCardSide.value == 1
                            ? 'Step 1: Scan Front Side'
                            : 'Step 2: Scan Back Side',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // 4. Top Action Bar
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _CircleIconButton(icon: Icons.close, onTap: () => Get.back()),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: controller.toggleAutoCapture,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color:
                                controller.autoCapture.value
                                    ? AppColors.primary
                                    : const Color(
                                      0xFF0F172A,
                                    ).withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                controller.autoCapture.value
                                    ? Icons.auto_awesome
                                    : Icons.touch_app,
                                color: Colors.white,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                controller.autoCapture.value
                                    ? 'Auto Snap ON'
                                    : 'Manual Snap',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _CircleIconButton(
                        icon:
                            controller.flashMode == FlashMode.torch
                                ? Icons.flash_on
                                : controller.flashMode == FlashMode.auto
                                ? Icons.flash_auto
                                : Icons.flash_off,
                        color:
                            controller.flashMode != FlashMode.off
                                ? Colors.amber
                                : Colors.white,
                        onTap: controller.toggleFlash,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 5. Bottom Controls & Mode Selector
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + 20,
                  top: 20,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.7),
                      Colors.black.withValues(alpha: 0.95),
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildModeTab('Document', ScannerScanMode.document),
                          _buildModeTab(
                            AppStrings.idCard,
                            ScannerScanMode.idCard,
                          ),
                          _buildModeTab(
                            AppStrings.passport,
                            ScannerScanMode.passport,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Shutter Row with Gallery Button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 36),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _CircleIconButton(
                            icon: Icons.photo_library_outlined,
                            size: 48,
                            iconSize: 22,
                            onTap: controller.pickFromGallery,
                          ),

                          // CamScanner Shutter Ring
                          GestureDetector(
                            onTap: controller.captureImage,
                            child: SizedBox(
                              height: 84,
                              width: 84,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  CircularProgressIndicator(
                                    value:
                                        controller.autoCapture.value
                                            ? (stabilityScore / 100.0)
                                            : 0.0,
                                    strokeWidth: 4,
                                    backgroundColor: Colors.white.withValues(
                                      alpha: 0.3,
                                    ),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      isStable
                                          ? AppColors.primary
                                          : AppColors.accent,
                                    ),
                                  ),
                                  Container(
                                    height: 66,
                                    width: 66,
                                    decoration: BoxDecoration(
                                      color:
                                          controller.isCapturing.value
                                              ? Colors.white.withValues(
                                                alpha: 0.5,
                                              )
                                              : (controller.autoCapture.value &&
                                                      isStable
                                                  ? AppColors.primary
                                                  : Colors.white),
                                      shape: BoxShape.circle,
                                    ),
                                    child:
                                        controller.isCapturing.value
                                            ? const Center(
                                              child: SizedBox(
                                                width: 24,
                                                height: 24,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2.5,
                                                      color: Colors.black,
                                                    ),
                                              ),
                                            )
                                            : (controller.autoCapture.value &&
                                                    isStable
                                                ? const Icon(
                                                  Icons.check,
                                                  color: Colors.white,
                                                  size: 32,
                                                )
                                                : const Icon(
                                                  Icons.camera_alt,
                                                  color: Colors.black87,
                                                  size: 28,
                                                )),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(width: 48),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildModeTab(String title, ScannerScanMode mode) {
    final isSelected = controller.scanMode.value == mode;
    return GestureDetector(
      onTap: () => controller.setScanMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          title,
          style: TextStyle(
            color:
                isSelected ? Colors.black : Colors.white.withValues(alpha: 0.8),
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final double iconSize;
  final Color color;

  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    this.size = 40,
    this.iconSize = 20,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: size,
        width: size,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Icon(icon, color: color, size: iconSize),
      ),
    );
  }
}
