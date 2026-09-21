import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/navigation/app_navigator.dart';
import '../../../core/services/camera_service.dart';
import '../../../core/services/document_detection_service.dart';
import '../../../core/services/image_processing_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../../application/services/capture_service.dart';
import '../../../domain/contracts/capture_provider.dart';
import '../../../core/result/result.dart';
import '../../../data/models/document_corners.dart';
import '../../../routes/app_pages.dart';
import '../../settings/controllers/settings_controller.dart';

class ScannerController extends GetxController {
  final CameraService cameraService = Get.find<CameraService>();
  final DocumentDetectionService detectionService = Get.put(
    DocumentDetectionService(),
  );
  final StorageService storageService = Get.find<StorageService>();
  final ImageProcessingService imageProcessingService =
      Get.find<ImageProcessingService>();
  final ImagePicker _picker = ImagePicker();
  final CaptureService captureService = Get.find<CaptureService>();

  var scanMode = ScannerScanMode.document.obs;
  var autoCapture = true.obs;
  var isCapturing = false.obs;
  var currentCorners = DocumentCorners.defaultGuide().obs;
  Rx<DocumentDetectionResult?> detectionResult = Rx<DocumentDetectionResult?>(
    null,
  );

  var idCardSide = 1.obs;
  String? idCardFrontPath;

  bool _autoCaptureScheduled = false;

  CameraController? get cameraController => cameraService.controller;
  bool get isInitialized => cameraService.isInitialized.value;
  bool get hasPermission => cameraService.hasPermission.value;
  FlashMode get flashMode => cameraService.flashMode.value;

  @override
  void onInit() {
    super.onInit();
    autoCapture.value = storageService.getBool(
      AppConstants.keyAutoCapture,
      defaultValue: true,
    );

    final args = Get.arguments as Map<String, dynamic>?;
    if (args != null && args.containsKey('mode')) {
      setScanMode(args['mode'] as ScannerScanMode);
    } else {
      final s =
          storageService.getString(AppConstants.keyDefaultScanMode) ??
          'document';
      setScanMode(
        s == 'id_card'
            ? ScannerScanMode.idCard
            : s == 'passport'
            ? ScannerScanMode.passport
            : ScannerScanMode.document,
      );
    }
    _initScanner();
  }

  Future<void> _initScanner() async {
    await cameraService.initializeCamera();
    if (cameraService.isInitialized.value) _startLiveDetection();
    cameraService.isInitialized.listen((ok) {
      if (ok && !cameraService.isStreaming.value) _startLiveDetection();
      update();
    });
  }

  void setScanMode(ScannerScanMode mode) {
    scanMode.value = mode;
    idCardSide.value = 1;
    idCardFrontPath = null;
    _autoCaptureScheduled = false;
    detectionService.resetStability();
    currentCorners.value =
        mode == ScannerScanMode.idCard
            ? DocumentCorners.idCardGuide()
            : mode == ScannerScanMode.passport
            ? DocumentCorners.passportGuide()
            : DocumentCorners.defaultGuide();
    update();
  }

  void toggleAutoCapture() {
    final newVal = !autoCapture.value;
    autoCapture.value = newVal;
    storageService.setBool(AppConstants.keyAutoCapture, newVal);
    if (Get.isRegistered<SettingsController>()) {
      Get.find<SettingsController>().autoCapture.value = newVal;
    }
    _autoCaptureScheduled = false;
    detectionService.resetStability();
    update();
  }

  Future<void> toggleFlash() async {
    await cameraService.toggleFlash();
    update();
  }

  void _startLiveDetection() {
    cameraService.startFrameStream((frame) async {
      if (isCapturing.value || _autoCaptureScheduled) return;

      final result = await detectionService.analyzeFrame(
        image: frame,
        mode: scanMode.value,
      );
      if (result == null) return;

      detectionResult.value = result;

      currentCorners.value = DocumentCorners.lerp(
        currentCorners.value,
        result.corners,
        0.35,
      );

      // Auto-capture: wait 400ms after stable, then open ML Kit scanner
      if (autoCapture.value &&
          result.isStable &&
          !isCapturing.value &&
          !_autoCaptureScheduled) {
        _autoCaptureScheduled = true;
        // Small delay so user sees the "detected" overlay animation
        await Future.delayed(const Duration(milliseconds: 400));
        if (!isCapturing.value) {
          HapticFeedback.mediumImpact();
          await captureImage();
        } else {
          _autoCaptureScheduled = false;
        }
      }

      if (!result.isStable && !isCapturing.value && !_autoCaptureScheduled) {
        // Keep false only if stable hasn't been triggered yet
      }
    });
  }

