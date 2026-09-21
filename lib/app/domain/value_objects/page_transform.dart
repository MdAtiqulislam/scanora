import '../../core/errors/app_failure.dart';

class PageTransform {
  final double scaleX;
  final double scaleY;
  final double translationX;
  final double translationY;
  final double rotation;

  const PageTransform({
    this.scaleX = 1,
    this.scaleY = 1,
    this.translationX = 0,
    this.translationY = 0,
    this.rotation = 0,
  });

  Map<String, double> toMap() => {
    'scaleX': scaleX,
    'scaleY': scaleY,
    'translationX': translationX,
    'translationY': translationY,
    'rotation': rotation,
  };

  factory PageTransform.fromMap(Map<String, dynamic> map) => PageTransform(
    scaleX: (map['scaleX'] as num?)?.toDouble() ?? 1,
    scaleY: (map['scaleY'] as num?)?.toDouble() ?? 1,
    translationX: (map['translationX'] as num?)?.toDouble() ?? 0,
    translationY: (map['translationY'] as num?)?.toDouble() ?? 0,
    rotation: (map['rotation'] as num?)?.toDouble() ?? 0,
  );

  void validate() {
    final values = [scaleX, scaleY, translationX, translationY, rotation];
    if (values.any((value) => !value.isFinite) || scaleX == 0 || scaleY == 0) {
      throw const ValidationFailure('Page transform contains invalid values');
    }
  }
}
