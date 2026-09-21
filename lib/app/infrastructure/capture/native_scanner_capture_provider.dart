import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/contracts/capture_provider.dart';

class NativeScannerCaptureProvider implements CaptureProvider {
  const NativeScannerCaptureProvider();

  @override
  CaptureSource get source => CaptureSource.nativeScanner;

  @override
  CaptureProviderCapabilities get capabilities =>
      const CaptureProviderCapabilities(
        supportsDocumentDetection: true,
        supportsMultiPage: true,
        supportsIdCard: true,
      );

  @override
  Future<Result<bool>> isAvailable() async => const Success(true);

  @override
  Future<Result<CaptureSessionResult>> capture(CaptureRequest request) async {
    try {
      final pictures = await CunningDocumentScanner.getPictures(
        noOfPages:
            request.mode == CaptureMode.singlePage ? 1 : request.maxPages,
      );
      if (pictures == null || pictures.isEmpty) {
        return const Success(CaptureSessionResult(cancelled: true));
      }
      final pages = pictures
          .map((path) => CapturedPage(sourcePath: path, source: source))
          .toList(growable: false);
      for (final page in pages) {
        final file = File(page.sourcePath);
        if (!await file.exists() || await file.length() == 0) {
          return const Failure(
            InvalidCaptureFailure('Scanner returned an invalid file'),
          );
        }
      }
      return Success(CaptureSessionResult(pages: pages));
    } catch (cause, stackTrace) {
      return Failure(
        CaptureProviderFailure(
          'Native scanner failed',
          cause: cause,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
