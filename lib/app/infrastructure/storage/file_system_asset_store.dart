import 'dart:async';
import 'dart:io';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/contracts/asset_store.dart';
import 'document_asset_path_resolver.dart';

class FileSystemAssetStore implements AssetStore {
  final Directory root;
  final DocumentAssetPathResolver paths;

  FileSystemAssetStore(this.root)
    : paths = DocumentAssetPathResolver(root.path);

  @override
  Future<Result<String>> createDocumentStorage(String documentId) async {
    try {
      paths.validateDocumentId(documentId);
      final directory = Directory(paths.documentDirectory(documentId));
      await directory.create(recursive: true);
      await Directory(paths.pagesDirectory(documentId)).create(recursive: true);
      await Directory(
        paths.exportsDirectory(documentId),
      ).create(recursive: true);
      return Success(directory.path);
    } catch (cause, stackTrace) {
      return Failure(_failure('create document storage', cause, stackTrace));
    }
  }

  @override
  Future<Result<String>> createPageStorage(
    String documentId,
    String pageId,
  ) async {
    try {
      paths.validateDocumentId(documentId);
      paths.validatePageId(pageId);
      final directory = Directory(paths.pageDirectory(documentId, pageId));
      await directory.create(recursive: true);
      return Success(directory.path);
    } catch (cause, stackTrace) {
      return Failure(_failure('create page storage', cause, stackTrace));
    }
  }

  @override
  Future<Result<String>> saveRawImage(
    String documentId,
    String pageId,
    List<int> bytes,
  ) async {
    final destination = _assetPath(documentId, pageId, AssetKind.raw);
    final destinationFile = File(destination);
    if (await destinationFile.exists()) {
      final existingBytes = await destinationFile.readAsBytes();
      if (existingBytes.isNotEmpty) {
        if (_listEquals(existingBytes, bytes)) {
          return Success(destination);
        }
        return const Failure(
          StorageFailure(
            'Raw asset already exists and is immutable. Cannot overwrite with different bytes.',
          ),
        );
      }
    }
    return _save(documentId, pageId, AssetKind.raw, bytes);
  }

