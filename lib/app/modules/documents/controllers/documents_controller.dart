import 'package:get/get.dart';
import '../../../data/models/scanned_document.dart';
import '../../../data/repositories/document_repository.dart';
import '../../../core/utils/snackbar_helper.dart';

class DocumentsController extends GetxController {
  final DocumentRepository repository = Get.find<DocumentRepository>();

  RxList<ScannedDocument> get documents => repository.documents;
  var isGridView = false.obs;
  var searchQuery = ''.obs;

  List<ScannedDocument> get filteredDocuments {
    if (searchQuery.value.trim().isEmpty) {
      return documents;
    }
    final q = searchQuery.value.toLowerCase();
    return documents.where((d) => d.title.toLowerCase().contains(q)).toList();
  }

  void toggleViewMode() {
    isGridView.value = !isGridView.value;
  }

  void updateSearch(String val) {
    searchQuery.value = val;
  }

  Future<void> deleteDocument(String id) async {
    await repository.deleteDocument(id);
    SnackbarHelper.showSuccess('Document deleted');
  }
}