  /// Capture via Google ML Kit Document Scanner (CunningDocumentScanner)
  /// This replaces our own broken Dart ray-casting pipeline.
  /// ML Kit auto-detects edges, does perspective correction, and returns clean cropped images.
  Future<void> captureImage() async {
    if (isCapturing.value) return;

    try {
      isCapturing.value = true;
      _autoCaptureScheduled = false;
      update();

      // Stop camera preview stream during ML Kit scan UI
      await cameraService.stopFrameStream();

      HapticFeedback.selectionClick();

      final isIdCard = scanMode.value == ScannerScanMode.idCard;
      final isPassport = scanMode.value == ScannerScanMode.passport;

      if (isIdCard) {
        await _captureIdCard();
        return;
      }

      // Document / Passport: use ML Kit scanner directly
      final captured = await captureService.acquire(
        CaptureRequest(
          mode: isPassport ? CaptureMode.singlePage : CaptureMode.multiPage,
          maxPages: isPassport ? 1 : 50,
        ),
      );

      if (captured case Success<CaptureSessionResult>(:final value)) {
        final pictures = value.pages.map((page) => page.sourcePath).toList();
        AppNavigator.toEditor({
          'images': pictures,
          'imagePath': pictures.first,
          'rawImagePath': pictures.first,
          'alreadyCropped': true,
          'corners': DocumentCorners.defaultGuide(),
          'mode': scanMode.value,
        })?.then((_) {
          isCapturing.value = false;
          _autoCaptureScheduled = false;
          detectionService.resetStability();
          _startLiveDetection();
        });
      } else {
        // User cancelled ML Kit scanner
        isCapturing.value = false;
        _autoCaptureScheduled = false;
        _startLiveDetection();
      }
    } catch (e) {
      debugPrint('Capture error: $e');
      isCapturing.value = false;
      _autoCaptureScheduled = false;
      _startLiveDetection();
    }
  }

  Future<void> _captureIdCard() async {
    try {
      if (idCardSide.value == 1) {
        // Step 1: Scan Front
        final step1Result = await captureService.acquire(
          const CaptureRequest(
            mode: CaptureMode.idCard,
            maxPages: 1,
            allowMultiple: false,
          ),
        );
        if (step1Result case Failure()) {
          isCapturing.value = false;
          _autoCaptureScheduled = false;
          _startLiveDetection();
          return;
        }

        final frontSaved =
            (step1Result as Success<CaptureSessionResult>)
                .value
                .pages
                .first
                .sourcePath;
        final frontFile = await imageProcessingService.normalizeLandscapeImage(
          File(frontSaved),
        );
        idCardFrontPath = frontFile.path;
        idCardSide.value = 2;
        isCapturing.value = false;
        _autoCaptureScheduled = false;
        detectionService.resetStability();
        SnackbarHelper.showSuccess(
          'Front side scanned — Please scan the back side',
        );
        _startLiveDetection();
        update();
      } else {
        // Step 2: Scan Back
        final step2Result = await captureService.acquire(
          const CaptureRequest(
            mode: CaptureMode.idCard,
            maxPages: 1,
            allowMultiple: false,
          ),
        );
        if (step2Result case Failure()) {
          isCapturing.value = false;
          _autoCaptureScheduled = false;
          _startLiveDetection();
          return;
        }

        final frontPath = idCardFrontPath!;
        final backSaved =
            (step2Result as Success<CaptureSessionResult>)
                .value
                .pages
                .first
                .sourcePath;
        final backFile = await imageProcessingService.normalizeLandscapeImage(
          File(backSaved),
        );

        isCapturing.value = false;
        _autoCaptureScheduled = false;
        idCardSide.value = 1;
        idCardFrontPath = null;

        Get.toNamed(
          Routes.idCardMerge,
          arguments: {
            'frontPath': frontPath,
            'rawFrontPath': frontPath,
            'backPath': backFile.path,
            'rawBackPath': backFile.path,
          },
        )?.then((_) {
          detectionService.resetStability();
          _autoCaptureScheduled = false;
          _startLiveDetection();
        });
      }
    } catch (e) {
      debugPrint('ID card capture error: $e');
      isCapturing.value = false;
      _autoCaptureScheduled = false;
      _startLiveDetection();
    }
  }

  Future<void> pickFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        await cameraService.stopFrameStream();
        AppNavigator.toEditor({
          'imagePath': image.path,
          'rawImagePath': image.path,
          'alreadyCropped':
              false, // Gallery images may need manual crop/perspective fix
          'corners': DocumentCorners.defaultGuide(),
          'mode': scanMode.value,
        })?.then((_) {
          detectionService.resetStability();
          _autoCaptureScheduled = false;
          _startLiveDetection();
        });
      }
    } catch (e) {
      debugPrint('Gallery error: $e');
    }
  }

  @override
  void onClose() {
    cameraService.stopFrameStream();
    cameraService.disposeCamera();
    super.onClose();
  }
}
