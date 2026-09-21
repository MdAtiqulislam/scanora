import 'dart:io';
import 'package:flutter/material.dart';
import '../../../data/models/document_corners.dart';

class CropQuadEditor extends StatefulWidget {
  final String imagePath;
  final DocumentCorners initialCorners;
  final ValueChanged<DocumentCorners> onCropApplied;
  final VoidCallback onCancel;

  const CropQuadEditor({
    super.key,
    required this.imagePath,
    required this.initialCorners,
    required this.onCropApplied,
    required this.onCancel,
  });

  @override
  State<CropQuadEditor> createState() => _CropQuadEditorState();
}

class _CropQuadEditorState extends State<CropQuadEditor> {
  late DocumentCorners corners;
  int? activeCornerIndex;

  @override
  void initState() {
    super.initState();
    corners = widget.initialCorners;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top action bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: widget.onCancel,
                  ),
                  const Text(
                    'Adjust Corners',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.check,
                      color: Color(0xFF10B981),
                      size: 28,
                    ),
                    onPressed: () => widget.onCropApplied(corners),
                  ),
                ],
              ),
            ),

            // Main interactive crop area
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  final scaledCorners = corners.scale(size.width, size.height);

                  return GestureDetector(
                    onPanDown: (details) {
                      final localPos = details.localPosition;
                      const double hitRadius = 36.0;

                      final d0 = (scaledCorners.topLeft - localPos).distance;
                      final d1 = (scaledCorners.topRight - localPos).distance;
                      final d2 =
                          (scaledCorners.bottomRight - localPos).distance;
                      final d3 = (scaledCorners.bottomLeft - localPos).distance;

                      final minDistance = [
                        d0,
                        d1,
                        d2,
                        d3,
                      ].reduce((a, b) => a < b ? a : b);

                      if (minDistance <= hitRadius) {
                        if (minDistance == d0) {
                          activeCornerIndex = 0;
                        } else if (minDistance == d1) {
                          activeCornerIndex = 1;
                        } else if (minDistance == d2) {
                          activeCornerIndex = 2;
                        } else if (minDistance == d3) {
                          activeCornerIndex = 3;
                        }
                      }
                    },
                    onPanUpdate: (details) {
                      if (activeCornerIndex == null) return;

                      final normX = (details.localPosition.dx / size.width)
                          .clamp(0.0, 1.0);
                      final normY = (details.localPosition.dy / size.height)
                          .clamp(0.0, 1.0);
                      final newPoint = Offset(normX, normY);

                      setState(() {
                        if (activeCornerIndex == 0) {
                          corners = corners.copyWith(topLeft: newPoint);
                        } else if (activeCornerIndex == 1) {
                          corners = corners.copyWith(topRight: newPoint);
                        } else if (activeCornerIndex == 2) {
                          corners = corners.copyWith(bottomRight: newPoint);
                        } else if (activeCornerIndex == 3) {
                          corners = corners.copyWith(bottomLeft: newPoint);
                        }
                      });
                    },
                    onPanEnd: (_) {
                      activeCornerIndex = null;
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(File(widget.imagePath), fit: BoxFit.fill),
                        CustomPaint(
                          size: size,
                          painter: _CropPainter(corners: scaledCorners),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Bottom reset pill
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    corners = DocumentCorners.defaultGuide();
                  });
                },
                icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
                label: const Text(
                  'Reset Crop',
                  style: TextStyle(color: Colors.white),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  final DocumentCorners corners;
  _CropPainter({required this.corners});

  @override
  void paint(Canvas canvas, Size size) {
    final maskPath =
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final cropPath =
        Path()
          ..moveTo(corners.topLeft.dx, corners.topLeft.dy)
          ..lineTo(corners.topRight.dx, corners.topRight.dy)
          ..lineTo(corners.bottomRight.dx, corners.bottomRight.dy)
          ..lineTo(corners.bottomLeft.dx, corners.bottomLeft.dy)
          ..close();

    final combinedMask = Path.combine(
      PathOperation.difference,
      maskPath,
      cropPath,
    );
    canvas.drawPath(
      combinedMask,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    final borderPaint =
        Paint()
          ..color = const Color(0xFF10B981)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;

    canvas.drawPath(cropPath, borderPaint);

    final handleFillPaint =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;

    final handleBorderPaint =
        Paint()
          ..color = const Color(0xFF10B981)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0;

    for (final pt in corners.points) {
      canvas.drawCircle(pt, 12, handleFillPaint);
      canvas.drawCircle(pt, 12, handleBorderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CropPainter oldDelegate) {
    return oldDelegate.corners != corners;
  }
}
