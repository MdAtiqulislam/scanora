import 'package:get/get.dart';
import '../../documents/controllers/documents_controller.dart';
import '../../settings/controllers/settings_controller.dart';
import '../controllers/home_controller.dart';

class HomeBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<HomeController>(() => HomeController());
    Get.lazyPut<DocumentsController>(() => DocumentsController());
    Get.lazyPut<SettingsController>(() => SettingsController());
  }
}
