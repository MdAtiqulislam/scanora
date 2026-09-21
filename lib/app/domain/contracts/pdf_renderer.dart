import '../../core/result/result.dart';
import '../entities/scan_document.dart';
import '../value_objects/export_options.dart';

abstract interface class PdfRenderer {
  Future<Result<String>> render(ScanDocument document, ExportOptions options);
}
