import 'dart:convert';

import '../../core/errors/app_failure.dart';
import '../../domain/entities/scan_document.dart';
import '../../domain/entities/scan_page.dart';
import '../../domain/value_objects/page_corners.dart';
import '../../domain/value_objects/page_transform.dart';
import '../../domain/value_objects/processing_profile.dart';
import '../../domain/enums/scan_enums.dart';

class ScanDocumentDbMapper {
  const ScanDocumentDbMapper();

  ScanDocument documentFromRows(
    Map<String, dynamic> documentRow,
    List<Map<String, dynamic>> pageRows, {
    bool strictEditMetadata = false,
  }) {
    final pages = pageRows
        .map((row) => pageFromRow(row, strictEditMetadata: strictEditMetadata))
        .toList(growable: false);
    return ScanDocument(
      id: documentRow['id'] as String,
      title: documentRow['title'] as String,
      createdAt: DateTime.parse(documentRow['created_at'] as String),
      updatedAt: DateTime.parse(documentRow['updated_at'] as String),
      favorite: documentRow['favorite'] == 1,
      tags: _decodeTags(documentRow['tags_json']),
      pdfPath: documentRow['pdf_path'] as String?,
      pages: pages,
    );
  }

  ScanPage pageFromRow(
    Map<String, dynamic> row, {
    bool strictEditMetadata = false,
  }) {
    return ScanPage(
      id: row['id'] as String,
      documentId: row['document_id'] as String,
      pageIndex: row['page_index'] as int,
      rawImagePath: row['raw_image_path'] as String?,
      processedImagePath: row['processed_image_path'] as String?,
      thumbnailPath: row['thumbnail_path'] as String?,
      corners: _decodeCorners(row['corners_json'], strict: strictEditMetadata),
      rotationAngle: (row['rotation_angle'] as num?)?.toDouble() ?? 0,
      cropTransform: _decodeTransform(
        row['crop_transform_json'],
        strict: strictEditMetadata,
      ),
      processingProfile: _decodeProfile(
        row['processing_profile_json'],
        strict: strictEditMetadata,
      ),
      ocrResult: row['ocr_result'] as String?,
      isDirty: row['is_dirty'] == 1,
      processedCacheKey: row['processed_cache_key'] as String?,
      thumbnailCacheKey: row['thumbnail_cache_key'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  Map<String, Object?> documentValues(ScanDocument document) => {
    'id': document.id,
    'title': document.title,
    'created_at': document.createdAt.toIso8601String(),
    'updated_at': document.updatedAt.toIso8601String(),
    'favorite': document.favorite ? 1 : 0,
    'tags_json': jsonEncode(document.tags),
    'pdf_path': document.pdfPath,
    'page_count': document.pageCount,
  };

  Map<String, Object?> pageValues(ScanPage page) => {
    'id': page.id,
    'document_id': page.documentId,
    'page_index': page.pageIndex,
    'raw_image_path': page.rawImagePath,
    'processed_image_path': page.processedImagePath,
    'thumbnail_path': page.thumbnailPath,
    'corners_json':
        page.corners == null ? null : jsonEncode(page.corners!.toMap()),
    'rotation_angle': page.rotationAngle,
    'crop_transform_json': jsonEncode(page.cropTransform.toMap()),
    'processing_profile_json': jsonEncode(page.processingProfile.toMap()),
    'ocr_result': page.ocrResult,
    'is_dirty': page.isDirty ? 1 : 0,
    'processed_cache_key': page.processedCacheKey,
    'thumbnail_cache_key': page.thumbnailCacheKey,
    'created_at': page.createdAt.toIso8601String(),
    'updated_at': page.updatedAt.toIso8601String(),
  };

  static List<String> _decodeTags(Object? value) {
    try {
      final decoded = jsonDecode(value?.toString() ?? '[]');
      return decoded is List
          ? decoded.map((item) => item.toString()).toList()
          : const [];
    } catch (_) {
      return const [];
    }
  }

  static PageCorners? _decodeCorners(Object? value, {bool strict = false}) {
    if (value == null) return null;
    try {
      return PageCorners.fromMap(
        (jsonDecode(value.toString()) as Map).cast<String, dynamic>(),
      );
    } catch (error, stackTrace) {
      if (strict) {
        throw StorageFailure(
          'Malformed persisted page corners',
          cause: error,
          stackTrace: stackTrace,
        );
      }
      return null;
    }
  }

  static PageTransform _decodeTransform(Object? value, {bool strict = false}) {
    try {
      return PageTransform.fromMap(
        (jsonDecode(value?.toString() ?? '{}') as Map).cast<String, dynamic>(),
      );
    } catch (error, stackTrace) {
      if (strict) {
        throw StorageFailure(
          'Malformed persisted page transform',
          cause: error,
          stackTrace: stackTrace,
        );
      }
      return const PageTransform();
    }
  }

  static ProcessingProfile _decodeProfile(
    Object? value, {
    bool strict = false,
  }) {
    try {
      final decoded =
          (jsonDecode(value?.toString() ?? '{}') as Map)
              .cast<String, dynamic>();
      final filterName = decoded['filterType'] as String?;
      if (strict &&
          filterName != null &&
          !ScanFilterType.values.any((filter) => filter.name == filterName)) {
        throw const StorageFailure('Unknown persisted processing filter');
      }
      return ProcessingProfile.fromMap(decoded);
    } catch (error, stackTrace) {
      if (strict) {
        throw StorageFailure(
          'Malformed persisted processing profile',
          cause: error,
          stackTrace: stackTrace,
        );
      }
      return const ProcessingProfile();
    }
  }
}
