import 'dart:io';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../core/services/image_processing_service.dart';
import '../../domain/contracts/scan_processing_engine.dart';

/// Compatibility bridge for the current image service.
/// Future processing stages can be added behind this contract without UI changes.
class LegacyProcessingEngine implements ScanProcessingEngine {
  final ImageProcessingService service;

  const LegacyProcessingEngine(this.service);

  @override
  Future<Result<ProcessingOutput>> process(ProcessingRequest request) async {
    try {
      final output = await service.normalizeLandscapeImage(
        File(request.inputPath),
      );
      return Success(ProcessingOutput(output.path));
    } catch (cause, stackTrace) {
      return Failure(
        ProcessingFailure(
          'Image processing failed',
          cause: cause,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
