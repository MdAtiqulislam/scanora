import 'package:get/get.dart';
import '../controllers/ocr_controller.dart';

class OcrBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<OcrController>(() => OcrController());
  }
}
