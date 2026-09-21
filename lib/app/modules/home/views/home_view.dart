/*
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/scanora_logo.dart';
import '../../../routes/app_pages.dart';
import '../../../theme/theme_controller.dart';
import '../../documents/views/documents_view.dart';
import '../../settings/views/settings_view.dart';
import '../controllers/home_controller.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      return Scaffold(
        body: IndexedStack(
          index: controller.currentNavIndex.value,
          children: [
            _buildHomeContent(context),
            const DocumentsView(),
            const SettingsView(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: controller.currentNavIndex.value,
          onDestinationSelected: controller.changeNavIndex,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_filled), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.folder_outlined), label: 'Documents'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
          ],
        ),
      );
    });
  }

  Widget _buildHomeContent(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeController = Get.find<ThemeController>();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top App Bar with Scanora Brand Logo
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Row(
                    children: [
                      const ScanoraLogo(size: 40, showGlow: true),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Scanora',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                            ),
                            Text(
                              AppStrings.privacyNotice,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: themeController.toggleTheme,
                  icon: Icon(
                    isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Hero Scan Document Card
            GestureDetector(
              onTap: controller.startDocumentScan,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.lightCard,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: isDark ? 0.25 : 0.15),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: isDark ? 0.08 : 0.06),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const ScanoraLogo(size: 48, color: AppColors.primary),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      AppStrings.scanDocument,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Auto edge detection • Multi-page • Magic Filter',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: controller.startDocumentScan,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(200, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.camera_alt_outlined, size: 20),
                      label: const Text(
                        AppStrings.scanNow,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 28),
            Text(
              AppStrings.quickScan,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),

            // Quick Scan Grid
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 2.4,
              children: [
                _buildQuickAction(context, 'Document', Icons.description_outlined, controller.startDocumentScan),
                _buildQuickAction(context, AppStrings.idCard, Icons.badge_outlined, controller.startIdCardScan),
                _buildQuickAction(context, AppStrings.passport, Icons.book_outlined, controller.startPassportScan),
                _buildQuickAction(context, AppStrings.gallery, Icons.photo_library_outlined, controller.startGalleryImport),
              ],
            ),

            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppStrings.recentDocuments,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: controller.goToDocuments,
                  child: const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Recent Documents List
            Obx(() {
              final recent = controller.recentDocuments;

              if (recent.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkCard : Colors.grey[100],
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.folder_open_outlined, size: 40, color: Colors.grey[500]),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          AppStrings.emptyDocumentsTitle,
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AppStrings.emptyDocumentsSubtitle,
                          style: TextStyle(color: Colors.grey[500], fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: recent.take(3).length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final doc = recent[index];
                  return Card(
                    child: ListTile(
                      onTap: () => Get.toNamed(Routes.documentDetail, arguments: doc),
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: doc.thumbnailPath != null && File(doc.thumbnailPath!).existsSync()
                            ? Image.file(File(doc.thumbnailPath!), fit: BoxFit.cover)
                            : const Icon(Icons.description_outlined, color: AppColors.primary),
                      ),
                      title: Text(doc.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${doc.pageCount} pages • ${doc.updatedAt.toString().substring(0, 10)}'),
                      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                    ),
                  );
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAction(BuildContext context, String title, IconData icon, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppColors.primary),
            const SizedBox(width: 10),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
*/

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/scanora_logo.dart';
import '../../../routes/app_pages.dart';
import '../../documents/views/documents_view.dart';
import '../../settings/views/settings_view.dart';
import '../controllers/home_controller.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      return Scaffold(
        body: IndexedStack(
          index: controller.currentNavIndex.value,
          children: [
            _buildHomeContent(context),
            const DocumentsView(),
            const SettingsView(),
          ],
        ),
        bottomNavigationBar: _buildBottomNavigation(context),
      );
    });
  }

  // ============================================================
  // HOME
  // ============================================================

  Widget _buildHomeContent(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildHeader(context, isDark),

                const SizedBox(height: 24),

                _buildHeroScanCard(context, isDark),

                const SizedBox(height: 30),

                _buildSectionHeader(context, title: AppStrings.quickScan),

                const SizedBox(height: 14),

                _buildQuickScanGrid(context, isDark),

                const SizedBox(height: 30),

                _buildRecentHeader(context),

                const SizedBox(height: 12),

                _buildRecentDocuments(context, isDark),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================

  Widget _buildHeader(BuildContext context, bool isDark) {
    final secondaryColor =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Row(
      children: [
        const ScanoraLogo(size: 42, showGlow: true),

        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Scanora',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.7,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Scan. Enhance. Organize.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: secondaryColor,
                ),
              ),
            ],
          ),
        ),

        // Privacy indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color:
                isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 14,
                color: AppColors.primary,
              ),
              const SizedBox(width: 5),
              Text(
                'Private',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: secondaryColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // HERO SCAN CARD
  // ============================================================

  Widget _buildHeroScanCard(BuildContext context, bool isDark) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: controller.startDefaultScan,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primary,
                AppColors.primary.withValues(alpha: 0.82),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(
                  alpha: isDark ? 0.22 : 0.18,
                ),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            children: [
              // Left content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            size: 13,
                            color: Colors.white,
                          ),
                          SizedBox(width: 5),
                          Text(
                            'SMART SCANNER',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    const Text(
                      'Scan Document',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      'Fast, clear and effortless scanning',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const SizedBox(height: 18),

                    FilledButton.icon(
                      onPressed: controller.startDefaultScan,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primary,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.camera_alt_rounded, size: 18),
                      label: const Text(
                        'Scan Now',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Scanner illustration
              _buildScannerIllustration(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScannerIllustration() {
    return SizedBox(
      width: 86,
      height: 112,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background glow
          Container(
            width: 78,
            height: 102,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
            ),
          ),

          // Document
          Container(
            width: 58,
            height: 78,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 26,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  const SizedBox(height: 9),
                  Container(
                    width: double.infinity,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 30,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Scan line
          Positioned(
            top: 29,
            child: Container(
              width: 68,
              height: 2,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // QUICK SCAN
  // ============================================================

  Widget _buildQuickScanGrid(BuildContext context, bool isDark) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildQuickAction(
          context,
          title: 'Document',
          subtitle: 'Paper & files',
          icon: Icons.description_outlined,
          onTap: controller.startDocumentScan,
          isDark: isDark,
        ),
        _buildQuickAction(
          context,
          title: 'ID Card',
          subtitle: 'Front & back',
          icon: Icons.badge_outlined,
          onTap: controller.startIdCardScan,
          isDark: isDark,
        ),
        _buildQuickAction(
          context,
          title: 'Passport',
          subtitle: 'Passport page',
          icon: Icons.menu_book_outlined,
          onTap: controller.startPassportScan,
          isDark: isDark,
        ),
        _buildQuickAction(
          context,
          title: 'Import',
          subtitle: 'From gallery',
          icon: Icons.photo_library_outlined,
          onTap: controller.startGalleryImport,
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildQuickAction(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final cardColor = isDark ? AppColors.darkCard : AppColors.lightCard;

    final secondaryColor =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color:
                  isDark
                      ? Colors.white.withValues(alpha: 0.07)
                      : Colors.black.withValues(alpha: 0.055),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: AppColors.primary),
              ),

              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
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

                  const SizedBox(height: 2),

                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: secondaryColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // SECTION HEADER
  // ============================================================

  Widget _buildSectionHeader(BuildContext context, {required String title}) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
      ),
    );
  }

  // ============================================================
  // RECENT HEADER
  // ============================================================

  Widget _buildRecentHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          AppStrings.recentDocuments,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
        TextButton(
          onPressed: controller.goToDocuments,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            'View All',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // RECENT DOCUMENTS
  // ============================================================

  Widget _buildRecentDocuments(BuildContext context, bool isDark) {
    return Obx(() {
      final recent = controller.recentDocuments;

      if (recent.isEmpty) {
        return _buildEmptyDocuments(context, isDark);
      }

      return Column(
        children: List.generate(recent.take(3).length, (index) {
          final doc = recent[index];

          return Padding(
            padding: EdgeInsets.only(
              bottom: index == recent.take(3).length - 1 ? 0 : 10,
            ),
            child: _buildDocumentCard(context, doc, isDark),
          );
        }),
      );
    });
  }

  Widget _buildDocumentCard(BuildContext context, dynamic doc, bool isDark) {
    final cardColor = isDark ? AppColors.darkCard : AppColors.lightCard;

    final secondaryColor =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    final hasThumbnail =
        doc.thumbnailPath != null &&
        doc.thumbnailPath!.isNotEmpty &&
        File(doc.thumbnailPath!).existsSync();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Get.toNamed(Routes.documentDetail, arguments: doc);
        },
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color:
                  isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.05),
            ),
          ),
          child: Row(
            children: [
              // Thumbnail
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(13),
                ),
                clipBehavior: Clip.antiAlias,
                child:
                    hasThumbnail
                        ? Image.file(
                          File(doc.thumbnailPath!),
                          fit: BoxFit.cover,
                        )
                        : const Icon(
                          Icons.description_outlined,
                          color: AppColors.primary,
                          size: 24,
                        ),
              ),

              const SizedBox(width: 13),

              // Information
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Row(
                      children: [
                        Icon(
                          Icons.layers_outlined,
                          size: 13,
                          color: secondaryColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${doc.pageCount} ${doc.pageCount == 1 ? 'page' : 'pages'}',
                          style: TextStyle(
                            fontSize: 11,
                            color: secondaryColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 3,
                          height: 3,
                          decoration: BoxDecoration(
                            color: secondaryColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatDate(doc.updatedAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: secondaryColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color:
                      isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.black.withValues(alpha: 0.035),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: secondaryColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // EMPTY DOCUMENTS
  // ============================================================

  Widget _buildEmptyDocuments(BuildContext context, bool isDark) {
    final secondaryColor =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color:
              isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.09),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.description_outlined,
              size: 30,
              color: AppColors.primary,
            ),
          ),

          const SizedBox(height: 14),

          const Text(
            'No documents yet',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),

          const SizedBox(height: 5),

          Text(
            'Scan your first document and it will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.4, color: secondaryColor),
          ),

          const SizedBox(height: 16),

          OutlinedButton.icon(
            onPressed: controller.startDocumentScan,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(
                color: AppColors.primary.withValues(alpha: 0.35),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            icon: const Icon(Icons.camera_alt_outlined, size: 17),
            label: const Text(
              'Scan Now',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BOTTOM NAVIGATION
  // ============================================================

  Widget _buildBottomNavigation(BuildContext context) {
    return NavigationBar(
      selectedIndex: controller.currentNavIndex.value,
      onDestinationSelected: controller.changeNavIndex,
      height: 68,
      elevation: 0,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.folder_outlined),
          selectedIcon: Icon(Icons.folder_rounded),
          label: 'Documents',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings_rounded),
          label: 'Settings',
        ),
      ],
    );
  }

  // ============================================================
  // DATE FORMATTER
  // ============================================================

  String _formatDate(DateTime date) {
    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);

    final documentDate = DateTime(date.year, date.month, date.day);

    final difference = today.difference(documentDate).inDays;

    if (difference == 0) {
      return 'Today';
    }

    if (difference == 1) {
      return 'Yesterday';
    }

    if (difference < 7) {
      return '$difference days ago';
    }

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${date.day} ${months[date.month - 1]}';
  }
}
