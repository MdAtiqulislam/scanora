import 'package:get/get.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../data/models/scanned_document.dart';
import '../../domain/contracts/capture_provider.dart';
import '../services/capture_service.dart';

enum CaptureLifecycleState {
  idle,
  starting,
  capturing,
  persisting,
  completed,
  cancelled,
  failed,
}

class CaptureController extends GetxController {
  final CaptureService service;
  final state = CaptureLifecycleState.idle.obs;
  final error = Rxn<AppFailure>();

  CaptureController(this.service);

  Future<Result<ScannedDocument>> start(CaptureRequest request) async {
    if (state.value != CaptureLifecycleState.idle &&
        state.value != CaptureLifecycleState.completed &&
        state.value != CaptureLifecycleState.cancelled &&
        state.value != CaptureLifecycleState.failed) {
      return const Failure(CaptureFailure('Capture already in progress'));
    }
    state.value = CaptureLifecycleState.capturing;
    error.value = null;
    final result = await service.capture(request);
    if (result case Success<ScannedDocument>()) {
      state.value = CaptureLifecycleState.completed;
    } else if (result case Failure<ScannedDocument>(:final error)) {
      this.error.value = error;
      state.value =
          error is CaptureCancelledFailure
              ? CaptureLifecycleState.cancelled
              : CaptureLifecycleState.failed;
    }
    return result;
  }
}
