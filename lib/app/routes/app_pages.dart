import 'package:get/get.dart';

import '../modules/documents/bindings/documents_binding.dart';
import '../modules/documents/views/document_detail_view.dart';
import '../modules/documents/views/documents_view.dart';
import '../modules/editor/bindings/editor_binding.dart';
import '../modules/editor/views/editor_view.dart';
import '../modules/home/bindings/home_binding.dart';
import '../modules/home/views/home_view.dart';
import '../modules/id_card_merge/bindings/id_card_merge_binding.dart';
import '../modules/id_card_merge/views/id_card_merge_view.dart';
import '../modules/ocr/bindings/ocr_binding.dart';
import '../modules/ocr/views/ocr_view.dart';
import '../modules/scanner/bindings/scanner_binding.dart';
import '../modules/scanner/views/scanner_view.dart';
import '../modules/settings/bindings/settings_binding.dart';
import '../modules/settings/views/settings_view.dart';

part 'app_routes.dart';

class AppPages {
  AppPages._();

  static const initial = Routes.home;

  static final routes = [
    GetPage(
      name: _Paths.home,
      page: () => const HomeView(),
      binding: HomeBinding(),
    ),
    GetPage(
      name: _Paths.scanner,
      page: () => const ScannerView(),
      binding: ScannerBinding(),
    ),
    GetPage(
      name: _Paths.editor,
      page: () => const EditorView(),
      binding: EditorBinding(),
    ),
    GetPage(
      name: _Paths.idCardMerge,
      page: () => const IdCardMergeView(),
      binding: IdCardMergeBinding(),
    ),
    GetPage(
      name: _Paths.documents,
      page: () => const DocumentsView(),
      binding: DocumentsBinding(),
    ),
    GetPage(
      name: _Paths.documentDetail,
      page: () => const DocumentDetailView(),
    ),
    GetPage(
      name: _Paths.ocr,
      page: () => const OcrView(),
      binding: OcrBinding(),
    ),
    GetPage(
      name: _Paths.settings,
      page: () => const SettingsView(),
      binding: SettingsBinding(),
    ),
  ];
}
