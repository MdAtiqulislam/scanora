import 'package:flutter/material.dart';

/// Abstract Scanora Brand Logo:
/// Combines a clean Document silhouette, Corner Brackets, and a subtle glowing "S" wave.
class ScanoraLogo extends StatelessWidget {
  final double size;
  final Color? color;
  final bool showGlow;

  const ScanoraLogo({
    super.key,
    this.size = 48,
    this.color,
    this.showGlow = false,
  });

  @override
  Widget build(BuildContext context) {
    final primary = color ?? const Color(0xFF10B981);

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size(size, size),
        painter: _ScanoraLogoPainter(primaryColor: primary, showGlow: showGlow),
      ),
    );
  }
}

class _ScanoraLogoPainter extends CustomPainter {
  final Color primaryColor;
  final bool showGlow;

  _ScanoraLogoPainter({required this.primaryColor, required this.showGlow});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    if (showGlow) {
      final glowPaint =
          Paint()
            ..color = primaryColor.withValues(alpha: 0.25)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawCircle(Offset(w / 2, h / 2), w * 0.35, glowPaint);
    }

    // 1. Draw 4 Corner Scanning Brackets
    final bracketPaint =
        Paint()
          ..color = primaryColor.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = w * 0.06;

    final bracketLen = w * 0.22;
    final inset = w * 0.08;

    // Top-Left
    canvas.drawPath(
      Path()
        ..moveTo(inset + bracketLen, inset)
        ..lineTo(inset, inset)
        ..lineTo(inset, inset + bracketLen),
      bracketPaint,
    );

    // Top-Right
    canvas.drawPath(
      Path()
        ..moveTo(w - inset - bracketLen, inset)
        ..lineTo(w - inset, inset)
        ..lineTo(w - inset, inset + bracketLen),
      bracketPaint,
    );

    // Bottom-Left
    canvas.drawPath(
      Path()
        ..moveTo(inset, h - inset - bracketLen)
        ..lineTo(inset, h - inset)
        ..lineTo(inset + bracketLen, h - inset),
      bracketPaint,
    );

    // Bottom-Right
    canvas.drawPath(
      Path()
        ..moveTo(w - inset - bracketLen, h - inset)
        ..lineTo(w - inset, h - inset)
        ..lineTo(w - inset, h - inset - bracketLen),
      bracketPaint,
    );

    // 2. Draw Center Document Silhouette with subtle "S" flow
    final docPaint =
        Paint()
          ..color = primaryColor
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = w * 0.07;

    // Elegant S-shaped scanning curve through document
    final sPath =
        Path()
          ..moveTo(w * 0.65, h * 0.32)
          ..cubicTo(w * 0.35, h * 0.30, w * 0.30, h * 0.48, w * 0.50, h * 0.52)
          ..cubicTo(w * 0.70, h * 0.56, w * 0.65, h * 0.72, w * 0.35, h * 0.70);

    canvas.drawPath(sPath, docPaint);

    // Document outline dots / accents
    final accentPaint =
        Paint()
          ..color = primaryColor.withValues(alpha: 0.9)
          ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(w * 0.65, h * 0.32), w * 0.04, accentPaint);
    canvas.drawCircle(Offset(w * 0.35, h * 0.70), w * 0.04, accentPaint);
  }

  @override
  bool shouldRepaint(covariant _ScanoraLogoPainter oldDelegate) {
    return oldDelegate.primaryColor != primaryColor ||
        oldDelegate.showGlow != showGlow;
  }
}
