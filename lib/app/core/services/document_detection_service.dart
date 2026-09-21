import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../data/models/document_corners.dart';

enum ScannerScanMode { document, idCard, passport }

enum DetectionGuidance {
  searching,
  moveCloser,
  moveFarther,
  holdSteady,
  documentDetected,
  tooDark,
  tooBlurry,
  goodLighting,
}

class DocumentDetectionResult {
  final DocumentCorners corners;
  final DetectionGuidance guidance;
  final double confidence;
  final bool isStable;
  final int stabilityScore;

  const DocumentDetectionResult({
    required this.corners,
    required this.guidance,
    required this.confidence,
    required this.isStable,
    required this.stabilityScore,
  });

  String getGuidanceMessage({bool isAutoCapture = true}) {
    switch (guidance) {
      case DetectionGuidance.searching:
        return 'Align document in camera view';
      case DetectionGuidance.moveCloser:
        return 'Move closer to document';
      case DetectionGuidance.moveFarther:
        return 'Move farther away';
      case DetectionGuidance.holdSteady:
        return isAutoCapture
            ? 'Hold steady — Auto Capturing'
            : 'Document aligned — Tap shutter';
      case DetectionGuidance.documentDetected:
        return isAutoCapture
            ? 'Document detected'
            : 'Document detected — Tap shutter';
      case DetectionGuidance.tooDark:
        return 'Too dark — turn on flash';
      case DetectionGuidance.tooBlurry:
        return 'Too blurry — hold still';
      case DetectionGuidance.goodLighting:
        return 'Good lighting';
    }
  }

  String get guidanceMessage => getGuidanceMessage(isAutoCapture: true);
}

class DocumentDetectionService extends GetxService {
  bool _isProcessing = false;
  DateTime _lastProcessTime = DateTime.now();
  DocumentCorners? _lastDetectedCorners;
  int _stableFrameCount = 0;
  static const int kRequiredStableFrames = 3;

  Future<DocumentDetectionResult?> analyzeFrame({
    required CameraImage image,
    required ScannerScanMode mode,
  }) async {
    final now = DateTime.now();
    if (_isProcessing || now.difference(_lastProcessTime).inMilliseconds < 90) {
      return null;
    }

    _isProcessing = true;
    _lastProcessTime = now;

    try {
      final frameStats = _analyzeFrameStats(image);

      // 1. Lighting check
      if (frameStats.luminance < 25) {
        return DocumentDetectionResult(
          corners: _lastDetectedCorners ?? _getDefaultCorners(mode),
          guidance: DetectionGuidance.tooDark,
          confidence: 0.2,
          isStable: false,
          stabilityScore: 0,
        );
      }

      // 2. Blur check
      if (frameStats.blurScore < 8.0) {
        _stableFrameCount = max(0, _stableFrameCount - 1);
        return DocumentDetectionResult(
          corners: _lastDetectedCorners ?? _getDefaultCorners(mode),
          guidance: DetectionGuidance.tooBlurry,
          confidence: 0.3,
          isStable: false,
          stabilityScore:
              (_stableFrameCount / kRequiredStableFrames * 100).toInt(),
        );
      }

      // 3. Document Quad Edge & Corner Detection
      final detectedCorners = _detectDocumentQuad(image, mode);
      final area = detectedCorners.normalizedArea;

      DetectionGuidance guidance = DetectionGuidance.documentDetected;
      if (area < 0.12) {
        guidance = DetectionGuidance.moveCloser;
      } else if (area > 0.94) {
        guidance = DetectionGuidance.moveFarther;
      }

      // 4. Stability tracking
      if (_lastDetectedCorners != null) {
        final displacement = detectedCorners.maxDisplacement(
          _lastDetectedCorners!,
        );
        if (displacement < 0.065 && area >= 0.12 && area <= 0.94) {
          _stableFrameCount++;
          if (_stableFrameCount >= 2) {
            guidance = DetectionGuidance.holdSteady;
          }
        } else {
          _stableFrameCount = max(0, _stableFrameCount - 1);
        }
      } else {
        _stableFrameCount = 1;
      }

      _lastDetectedCorners = detectedCorners;

      final isStable = _stableFrameCount >= kRequiredStableFrames;
      final stabilityScore = min(
        100,
        (_stableFrameCount / kRequiredStableFrames * 100).toInt(),
      );

      return DocumentDetectionResult(
        corners: detectedCorners,
        guidance: guidance,
        confidence: isStable ? 0.98 : 0.85,
        isStable: isStable,
        stabilityScore: stabilityScore,
      );
    } catch (e) {
      debugPrint('Error analyzing frame: $e');
      return null;
    } finally {
      _isProcessing = false;
    }
  }

