import 'package:get/get.dart';
import '../../routes/app_pages.dart';

class AppNavigator {
  AppNavigator._();

  static void toHome() => Get.offAllNamed(Routes.home);
  static void toScanner() => Get.toNamed(Routes.scanner);
  static Future<dynamic>? toEditor(Map<String, dynamic> arguments) =>
      Get.toNamed(Routes.editor, arguments: arguments);
  static void toDocuments() => Get.toNamed(Routes.documents);
  static void toSettings() => Get.toNamed(Routes.settings);
  static void back<T>([T? result]) => Get.back(result: result);
}
