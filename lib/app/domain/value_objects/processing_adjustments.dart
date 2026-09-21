import '../../core/errors/app_failure.dart';

class ProcessingAdjustments {
  final double brightness;
  final double contrast;
  final double saturation;

  const ProcessingAdjustments({
    this.brightness = 0,
    this.contrast = 1,
    this.saturation = 1,
  });

  Map<String, double> toMap() => {
    'brightness': brightness,
    'contrast': contrast,
    'saturation': saturation,
  };

  factory ProcessingAdjustments.fromMap(Map<String, dynamic> map) =>
      ProcessingAdjustments(
        brightness: (map['brightness'] as num?)?.toDouble() ?? 0,
        contrast: (map['contrast'] as num?)?.toDouble() ?? 1,
        saturation: (map['saturation'] as num?)?.toDouble() ?? 1,
      );

  void validate() {
    if (![brightness, contrast, saturation].every((value) => value.isFinite)) {
      throw const ValidationFailure(
        'Processing adjustments contain invalid values',
      );
    }
    if (contrast < 0 || saturation < 0) {
      throw const ValidationFailure(
        'Contrast and saturation cannot be negative',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ProcessingAdjustments &&
      other.brightness == brightness &&
      other.contrast == contrast &&
      other.saturation == saturation;

  @override
  int get hashCode => Object.hash(brightness, contrast, saturation);
}
