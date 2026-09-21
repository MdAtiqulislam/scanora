import 'dart:io';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../data/models/scanned_document.dart';
import '../../data/models/scanned_page.dart';
import '../../data/repositories/document_repository.dart';
import '../../domain/contracts/asset_store.dart';
import '../../domain/contracts/capture_provider.dart';

class CaptureService {
  final CaptureProvider provider;
  final AssetStore assetStore;
  final DocumentRepository repository;
  bool _active = false;

  CaptureService({
    required this.provider,
    required this.assetStore,
    required this.repository,
  });

  bool get isActive => _active;

  Future<Result<CaptureSessionResult>> acquire(CaptureRequest request) async {
    if (_active) {
      return const Failure(CaptureFailure('Capture already in progress'));
    }
    _active = true;
    try {
      final result = await provider.capture(request);
      if (result case Failure<CaptureSessionResult>()) return result;
      final session = (result as Success<CaptureSessionResult>).value;
      if (session.cancelled || session.pages.isEmpty) {
        return const Failure(CaptureCancelledFailure());
      }
      for (final page in session.pages) {
        final file = File(page.sourcePath);
        if (!await file.exists() || await file.length() == 0) {
          return const Failure(
            InvalidCaptureFailure('Captured source is missing or empty'),
          );
        }
      }
      return Success(session);
    } catch (cause, stackTrace) {
      return Failure(
        CaptureFailure(
          'Capture acquisition failed',
          cause: cause,
          stackTrace: stackTrace,
        ),
      );
    } finally {
      _active = false;
    }
  }

  Future<Result<ScannedDocument>> capture(CaptureRequest request) async {
    if (_active) {
      return const Failure(CaptureFailure('Capture already in progress'));
    }
    _active = true;
    final createdAssets = <({String documentId, String pageId})>[];
    try {
      final result = await provider.capture(request);
      if (result case Failure<CaptureSessionResult>(:final error)) {
        return Failure(error);
      }
      final session = (result as Success<CaptureSessionResult>).value;
      if (session.cancelled || session.pages.isEmpty) {
        return const Failure(CaptureCancelledFailure());
      }
      final documentId = _id('document');
      final pages = <ScannedPage>[];
      for (var index = 0; index < session.pages.length; index++) {
        final captured = session.pages[index];
        final source = File(captured.sourcePath);
        if (!await source.exists() || await source.length() == 0) {
          throw const InvalidCaptureFailure(
            'Captured source is missing or empty',
          );
        }
        final pageId = '$documentId-page-$index';
        final rawResult = await assetStore.saveRawImage(
          documentId,
          pageId,
          await source.readAsBytes(),
        );
        if (rawResult case Failure<String>(:final error)) throw error;
        final rawPath = (rawResult as Success<String>).value;
        createdAssets.add((documentId: documentId, pageId: pageId));
        final now = DateTime.now();
        pages.add(
          ScannedPage(
            id: pageId,
            imagePath: rawPath,
            rawImagePath: rawPath,
            createdAt: now,
          ),
        );
      }
      final document = ScannedDocument(
        id: documentId,
        title: 'Scan ${DateTime.now().toString().substring(0, 16)}',
        pages: pages,
      );
      await repository.saveDocument(document);
      return Success(document);
    } catch (cause, stackTrace) {
      for (final asset in createdAssets) {
        await assetStore.deleteDocumentAssets(asset.documentId);
        break;
      }
      final failure =
          cause is AppFailure
              ? cause
              : CaptureFailure(
                'Capture persistence failed',
                cause: cause,
                stackTrace: stackTrace,
              );
      return Failure(failure);
    } finally {
      _active = false;
    }
  }

  String _id(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';
}