  static bool _listEquals(List<int> a, List<int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Future<Result<String>> saveProcessedImage(
    String documentId,
    String pageId,
    List<int> bytes,
  ) => _save(documentId, pageId, AssetKind.processed, bytes);

  @override
  Future<Result<String>> saveThumbnail(
    String documentId,
    String pageId,
    List<int> bytes,
  ) => _save(documentId, pageId, AssetKind.thumbnail, bytes);

  Future<Result<String>> _save(
    String documentId,
    String pageId,
    AssetKind kind,
    List<int> bytes,
  ) async {
    String? temporaryPath;
    try {
      final pageResult = await createPageStorage(documentId, pageId);
      if (pageResult case Failure<String>(:final error)) {
        return Failure(error);
      }
      final destination = _assetPath(documentId, pageId, kind);
      final temporary = File(
        '$destination.tmp-${DateTime.now().microsecondsSinceEpoch}',
      );
      temporaryPath = temporary.path;
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(destination);
      if (!await File(destination).exists()) {
        throw const StorageFailure('Asset write did not produce a file');
      }
      return Success(destination);
    } catch (cause, stackTrace) {
      if (temporaryPath != null) {
        try {
          final temporary = File(temporaryPath);
          if (await temporary.exists()) await temporary.delete();
        } catch (_) {}
      }
      return Failure(_failure('write ${kind.name} image', cause, stackTrace));
    }
  }

  @override
  Future<Result<List<int>>> readRawImage(String documentId, String pageId) =>
      _read(documentId, pageId, AssetKind.raw);

  @override
  Future<Result<List<int>>> readProcessedImage(
    String documentId,
    String pageId,
  ) => _read(documentId, pageId, AssetKind.processed);

  @override
  Future<Result<List<int>>> readThumbnail(String documentId, String pageId) =>
      _read(documentId, pageId, AssetKind.thumbnail);

  Future<Result<List<int>>> _read(
    String documentId,
    String pageId,
    AssetKind kind,
  ) async {
    try {
      final file = File(_assetPath(documentId, pageId, kind));
      if (!await file.exists()) {
        return Failure(AssetNotFoundFailure('${kind.name} asset not found'));
      }
      return Success(await file.readAsBytes());
    } catch (cause, stackTrace) {
      return Failure(_failure('read ${kind.name} image', cause, stackTrace));
    }
  }

  @override
  Future<Result<bool>> exists(
    String documentId,
    String pageId,
    AssetKind kind,
  ) async {
    try {
      final file = File(_assetPath(documentId, pageId, kind));
      if (!await file.exists()) return const Success(false);
      final length = await file.length();
      return Success(length > 0);
    } catch (cause, stackTrace) {
      return Failure(_failure('check ${kind.name} image', cause, stackTrace));
    }
  }

  @override
  Future<Result<String>> pathFor(
    String documentId,
    String pageId,
    AssetKind kind,
  ) async => Success(_assetPath(documentId, pageId, kind));

  @override
  Future<Result<void>> deletePageAssets(
    String documentId,
    String pageId,
  ) async {
    try {
      final directory = Directory(paths.pageDirectory(documentId, pageId));
      if (await directory.exists()) await directory.delete(recursive: true);
      return const Success(null);
    } catch (cause, stackTrace) {
      return Failure(_failure('delete page assets', cause, stackTrace));
    }
  }

  @override
  Future<Result<void>> deleteDocumentAssets(String documentId) async {
    try {
      paths.validateDocumentId(documentId);
      final directory = Directory(paths.documentDirectory(documentId));
      if (await directory.exists()) await directory.delete(recursive: true);
      return const Success(null);
    } catch (cause, stackTrace) {
      return Failure(_failure('delete document assets', cause, stackTrace));
    }
  }

  @override
  Future<Result<AssetIntegrityReport>> inspectIntegrity({
    required Iterable<String> documentIds,
    required Iterable<({String documentId, String pageId})> pages,
    required Iterable<({String documentId, String pageId, AssetKind kind})>
    referencedAssets,
  }) async {
    try {
      final expectedDocuments = documentIds.toSet();
      final expectedPages =
          pages.map((page) => '${page.documentId}/${page.pageId}').toSet();
      final missingRaw = <String>[];
      final missingProcessed = <String>[];
      final missingThumbnails = <String>[];
      for (final reference in referencedAssets) {
        final file = File(
          _assetPath(reference.documentId, reference.pageId, reference.kind),
        );
        if (await file.exists() && await file.length() > 0) continue;
        final key = '${reference.documentId}/${reference.pageId}';
        switch (reference.kind) {
          case AssetKind.raw:
            missingRaw.add(key);
          case AssetKind.processed:
            missingProcessed.add(key);
          case AssetKind.thumbnail:
            missingThumbnails.add(key);
        }
      }
      final orphanDocuments = <String>[];
      final orphanPages = <String>[];
      final unknownFiles = <String>[];
      final managedRoot = Directory('${root.path}/documents');
      if (await managedRoot.exists()) {
        await for (final documentEntity in managedRoot.list()) {
          if (documentEntity is! Directory) continue;
          final documentId = _lastSegment(documentEntity.path);
          if (!expectedDocuments.contains(documentId)) {
            orphanDocuments.add(documentId);
            continue;
          }
          final pagesDirectory = Directory('${documentEntity.path}/pages');
          if (!await pagesDirectory.exists()) continue;
          await for (final pageEntity in pagesDirectory.list()) {
            if (pageEntity is! Directory) continue;
            final pageId = _lastSegment(pageEntity.path);
            final key = '$documentId/$pageId';
            if (!expectedPages.contains(key)) {
              orphanPages.add(key);
              continue;
            }
            await for (final asset in pageEntity.list()) {
              if (asset is File &&
                  !const {
                    'raw.jpg',
                    'processed.jpg',
                    'thumbnail.jpg',
                  }.contains(_lastSegment(asset.path))) {
                unknownFiles.add(asset.path);
              }
            }
          }
        }
      }
      return Success(
        AssetIntegrityReport(
          orphanDocuments: orphanDocuments,
          orphanPages: orphanPages,
          missingRawAssets: missingRaw,
          missingProcessedAssets: missingProcessed,
          missingThumbnails: missingThumbnails,
          unknownFiles: unknownFiles,
        ),
      );
    } catch (cause, stackTrace) {
      return Failure(_failure('inspect asset integrity', cause, stackTrace));
    }
  }

  String _assetPath(String documentId, String pageId, AssetKind kind) {
    return switch (kind) {
      AssetKind.raw => paths.rawImagePath(documentId, pageId),
      AssetKind.processed => paths.processedImagePath(documentId, pageId),
      AssetKind.thumbnail => paths.thumbnailPath(documentId, pageId),
    };
  }

  String _lastSegment(String value) => value.split(Platform.pathSeparator).last;

  StorageFailure _failure(
    String operation,
    Object cause,
    StackTrace stackTrace,
  ) =>
      cause is StorageFailure
          ? cause
          : StorageFailure(
            'Unable to $operation',
            cause: cause,
            stackTrace: stackTrace,
          );
}
