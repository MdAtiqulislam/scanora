import 'dart:io';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../core/services/ocr_service.dart';
import '../../domain/contracts/ocr_engine.dart';

class LegacyOcrEngine implements OcrEngine, OcrProvider {
  final OcrService service;

  const LegacyOcrEngine(this.service);

  @override
  Future<Result<String>> recognize(String imagePath) async {
    try {
      return Success(await service.extractText(File(imagePath)));
    } catch (cause, stackTrace) {
      return Failure(
        OcrFailure('OCR failed', cause: cause, stackTrace: stackTrace),
      );
    }
  }
}
