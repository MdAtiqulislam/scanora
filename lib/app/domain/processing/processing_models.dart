import '../entities/scan_page.dart';
import '../geometry/geometry_models.dart';

class ThumbnailSpecification {
  final int width;
  final int height;
  final int quality;

  const ThumbnailSpecification({
    this.width = 320,
    this.height = 320,
    this.quality = 85,
  })  : assert(width > 0, 'Thumbnail width must be > 0'),
        assert(height > 0, 'Thumbnail height must be > 0'),
        assert(quality >= 0 && quality <= 100, 'Thumbnail quality must be between 0 and 100');

  bool get isValid => width > 0 && height > 0 && quality >= 0 && quality <= 100;

  void validate() {
    if (width <= 0) {
      throw ArgumentError.value(width, 'width', 'Thumbnail width must be greater than 0');
    }
    if (height <= 0) {
      throw ArgumentError.value(height, 'height', 'Thumbnail height must be greater than 0');
    }
    if (quality < 0 || quality > 100) {
      throw ArgumentError.value(quality, 'quality', 'Thumbnail quality must be between 0 and 100');
    }
  }

  Map<String, Object> toMap() => {
    'width': width,
    'height': height,
    'quality': quality,
  };
}

class ProcessingRequest {
  final String documentId;
  final String pageId;
  final String rawAssetIdentity;
  final PageEditStateSnapshot editState;
  final PixelSize sourceSize;
  final bool forceReprocess;
  final ThumbnailSpecification thumbnail;
  final bool Function()? isCancelled;

  const ProcessingRequest({
    required this.documentId,
    required this.pageId,
    required this.rawAssetIdentity,
    required this.editState,
    required this.sourceSize,
    this.forceReprocess = false,
    this.thumbnail = const ThumbnailSpecification(),
    this.isCancelled,
  });
}

class PageEditStateSnapshot {
  final ScanPage page;
  const PageEditStateSnapshot(this.page);
}

class ProcessingPlan {
  final String engineVersion;
  final String processedCacheKey;
  final String thumbnailCacheKey;
  final GeometryResult geometry;
  final bool supportsProfile;

  const ProcessingPlan({
    required this.engineVersion,
    required this.processedCacheKey,
    required this.thumbnailCacheKey,
    required this.geometry,
    required this.supportsProfile,
  });
}

class ProcessingResult {
  final String processedPath;
  final String thumbnailPath;
  final ProcessingPlan plan;

  const ProcessingResult({
    required this.processedPath,
    required this.thumbnailPath,
    required this.plan,
  });
}
