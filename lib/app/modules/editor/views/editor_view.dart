import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/services/image_processing_service.dart';
import '../../../core/widgets/file_tile.dart';
import '../controllers/editor_controller.dart';
import '../widgets/crop_quad_editor.dart';
import '../widgets/image_filter_dialog.dart';

class EditorView extends GetView<EditorController> {
  const EditorView({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.isCropMode.value && controller.currentPage != null) {
        return CropQuadEditor(
          imagePath: controller.currentPage!.rawImagePath,
          initialCorners: controller.initialCorners,
          onCropApplied: controller.applyNewCrop,
          onCancel: controller.toggleCropMode,
        );
      }

      final isDark = Theme.of(context).brightness == Brightness.dark;
      final currentPage = controller.currentPage;

      return Scaffold(
        appBar: AppBar(
          leading: TextButton(
            onPressed: controller.retake,
            child: const Text(
              'Retake',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          leadingWidth: 80,
          title: Text(
            controller.isPassport.value
                ? 'Passport Scan'
                : controller.isIdCard.value
                ? 'ID Card Scan'
                : AppStrings.enhanceAndEdit,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          actions: [
            // Toggle between Canvas View and List View (pdf_tool style)
            if (controller.editorPages.length > 1)
              IconButton(
                icon: Icon(
                  controller.isListViewMode.value
                      ? Icons.view_carousel_rounded
                      : Icons.view_list_rounded,
                  color: AppColors.primary,
                ),
                tooltip:
                    controller.isListViewMode.value
                        ? 'Canvas View'
                        : 'List / Reorder View',
                onPressed: controller.toggleViewMode,
              ),
            // OCR Text Extraction Action
            IconButton(
              icon: const Icon(
                Icons.document_scanner_outlined,
                color: AppColors.primary,
              ),
              tooltip: 'Extract Text (OCR)',
              onPressed: controller.openOcr,
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12.0, left: 4.0),
              child: FilledButton(
                onPressed:
                    controller.isProcessing.value
                        ? null
                        : controller.saveAndFinish,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                child:
                    controller.isProcessing.value
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : const Text(
                          'Save',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            // Quick Document Filters Strip on Top (pdf_tool style)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: isDark ? AppColors.darkCard : Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip('Magic ✨', DocumentFilterType.magic),
                          _buildFilterChip('Auto ☀️', DocumentFilterType.auto),
                          _buildFilterChip(
                            'Original',
                            DocumentFilterType.original,
                          ),
                          _buildFilterChip('Gray 🔘', DocumentFilterType.gray),
                          _buildFilterChip(
                            'B&W 📄',
                            DocumentFilterType.blackAndWhite,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (controller.editorPages.length > 1)
                    TextButton(
                      onPressed:
                          () => controller.applyFilterToAll(
                            controller.selectedFilter.value,
                          ),
                      child: const Text(
                        'Apply to All',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Main Body: List View (pdf_tool style) OR Canvas Preview
            Expanded(
              child:
                  controller.isListViewMode.value
                      ? _buildListViewMode(context, isDark)
                      : _buildCanvasViewMode(context, isDark, currentPage),
            ),

            // Bottom Actions (Crop, Rotate, Adjust, OCR / Add Page)
            Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 12,
                top: 12,
              ),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : AppColors.lightCard,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildToolButton(
                    context,
                    icon: Icons.add_photo_alternate_rounded,
                    label: 'Add Page',
                    onTap: controller.addPage,
                  ),
                  _buildToolButton(
                    context,
                    icon: Icons.crop,
                    label: AppStrings.crop,
                    onTap: controller.toggleCropMode,
                  ),
                  _buildToolButton(
                    context,
                    icon: Icons.rotate_right,
                    label: AppStrings.rotate,
                    onTap: controller.rotateImage,
                  ),
                  _buildToolButton(
                    context,
                    icon: Icons.tune,
                    label: AppStrings.adjust,
                    onTap: () => _showAdjustmentBottomSheet(context),
                  ),
                  _buildToolButton(
                    context,
                    icon: Icons.text_snippet_outlined,
                    label: 'OCR Text',
                    onTap: controller.openOcr,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildCanvasViewMode(
    BuildContext context,
    bool isDark,
    EditorPageModel? currentPage,
  ) {
    return Column(
      children: [
        // 1. Crystal-Clear Ultra-HD Document Preview Canvas
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child:
                  currentPage != null &&
                          File(currentPage.imagePath).existsSync()
                      ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: isDark ? 0.3 : 0.1,
                                ),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: RotatedBox(
                            quarterTurns: currentPage.quarterTurns,
                            child: _applyFilterWidget(
                              Image.file(
                                File(currentPage.imagePath),
                                key: ValueKey(
                                  '${currentPage.imagePath}-${currentPage.quarterTurns}-${currentPage.filter.name}',
                                ),
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                              ),
                              currentPage.filter,
                            ),
                          ),
                        ),
                      )
                      : const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      ),
            ),
          ),
        ),

        // 2. Multi-Page Thumbnail Strip (Section 19 in Specs)
        if (controller.editorPages.length > 1 || !controller.isIdCard.value)
          Container(
            height: 72,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: controller.editorPages.length + 1,
              itemBuilder: (context, index) {
                if (index == controller.editorPages.length) {
                  return GestureDetector(
                    onTap: controller.addPage,
                    child: Container(
                      width: 50,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AppColors.primary,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Icon(Icons.add, color: AppColors.primary),
                      ),
                    ),
                  );
                }

                final isSelected = controller.currentPageIndex.value == index;
                final pageItem = controller.editorPages[index];

                return GestureDetector(
                  onTap: () => controller.selectPage(index),
                  child: Container(
                    width: 50,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color:
                            isSelected ? AppColors.primary : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        RotatedBox(
                          quarterTurns: pageItem.quarterTurns,
                          child: _applyFilterWidget(
                            Image.file(
                              File(pageItem.imagePath),
                              fit: BoxFit.cover,
                              cacheWidth: 300,
                            ),
                            pageItem.filter,
                          ),
                        ),
                        Positioned(
                          top: 2,
                          left: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildListViewMode(BuildContext context, bool isDark) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: controller.editorPages.length,
      onReorder:
          (oldIndex, newIndex) => controller.reorderPages(oldIndex, newIndex),
      itemBuilder: (context, index) {
        final pageItem = controller.editorPages[index];
        return FileTile(
          key: ValueKey('${pageItem.imagePath}_$index'),
          title: 'Page ${index + 1} (${pageItem.fileName})',
          sizeInBytes: pageItem.sizeInBytes,
          imagePath: pageItem.imagePath,
          isReorderable: true,
          index: index,
          badgeText: _getFilterBadge(pageItem.filter),
          onTap: () => _openFilterDialog(context, index, pageItem),
          onEdit: () => _openFilterDialog(context, index, pageItem),
          onDelete: () => controller.deletePage(index),
        );
      },
    );
  }

  void _openFilterDialog(
    BuildContext context,
    int index,
    EditorPageModel pageModel,
  ) {
    ImageFilterDialog.show(
      context,
      pageModel: pageModel,
      onApply: (updated) => controller.updatePageAt(index, updated),
      onApplyToAll: (filter) => controller.applyFilterToAll(filter),
    );
  }

  String? _getFilterBadge(DocumentFilterType type) {
    switch (type) {
      case DocumentFilterType.smart:
        return 'Smart 🪄';
      case DocumentFilterType.magic:
        return 'Magic ✨';
      case DocumentFilterType.blackAndWhite:
        return 'B&W 📄';
      case DocumentFilterType.auto:
        return 'Bright ☀️';
      case DocumentFilterType.gray:
        return 'Gray 🔘';
      case DocumentFilterType.original:
        return null;
    }
  }

  Widget _applyFilterWidget(Widget child, DocumentFilterType filter) {
    switch (filter) {
      case DocumentFilterType.smart:
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            1.4,
            0,
            0,
            0,
            -30,
            0,
            1.4,
            0,
            0,
            -30,
            0,
            0,
            1.4,
            0,
            -30,
            0,
            0,
            0,
            1,
            0,
          ]),
          child: child,
        );
      case DocumentFilterType.gray:
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            0.2126,
            0.7152,
            0.0722,
            0,
            0,
            0.2126,
            0.7152,
            0.0722,
            0,
            0,
            0.2126,
            0.7152,
            0.0722,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
          ]),
          child: child,
        );
      case DocumentFilterType.blackAndWhite:
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            1.6,
            1.6,
            1.6,
            0,
            -180,
            1.6,
            1.6,
            1.6,
            0,
            -180,
            1.6,
            1.6,
            1.6,
            0,
            -180,
            0,
            0,
            0,
            1,
            0,
          ]),
          child: child,
        );
      case DocumentFilterType.magic:
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            1.12,
            0,
            0,
            0,
            5,
            0,
            1.12,
            0,
            0,
            5,
            0,
            0,
            1.12,
            0,
            5,
            0,
            0,
            0,
            1,
            0,
          ]),
          child: child,
        );
      case DocumentFilterType.auto:
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            1.08,
            0,
            0,
            0,
            5,
            0,
            1.08,
            0,
            0,
            5,
            0,
            0,
            1.08,
            0,
            5,
            0,
            0,
            0,
            1,
            0,
          ]),
          child: child,
        );
      case DocumentFilterType.original:
        return child;
    }
  }

  Widget _buildFilterChip(String title, DocumentFilterType filter) {
    final isSelected = controller.selectedFilter.value == filter;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ChoiceChip(
        label: Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : null,
          ),
        ),
        selected: isSelected,
        selectedColor: AppColors.primary,
        onSelected: (_) => controller.applyFilter(filter),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Widget _buildToolButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: AppColors.primary),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  void _showAdjustmentBottomSheet(BuildContext context) {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Fine-tune Adjustments',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                const SizedBox(width: 80, child: Text('Brightness')),
                Expanded(
                  child: Obx(
                    () => Slider(
                      value: controller.brightness.value,
                      min: -0.5,
                      max: 0.5,
                      divisions: 20,
                      label: '${(controller.brightness.value * 100).toInt()}%',
                      onChanged: (val) {
                        controller.brightness.value = val;
                      },
                    ),
                  ),
                ),
              ],
            ),

            Row(
              children: [
                const SizedBox(width: 80, child: Text('Contrast')),
                Expanded(
                  child: Obx(
                    () => Slider(
                      value: controller.contrast.value,
                      min: 0.5,
                      max: 2.0,
                      divisions: 15,
                      label: '${(controller.contrast.value * 100).toInt()}%',
                      onChanged: (val) {
                        controller.contrast.value = val;
                      },
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () {
                  controller.brightness.value = 0.0;
                  controller.contrast.value = 1.0;
                  Get.back();
                },
                child: const Text('Reset Adjustments'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
