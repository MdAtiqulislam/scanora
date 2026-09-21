import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/image_processing_service.dart';
import '../controllers/editor_controller.dart';

class ImageFilterDialog extends StatefulWidget {
  final EditorPageModel pageModel;
  final Function(EditorPageModel updatedPage) onApply;
  final Function(DocumentFilterType filter)? onApplyToAll;

  const ImageFilterDialog({
    super.key,
    required this.pageModel,
    required this.onApply,
    this.onApplyToAll,
  });

  static Future<void> show(
    BuildContext context, {
    required EditorPageModel pageModel,
    required Function(EditorPageModel updatedPage) onApply,
    Function(DocumentFilterType filter)? onApplyToAll,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => ImageFilterDialog(
            pageModel: pageModel,
            onApply: onApply,
            onApplyToAll: onApplyToAll,
          ),
    );
  }

  @override
  State<ImageFilterDialog> createState() => _ImageFilterDialogState();
}

class _ImageFilterDialogState extends State<ImageFilterDialog> {
  late DocumentFilterType _selectedFilter;
  late int _quarterTurns;
  Uint8List? _previewBytes;
  Uint8List? _originalBytes;

  @override
  void initState() {
    super.initState();
    _selectedFilter = widget.pageModel.filter;
    _quarterTurns = widget.pageModel.quarterTurns;
    _loadOriginalBytes();
  }

  Future<void> _loadOriginalBytes() async {
    final bytes = await File(widget.pageModel.imagePath).readAsBytes();
    _originalBytes = bytes;
    if (mounted) {
      setState(() {
        _previewBytes = _originalBytes;
      });
    }
  }

  void _rotate(int deltaQuarterTurns) {
    setState(() {
      _quarterTurns = (_quarterTurns + deltaQuarterTurns) % 4;
    });
  }

  void _selectFilter(DocumentFilterType filter) {
    setState(() {
      _selectedFilter = filter;
    });
  }

  void _applyChanges() {
    widget.pageModel.filter = _selectedFilter;
    widget.pageModel.quarterTurns = _quarterTurns;
    widget.onApply(widget.pageModel);
    Get.back();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final filters = [
      _FilterOption(
        DocumentFilterType.smart,
        'Smart',
        Icons.auto_fix_high_rounded,
      ),
      _FilterOption(
        DocumentFilterType.original,
        'Original',
        Icons.image_rounded,
      ),
      _FilterOption(
        DocumentFilterType.magic,
        'Magic Color',
        Icons.auto_awesome_rounded,
      ),
      _FilterOption(
        DocumentFilterType.blackAndWhite,
        'B&W Doc',
        Icons.document_scanner_rounded,
      ),
      _FilterOption(
        DocumentFilterType.auto,
        'Brighten',
        Icons.wb_sunny_rounded,
      ),
      _FilterOption(
        DocumentFilterType.gray,
        'Grayscale',
        Icons.filter_b_and_w_rounded,
      ),
    ];

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Top Header & Rotation Controls
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Edit & Filter Image',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color:
                            isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.lightTextPrimary,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.rotate_left_rounded),
                          tooltip: 'Rotate Left',
                          onPressed: () => _rotate(3),
                        ),
                        IconButton(
                          icon: const Icon(Icons.rotate_right_rounded),
                          tooltip: 'Rotate Right',
                          onPressed: () => _rotate(1),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Main Instant Preview Area
          Expanded(
            child: Container(
              color: isDark ? Colors.black26 : Colors.grey.shade100,
              padding: const EdgeInsets.all(16),
              child: Center(
                child:
                    _previewBytes != null
                        ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: RotatedBox(
                            quarterTurns: _quarterTurns,
                            child: _applyFilterWidget(
                              Image.memory(_previewBytes!, fit: BoxFit.contain),
                              _selectedFilter,
                            ),
                          ),
                        )
                        : const CircularProgressIndicator(),
              ),
            ),
          ),

          // Bottom Filter Selector & Buttons
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : AppColors.lightCard,
              border: Border(
                top: BorderSide(
                  color:
                      isDark ? AppColors.darkDivider : AppColors.lightDivider,
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Filter Selection Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children:
                        filters.map((opt) {
                          final isSelected = _selectedFilter == opt.type;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              avatar: Icon(
                                opt.icon,
                                size: 16,
                                color:
                                    isSelected
                                        ? Colors.white
                                        : (isDark
                                            ? AppColors.darkTextPrimary
                                            : AppColors.lightTextPrimary),
                              ),
                              label: Text(opt.label),
                              selected: isSelected,
                              onSelected: (_) => _selectFilter(opt.type),
                              selectedColor: AppColors.primary,
                              labelStyle: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color:
                                    isSelected
                                        ? Colors.white
                                        : (isDark
                                            ? AppColors.darkTextSecondary
                                            : AppColors.lightTextSecondary),
                              ),
                            ),
                          );
                        }).toList(),
                  ),
                ),
                const SizedBox(height: 14),

                // Action Buttons
                Row(
                  children: [
                    if (widget.onApplyToAll != null) ...[
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            widget.onApplyToAll!(_selectedFilter);
                            _applyChanges();
                          },
                          child: const Text(
                            'Apply to All',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text(
                          'Confirm',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: _applyChanges,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _applyFilterWidget(Widget child, DocumentFilterType filter) {
    switch (filter) {
      case DocumentFilterType.smart:
        // Preview: high contrast to simulate text whitening
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
        // Reduced: matches the new gentler 1.12 contrast values
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
}

class _FilterOption {
  final DocumentFilterType type;
  final String label;
  final IconData icon;
  _FilterOption(this.type, this.label, this.icon);
}
