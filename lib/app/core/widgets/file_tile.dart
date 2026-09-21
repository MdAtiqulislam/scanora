import 'dart:io';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../utils/file_utils.dart';

class FileTile extends StatelessWidget {
  final String title;
  final int sizeInBytes;
  final String? subtitle;
  final String? imagePath;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final VoidCallback? onTap;
  final bool isReorderable;
  final int? index;
  final String? badgeText;

  const FileTile({
    super.key,
    required this.title,
    required this.sizeInBytes,
    this.subtitle,
    this.imagePath,
    this.onDelete,
    this.onEdit,
    this.onTap,
    this.isReorderable = false,
    this.index,
    this.badgeText,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.darkDivider : AppColors.lightDivider,
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        onTap: onTap,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (index != null) ...[
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${index! + 1}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Stack(
              alignment: Alignment.bottomCenter,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child:
                      imagePath != null
                          ? Image.file(
                            File(imagePath!),
                            width: 46,
                            height: 46,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildFallbackIcon(),
                          )
                          : _buildFallbackIcon(),
                ),
                if (badgeText != null)
                  Container(
                    width: 46,
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.85),
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(8),
                      ),
                    ),
                    child: Text(
                      badgeText!,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color:
                isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitle ?? FileUtils.formatBytes(sizeInBytes),
            style: TextStyle(
              fontSize: 12,
              color:
                  isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
            ),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onEdit != null)
              IconButton(
                icon: const Icon(
                  Icons.auto_fix_high_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
                tooltip: 'Edit / Filter',
                onPressed: onEdit,
              ),
            if (onDelete != null)
              IconButton(
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.error,
                  size: 20,
                ),
                onPressed: onDelete,
              ),
            if (isReorderable)
              Icon(
                Icons.drag_handle_rounded,
                color:
                    isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackIcon() {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        Icons.picture_as_pdf_rounded,
        color: AppColors.primary,
        size: 24,
      ),
    );
  }
}