  void resetStability() {
    _stableFrameCount = 0;
    _lastDetectedCorners = null;
  }

  DocumentCorners _getDefaultCorners(ScannerScanMode mode) {
    switch (mode) {
      case ScannerScanMode.document:
        return DocumentCorners.defaultGuide();
      case ScannerScanMode.idCard:
        return DocumentCorners.idCardGuide();
      case ScannerScanMode.passport:
        return DocumentCorners.passportGuide();
    }
  }

  _FrameStats _analyzeFrameStats(CameraImage image) {
    final Uint8List plane = image.planes[0].bytes;
    final int width = image.width;
    final int height = image.height;
    final int step = max(1, plane.length ~/ 1000);

    int sumLuminance = 0;
    int samples = 0;

    for (int i = 0; i < plane.length; i += step) {
      sumLuminance += plane[i];
      samples++;
    }
    final double avgLuminance = samples > 0 ? (sumLuminance / samples) : 128.0;

    int centerSamples = 0;
    double gradSum = 0;
    final int startY = height ~/ 4;
    final int endY = (height * 3) ~/ 4;
    final int startX = width ~/ 4;
    final int endX = (width * 3) ~/ 4;

    for (int y = startY; y < endY; y += 12) {
      for (int x = startX; x < endX; x += 12) {
        final idx = y * width + x;
        if (idx + 1 < plane.length && idx + width < plane.length) {
          final gx = (plane[idx + 1] - plane[idx]).abs();
          final gy = (plane[idx + width] - plane[idx]).abs();
          gradSum += (gx + gy);
          centerSamples++;
        }
      }
    }

    final double laplacianVariance =
        centerSamples > 0 ? (gradSum / centerSamples) : 25.0;

    return _FrameStats(luminance: avgLuminance, blurScore: laplacianVariance);
  }

  DocumentCorners _detectDocumentQuad(CameraImage image, ScannerScanMode mode) {
    final baseGuide = _getDefaultCorners(mode);
    final Uint8List plane = image.planes[0].bytes;
    final int width = image.width;
    final int height = image.height;

    final double cx = width / 2.0;
    final double cy = height / 2.0;

    // Scan rays diagonally from center
    final topLeft = _castRayForCorner(
      plane,
      width,
      height,
      cx,
      cy,
      -0.7071,
      -0.7071,
      baseGuide.topLeft,
    );
    final topRight = _castRayForCorner(
      plane,
      width,
      height,
      cx,
      cy,
      0.7071,
      -0.7071,
      baseGuide.topRight,
    );
    final bottomRight = _castRayForCorner(
      plane,
      width,
      height,
      cx,
      cy,
      0.7071,
      0.7071,
      baseGuide.bottomRight,
    );
    final bottomLeft = _castRayForCorner(
      plane,
      width,
      height,
      cx,
      cy,
      -0.7071,
      0.7071,
      baseGuide.bottomLeft,
    );

    final rawDetected = DocumentCorners(
      topLeft: topLeft,
      topRight: topRight,
      bottomRight: bottomRight,
      bottomLeft: bottomLeft,
    );

    return DocumentCorners.lerp(baseGuide, rawDetected, 0.55);
  }

  Offset _castRayForCorner(
    Uint8List plane,
    int width,
    int height,
    double cx,
    double cy,
    double dirX,
    double dirY,
    Offset defaultNormalized,
  ) {
    final double maxDist = sqrt(cx * cx + cy * cy) * 0.90;
    int maxGrad = 0;
    double bestDist = 0;

    for (double dist = maxDist * 0.25; dist < maxDist; dist += 8.0) {
      final px = (cx + dirX * dist).round();
      final py = (cy + dirY * dist).round();

      if (px > 4 && px < width - 4 && py > 4 && py < height - 4) {
        final idx = py * width + px;
        final nextIdx =
            (py + (dirY > 0 ? 3 : -3)) * width + (px + (dirX > 0 ? 3 : -3));

        if (idx < plane.length && nextIdx >= 0 && nextIdx < plane.length) {
          final grad = (plane[idx] - plane[nextIdx]).abs();
          if (grad > maxGrad && grad > 20) {
            maxGrad = grad;
            bestDist = dist;
          }
        }
      }
    }

    if (maxGrad > 20 && bestDist > 0) {
      final edgeX = (cx + dirX * bestDist).clamp(0.0, width.toDouble());
      final edgeY = (cy + dirY * bestDist).clamp(0.0, height.toDouble());
      return Offset(edgeX / width, edgeY / height);
    }

    return defaultNormalized;
  }
}

class _FrameStats {
  final double luminance;
  final double blurScore;
  const _FrameStats({required this.luminance, required this.blurScore});
}
