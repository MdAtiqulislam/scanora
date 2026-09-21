import '../../core/result/result.dart';
import '../entities/scan_page.dart';
import '../enums/scan_enums.dart';

class ProcessingRequest {
  final String inputPath;
  final ScanPage page;
  final Set<ProcessingStage> stages;

  const ProcessingRequest({
    required this.inputPath,
    required this.page,
    this.stages = const {},
  });
}

class ProcessingOutput {
  final String outputPath;

  const ProcessingOutput(this.outputPath);
}

abstract interface class ScanProcessingEngine {
  Future<Result<ProcessingOutput>> process(ProcessingRequest request);
}
