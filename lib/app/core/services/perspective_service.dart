import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image/image.dart' as img;
import '../../data/models/document_corners.dart';

class PerspectiveService extends GetxService {
  /// Perspective-corrects document area defined by [normalizedCorners].
  /// Uses proper homography transform (not bilinear lerp) for accurate straightening.
  Future<File> warpPerspective({
    required File inputFile,
    required DocumentCorners normalizedCorners,
    bool isIdCard = false,
  }) async {
    return compute(
      _warpPerspectiveIsolate,
      _WarpParams(
        filePath: inputFile.path,
        corners: normalizedCorners,
        isIdCard: isIdCard,
      ),
    );
  }

  Future<File> autoDeskewAndStraighten(File inputFile) async {
    return compute(_autoDeskewIsolate, inputFile.path);
  }
}

class _WarpParams {
  final String filePath;
  final DocumentCorners corners;
  final bool isIdCard;
  _WarpParams({
    required this.filePath,
    required this.corners,
    required this.isIdCard,
  });
}

// ── Homography 8-param struct ─────────────────────────────────────────────────
class _H {
  final double a, b, c, d, e, f, g, h;
  const _H(this.a, this.b, this.c, this.d, this.e, this.f, this.g, this.h);
}

/// Compute homography from destination rectangle (W×H) → source quadrilateral.
/// Uses the analytical closed-form solution for 4-point projective mapping.
/// src: [TL, TR, BR, BL] pixel coordinates in the source image.
_H _computeInverseHomography(List<Offset> src, int dstW, int dstH) {
  final double x0 = src[0].dx, y0 = src[0].dy; // TL
  final double x1 = src[1].dx, y1 = src[1].dy; // TR
  final double x2 = src[2].dx, y2 = src[2].dy; // BR
  final double x3 = src[3].dx, y3 = src[3].dy; // BL

  final double W = dstW.toDouble();
  final double H = dstH.toDouble();

  // Solve 2×2 system for g, h:
  // W*(x1-x2)*g + H*(x3-x2)*h = x0 - x1 - x3 + x2
  // W*(y1-y2)*g + H*(y3-y2)*h = y0 - y1 - y3 + y2
  final double a1 = W * (x1 - x2);
  final double b1 = H * (x3 - x2);
  final double c1 = x0 - x1 - x3 + x2;
  final double a2 = W * (y1 - y2);
  final double b2 = H * (y3 - y2);
  final double c2 = y0 - y1 - y3 + y2;

  final double det = a1 * b2 - a2 * b1;
  double gv = 0, hv = 0;
  if (det.abs() > 1e-10) {
    gv = (c1 * b2 - c2 * b1) / det;
    hv = (a1 * c2 - a2 * c1) / det;
  }

  final double av = (x1 - x0) / W + x1 * gv;
  final double bv = (x3 - x0) / H + x3 * hv;
  final double cv = x0;
  final double dv = (y1 - y0) / W + y1 * gv;
  final double ev = (y3 - y0) / H + y3 * hv;
  final double fv = y0;

  return _H(av, bv, cv, dv, ev, fv, gv, hv);
}

/// Map a destination pixel (dx, dy) back to source pixel using homography.
Offset _mapDstToSrc(_H h, double dx, double dy) {
  final double w = h.g * dx + h.h * dy + 1.0;
  if (w.abs() < 1e-10) return Offset.zero;
  return Offset(
    (h.a * dx + h.b * dy + h.c) / w,
    (h.d * dx + h.e * dy + h.f) / w,
  );
}

File _autoDeskewIsolate(String filePath) {
  final bytes = File(filePath).readAsBytesSync();
  var image = img.decodeImage(bytes);
  if (image == null) return File(filePath);
  image = img.bakeOrientation(image);

  // ── Step 1: Detect if there's a dark border around a bright document ──
  // e.g., phone screen on desk, paper on dark surface, etc.
  final brightRegion = _detectBrightDocumentBounds(image);
  if (brightRegion != null) {
    // Crop to the detected bright region (removes dark background)
    final cropped = img.copyCrop(
      image,
      x: brightRegion[0],
      y: brightRegion[1],
      width: brightRegion[2],
      height: brightRegion[3],
    );
    // Try perspective correction on the cropped region
    final quad = _detectDocumentQuadOnImage(cropped);
    final result = quad != null ? _homographyWarp(cropped, quad) : cropped;
    final outPath =
        '${filePath}_deskewed_${DateTime.now().millisecondsSinceEpoch}.jpg';
    File(outPath).writeAsBytesSync(img.encodeJpg(result, quality: 98));
    return File(outPath);
  }

  // ── Step 2: No dark border — try perspective quad detection directly ──
  final detected = _detectDocumentQuadOnImage(image);
  if (detected != null) {
    final warped = _homographyWarp(image, detected);
    final outPath =
        '${filePath}_deskewed_${DateTime.now().millisecondsSinceEpoch}.jpg';
    File(outPath).writeAsBytesSync(img.encodeJpg(warped, quality: 98));
    return File(outPath);
  }

  // ── Step 3: Nothing detected, return original ──
  return File(filePath);
}

