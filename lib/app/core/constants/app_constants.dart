class AppConstants {
  AppConstants._();

  static const String appName = 'Scanora';
  static const String appTagline = 'Scan. Enhance. Organize.';
  static const String appVersion = '1.0.0';

  // Storage Keys
  static const String keyThemeMode = 'app_theme_mode';
  static const String keyAutoCapture = 'auto_capture_pref';
  static const String keyDefaultScanMode = 'default_scan_mode_pref';
  static const String keyAutoEnhancement = 'auto_enhancement_pref';
  static const String keyDefaultFilter = 'default_filter_pref';
  static const String keyPdfQuality = 'pdf_quality_pref';
  static const String keyDefaultPageSize = 'default_page_size_pref';
  static const String keyAppLockEnabled = 'app_lock_pref';

  // Animation Timers
  static const int animDurationMs = 250;
  static const int scanFrameThrottleMs = 110;
}
