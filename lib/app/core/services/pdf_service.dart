import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

enum PdfQuality { low, medium, high }

enum PdfPageFormatType { a4, letter, original }

class PdfService extends GetxService {
  Future<File> generatePdf({
    required List<String> imagePaths,
    required String outputFilePath,
    PdfQuality quality = PdfQuality.high,
    PdfPageFormatType pageFormat = PdfPageFormatType.a4,
  }) async {
    return compute(
      _generatePdfIsolate,
      _PdfGenParams(
        imagePaths: imagePaths,
        outputFilePath: outputFilePath,
        quality: quality,
        pageFormat: pageFormat,
      ),
    );
  }
}

class _PdfGenParams {
  final List<String> imagePaths;
  final String outputFilePath;
  final PdfQuality quality;
  final PdfPageFormatType pageFormat;

  _PdfGenParams({
    required this.imagePaths,
    required this.outputFilePath,
    required this.quality,
    required this.pageFormat,
  });
}

Future<File> _generatePdfIsolate(_PdfGenParams params) async {
  final doc = pw.Document();

  for (final path in params.imagePaths) {
    final file = File(path);
    if (!file.existsSync()) continue;

    Uint8List imageBytes = file.readAsBytesSync();
    if (imageBytes.isEmpty) continue;

    int imageWidth = 0;
    int imageHeight = 0;

    // Apply quality compression and get dimensions if needed
    if (params.quality != PdfQuality.high ||
        params.pageFormat == PdfPageFormatType.original) {
      final decoded = img.decodeImage(imageBytes);
      if (decoded != null) {
        imageWidth = decoded.width;
        imageHeight = decoded.height;

        img.Image processed = decoded;
        int jpgQuality = 95;
        if (params.quality == PdfQuality.low) {
          jpgQuality = 60;
          if (processed.width > 1200 || processed.height > 1200) {
            processed = img.copyResize(
              processed,
              width: processed.width > processed.height ? 1200 : null,
              height: processed.height >= processed.width ? 1200 : null,
              interpolation: img.Interpolation.linear,
            );
            imageWidth = processed.width;
            imageHeight = processed.height;
          }
        } else if (params.quality == PdfQuality.medium) {
          jpgQuality = 80;
        }

        imageBytes = Uint8List.fromList(
          img.encodeJpg(processed, quality: jpgQuality),
        );
      }
    }

    final image = pw.MemoryImage(imageBytes);

    PdfPageFormat pageFormat = PdfPageFormat.a4;
    pw.EdgeInsets margin = const pw.EdgeInsets.all(16);

    if (params.pageFormat == PdfPageFormatType.letter) {
      pageFormat = PdfPageFormat.letter;
    } else if (params.pageFormat == PdfPageFormatType.original &&
        imageWidth > 0 &&
        imageHeight > 0) {
      const double targetWidth = 595.28; // Standard A4 width in points
      final double targetHeight = targetWidth * (imageHeight / imageWidth);
      pageFormat = PdfPageFormat(targetWidth, targetHeight, marginAll: 0);
      margin = pw.EdgeInsets.zero;
    }

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: margin,
        build: (pw.Context context) {
          return pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain));
        },
      ),
    );
  }

  final file = File(params.outputFilePath);
  final bytes = await doc.save();
  file.writeAsBytesSync(bytes);
  return file;
}
