import '../../core/result/result.dart';
import '../geometry/geometry_models.dart';
import '../value_objects/page_corners.dart';
import '../value_objects/point.dart';

abstract interface class GeometryEngine {
  Result<GeometryResult> calculate({
    required PageCorners corners,
    required PixelSize sourceSize,
    int rotationDegrees = 0,
  });

  Result<PageCorners> canonicalize(Iterable<Point2D> points);
}
