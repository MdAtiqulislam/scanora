import 'package:flutter/material.dart';
import '../../data/models/document_corners.dart';
import '../services/document_detection_service.dart';

class DocumentOverlayWidget extends StatefulWidget {
  final DocumentCorners corners;
  final DocumentDetectionResult? detectionResult;
  final ScannerScanMode mode;
  final bool isAutoCapture;

  const DocumentOverlayWidget({
    super.key,
    required this.corners,
    this.detectionResult,
    required this.mode,
    this.isAutoCapture = true,
  });

  @override
  State<DocumentOverlayWidget> createState() => _DocumentOverlayWidgetState();
}

class _DocumentOverlayWidgetState extends State<DocumentOverlayWidget>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _laserController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _laserController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isIdCard = widget.mode == ScannerScanMode.idCard;
        final isStable = widget.detectionResult?.isStable ?? false;

        // Scaled Corners dynamically adapting in real-time
        final scaledCorners = widget.corners.scale(
          constraints.maxWidth,
          constraints.maxHeight,
        );

        final guidanceTop =
            (scaledCorners.topLeft.dy + scaledCorners.topRight.dy) / 2 - 56;
        final guidanceText =
            isIdCard
                ? (isStable
                    ? (widget.isAutoCapture
                        ? 'Holding Steady — Capturing'
                        : 'ID Card aligned — Tap shutter')
                    : 'Fit ID Card into the borders')
                : (widget.detectionResult?.getGuidanceMessage(
                      isAutoCapture: widget.isAutoCapture,
                    ) ??
                    'Align document in frame');

        return Stack(
          children: [
            // Dark Cutout Mask & Auto-Adjustable Brackets
            AnimatedBuilder(
              animation: Listenable.merge([_pulseController, _laserController]),
              builder: (context, child) {
                return CustomPaint(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  painter: _AutoAdjustableCutoutPainter(
                    corners: scaledCorners,
                    isIdCard: isIdCard,
                    pulseValue: _pulseController.value,
                    laserProgress: _laserController.value,
                    isStable: isStable,
                  ),
                );
              },
            ),

            // Top Guidance Pill ("Fit it into the borders")
            Positioned(
              top: guidanceTop.clamp(
                MediaQuery.of(context).padding.top + 50,
                constraints.maxHeight - 200,
              ),
              left: 24,
              right: 24,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color:
                        isStable
                            ? const Color(0xFF10B981) // Solid Emerald
                            : const Color(0xFF0F172A).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color:
                          isStable
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.2),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isStable)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(
                            Icons.check_circle,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      Text(
                        guidanceText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AutoAdjustableCutoutPainter extends CustomPainter {
  final DocumentCorners corners;
  final bool isIdCard;
  final double pulseValue;
  final double laserProgress;
  final bool isStable;

  _AutoAdjustableCutoutPainter({
    required this.corners,
    required this.isIdCard,
    required this.pulseValue,
    required this.laserProgress,
    required this.isStable,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const emerald = Color(0xFF10B981);
    final themeColor = isStable ? emerald : Colors.white;

    // Full screen background path
    final fullScreenPath =
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // Dynamic quad path defined by corners
    final docPath =
        Path()
          ..moveTo(corners.topLeft.dx, corners.topLeft.dy)
          ..lineTo(corners.topRight.dx, corners.topRight.dy)
          ..lineTo(corners.bottomRight.dx, corners.bottomRight.dy)
          ..lineTo(corners.bottomLeft.dx, corners.bottomLeft.dy)
          ..close();

    // 1. Dark opacity outside the auto-adjusting frame
    final cutoutPath = Path.combine(
      PathOperation.difference,
      fullScreenPath,
      docPath,
    );

    final maskPaint =
        Paint()
          ..color = Colors.black.withValues(alpha: isIdCard ? 0.65 : 0.45)
          ..style = PaintingStyle.fill;
    canvas.drawPath(cutoutPath, maskPaint);

    // 2. Smooth border stroke
    final borderPaint =
        Paint()
          ..color = themeColor.withValues(alpha: isStable ? 0.9 : 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isStable ? 2.5 : 1.5;
    canvas.drawPath(docPath, borderPaint);

    // 3. Prominent White/Emerald Corner Brackets
    final cornerPaint =
        Paint()
          ..color = isStable ? emerald : Colors.white
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = isIdCard ? 4.5 : 4.0;

    final double cornerLen = isIdCard ? 32.0 : 28.0;

    _drawCorner(
      canvas,
      corners.topLeft,
      corners.topRight - corners.topLeft,
      corners.bottomLeft - corners.topLeft,
      cornerLen,
      cornerPaint,
    );
    _drawCorner(
      canvas,
      corners.topRight,
      corners.topLeft - corners.topRight,
      corners.bottomRight - corners.topRight,
      cornerLen,
      cornerPaint,
    );
    _drawCorner(
      canvas,
      corners.bottomRight,
      corners.topRight - corners.bottomRight,
      corners.bottomLeft - corners.bottomRight,
      cornerLen,
      cornerPaint,
    );
    _drawCorner(
      canvas,
      corners.bottomLeft,
      corners.bottomRight - corners.bottomLeft,
      corners.topLeft - corners.bottomLeft,
      cornerLen,
      cornerPaint,
    );
  }

  void _drawCorner(
    Canvas canvas,
    Offset vertex,
    Offset dir1,
    Offset dir2,
    double length,
    Paint paint,
  ) {
    final norm1 = dir1 / dir1.distance;
    final norm2 = dir2 / dir2.distance;

    final p1 = vertex + (norm1 * length);
    final p2 = vertex + (norm2 * length);

    final cornerPath =
        Path()
          ..moveTo(p1.dx, p1.dy)
          ..lineTo(vertex.dx, vertex.dy)
          ..lineTo(p2.dx, p2.dy);

    canvas.drawPath(cornerPath, paint);
  }

  @override
  bool shouldRepaint(covariant _AutoAdjustableCutoutPainter oldDelegate) {
    return oldDelegate.corners != corners ||
        oldDelegate.isIdCard != isIdCard ||
        oldDelegate.pulseValue != pulseValue ||
        oldDelegate.laserProgress != laserProgress ||
        oldDelegate.isStable != isStable;
  }
}
