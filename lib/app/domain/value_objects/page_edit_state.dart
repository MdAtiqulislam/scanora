import 'dart:convert';

import '../../core/errors/app_failure.dart';
import '../enums/scan_enums.dart';
import 'page_corners.dart';
import 'page_transform.dart';
import 'processing_adjustments.dart';
import 'processing_profile.dart';

class PageEditState {
  static const currentVersion = 1;

  final PageCorners? corners;
  final PageTransform cropTransform;
  final int rotationAngle;
  final ScanFilterType filterType;
  final ProcessingAdjustments adjustments;
  final ProcessingProfile processingProfile;

  PageEditState({
    this.corners,
    this.cropTransform = const PageTransform(),
    this.rotationAngle = 0,
    this.filterType = ScanFilterType.original,
    this.adjustments = const ProcessingAdjustments(),
    ProcessingProfile? processingProfile,
  }) : processingProfile =
           processingProfile ??
           ProcessingProfile(filterType: filterType, adjustments: adjustments) {
    _validate();
  }

  void _validate() {
    if (rotationAngle % 90 != 0) {
      throw const ValidationFailure(
        'Rotation must be a multiple of 90 degrees',
      );
    }
    cropTransform.validate();
    adjustments.validate();
    if (processingProfile.filterType != filterType ||
        processingProfile.adjustments != adjustments) {
      throw const ValidationFailure(
        'Processing profile does not match edit state',
      );
    }
  }

  int get normalizedRotation => ((rotationAngle % 360) + 360) % 360;

  PageEditState rotateBy(int degrees) => PageEditState(
    corners: corners,
    cropTransform: cropTransform,
    rotationAngle: normalizedRotation + degrees,
    filterType: filterType,
    adjustments: adjustments,
    processingProfile: processingProfile,
  );

  Map<String, dynamic> toMap() => {
    'version': currentVersion,
    'corners': corners?.toMap(),
    'cropTransform': cropTransform.toMap(),
    'rotationAngle': normalizedRotation,
    'filterType': filterType.name,
    'adjustments': adjustments.toMap(),
    'processingProfile': processingProfile.toMap(),
  };

  String canonicalJson() => jsonEncode(toMap());

  @override
  bool operator ==(Object other) =>
      other is PageEditState && other.canonicalJson() == canonicalJson();

  @override
  int get hashCode => canonicalJson().hashCode;
}

class PageCacheIdentity {
  static const profileVersion = 1;
  static const defaultEngineVersion = 'M07-v1';

  static String forState({
    required String documentId,
    required String pageId,
    required String rawAssetIdentity,
    required PageEditState state,
  }) {
    final input = jsonEncode({
      'documentId': documentId,
      'pageId': pageId,
      'rawAssetIdentity': rawAssetIdentity,
      'profileVersion': profileVersion,
      'editState': state.toMap(),
    });
    return _fnv1a(input);
  }

  static String forProcessed({
    String engineVersion = defaultEngineVersion,
    required String documentId,
    required String pageId,
    required String rawAssetIdentity,
    required PageEditState editState,
    required List<double> geometryTransform,
    Map<String, Object>? outputSpec,
  }) {
    final input = jsonEncode({
      'documentId': documentId,
      'editState': editState.toMap(),
      'engineVersion': engineVersion,
      'geometryTransform': geometryTransform,
      'outputSpec': outputSpec ?? const {'format': 'jpeg', 'quality': 92},
      'pageId': pageId,
      'rawAssetIdentity': rawAssetIdentity,
    });
    return _fnv1a(input);
  }

  static String forThumbnail({
    required String processedCacheKey,
    required int width,
    required int height,
    required int quality,
  }) {
    final input = jsonEncode({
      'height': height,
      'processedCacheKey': processedCacheKey,
      'quality': quality,
      'width': width,
    });
    return _fnv1a(input);
  }

  static String _fnv1a(String value) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
