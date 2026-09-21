import '../../core/result/result.dart';
import '../../core/errors/app_failure.dart';

enum AssetKind { raw, processed, thumbnail }

class AssetIntegrityReport {
  final List<String> orphanDocuments;
  final List<String> orphanPages;
  final List<String> missingRawAssets;
  final List<String> missingProcessedAssets;
  final List<String> missingThumbnails;
  final List<String> unknownFiles;

  const AssetIntegrityReport({
    this.orphanDocuments = const [],
    this.orphanPages = const [],
    this.missingRawAssets = const [],
    this.missingProcessedAssets = const [],
    this.missingThumbnails = const [],
    this.unknownFiles = const [],
  });

  bool get isHealthy =>
      orphanDocuments.isEmpty &&
      orphanPages.isEmpty &&
      missingRawAssets.isEmpty &&
      missingProcessedAssets.isEmpty &&
      missingThumbnails.isEmpty &&
      unknownFiles.isEmpty;
}

abstract interface class AssetStore {
  Future<Result<String>> createDocumentStorage(String documentId);
  Future<Result<String>> createPageStorage(String documentId, String pageId);

  Future<Result<String>> saveRawImage(
    String documentId,
    String pageId,
    List<int> bytes,
  );

  Future<Result<String>> saveProcessedImage(
    String documentId,
    String pageId,
    List<int> bytes,
  );

  Future<Result<String>> saveThumbnail(
    String documentId,
    String pageId,
    List<int> bytes,
  );

  Future<Result<List<int>>> readRawImage(String documentId, String pageId);
  Future<Result<List<int>>> readProcessedImage(
    String documentId,
    String pageId,
  );
  Future<Result<List<int>>> readThumbnail(String documentId, String pageId);

  Future<Result<bool>> exists(String documentId, String pageId, AssetKind kind);
  Future<Result<String>> pathFor(
    String documentId,
    String pageId,
    AssetKind kind,
  ) async =>
      const Failure(StorageFailure('Asset path is not exposed by this store'));
  Future<Result<void>> deletePageAssets(String documentId, String pageId);
  Future<Result<void>> deleteDocumentAssets(String documentId);

  Future<Result<AssetIntegrityReport>> inspectIntegrity({
    required Iterable<String> documentIds,
    required Iterable<({String documentId, String pageId})> pages,
    required Iterable<({String documentId, String pageId, AssetKind kind})>
    referencedAssets,
  });
}
