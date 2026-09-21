import '../../core/result/result.dart';
import '../processing/processing_models.dart';
import '../value_objects/page_corners.dart';
import '../value_objects/page_edit_state.dart';

typedef MarkCacheCurrentCallback = Future<Result<void>> Function({
  required String pageId,
  required String processedCacheKey,
  required String thumbnailCacheKey,
  required String expectedRawAssetIdentity,
  required PageEditState expectedEditState,
});

abstract interface class ProcessingEngine {
  Future<Result<ProcessingResult>> process(ProcessingRequest request);

  Future<Result<List<int>>> renderPreview({
    required List<int> sourceBytes,
    required PageCorners corners,
    int quarterTurns = 0,
  });
}
