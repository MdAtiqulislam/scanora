import '../value_objects/page_corners.dart';
import '../value_objects/point.dart';

class PixelSize {
  final int width;
  final int height;

  const PixelSize(this.width, this.height);

  bool get isValid => width > 0 && height > 0;
}

class PixelQuad {
  final Point2D topLeft;
  final Point2D topRight;
  final Point2D bottomRight;
  final Point2D bottomLeft;

  const PixelQuad({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  List<Point2D> get points => [topLeft, topRight, bottomRight, bottomLeft];
}

class PerspectiveTransform {
  final List<double> coefficients;

  const PerspectiveTransform(this.coefficients)
    : assert(coefficients.length == 9);

  bool get isFinite => coefficients.every((value) => value.isFinite);
}

class GeometryResult {
  final PageCorners corners;
  final PixelQuad pixelCorners;
  final PixelSize destinationSize;
  final PerspectiveTransform transform;

  const GeometryResult({
    required this.corners,
    required this.pixelCorners,
    required this.destinationSize,
    required this.transform,
  });
}
