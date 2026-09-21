import 'dart:convert';
import 'document_corners.dart';

class ScannedPage {
  final String id;
  final String imagePath;
  final String? rawImagePath;
  final DocumentCorners? corners;
  final String filter;
  final int rotationAngle;
  final String? processedCacheKey;
  final String? thumbnailCacheKey;
  final double brightness;
  final double contrast;
  final double saturation;
  final DateTime createdAt;

  ScannedPage({
    required this.id,
    required this.imagePath,
    this.rawImagePath,
    this.corners,
    this.filter = 'magic',
    this.rotationAngle = 0,
    this.processedCacheKey,
    this.thumbnailCacheKey,
    this.brightness = 0,
    this.contrast = 1,
    this.saturation = 1,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'imagePath': imagePath,
      'rawImagePath': rawImagePath,
      'corners': corners?.toMap(),
      'filter': filter,
      'rotationAngle': rotationAngle,
      'processedCacheKey': processedCacheKey,
      'thumbnailCacheKey': thumbnailCacheKey,
      'brightness': brightness,
      'contrast': contrast,
      'saturation': saturation,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ScannedPage.fromMap(Map<String, dynamic> map) {
    return ScannedPage(
      id: map['id'] ?? '',
      imagePath: map['imagePath'] ?? '',
      rawImagePath: map['rawImagePath'],
      filter: map['filter'] ?? 'magic',
      rotationAngle: (map['rotationAngle'] as num?)?.toInt() ?? 0,
      processedCacheKey: map['processedCacheKey'],
      thumbnailCacheKey: map['thumbnailCacheKey'],
      brightness: (map['brightness'] as num?)?.toDouble() ?? 0,
      contrast: (map['contrast'] as num?)?.toDouble() ?? 1,
      saturation: (map['saturation'] as num?)?.toDouble() ?? 1,
      createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
    );
  }

  String toJson() => json.encode(toMap());
  factory ScannedPage.fromJson(String source) =>
      ScannedPage.fromMap(json.decode(source));
}
