import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'app_lock_service.dart';

class AppLifecycleController extends GetxController
    with WidgetsBindingObserver {
  final AppLockService appLockService = Get.find<AppLockService>();

  @override
  void onInit() {
    super.onInit();

    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);

    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      appLockService.lock();
    }
  }
}
