import 'scan_page.dart';

class ScanDocument {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool favorite;
  final List<String> tags;
  final String? pdfPath;
  final List<ScanPage> pages;

  const ScanDocument({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.favorite = false,
    this.tags = const [],
    this.pdfPath,
    this.pages = const [],
  });

  int get pageCount => pages.length;
}
