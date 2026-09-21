import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../core/services/pdf_service.dart';
import '../../domain/contracts/pdf_renderer.dart';
import '../../domain/entities/scan_document.dart';
import '../../domain/value_objects/export_options.dart';

class LegacyPdfRenderer implements PdfRenderer {
  final PdfService service;

  const LegacyPdfRenderer(this.service);

  @override
  Future<Result<String>> render(
    ScanDocument document,
    ExportOptions options,
  ) async {
    try {
      final paths =
          document.pages
              .map((page) => page.processedImagePath ?? page.rawImagePath)
              .whereType<String>()
              .toList();
      final file = await service.generatePdf(
        imagePaths: paths,
        outputFilePath: options.outputPath,
      );
      return Success(file.path);
    } catch (cause, stackTrace) {
      return Failure(
        PdfFailure(
          'PDF rendering failed',
          cause: cause,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
