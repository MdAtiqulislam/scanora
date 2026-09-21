import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../core/constants/app_constants.dart';
import '../core/services/storage_service.dart';

class ThemeController extends GetxController {
  final StorageService _storageService = Get.find<StorageService>();
  final Rx<ThemeMode> themeMode = ThemeMode.system.obs;

  bool get isDarkMode {
    if (themeMode.value == ThemeMode.system) {
      return Get.isPlatformDarkMode;
    }
    return themeMode.value == ThemeMode.dark;
  }

  @override
  void onInit() {
    super.onInit();
    final savedMode = _storageService.getString(AppConstants.keyThemeMode);
    if (savedMode == 'dark') {
      themeMode.value = ThemeMode.dark;
    } else if (savedMode == 'light') {
      themeMode.value = ThemeMode.light;
    } else {
      themeMode.value = ThemeMode.system;
    }
  }

  void setThemeMode(ThemeMode mode) {
    themeMode.value = mode;
    Get.changeThemeMode(mode);
    if (mode == ThemeMode.dark) {
      _storageService.setString(AppConstants.keyThemeMode, 'dark');
    } else if (mode == ThemeMode.light) {
      _storageService.setString(AppConstants.keyThemeMode, 'light');
    } else {
      _storageService.setString(AppConstants.keyThemeMode, 'system');
    }
    update();
  }

  void toggleTheme() {
    if (isDarkMode) {
      setThemeMode(ThemeMode.light);
    } else {
      setThemeMode(ThemeMode.dark);
    }
  }
}
