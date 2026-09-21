import '../value_objects/page_corners.dart';
import '../value_objects/page_transform.dart';
import '../value_objects/processing_profile.dart';
import '../enums/scan_enums.dart';
import '../value_objects/page_edit_state.dart';

class ScanPage {
  final String id;
  final String documentId;
  final int pageIndex;
  final String? rawImagePath;
  final String? processedImagePath;
  final String? thumbnailPath;
  final PageCorners? corners;
  final double rotationAngle;
  final PageTransform cropTransform;
  final ProcessingProfile processingProfile;
  final String? ocrResult;
  final bool isDirty;
  final String? processedCacheKey;
  final String? thumbnailCacheKey;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ScanPage({
    required this.id,
    required this.documentId,
    required this.pageIndex,
    this.rawImagePath,
    this.processedImagePath,
    this.thumbnailPath,
    this.corners,
    this.rotationAngle = 0,
    this.cropTransform = const PageTransform(),
    this.processingProfile = const ProcessingProfile(),
    this.ocrResult,
    this.isDirty = false,
    this.processedCacheKey,
    this.thumbnailCacheKey,
    required this.createdAt,
    required this.updatedAt,
  });

  ScanFilterType get filterType => processingProfile.filterType;

  double get brightness => processingProfile.adjustments.brightness;

  double get contrast => processingProfile.adjustments.contrast;

  double get saturation => processingProfile.adjustments.saturation;

  PageEditState get editState => PageEditState(
    corners: corners,
    cropTransform: cropTransform,
    rotationAngle: rotationAngle.round(),
    filterType: filterType,
    adjustments: processingProfile.adjustments,
    processingProfile: processingProfile,
  );
}
