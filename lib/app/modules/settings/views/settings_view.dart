import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/pdf_service.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../../core/widgets/scanora_logo.dart';
import '../controllers/settings_controller.dart';

class SettingsView extends GetView<SettingsController> {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildHeader(context, isDark),
                  const SizedBox(height: 30),
                  _buildAppearanceSection(context, isDark),
                  const SizedBox(height: 26),
                  _buildScannerSection(context, isDark),
                  const SizedBox(height: 26),
                  _buildDocumentsSection(context, isDark),
                  const SizedBox(height: 26),
                  _buildPrivacySection(context, isDark),
                  const SizedBox(height: 26),
                  _buildAboutSection(context, isDark),
                  const SizedBox(height: 28),
                  _buildFooter(context, isDark),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================

  Widget _buildHeader(BuildContext context, bool isDark) {
    final secondaryColor =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Settings',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Customize your Scanora experience',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: secondaryColor,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // APPEARANCE
  // ============================================================

  Widget _buildAppearanceSection(BuildContext context, bool isDark) {
    return _buildSection(
      title: 'Appearance',
      children: [
        Obx(() {
          final mode = controller.themeController.themeMode.value;

          return _buildSettingsTile(
            context,
            isDark: isDark,
            icon: Icons.palette_outlined,
            title: 'Theme',
            subtitle: _themeName(mode),
            trailing: const Icon(Icons.chevron_right_rounded, size: 22),
            onTap: () => _showThemeSelector(context, isDark),
          );
        }),
      ],
    );
  }

  // ============================================================
  // SCANNER
  // ============================================================

  Widget _buildScannerSection(BuildContext context, bool isDark) {
    return _buildSection(
      title: 'Scanner',
      children: [
        Obx(
          () => _buildSwitchTile(
            context,
            isDark: isDark,
            icon: Icons.auto_awesome_outlined,
            title: 'Auto Capture',
            subtitle: 'Capture automatically when the document is steady',
            value: controller.autoCapture.value,
            onChanged: controller.toggleAutoCapture,
          ),
        ),
        _buildDivider(isDark),
        Obx(
          () => _buildSettingsTile(
            context,
            isDark: isDark,
            icon: Icons.document_scanner_outlined,
            title: 'Default Scan Mode',
            subtitle: controller.getScanModeName(
              controller.defaultScanMode.value,
            ),
            trailing: const Icon(Icons.chevron_right_rounded, size: 22),
            onTap: () => _showScanModeSelector(context, isDark),
          ),
        ),
        _buildDivider(isDark),
        Obx(
          () => _buildSwitchTile(
            context,
            isDark: isDark,
            icon: Icons.auto_fix_high_outlined,
            title: 'Auto Enhancement',
            subtitle: 'Automatically enhance scans with Magic filter',
            value: controller.autoEnhancement.value,
            onChanged: controller.toggleAutoEnhancement,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // DOCUMENTS
  // ============================================================

  Widget _buildDocumentsSection(BuildContext context, bool isDark) {
    return _buildSection(
      title: 'Documents',
      children: [
        Obx(
          () => _buildSettingsTile(
            context,
            isDark: isDark,
            icon: Icons.picture_as_pdf_outlined,
            title: 'PDF Quality',
            subtitle: controller.getPdfQualityName(controller.pdfQuality.value),
            trailing: const Icon(Icons.chevron_right_rounded, size: 22),
            onTap: () => _showPdfQualitySelector(context, isDark),
          ),
        ),
        _buildDivider(isDark),
        Obx(
          () => _buildSettingsTile(
            context,
            isDark: isDark,
            icon: Icons.crop_outlined,
            title: 'Default Page Size',
            subtitle: controller.getPageSizeName(
              controller.defaultPageSize.value,
            ),
            trailing: const Icon(Icons.chevron_right_rounded, size: 22),
            onTap: () => _showPageSizeSelector(context, isDark),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // PRIVACY
  // ============================================================

  Widget _buildPrivacySection(BuildContext context, bool isDark) {
    return _buildSection(
      title: 'Privacy & Security',
      children: [
        _buildSettingsTile(
          context,
          isDark: isDark,
          icon: Icons.shield_outlined,
          title: 'Privacy Overview',
          subtitle: 'Your scans are stored locally on this device',
          trailing: const Icon(Icons.chevron_right_rounded, size: 22),
          onTap: () => _showPrivacyInfo(context, isDark),
        ),
        _buildDivider(isDark),
        Obx(
          () => _buildSwitchTile(
            context,
            isDark: isDark,
            icon: Icons.lock_outline_rounded,
            title: 'App Lock',
            subtitle: 'Protect Scanora with biometric or PIN',
            value: controller.appLockEnabled.value,
            onChanged: controller.toggleAppLock,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // ABOUT
  // ============================================================

  Widget _buildAboutSection(BuildContext context, bool isDark) {
    return _buildSection(
      title: 'About',
      children: [
        _buildSettingsTile(
          context,
          isDark: isDark,
          icon: Icons.info_outline_rounded,
          title: 'About Scanora',
          subtitle: 'Version ${AppConstants.appVersion}',
          trailing: const Icon(Icons.chevron_right_rounded, size: 22),
          onTap: () => _showAboutDialog(context, isDark),
        ),
        _buildDivider(isDark),
        _buildSettingsTile(
          context,
          isDark: isDark,
          icon: Icons.star_outline_rounded,
          title: 'Rate Scanora',
          subtitle: 'Enjoying Scanora? Leave a review',
          trailing: const Icon(Icons.chevron_right_rounded, size: 22),
          onTap: () => _showRateDialog(context, isDark),
        ),
        _buildDivider(isDark),
        _buildSettingsTile(
          context,
          isDark: isDark,
          icon: Icons.privacy_tip_outlined,
          title: 'Privacy Policy',
          subtitle: 'Learn how your data is protected',
          trailing: const Icon(Icons.open_in_new_rounded, size: 18),
          onTap: () => _showPrivacyPolicyDialog(context, isDark),
        ),
        _buildDivider(isDark),
        _buildSettingsTile(
          context,
          isDark: isDark,
          icon: Icons.description_outlined,
          title: 'Terms of Service',
          subtitle: 'Read Scanora terms',
          trailing: const Icon(Icons.open_in_new_rounded, size: 18),
          onTap: () => _showTermsDialog(context, isDark),
        ),
      ],
    );
  }

  // ============================================================
  // FOOTER
  // ============================================================

  Widget _buildFooter(BuildContext context, bool isDark) {
    final secondaryColor =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Column(
      children: [
        const ScanoraLogo(size: 38, showGlow: true),
        const SizedBox(height: 10),
        const Text(
          AppConstants.appName,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        Text(
          'Scan. Enhance. Organize.',
          style: TextStyle(
            fontSize: 11,
            color: secondaryColor,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Version ${AppConstants.appVersion}',
          style: TextStyle(fontSize: 10, color: secondaryColor),
        ),
      ],
    );
  }

  // ============================================================
  // SECTION CONTAINER
  // ============================================================

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 9),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
              letterSpacing: 0.1,
            ),
          ),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Theme.of(Get.context!).cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color:
                  Theme.of(Get.context!).brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.05),
            ),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  // ============================================================
  // SETTINGS TILE
  // ============================================================

  Widget _buildSettingsTile(
    BuildContext context, {
    required bool isDark,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
    required VoidCallback onTap,
  }) {
    final secondaryColor =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: AppColors.primary),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.3,
                        color: secondaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing,
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // SWITCH TILE
  // ============================================================

  Widget _buildSwitchTile(
    BuildContext context, {
    required bool isDark,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return _buildSettingsTile(
      context,
      isDark: isDark,
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: Switch.adaptive(
        value: value,
        activeTrackColor: AppColors.primary,
        onChanged: onChanged,
      ),
      onTap: () => onChanged(!value),
    );
  }

  // ============================================================
  // DIVIDER
  // ============================================================

  Widget _buildDivider(bool isDark) {
    return Divider(
      height: 1,
      thickness: 0.7,
      indent: 68,
      endIndent: 15,
      color:
          isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.05),
    );
  }

  // ============================================================
  // THEME SELECTOR
  // ============================================================

  void _showThemeSelector(BuildContext context, bool isDark) {
    final current = controller.themeController.themeMode.value;

    Get.bottomSheet(
      _buildBottomSheet(
        context,
        isDark: isDark,
        title: 'Theme',
        children: [
          _buildOptionTile(
            context,
            title: 'System Default',
            icon: Icons.brightness_auto_outlined,
            selected: current == ThemeMode.system,
            onTap: () {
              controller.setThemeMode(ThemeMode.system);
              Get.back();
            },
          ),
          _buildOptionTile(
            context,
            title: 'Light Mode',
            icon: Icons.light_mode_outlined,
            selected: current == ThemeMode.light,
            onTap: () {
              controller.setThemeMode(ThemeMode.light);
              Get.back();
            },
          ),
          _buildOptionTile(
            context,
            title: 'Dark Mode',
            icon: Icons.dark_mode_outlined,
            selected: current == ThemeMode.dark,
            onTap: () {
              controller.setThemeMode(ThemeMode.dark);
              Get.back();
            },
          ),
        ],
      ),
      isScrollControlled: true,
    );
  }

  // ============================================================
  // SCAN MODE SELECTOR
  // ============================================================

  void _showScanModeSelector(BuildContext context, bool isDark) {
    final current = controller.defaultScanMode.value;

    Get.bottomSheet(
      _buildBottomSheet(
        context,
        isDark: isDark,
        title: 'Default Scan Mode',
        children: [
          _buildOptionTile(
            context,
            title: 'Document',
            icon: Icons.description_outlined,
            selected: current == 'document',
            onTap: () {
              controller.setDefaultScanMode('document');
              Get.back();
            },
          ),
          _buildOptionTile(
            context,
            title: 'ID Card',
            icon: Icons.badge_outlined,
            selected: current == 'id_card',
            onTap: () {
              controller.setDefaultScanMode('id_card');
              Get.back();
            },
          ),
          _buildOptionTile(
            context,
            title: 'Passport',
            icon: Icons.menu_book_outlined,
            selected: current == 'passport',
            onTap: () {
              controller.setDefaultScanMode('passport');
              Get.back();
            },
          ),
        ],
      ),
      isScrollControlled: true,
    );
  }

  // ============================================================
  // PDF QUALITY
  // ============================================================

  void _showPdfQualitySelector(BuildContext context, bool isDark) {
    final current = controller.pdfQuality.value;

    Get.bottomSheet(
      _buildBottomSheet(
        context,
        isDark: isDark,
        title: 'PDF Quality',
        children: [
          _buildOptionTile(
            context,
            title: 'Low (Small file size)',
            icon: Icons.compress_outlined,
            selected: current == PdfQuality.low,
            onTap: () {
              controller.setPdfQuality(PdfQuality.low);
              Get.back();
            },
          ),
          _buildOptionTile(
            context,
            title: 'Medium (Balanced)',
            icon: Icons.tune_outlined,
            selected: current == PdfQuality.medium,
            onTap: () {
              controller.setPdfQuality(PdfQuality.medium);
              Get.back();
            },
          ),
          _buildOptionTile(
            context,
            title: 'High (Best quality)',
            icon: Icons.high_quality_outlined,
            selected: current == PdfQuality.high,
            onTap: () {
              controller.setPdfQuality(PdfQuality.high);
              Get.back();
            },
          ),
        ],
      ),
      isScrollControlled: true,
    );
  }

  // ============================================================
  // PAGE SIZE
  // ============================================================

  void _showPageSizeSelector(BuildContext context, bool isDark) {
    final current = controller.defaultPageSize.value;

    Get.bottomSheet(
      _buildBottomSheet(
        context,
        isDark: isDark,
        title: 'Default Page Size',
        children: [
          _buildOptionTile(
            context,
            title: 'Original (Auto-fit scanned size)',
            icon: Icons.crop_free_outlined,
            selected: current == PdfPageFormatType.original,
            onTap: () {
              controller.setDefaultPageSize(PdfPageFormatType.original);
              Get.back();
            },
          ),
          _buildOptionTile(
            context,
            title: 'A4 (210 × 297 mm)',
            icon: Icons.description_outlined,
            selected: current == PdfPageFormatType.a4,
            onTap: () {
              controller.setDefaultPageSize(PdfPageFormatType.a4);
              Get.back();
            },
          ),
          _buildOptionTile(
            context,
            title: 'Letter (8.5 × 11 in)',
            icon: Icons.article_outlined,
            selected: current == PdfPageFormatType.letter,
            onTap: () {
              controller.setDefaultPageSize(PdfPageFormatType.letter);
              Get.back();
            },
          ),
        ],
      ),
      isScrollControlled: true,
    );
  }

  // ============================================================
  // BOTTOM SHEET
  // ============================================================

  Widget _buildBottomSheet(
    BuildContext context, {
    required bool isDark,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  // ============================================================
  // OPTION TILE
  // ============================================================

  Widget _buildOptionTile(
    BuildContext context, {
    required String title,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 20, color: AppColors.primary),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      trailing:
          selected
              ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
              : const Icon(Icons.circle_outlined, color: Colors.grey),
      onTap: onTap,
    );
  }

  // ============================================================
  // PRIVACY INFO
  // ============================================================

  void _showPrivacyInfo(BuildContext context, bool isDark) {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: AppColors.primary),
            SizedBox(width: 10),
            Text('100% Private & Offline'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Scanora is built from the ground up with a local-first, privacy-by-design architecture:\n\n'
                '• Scans & PDFs are kept securely on your device storage.\n'
                '• Text recognition (OCR) runs completely on-device without cloud servers.\n'
                '• No analytics tracking, telemetry, or third-party ad profiling.\n'
                '• Only you decide when and where to export or share your files.',
                style: TextStyle(height: 1.45, fontSize: 13.5),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: Get.back,
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // RATE DIALOG
  // ============================================================

  void _showRateDialog(BuildContext context, bool isDark) {
    int rating = 5;
    final feedbackController = TextEditingController();

    Get.dialog(
      StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.star_rounded, color: Colors.amber, size: 28),
                SizedBox(width: 10),
                Text('Rate Scanora'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'How is your experience scanning documents with Scanora?',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final starIndex = index + 1;
                      return IconButton(
                        icon: Icon(
                          starIndex <= rating
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color: Colors.amber,
                          size: 36,
                        ),
                        onPressed: () {
                          setState(() {
                            rating = starIndex;
                          });
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: feedbackController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Share any feedback or suggestions (optional)',
                      hintStyle: const TextStyle(fontSize: 12),
                      filled: true,
                      fillColor:
                          isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.black.withValues(alpha: 0.04),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: Get.back, child: const Text('Maybe Later')),
              FilledButton(
                onPressed: () {
                  Get.back();
                  SnackbarHelper.showSuccess(
                    'Thank you for rating Scanora $rating stars! ⭐',
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                child: const Text('Submit'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ============================================================
  // PRIVACY POLICY DIALOG
  // ============================================================

  void _showPrivacyPolicyDialog(BuildContext context, bool isDark) {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.privacy_tip_outlined, color: AppColors.primary),
            SizedBox(width: 10),
            Text('Privacy Policy'),
          ],
        ),
        content: const SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Last Updated: 2026\n\n'
                  '1. Local Storage Only\n'
                  'All documents, images, passports, ID cards, and generated PDF files created with Scanora remain stored exclusively in your local device sandbox.\n\n'
                  '2. Camera & Image Processing\n'
                  'Camera access is utilized purely for real-time document edge detection and photography. No image streams or data are transmitted outside your device.\n\n'
                  '3. On-Device OCR\n'
                  'Optical Character Recognition (OCR) and passport MRZ parsing run completely on-device using local machine learning models without internet dependencies.\n\n'
                  '4. Biometric App Lock\n'
                  'App Lock relies on native Android/iOS biometric hardware. Scanora does not store or process your biometric data.',
                  style: TextStyle(height: 1.45, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: Get.back,
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TERMS OF SERVICE DIALOG
  // ============================================================

  void _showTermsDialog(BuildContext context, bool isDark) {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.description_outlined, color: AppColors.primary),
            SizedBox(width: 10),
            Text('Terms of Service'),
          ],
        ),
        content: const SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Last Updated: 2026\n\n'
                  '1. Acceptance of Terms\n'
                  'By downloading and using Scanora, you agree to use the application for lawful document scanning and storage purposes.\n\n'
                  '2. Ownership of Content\n'
                  'You retain 100% full copyright and ownership of all scanned papers, ID cards, passports, and PDFs produced by Scanora.\n\n'
                  '3. License & Use\n'
                  'Scanora grants you a personal, non-exclusive license to use the app for personal and business document digitization.\n\n'
                  '4. Disclaimer\n'
                  'The application is provided "as is" with on-device functionality. Ensure you keep backups of critical documents.',
                  style: TextStyle(height: 1.45, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: Get.back,
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ABOUT DIALOG
  // ============================================================

  void _showAboutDialog(BuildContext context, bool isDark) {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ScanoraLogo(size: 62, showGlow: true),
            const SizedBox(height: 14),
            const Text(
              AppConstants.appName,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            const Text(
              'Scan. Enhance. Organize.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Text(
              'Version ${AppConstants.appVersion}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            const Text(
              '100% On-Device • Privacy First • Ultra HD PDF Engine',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        actions: [TextButton(onPressed: Get.back, child: const Text('Close'))],
      ),
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================

  String _themeName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'Dark Mode';
      case ThemeMode.light:
        return 'Light Mode';
      case ThemeMode.system:
        return 'System Default';
    }
  }
}
