import 'package:pdf/pdf.dart';

/// Single source of truth for ID Card physical dimensions and conversions
class IdCardDimensions {
  IdCardDimensions._();

  /// Physical dimensions in millimeters
  static const double widthMm = 90.0; // 9.0 cm (90 mm)
  static const double heightMm = 55.0; // 5.5 cm (55 mm)

  /// Aspect ratio: 9.0 / 5.5 ≈ 1.6363636
  static const double aspectRatio = widthMm / heightMm;

  /// Exact PDF point dimensions (1 mm = 72.0 / 25.4 pt ≈ 2.83464567 pt)
  static const double widthPt = widthMm * PdfPageFormat.mm; // 255.11811 pt
  static const double heightPt = heightMm * PdfPageFormat.mm; // 155.90551 pt

  /// Standard A4 sheet dimensions in millimeters (210 x 297 mm)
  static const double a4WidthMm = 210.0;
  static const double a4HeightMm = 297.0;

  /// Proportional width of the ID card on an A4 sheet for physical 1:1 preview representation
  static const double a4WidthRatio = widthMm / a4WidthMm; // 90 / 210 ≈ 0.42857

  /// Standard 300 DPI pixel dimensions for 1:1 print rasterization
  /// 300 DPI = 300 / 25.4 ≈ 11.811 pixels per mm
  static const double dpi = 300.0;
  static const double pixelsPerMm = dpi / 25.4;
  static const int widthPx300Dpi = 1063; // (90 * 300 / 25.4).round()
  static const int heightPx300Dpi = 650; // (55 * 300 / 25.4).round()
}
