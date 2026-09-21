import 'dart:math';
import 'package:flutter/material.dart';

class DocumentCorners {
  final Offset topLeft;
  final Offset topRight;
  final Offset bottomRight;
  final Offset bottomLeft;

  const DocumentCorners({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  /// Full-frame normalized (0,0) to (1,1) corners
  factory DocumentCorners.fullFrame() {
    return const DocumentCorners(
      topLeft: Offset(0, 0),
      topRight: Offset(1, 0),
      bottomRight: Offset(1, 1),
      bottomLeft: Offset(0, 1),
    );
  }

  /// Default centered guide rectangle (normalized 0..1)
  factory DocumentCorners.defaultGuide({
    double padding = 0.08,
    double aspectRatio = 1.414,
  }) {
    final double left = padding;
    final double right = 1.0 - padding;
    final double width = right - left;
    final double height = width * aspectRatio;
    final double top = (1.0 - height).clamp(0.08, 0.3) / 2;
    final double bottom = (top + height).clamp(0.65, 0.92);

    return DocumentCorners(
      topLeft: Offset(left, top),
      topRight: Offset(right, top),
      bottomRight: Offset(right, bottom),
      bottomLeft: Offset(left, bottom),
    );
  }

  factory DocumentCorners.idCardGuide() {
    const double left = 0.07;
    const double right = 0.93;
    const double width = right - left;
    const double height = width / 1.586; // Standard ID-1 Aspect Ratio
    const double top = 0.26;
    const double bottom = top + height;

    return const DocumentCorners(
      topLeft: Offset(left, top),
      topRight: Offset(right, top),
      bottomRight: Offset(right, bottom),
      bottomLeft: Offset(left, bottom),
    );
  }

  factory DocumentCorners.passportGuide() {
    const double left = 0.12;
    const double right = 0.88;
    const double top = 0.18;
    const double bottom = 0.82;

    return const DocumentCorners(
      topLeft: Offset(left, top),
      topRight: Offset(right, top),
      bottomRight: Offset(right, bottom),
      bottomLeft: Offset(left, bottom),
    );
  }

  List<Offset> get points => [topLeft, topRight, bottomRight, bottomLeft];

  static DocumentCorners lerp(DocumentCorners a, DocumentCorners b, double t) {
    return DocumentCorners(
      topLeft: Offset.lerp(a.topLeft, b.topLeft, t) ?? a.topLeft,
      topRight: Offset.lerp(a.topRight, b.topRight, t) ?? a.topRight,
      bottomRight:
          Offset.lerp(a.bottomRight, b.bottomRight, t) ?? a.bottomRight,
      bottomLeft: Offset.lerp(a.bottomLeft, b.bottomLeft, t) ?? a.bottomLeft,
    );
  }

  double maxDisplacement(DocumentCorners other) {
    final d1 = (topLeft - other.topLeft).distance;
    final d2 = (topRight - other.topRight).distance;
    final d3 = (bottomRight - other.bottomRight).distance;
    final d4 = (bottomLeft - other.bottomLeft).distance;
    return [d1, d2, d3, d4].reduce(max);
  }

  double get normalizedArea {
    final x1 = topLeft.dx, y1 = topLeft.dy;
    final x2 = topRight.dx, y2 = topRight.dy;
    final x3 = bottomRight.dx, y3 = bottomRight.dy;
    final x4 = bottomLeft.dx, y4 = bottomLeft.dy;

    final area =
        0.5 *
        ((x1 * y2 + x2 * y3 + x3 * y4 + x4 * y1) -
                (y1 * x2 + y2 * x3 + y3 * x4 + y4 * x1))
            .abs();
    return area;
  }

  DocumentCorners scale(double width, double height) {
    return DocumentCorners(
      topLeft: Offset(topLeft.dx * width, topLeft.dy * height),
      topRight: Offset(topRight.dx * width, topRight.dy * height),
      bottomRight: Offset(bottomRight.dx * width, bottomRight.dy * height),
      bottomLeft: Offset(bottomLeft.dx * width, bottomLeft.dy * height),
    );
  }

  DocumentCorners copyWith({
    Offset? topLeft,
    Offset? topRight,
    Offset? bottomRight,
    Offset? bottomLeft,
  }) {
    return DocumentCorners(
      topLeft: topLeft ?? this.topLeft,
      topRight: topRight ?? this.topRight,
      bottomRight: bottomRight ?? this.bottomRight,
      bottomLeft: bottomLeft ?? this.bottomLeft,
    );
  }
}
