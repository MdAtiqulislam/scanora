import '../../core/result/result.dart';

enum CaptureMode { singlePage, multiPage, idCard }

enum CaptureSource { nativeScanner, gallery, camera }

class CaptureRequest {
  final CaptureMode mode;
  final int maxPages;
  final bool allowMultiple;

  const CaptureRequest({
    this.mode = CaptureMode.multiPage,
    this.maxPages = 20,
    this.allowMultiple = true,
  }) : assert(maxPages > 0);
}

class CaptureProviderCapabilities {
  final bool supportsDocumentDetection;
  final bool supportsMultiPage;
  final bool supportsFlash;
  final bool supportsIdCard;
  final bool supportsManualCapture;

  const CaptureProviderCapabilities({
    this.supportsDocumentDetection = false,
    this.supportsMultiPage = false,
    this.supportsFlash = false,
    this.supportsIdCard = false,
    this.supportsManualCapture = false,
  });
}

class CapturedPage {
  final String sourcePath;
  final CaptureSource source;
  final int? width;
  final int? height;
  final int rotationDegrees;

  const CapturedPage({
    required this.sourcePath,
    required this.source,
    this.width,
    this.height,
    this.rotationDegrees = 0,
  });
}

class CaptureSessionResult {
  final List<CapturedPage> pages;
  final bool cancelled;

  const CaptureSessionResult({this.pages = const [], this.cancelled = false});
}

abstract interface class CaptureProvider {
  CaptureSource get source;
  CaptureProviderCapabilities get capabilities;

  Future<Result<CaptureSessionResult>> capture(CaptureRequest request);

  Future<Result<bool>> isAvailable();
}
