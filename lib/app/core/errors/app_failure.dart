abstract class AppFailure implements Exception {
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  const AppFailure(this.message, {this.cause, this.stackTrace});

  @override
  String toString() => '$runtimeType: $message';
}

class CaptureFailure extends AppFailure {
  const CaptureFailure(super.message, {super.cause, super.stackTrace});
}

class CaptureCancelledFailure extends CaptureFailure {
  const CaptureCancelledFailure([String message = 'Capture cancelled'])
    : super(message);
}

class CapturePermissionFailure extends CaptureFailure {
  const CapturePermissionFailure(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}

class CaptureProviderFailure extends CaptureFailure {
  const CaptureProviderFailure(super.message, {super.cause, super.stackTrace});
}

class InvalidCaptureFailure extends CaptureFailure {
  const InvalidCaptureFailure(super.message, {super.cause, super.stackTrace});
}

class ProcessingFailure extends AppFailure {
  const ProcessingFailure(super.message, {super.cause, super.stackTrace});
}

class StorageFailure extends AppFailure {
  const StorageFailure(super.message, {super.cause, super.stackTrace});
}

class InvalidAssetIdentifierFailure extends StorageFailure {
  const InvalidAssetIdentifierFailure(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}

class AssetNotFoundFailure extends StorageFailure {
  const AssetNotFoundFailure(super.message, {super.cause, super.stackTrace});
}

class OcrFailure extends AppFailure {
  const OcrFailure(super.message, {super.cause, super.stackTrace});
}

class PdfFailure extends AppFailure {
  const PdfFailure(super.message, {super.cause, super.stackTrace});
}

class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message, {super.cause, super.stackTrace});
}
