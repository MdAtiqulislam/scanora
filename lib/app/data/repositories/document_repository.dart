import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../domain/entities/scan_document.dart' as domain;
import '../../domain/contracts/asset_store.dart';
import '../../domain/entities/scan_page.dart' as domain_page;
import '../../domain/enums/scan_enums.dart';
import '../../domain/value_objects/page_corners.dart';
import '../../domain/value_objects/point.dart';
import '../../domain/value_objects/processing_profile.dart';
import '../../domain/value_objects/processing_adjustments.dart';
import '../datasources/scanora_database.dart';
import '../models/document_corners.dart';
import '../models/scanned_document.dart';
import '../models/scanned_page.dart';
import 'sqlite_document_repository_v2.dart';

/// Compatibility facade for existing GetX controllers.
/// All reads and writes delegate to the normalized v2 SQLite repository.
class DocumentRepository extends GetxService {
  final SqliteDocumentRepositoryV2 v2Repository;
  final RxList<ScannedDocument> documents = <ScannedDocument>[].obs;

  DocumentRepository({
    SqliteDocumentRepositoryV2? repository,
    AssetStore? assetStore,
  }) : v2Repository = repository ?? _defaultRepository(assetStore);

  static SqliteDocumentRepositoryV2 _defaultRepository(
    AssetStore? assetStore,
  ) => SqliteDocumentRepositoryV2(
    database: ScanoraDatabase(),
    assetStore: assetStore,
  );

  Future<DocumentRepository> init() async {
    await loadDocuments();
    return this;
  }

  Future<void> loadDocuments() async {
    final loaded = await v2Repository.getAll();
    documents.assignAll(loaded.map(_toLegacy).toList());
  }

  Future<void> saveDocument(ScannedDocument document) async {
    await v2Repository.save(_toDomain(document));
    await loadDocuments();
  }

  Future<void> deleteDocument(String id) async {
    await v2Repository.delete(id);
    await loadDocuments();
  }

  static domain.ScanDocument _toDomain(ScannedDocument document) {
    return domain.ScanDocument(
      id: document.id,
      title: document.title,
      createdAt: document.createdAt,
      updatedAt: document.updatedAt,
      pdfPath: document.pdfPath,
      pages:
          document.pages.asMap().entries.map((entry) {
            final index = entry.key;
            final page = entry.value;
            final filter = _filterFromLegacy(page.filter);
            return domain_page.ScanPage(
              id: page.id.isEmpty ? '${document.id}-page-$index' : page.id,
              documentId: document.id,
              pageIndex: index,
              rawImagePath: page.rawImagePath,
              processedImagePath: page.imagePath,
              processedCacheKey: page.processedCacheKey,
              thumbnailCacheKey: page.thumbnailCacheKey,
              corners: _cornersToDomain(page.corners),
              rotationAngle: page.rotationAngle.toDouble(),
              processingProfile: ProcessingProfile(
                filterType: filter,
                adjustments: ProcessingAdjustments(
                  brightness: page.brightness,
                  contrast: page.contrast,
                  saturation: page.saturation,
                ),
              ),
              createdAt: page.createdAt,
              updatedAt: page.createdAt,
            );
          }).toList(),
    );
  }

  static ScannedDocument _toLegacy(domain.ScanDocument document) {
    return ScannedDocument(
      id: document.id,
      title: document.title,
      pdfPath: document.pdfPath,
      createdAt: document.createdAt,
      updatedAt: document.updatedAt,
      pages:
          document.pages.map((page) {
            return ScannedPage(
              id: page.id,
              imagePath: page.processedImagePath ?? page.rawImagePath ?? '',
              rawImagePath: page.rawImagePath,
              corners: _cornersToLegacy(page.corners),
              filter: _legacyFilterName(page.filterType),
              rotationAngle: page.rotationAngle.round(),
              processedCacheKey: page.processedCacheKey,
              thumbnailCacheKey: page.thumbnailCacheKey,
              brightness: page.brightness,
              contrast: page.contrast,
              saturation: page.saturation,
              createdAt: page.createdAt,
            );
          }).toList(),
    );
  }

  static ScanFilterType _filterFromLegacy(String value) => switch (value) {
    'original' => ScanFilterType.original,
    'auto' => ScanFilterType.auto,
    'magic' => ScanFilterType.magic,
    'gray' => ScanFilterType.gray,
    'blackAndWhite' => ScanFilterType.blackAndWhite,
    _ => ScanFilterType.smart,
  };

  static String _legacyFilterName(ScanFilterType value) => switch (value) {
    ScanFilterType.original => 'original',
    ScanFilterType.color => 'color',
    ScanFilterType.smart => 'smart',
    ScanFilterType.gray => 'gray',
    ScanFilterType.blackAndWhite => 'blackAndWhite',
    ScanFilterType.auto => 'auto',
    ScanFilterType.magic => 'magic',
  };

  static PageCorners? _cornersToDomain(DocumentCorners? corners) {
    if (corners == null) return null;
    return PageCorners(
      topLeft: Point2D(corners.topLeft.dx, corners.topLeft.dy),
      topRight: Point2D(corners.topRight.dx, corners.topRight.dy),
      bottomRight: Point2D(corners.bottomRight.dx, corners.bottomRight.dy),
      bottomLeft: Point2D(corners.bottomLeft.dx, corners.bottomLeft.dy),
    );
  }

  static DocumentCorners? _cornersToLegacy(PageCorners? corners) {
    if (corners == null) return null;
    return DocumentCorners(
      topLeft: Offset(corners.topLeft.x, corners.topLeft.y),
      topRight: Offset(corners.topRight.x, corners.topRight.y),
      bottomRight: Offset(corners.bottomRight.x, corners.bottomRight.y),
      bottomLeft: Offset(corners.bottomLeft.x, corners.bottomLeft.y),
    );
  }
}