/// Detect the bounding box of the bright document region within a dark background.
/// Returns [x, y, width, height] or null if no clear document found.
List<int>? _detectBrightDocumentBounds(img.Image image) {
  const int step = 8;
  const double brightThreshold =
      130.0; // pixels brighter than this are "document"
  const double darkBorderRatio = 0.30; // 30% of border must be dark to trigger

  // Sample the 4 edges of the image to detect dark border
  int darkEdgeCount = 0;
  int totalEdgeSamples = 0;

  // Top & bottom rows
  for (int x = 0; x < image.width; x += step) {
    for (int row in [0, image.height - 1]) {
      final p = image.getPixel(x, row);
      final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      if (lum < brightThreshold) darkEdgeCount++;
      totalEdgeSamples++;
    }
  }
  // Left & right columns
  for (int y = 0; y < image.height; y += step) {
    for (int col in [0, image.width - 1]) {
      final p = image.getPixel(col, y);
      final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      if (lum < brightThreshold) darkEdgeCount++;
      totalEdgeSamples++;
    }
  }

  if (totalEdgeSamples == 0) return null;
  if (darkEdgeCount / totalEdgeSamples < darkBorderRatio)
    return null; // No significant dark border

  // Find bounding box of all bright pixels
  int minX = image.width, maxX = 0, minY = image.height, maxY = 0;
  int brightCount = 0;
  int totalSamples = 0;

  for (int y = 0; y < image.height; y += step) {
    for (int x = 0; x < image.width; x += step) {
      final p = image.getPixel(x, y);
      final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      totalSamples++;
      if (lum > brightThreshold) {
        brightCount++;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }

  // Must have at least 15% bright pixels and the region must be smaller than 90% of image
  if (brightCount < totalSamples * 0.15) return null;
  if (brightCount > totalSamples * 0.90) return null;

  final regionW = maxX - minX;
  final regionH = maxY - minY;
  if (regionW < 50 || regionH < 50) return null;

  // Add margin
  const int margin = 12;
  final x = (minX - margin).clamp(0, image.width - 1);
  final y = (minY - margin).clamp(0, image.height - 1);
  final w = (maxX + margin).clamp(0, image.width) - x;
  final h = (maxY + margin).clamp(0, image.height) - y;

  return [x, y, w, h];
}

File _warpPerspectiveIsolate(_WarpParams params) {
  final bytes = File(params.filePath).readAsBytesSync();
  var image = img.decodeImage(bytes);
  if (image == null) return File(params.filePath);
  image = img.bakeOrientation(image);

  final double w = image.width.toDouble();
  final double h = image.height.toDouble();

  img.Image resultImage;

  if (params.isIdCard) {
    const double idCardRatio = 85.60 / 53.98;
    final smartCorners = _detectIdCardCornersOnImage(image, idCardRatio);
    if (smartCorners != null) {
      resultImage = _homographyWarp(image, smartCorners);
      // Resize to exact ID card proportions
      final int newH = (resultImage.width / idCardRatio).round();
      resultImage = img.copyResize(
        resultImage,
        width: resultImage.width,
        height: newH,
        interpolation: img.Interpolation.linear,
      );
    } else {
      final int cropWidth = (w * 0.84).round();
      final int cropHeight = (cropWidth / idCardRatio).round();
      final int cropX = ((w - cropWidth) / 2).round().clamp(
        0,
        image.width - 10,
      );
      final int cropY = ((h - cropHeight) / 2).round().clamp(
        0,
        image.height - 10,
      );
      resultImage = img.copyCrop(
        image,
        x: cropX,
        y: cropY,
        width: min(cropWidth, image.width - cropX),
        height: min(cropHeight, image.height - cropY),
      );
    }
  } else {
    // ── 4-point perspective warp using homography ──
    final p0 = Offset(
      (params.corners.topLeft.dx * w).clamp(0.0, w - 1),
      (params.corners.topLeft.dy * h).clamp(0.0, h - 1),
    );
    final p1 = Offset(
      (params.corners.topRight.dx * w).clamp(0.0, w - 1),
      (params.corners.topRight.dy * h).clamp(0.0, h - 1),
    );
    final p2 = Offset(
      (params.corners.bottomRight.dx * w).clamp(0.0, w - 1),
      (params.corners.bottomRight.dy * h).clamp(0.0, h - 1),
    );
    final p3 = Offset(
      (params.corners.bottomLeft.dx * w).clamp(0.0, w - 1),
      (params.corners.bottomLeft.dy * h).clamp(0.0, h - 1),
    );
    resultImage = _homographyWarp(image, [p0, p1, p2, p3]);
  }

  final outPath =
      '${params.filePath}_warped_${DateTime.now().millisecondsSinceEpoch}.jpg';
  File(outPath).writeAsBytesSync(img.encodeJpg(resultImage, quality: 98));
  return File(outPath);
}

/// Proper perspective warp using inverse homography mapping.
/// Maps destination rectangle pixels back to source quadrilateral using H^-1.
img.Image _homographyWarp(img.Image src, List<Offset> srcPts) {
  final p0 = srcPts[0]; // TL
  final p1 = srcPts[1]; // TR
  final p2 = srcPts[2]; // BR
  final p3 = srcPts[3]; // BL

  // Output width = max of top/bottom edges; height = max of left/right edges
  final int dstW = max(
    (p1 - p0).distance,
    (p2 - p3).distance,
  ).round().clamp(100, src.width);
  final int dstH = max(
    (p3 - p0).distance,
    (p2 - p1).distance,
  ).round().clamp(100, src.height);

  final hm = _computeInverseHomography(srcPts, dstW, dstH);
  final dst = img.Image(width: dstW, height: dstH);

  for (int dy = 0; dy < dstH; dy++) {
    for (int dx = 0; dx < dstW; dx++) {
      final mapped = _mapDstToSrc(hm, dx.toDouble(), dy.toDouble());
      final sx = mapped.dx.round().clamp(0, src.width - 1);
      final sy = mapped.dy.round().clamp(0, src.height - 1);
      dst.setPixel(dx, dy, src.getPixel(sx, sy));
    }
  }
  return dst;
}

List<Offset>? _detectDocumentQuadOnImage(img.Image image) {
  try {
    final double cx = image.width / 2.0;
    final double cy = image.height / 2.0;
    final p0 = _findEdgeRay(
      image,
      cx,
      cy,
      image.width * 0.05,
      image.height * 0.05,
    );
    final p1 = _findEdgeRay(
      image,
      cx,
      cy,
      image.width * 0.95,
      image.height * 0.05,
    );
    final p2 = _findEdgeRay(
      image,
      cx,
      cy,
      image.width * 0.95,
      image.height * 0.95,
    );
    final p3 = _findEdgeRay(
      image,
      cx,
      cy,
      image.width * 0.05,
      image.height * 0.95,
    );
    if (p0 != null && p1 != null && p2 != null && p3 != null)
      return [p0, p1, p2, p3];
  } catch (_) {}
  return null;
}

List<Offset>? _detectIdCardCornersOnImage(img.Image image, double targetRatio) {
  try {
    final double cx = image.width / 2.0;
    final double cy = image.height / 2.0;
    final int frameW = (image.width * 0.84).round();
    final int frameH = (frameW / targetRatio).round();
    final int startX = max(10, ((image.width - frameW) / 2).round() - 30);
    final int endX = min(image.width - 10, startX + frameW + 60);
    final int startY = max(10, ((image.height - frameH) / 2).round() - 30);
    final int endY = min(image.height - 10, startY + frameH + 60);
    final p0 = _findEdgeRay(
      image,
      cx,
      cy,
      startX.toDouble(),
      startY.toDouble(),
    );
    final p1 = _findEdgeRay(image, cx, cy, endX.toDouble(), startY.toDouble());
    final p2 = _findEdgeRay(image, cx, cy, endX.toDouble(), endY.toDouble());
    final p3 = _findEdgeRay(image, cx, cy, startX.toDouble(), endY.toDouble());
    if (p0 != null && p1 != null && p2 != null && p3 != null) {
      final width = (p1 - p0).distance;
      final height = (p3 - p0).distance;
      if (height > 50) {
        final ratio = width / height;
        if (ratio >= 1.2 && ratio <= 1.9) return [p0, p1, p2, p3];
      }
    }
  } catch (_) {}
  return null;
}

Offset? _findEdgeRay(
  img.Image image,
  double cx,
  double cy,
  double targetX,
  double targetY,
) {
  final double dx = targetX - cx;
  final double dy = targetY - cy;
  final double totalDist = sqrt(dx * dx + dy * dy);
  if (totalDist == 0) return null;
  final double stepX = dx / totalDist;
  final double stepY = dy / totalDist;
  int maxGrad = 0;
  double bestDist = 0;
  for (double dist = totalDist * 0.35; dist < totalDist * 1.05; dist += 6.0) {
    final int x = (cx + stepX * dist).round();
    final int y = (cy + stepY * dist).round();
    if (x > 2 && x < image.width - 2 && y > 2 && y < image.height - 2) {
      final p1 = image.getPixel(x, y).getChannel(img.Channel.luminance);
      final p2 = image
          .getPixel(
            (x + stepX * 4).round().clamp(0, image.width - 1),
            (y + stepY * 4).round().clamp(0, image.height - 1),
          )
          .getChannel(img.Channel.luminance);
      final grad = (p1 - p2).abs().toInt();
      if (grad > maxGrad && grad > 25) {
        maxGrad = grad;
        bestDist = dist;
      }
    }
  }
  if (maxGrad > 25 && bestDist > 0) {
    return Offset(
      (cx + stepX * bestDist).clamp(0.0, image.width - 1.0),
      (cy + stepY * bestDist).clamp(0.0, image.height - 1.0),
    );
  }
  return Offset(targetX, targetY);
}
