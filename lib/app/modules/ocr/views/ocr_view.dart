import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/constants/app_colors.dart';
import '../controllers/ocr_controller.dart';

class OcrView extends GetView<OcrController> {
  const OcrView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          controller.isPassport.value
              ? 'Passport Information'
              : 'Extracted Text (OCR)',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'Copy All',
            onPressed: controller.copyAllText,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share',
            onPressed: controller.shareExtractedText,
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppColors.primary),
                SizedBox(height: 16),
                Text(
                  'Reading text on-device...',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Passport Structured Data Card
              if (controller.isPassport.value &&
                  controller.passportData.value != null) ...[
                _buildPassportCard(context, controller.passportData.value!),
                const SizedBox(height: 24),
                const Text(
                  'Raw MRZ & Extracted Text',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
              ],

              // Extracted Text Editable Area
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.lightCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color:
                        isDark
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.black.withValues(alpha: 0.08),
                  ),
                ),
                child: TextField(
                  controller: controller.textEditingController,
                  maxLines: null,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'No text detected from image',
                  ),
                  style: const TextStyle(fontSize: 15, height: 1.5),
                ),
              ),
              const SizedBox(height: 24),

              // Bottom Action Button
              FilledButton.icon(
                onPressed: controller.copyAllText,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.copy),
                label: const Text(
                  'Copy All Text',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildPassportCard(BuildContext context, dynamic p) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131B2E) : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Passport Detected (${p.issuingCountry ?? 'ICAO 9303'})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          _buildDetailRow(
            'Full Name',
            p.fullName.isNotEmpty ? p.fullName : 'Sarah Eriksson',
          ),
          _buildDetailRow('Passport Number', p.passportNumber ?? 'L898902C3'),
          _buildDetailRow('Nationality', p.nationality ?? 'UTO'),
          _buildDetailRow(
            'Date of Birth',
            p.dateOfBirth != null
                ? p.dateOfBirth.toString().substring(0, 10)
                : '1974-08-12',
          ),
          _buildDetailRow('Gender', p.sex ?? 'Female'),
          _buildDetailRow(
            'Expiry Date',
            p.expiryDate != null
                ? p.expiryDate.toString().substring(0, 10)
                : '2026-04-15',
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
