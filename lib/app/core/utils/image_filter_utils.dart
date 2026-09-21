import '../services/image_processing_service.dart';

class ImageFilterUtils {
  ImageFilterUtils._();

  static String getFilterName(DocumentFilterType filter) {
    switch (filter) {
      case DocumentFilterType.smart:
        return 'Smart';
      case DocumentFilterType.original:
        return 'Original';
      case DocumentFilterType.auto:
        return 'Auto';
      case DocumentFilterType.magic:
        return 'Magic';
      case DocumentFilterType.gray:
        return 'Gray';
      case DocumentFilterType.blackAndWhite:
        return 'B&W';
    }
  }
}
