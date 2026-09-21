import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:scanora/app/core/services/image_processing_service.dart';

void main() {
  test('ImageProcessingService filter test', () async {
    final service = ImageProcessingService();
    final tempImg = img.Image(width: 800, height: 600);
    img.fill(tempImg, color: img.ColorRgb8(200, 200, 200));
    final tempFile = File('test_image.jpg')..writeAsBytesSync(img.encodeJpg(tempImg));

    final result = await service.applyFilterAndAdjustments(
      inputFile: tempFile,
      filter: DocumentFilterType.smart,
    );

    expect(result.existsSync(), isTrue);
    if (tempFile.existsSync()) tempFile.deleteSync();
    if (result.existsSync()) result.deleteSync();
  });
}
