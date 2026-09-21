import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/id_card_dimensions.dart';
import '../../../core/services/image_processing_service.dart';
import '../../../data/models/document_corners.dart';
import '../../editor/widgets/crop_quad_editor.dart';
import '../controllers/id_card_merge_controller.dart';

class IdCardMergeView extends GetView<IdCardMergeController> {
  const IdCardMergeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // 1. Interactive 4-Corner Crop Editor for Front Card
      if (controller.isCroppingFront.value) {
        return CropQuadEditor(
          imagePath: controller.rawFrontPath.value,
          initialCorners: DocumentCorners.idCardGuide(),
          onCropApplied: controller.applyFrontCrop,
          onCancel: controller.cancelCrop,
        );
      }

      // 2. Interactive 4-Corner Crop Editor for Back Card
      if (controller.isCroppingBack.value) {
        return CropQuadEditor(
          imagePath: controller.rawBackPath.value,
          initialCorners: DocumentCorners.idCardGuide(),
          onCropApplied: controller.applyBackCrop,
          onCancel: controller.cancelCrop,
        );
      }

      final isDark = Theme.of(context).brightness == Brightness.dark;

      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'ID Card Merge',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          actions: [
            // Share Action
            IconButton(
              icon: const Icon(Icons.share_outlined, color: AppColors.primary),
              tooltip: 'Share PDF',
              onPressed:
                  controller.isProcessing.value
                      ? null
                      : controller.shareDocument,
            ),
            // Save Action
            Padding(
              padding: const EdgeInsets.only(right: 12.0, left: 4.0),
              child: FilledButton.icon(
                onPressed:
                    controller.isProcessing.value
                        ? null
                        : controller.saveDocument,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                icon:
                    controller.isProcessing.value
                        ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : const Icon(Icons.check, size: 18),
                label: const Text(
                  'Save',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            // Physical Size Notice Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppColors.primary.withValues(alpha: 0.08),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.straighten_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Fixed Print Size: 9.0 cm × 5.5 cm (1:1 Standard)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),

            // 3. Live Interactive A4 Document Preview (210 x 297 mm proportion)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.35 : 0.15,
                          ),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: AspectRatio(
                      aspectRatio:
                          IdCardDimensions.a4WidthMm /
                          IdCardDimensions.a4HeightMm, // 210 / 297
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return Obx(() {
                            final front = controller.frontPath.value;
                            final back = controller.backPath.value;
                            final frontTurns =
                                controller.frontQuarterTurns.value;
                            final backTurns = controller.backQuarterTurns.value;
                            final filter = controller.selectedFilter.value;

                            // Exact Visual Proportion of 85mm Card on 210mm A4 sheet
                            final cardWidth =
                                constraints.maxWidth *
                                IdCardDimensions.a4WidthRatio;
                            final spacingVal =
                                (controller.spacingMm.value /
                                    IdCardDimensions.a4HeightMm) *
                                constraints.maxHeight;

                            if (front.isEmpty && back.isEmpty) {
                              return const Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.primary,
                                ),
                              );
                            }

                            return Center(
                              child: SingleChildScrollView(
                                physics: const NeverScrollableScrollPhysics(),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // Front Card View (8.5 x 5.5 cm)
                                    if (front.isNotEmpty &&
                                        File(front).existsSync())
                                      _buildCardItem(
                                        filePath: front,
                                        width: cardWidth,
                                        quarterTurns: frontTurns,
                                        filter: filter,
                                      ),

                                    // Dynamic Spacing Gap
                                    SizedBox(height: spacingVal),

                                    // Back Card View (8.5 x 5.5 cm)
                                    if (back.isNotEmpty &&
                                        File(back).existsSync())
                                      _buildCardItem(
                                        filePath: back,
                                        width: cardWidth,
                                        quarterTurns: backTurns,
                                        filter: filter,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          });
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 4. Filter Selector Strip
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _buildFilterChip('Smart', DocumentFilterType.smart),
                    _buildFilterChip('Magic', DocumentFilterType.magic),
                    _buildFilterChip('Auto', DocumentFilterType.auto),
                    _buildFilterChip('Original', DocumentFilterType.original),
                    _buildFilterChip('Gray', DocumentFilterType.gray),
                    _buildFilterChip('B&W', DocumentFilterType.blackAndWhite),
                  ],
                ),
              ),
            ),

            // 5. Spacing, Crop & Rotation Controls Sheet
            Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 12,
                top: 14,
                left: 20,
                right: 20,
              ),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : AppColors.lightCard,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Spacing Between Slider (in millimeters)
                  Row(
                    children: [
                      const Icon(
                        Icons.height,
                        size: 20,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 80,
                        child: Text(
                          'Spacing',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: controller.spacingMm.value,
                          min: 5.0,
                          max: 45.0,
                          divisions: 8,
                          activeColor: AppColors.primary,
                          label: '${controller.spacingMm.value.round()} mm',
                          onChanged: controller.updateSpacingMm,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Toolbar: Manual Crop Front / Back, Rotate, Swap
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildToolButton(
                          icon: Icons.crop,
                          label: 'Crop Front',
                          onTap: controller.openCropFront,
                        ),
                        const SizedBox(width: 6),
                        _buildToolButton(
                          icon: Icons.crop,
                          label: 'Crop Back',
                          onTap: controller.openCropBack,
                        ),
                        const SizedBox(width: 6),
                        _buildToolButton(
                          icon: Icons.rotate_90_degrees_cw_outlined,
                          label: 'Rotate Front',
                          onTap: controller.rotateFront,
                        ),
                        const SizedBox(width: 6),
                        _buildToolButton(
                          icon: Icons.rotate_90_degrees_cw_outlined,
                          label: 'Rotate Back',
                          onTap: controller.rotateBack,
                        ),
                        const SizedBox(width: 6),
                        _buildToolButton(
                          icon: Icons.swap_vert_circle_outlined,
                          label: 'Swap',
                          onTap: controller.swapFrontAndBack,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildCardItem({
    required String filePath,
    required double width,
    required int quarterTurns,
    required DocumentFilterType filter,
  }) {
    final double cardHeight = width / IdCardDimensions.aspectRatio;

    return Container(
      width: width,
      height: cardHeight,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: RotatedBox(
        quarterTurns: quarterTurns,
        child: _applyFilterWidget(
          Image.file(
            File(filePath),
            key: ValueKey('$filePath-$quarterTurns-${filter.name}'),
            fit: BoxFit.fill, // Exact 8.5 x 5.5 cm box fill
            cacheWidth: 800,
          ),
          filter,
        ),
      ),
    );
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
            1.5,
            1.5,
            1.5,
            0,
            -160,
            1.5,
            1.5,
            1.5,
            0,
            -160,
            1.5,
            1.5,
            1.5,
            0,
            -160,
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
            1.1,
            0,
            0,
            0,
            5,
            0,
            1.1,
            0,
            0,
            5,
            0,
            0,
            1.1,
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
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : null,
          ),
        ),
        selected: isSelected,
        selectedColor: AppColors.primary,
        onSelected: (_) => controller.selectFilter(filter),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
