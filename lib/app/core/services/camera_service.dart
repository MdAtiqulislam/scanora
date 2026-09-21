import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraService extends GetxService {
  List<CameraDescription> cameras = [];
  CameraController? controller;
  RxBool isInitialized = false.obs;
  RxBool hasPermission = false.obs;
  Rx<FlashMode> flashMode = FlashMode.off.obs;
  RxBool isStreaming = false.obs;

  Future<CameraService> init() async {
    try {
      cameras = await availableCameras();
    } catch (e) {
      debugPrint('Error fetching cameras: $e');
    }
    return this;
  }

  Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();
    hasPermission.value = status.isGranted;
    return status.isGranted;
  }

  Future<void> initializeCamera({CameraDescription? cameraDescription}) async {
    if (cameras.isEmpty) return;

    final hasPerm = await requestCameraPermission();
    if (!hasPerm) return;

    final camera = cameraDescription ?? cameras.first;

    // High resolution for clear scans
    controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await controller!.initialize();
      flashMode.value = controller!.value.flashMode;
      isInitialized.value = true;
    } catch (e) {
      debugPrint('Error initializing camera controller: $e');
    }
  }

  Future<void> toggleFlash() async {
    if (controller == null || !controller!.value.isInitialized) return;
    try {
      if (flashMode.value == FlashMode.off) {
        await controller!.setFlashMode(FlashMode.torch);
        flashMode.value = FlashMode.torch;
      } else if (flashMode.value == FlashMode.torch) {
        await controller!.setFlashMode(FlashMode.auto);
        flashMode.value = FlashMode.auto;
      } else {
        await controller!.setFlashMode(FlashMode.off);
        flashMode.value = FlashMode.off;
      }
    } catch (e) {
      debugPrint('Error toggling flash: $e');
    }
  }

  Future<void> startFrameStream(Function(CameraImage image) onFrame) async {
    if (controller == null ||
        !controller!.value.isInitialized ||
        isStreaming.value)
      return;
    try {
      isStreaming.value = true;
      await controller!.startImageStream((image) {
        if (isStreaming.value) {
          onFrame(image);
        }
      });
    } catch (e) {
      debugPrint('Error starting image stream: $e');
      isStreaming.value = false;
    }
  }

  Future<void> stopFrameStream() async {
    if (controller == null ||
        !controller!.value.isInitialized ||
        !isStreaming.value)
      return;
    try {
      isStreaming.value = false;
      await controller!.stopImageStream();
    } catch (e) {
      debugPrint('Error stopping image stream: $e');
    }
  }

  void disposeCamera() {
    isStreaming.value = false;
    controller?.dispose();
    controller = null;
    isInitialized.value = false;
  }
}
