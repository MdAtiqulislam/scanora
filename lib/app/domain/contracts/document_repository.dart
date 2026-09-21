import '../entities/scan_document.dart';

abstract interface class DocumentRepository {
  Future<List<ScanDocument>> getAll();
  Future<ScanDocument?> getById(String id);
  Future<void> save(ScanDocument document);
  Future<void> delete(String id);
}
