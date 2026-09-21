import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart';

import '../constants/app_constants.dart';
import 'storage_service.dart';

class AppLockService extends GetxService {
  final LocalAuthentication _localAuth = LocalAuthentication();

  final StorageService storageService = Get.find<StorageService>();

  final RxBool isLocked = false.obs;

  bool get isEnabled {
    return storageService.getBool(
      AppConstants.keyAppLockEnabled,
      defaultValue: false,
    );
  }

  Future<bool> canUseBiometrics() async {
    try {
      final isSupported = await _localAuth.isDeviceSupported();

      final canCheck = await _localAuth.canCheckBiometrics;

      return isSupported && canCheck;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate() async {
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate to access your Scanora documents',
        biometricOnly: false,
        /* options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),*/
      );

      return authenticated;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> enableAppLock() async {
    final available = await canUseBiometrics();

    if (!available) {
      return false;
    }

    final authenticated = await authenticate();

    if (!authenticated) {
      return false;
    }

    await storageService.setBool(AppConstants.keyAppLockEnabled, true);

    return true;
  }

  Future<void> disableAppLock() async {
    await storageService.setBool(AppConstants.keyAppLockEnabled, false);

    isLocked.value = false;
  }

  Future<bool> unlock() async {
    if (!isEnabled) {
      return true;
    }

    final success = await authenticate();

    if (success) {
      isLocked.value = false;
    }

    return success;
  }

  void lock() {
    if (isEnabled) {
      isLocked.value = true;
    }
  }
}
