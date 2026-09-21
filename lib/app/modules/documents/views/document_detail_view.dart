import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/pdf_service.dart';
import '../../../core/services/share_service.dart';
import '../../../core/utils/file_utils.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../../data/models/scanned_document.dart';
import '../../../data/repositories/document_repository.dart';
import '../../../routes/app_pages.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/storage_service.dart';

class DocumentDetailView extends StatefulWidget {
  const DocumentDetailView({super.key});

  @override
  State<DocumentDetailView> createState() => _DocumentDetailViewState();
}

class _DocumentDetailViewState extends State<DocumentDetailView> {
  final DocumentRepository repository = Get.find<DocumentRepository>();
  final ShareService shareService = Get.put(ShareService());
  final PdfService pdfService = Get.find<PdfService>();
  final StorageService storageService = Get.find<StorageService>();

  late ScannedDocument document;
  int currentPreviewPage = 0;

  @override
  void initState() {
    super.initState();
    document = Get.arguments as ScannedDocument;
  }

  void _renameDocument() {
    final textController = TextEditingController(text: document.title);
    Get.defaultDialog(
      title: 'Rename Document',
      content: TextField(
        controller: textController,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Document Name',
          border: OutlineInputBorder(),
        ),
      ),
      textConfirm: 'Save',
      textCancel: 'Cancel',
      confirmTextColor: Colors.white,
      buttonColor: AppColors.primary,
      onConfirm: () async {
        final newTitle = textController.text.trim();
        if (newTitle.isNotEmpty) {
          final updated = ScannedDocument(
            id: document.id,
            title: newTitle,
            pages: document.pages,
            pdfPath: document.pdfPath,
            createdAt: document.createdAt,
            updatedAt: DateTime.now(),
          );
          await repository.saveDocument(updated);
          setState(() {
            document = updated;
          });
          Get.back();
          SnackbarHelper.showSuccess('Document renamed');
        }
      },
    );
  }

  void _showPdfExportSheet() {
    final savedQuality = storageService.getString(AppConstants.keyPdfQuality);
    PdfQuality selectedQuality =
        savedQuality == 'low'
            ? PdfQuality.low
            : (savedQuality == 'medium' ? PdfQuality.medium : PdfQuality.high);

    final savedPageSize = storageService.getString(
      AppConstants.keyDefaultPageSize,
    );
    PdfPageFormatType selectedFormat =
        savedPageSize == 'a4'
            ? PdfPageFormatType.a4
            : (savedPageSize == 'letter'
                ? PdfPageFormatType.letter
                : PdfPageFormatType.original);

    Get.bottomSheet(
      StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Export PDF',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Quality',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Low'),
                      selected: selectedQuality == PdfQuality.low,
                      onSelected:
                          (_) => setSheetState(
                            () => selectedQuality = PdfQuality.low,
                          ),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Medium'),
                      selected: selectedQuality == PdfQuality.medium,
                      onSelected:
                          (_) => setSheetState(
                            () => selectedQuality = PdfQuality.medium,
                          ),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('High'),
                      selected: selectedQuality == PdfQuality.high,
                      onSelected:
                          (_) => setSheetState(
                            () => selectedQuality = PdfQuality.high,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Page Size',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Original'),
                      selected: selectedFormat == PdfPageFormatType.original,
                      onSelected:
                          (_) => setSheetState(
                            () => selectedFormat = PdfPageFormatType.original,
                          ),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('A4'),
                      selected: selectedFormat == PdfPageFormatType.a4,
                      onSelected:
                          (_) => setSheetState(
                            () => selectedFormat = PdfPageFormatType.a4,
                          ),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Letter'),
                      selected: selectedFormat == PdfPageFormatType.letter,
                      onSelected:
                          (_) => setSheetState(
                            () => selectedFormat = PdfPageFormatType.letter,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () async {
                    Get.back();
                    // Reuse cached PDF path if it exists, only regenerate if needed
                    String sharePath;
                    if (document.pdfPath != null &&
                        File(document.pdfPath!).existsSync()) {
                      sharePath = document.pdfPath!;
                    } else {
                      final path = await FileUtils.createTimestampedFilePath(
                        extension: 'pdf',
                      );
                      await pdfService.generatePdf(
                        imagePaths:
                            document.pages.map((p) => p.imagePath).toList(),
                        outputFilePath: path,
                        quality: selectedQuality,
                        pageFormat: selectedFormat,
                      );
                      sharePath = path;
                      // Update cached path
                      final updated = ScannedDocument(
                        id: document.id,
                        title: document.title,
                        pages: document.pages,
                        pdfPath: path,
                        createdAt: document.createdAt,
                        updatedAt: document.updatedAt,
                      );
                      await repository.saveDocument(updated);
                      setState(() => document = updated);
                    }
                    shareService.shareFile(sharePath, subject: document.title);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.share),
                  label: const Text(
                    'Export & Share PDF',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(document.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Rename',
            onPressed: _renameDocument,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share',
            onPressed: _showPdfExportSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          // Main Preview
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Center(
                child:
                    document.pages.isNotEmpty &&
                            File(
                              document.pages[currentPreviewPage].imagePath,
                            ).existsSync()
                        ? ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.file(
                            File(document.pages[currentPreviewPage].imagePath),
                            fit: BoxFit.contain,
                          ),
                        )
                        : const Icon(
                          Icons.broken_image,
                          size: 64,
                          color: Colors.grey,
                        ),
              ),
            ),
          ),

          // Multi-page selector if > 1 page
          if (document.pages.length > 1)
            Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: document.pages.length,
                itemBuilder: (context, index) {
                  final isSelected = currentPreviewPage == index;
                  return GestureDetector(
                    onTap: () => setState(() => currentPreviewPage = index),
                    child: Container(
                      width: 44,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isSelected ? AppColors.primary : Colors.grey,
                          width: isSelected ? 2.5 : 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.file(
                        File(document.pages[index].imagePath),
                        fit: BoxFit.cover,
                      ),
                    ),
                  );
                },
              ),
            ),

          // Bottom Action Bar (PDF, OCR, Delete)
          Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom + 16,
              top: 16,
              left: 20,
              right: 20,
            ),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : AppColors.lightCard,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _showPdfExportSheet,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text(
                      'Export PDF',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filledTonal(
                  onPressed: () {
                    Get.toNamed(
                      Routes.ocr,
                      arguments: {
                        'imagePath':
                            document.pages[currentPreviewPage].imagePath,
                        'isPassport': false,
                      },
                    );
                  },
                  icon: const Icon(Icons.text_snippet_outlined),
                  tooltip: 'OCR Text',
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: () async {
                    await repository.deleteDocument(document.id);
                    Get.back();
                    SnackbarHelper.showSuccess('Document deleted');
                  },
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'Delete',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
