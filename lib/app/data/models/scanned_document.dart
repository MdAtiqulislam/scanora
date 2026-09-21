import 'dart:convert';
import 'scanned_page.dart';

class ScannedDocument {
  final String id;
  final String title;
  final List<ScannedPage> pages;
  final String? pdfPath;
  final DateTime createdAt;
  final DateTime updatedAt;

  ScannedDocument({
    required this.id,
    required this.title,
    required this.pages,
    this.pdfPath,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  int get pageCount => pages.length;
  String? get thumbnailPath => pages.isNotEmpty ? pages.first.imagePath : null;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'pages': pages.map((p) => p.toMap()).toList(),
      'pdfPath': pdfPath,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ScannedDocument.fromMap(Map<String, dynamic> map) {
    return ScannedDocument(
      id: map['id'] ?? '',
      title: map['title'] ?? 'Document',
      pages:
          (map['pages'] as List<dynamic>? ?? [])
              .map((p) => ScannedPage.fromMap(p as Map<String, dynamic>))
              .toList(),
      pdfPath: map['pdfPath'],
      createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updatedAt'] ?? '') ?? DateTime.now(),
    );
  }

  String toJson() => json.encode(toMap());
  factory ScannedDocument.fromJson(String source) =>
      ScannedDocument.fromMap(json.decode(source));
}
