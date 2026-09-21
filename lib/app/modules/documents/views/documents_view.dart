import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/navigation/app_navigator.dart';
import '../../../routes/app_pages.dart';
import '../controllers/documents_controller.dart';

class DocumentsView extends GetView<DocumentsController> {
  const DocumentsView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Documents'),
        actions: [
          IconButton(
            icon: Obx(
              () => Icon(
                controller.isGridView.value
                    ? Icons.view_list_outlined
                    : Icons.grid_view_outlined,
              ),
            ),
            onPressed: controller.toggleViewMode,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: TextField(
              onChanged: controller.updateSearch,
              decoration: InputDecoration(
                hintText: 'Search documents or OCR text...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color:
                        isDark
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.black.withValues(alpha: 0.08),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color:
                        isDark
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.black.withValues(alpha: 0.08),
                  ),
                ),
              ),
            ),
          ),

          // Documents List / Grid
          Expanded(
            child: Obx(() {
              final docs = controller.filteredDocuments;

              if (docs.isEmpty) {
                return EmptyStateView(
                  title:
                      controller.searchQuery.value.isEmpty
                          ? 'No documents yet'
                          : 'No documents match your search',
                  subtitle:
                      controller.searchQuery.value.isEmpty
                          ? 'Scan your first document now'
                          : 'Try searching with a different title',
                  buttonText: 'Scan Document',
                  onButtonPressed: AppNavigator.toScanner,
                );
              }

              if (controller.isGridView.value) {
                return GridView.builder(
                  padding: const EdgeInsets.all(20),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    return GestureDetector(
                      onTap:
                          () => Get.toNamed(
                            Routes.documentDetail,
                            arguments: doc,
                          ),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child:
                                  doc.thumbnailPath != null &&
                                          File(doc.thumbnailPath!).existsSync()
                                      ? Image.file(
                                        File(doc.thumbnailPath!),
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                      )
                                      : Container(
                                        color: Colors.grey[800],
                                        child: const Center(
                                          child: Icon(
                                            Icons.description,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(10.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    doc.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    '${doc.pageCount} pages',
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                itemCount: docs.length,
                separatorBuilder:
                    (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  return Card(
                    child: ListTile(
                      onTap:
                          () => Get.toNamed(
                            Routes.documentDetail,
                            arguments: doc,
                          ),
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child:
                            doc.thumbnailPath != null &&
                                    File(doc.thumbnailPath!).existsSync()
                                ? Image.file(
                                  File(doc.thumbnailPath!),
                                  fit: BoxFit.cover,
                                )
                                : const Icon(
                                  Icons.description_outlined,
                                  color: AppColors.primary,
                                ),
                      ),
                      title: Text(
                        doc.title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${doc.pageCount} pages • ${doc.updatedAt.toString().substring(0, 10)}',
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: Colors.grey,
                      ),
                    ),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}
