import '../../core/result/result.dart';
import '../../domain/contracts/capture_provider.dart';

class CameraCaptureProvider implements CaptureProvider {
  const CameraCaptureProvider();

  @override
  CaptureSource get source => CaptureSource.camera;

  @override
  CaptureProviderCapabilities get capabilities =>
      const CaptureProviderCapabilities(
        supportsFlash: true,
        supportsManualCapture: true,
      );

  @override
  Future<Result<CaptureSessionResult>> capture(CaptureRequest request) async =>
      const Success(CaptureSessionResult(cancelled: true));

  @override
  Future<Result<bool>> isAvailable() async => const Success(false);
}
