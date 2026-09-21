import 'package:get/get.dart';
import 'app/core/services/app_lifecycle_controller.dart';
import 'app/core/services/app_lock_service.dart';
import 'app/core/services/storage_service.dart';
import 'app/theme/theme_controller.dart';

class InitialBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(StorageService(), permanent: true);

    Get.put(
      AppLockService(),
      permanent: true,
    );

    Get.put(
      AppLifecycleController(),
      permanent: true,
    );

    Get.put(
      ThemeController(),
      permanent: true,
    );
  }
}