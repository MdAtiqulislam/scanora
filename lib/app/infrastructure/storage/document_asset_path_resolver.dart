import 'package:path/path.dart' as path;

import '../../core/errors/app_failure.dart';

class DocumentAssetPathResolver {
  final String rootPath;

  const DocumentAssetPathResolver(this.rootPath);

  String documentDirectory(String documentId) =>
      path.join(rootPath, 'documents', _id(documentId));

  String pagesDirectory(String documentId) =>
      path.join(documentDirectory(documentId), 'pages');

  String pageDirectory(String documentId, String pageId) =>
      path.join(pagesDirectory(documentId), _id(pageId));

  String rawImagePath(String documentId, String pageId) =>
      path.join(pageDirectory(documentId, pageId), 'raw.jpg');

  String processedImagePath(String documentId, String pageId) =>
      path.join(pageDirectory(documentId, pageId), 'processed.jpg');

  String thumbnailPath(String documentId, String pageId) =>
      path.join(pageDirectory(documentId, pageId), 'thumbnail.jpg');

  String exportsDirectory(String documentId) =>
      path.join(documentDirectory(documentId), 'exports');

  String _id(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty ||
        trimmed == '.' ||
        trimmed == '..' ||
        trimmed.contains('/') ||
        trimmed.contains(r'\') ||
        path.isAbsolute(trimmed) ||
        trimmed.contains('..')) {
      throw InvalidAssetIdentifierFailure('Invalid asset identifier');
    }
    return trimmed;
  }

  void validateDocumentId(String documentId) => _id(documentId);

  void validatePageId(String pageId) => _id(pageId);
}
