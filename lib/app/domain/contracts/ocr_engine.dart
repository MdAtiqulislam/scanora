import '../../core/result/result.dart';

abstract interface class OcrProvider {
  Future<Result<String>> recognize(String imagePath);
}

abstract interface class OcrEngine {
  Future<Result<String>> recognize(String imagePath);
}
