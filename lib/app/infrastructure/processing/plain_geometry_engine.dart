import 'dart:math' as math;

import '../../core/errors/geometry_failure.dart';
import '../../core/result/result.dart';
import '../../domain/contracts/geometry_engine.dart';
import '../../domain/geometry/geometry_models.dart';
import '../../domain/value_objects/page_corners.dart';
import '../../domain/value_objects/point.dart';

class GeometryTolerances {
  static const coordinate = 1e-9;
  static const area = 1e-8;
  static const edge = 1e-7;
  static const determinant = 1e-12;
  static const coefficient = 1e12;
}

class PlainGeometryEngine implements GeometryEngine {
  const PlainGeometryEngine();

  @override
  Result<PageCorners> canonicalize(Iterable<Point2D> input) {
    try {
      final points = input.toList(growable: false);
      if (points.length != 4) {
        throw const InvalidGeometryFailure('Exactly four corners are required');
      }
      if (points.any((point) => !_finite(point))) {
        throw const InvalidGeometryFailure(
          'Corner contains a non-finite value',
        );
      }
      final topLeft = points.reduce((a, b) => _sum(a) < _sum(b) ? a : b);
      final bottomRight = points.reduce((a, b) => _sum(a) > _sum(b) ? a : b);
      final remaining =
          points
              .where((point) => point != topLeft && point != bottomRight)
              .toList();
      if (remaining.length != 2) {
        throw const InvalidGeometryFailure('Corners are ambiguous');
      }
      final topRight = remaining.reduce(
        (a, b) => _difference(a) < _difference(b) ? a : b,
      );
      final bottomLeft =
          remaining.first == topRight ? remaining.last : remaining.first;
      final rotated = [topLeft, topRight, bottomRight, bottomLeft];
      return Success(
        PageCorners(
          topLeft: rotated[0],
          topRight: rotated[1],
          bottomRight: rotated[2],
          bottomLeft: rotated[3],
        ),
      );
    } catch (error, stackTrace) {
      return Failure(
        error is InvalidGeometryFailure
            ? error
            : InvalidGeometryFailure(
              'Unable to order corners',
              cause: error,
              stackTrace: stackTrace,
            ),
      );
    }
  }

  @override
  Result<GeometryResult> calculate({
    required PageCorners corners,
    required PixelSize sourceSize,
    int rotationDegrees = 0,
  }) {
    try {
      if (!sourceSize.isValid) {
        throw const InvalidGeometryFailure(
          'Source dimensions must be positive',
        );
      }
      final normalized = _rotateCorners(corners, rotationDegrees);
      _validate(normalized);
      final pixel = PixelQuad(
        topLeft: _scale(normalized.topLeft, sourceSize),
        topRight: _scale(normalized.topRight, sourceSize),
        bottomRight: _scale(normalized.bottomRight, sourceSize),
        bottomLeft: _scale(normalized.bottomLeft, sourceSize),
      );
      final width = math.max(
        _distance(pixel.topLeft, pixel.topRight),
        _distance(pixel.bottomLeft, pixel.bottomRight),
      );
      final height = math.max(
        _distance(pixel.topLeft, pixel.bottomLeft),
        _distance(pixel.topRight, pixel.bottomRight),
      );
      final destination = PixelSize(
        width.round().clamp(1, 1 << 31),
        height.round().clamp(1, 1 << 31),
      );
      final transform = _homography(pixel.points, [
        const Point2D(0, 0),
        Point2D(destination.width.toDouble(), 0),
        Point2D(destination.width.toDouble(), destination.height.toDouble()),
        Point2D(0, destination.height.toDouble()),
      ]);
      return Success(
        GeometryResult(
          corners: normalized,
          pixelCorners: pixel,
          destinationSize: destination,
          transform: transform,
        ),
      );
    } catch (error, stackTrace) {
      return Failure(
        error is InvalidGeometryFailure
            ? error
            : PerspectiveTransformFailure(
              'Unable to calculate geometry',
              cause: error,
              stackTrace: stackTrace,
            ),
      );
    }
  }

  static void _validate(PageCorners quad) {
    final points = quad.points;
    final signs = <double>[];
    for (var i = 0; i < 4; i++) {
      final a = points[i];
      final b = points[(i + 1) % 4];
      final c = points[(i + 2) % 4];
      final cross = _cross(a, b, c);
      if (cross.abs() <= GeometryTolerances.edge) {
        throw const DegenerateQuadrilateralFailure('Quad edge is degenerate');
      }
      signs.add(cross);
    }
    if (signs.any((value) => value.sign != signs.first.sign)) {
      throw const InvalidGeometryFailure(
        'Quadrilateral must be convex and ordered',
      );
    }
    if (_signedArea(points).abs() <= GeometryTolerances.area) {
      throw const DegenerateQuadrilateralFailure(
        'Quadrilateral area is too small',
      );
    }
    if (_segmentsIntersect(points[0], points[1], points[2], points[3]) ||
        _segmentsIntersect(points[1], points[2], points[3], points[0])) {
      throw const InvalidGeometryFailure('Quadrilateral edges self-intersect');
    }
  }

  static PerspectiveTransform _homography(
    List<Point2D> source,
    List<Point2D> destination,
  ) {
    final matrix = <List<double>>[];
    final values = <double>[];
    for (var i = 0; i < 4; i++) {
      final x = source[i].x,
          y = source[i].y,
          u = destination[i].x,
          v = destination[i].y;
      matrix.add([x, y, 1, 0, 0, 0, -u * x, -u * y]);
      values.add(u);
      matrix.add([0, 0, 0, x, y, 1, -v * x, -v * y]);
      values.add(v);
    }
    final solution = _solve(matrix, values);
    final result = [...solution, 1.0];
    if (result.any(
      (value) =>
          !value.isFinite || value.abs() > GeometryTolerances.coefficient,
    )) {
      throw const PerspectiveTransformFailure(
        'Unstable homography coefficients',
      );
    }
    return PerspectiveTransform(result);
  }

  static List<double> _solve(List<List<double>> matrix, List<double> values) {
    final a = [
      for (var i = 0; i < 8; i++) [...matrix[i], values[i]],
    ];
    for (var column = 0; column < 8; column++) {
      var pivot = column;
      for (var row = column + 1; row < 8; row++) {
        if (a[row][column].abs() > a[pivot][column].abs()) pivot = row;
      }
      if (a[pivot][column].abs() <= GeometryTolerances.determinant) {
        throw const PerspectiveTransformFailure(
          'Homography system is singular',
        );
      }
      final temp = a[column];
      a[column] = a[pivot];
      a[pivot] = temp;
      final divisor = a[column][column];
      for (var j = column; j <= 8; j++) {
        a[column][j] /= divisor;
      }
      for (var row = 0; row < 8; row++) {
        if (row == column) continue;
        final factor = a[row][column];
        for (var j = column; j <= 8; j++) {
          a[row][j] -= factor * a[column][j];
        }
      }
    }
    return [for (var i = 0; i < 8; i++) a[i][8]];
  }

  static PageCorners _rotateCorners(PageCorners corners, int degrees) {
    final turns = ((degrees % 360) + 360) % 360;
    if (turns == 0) return corners;
    Point2D rotate(Point2D p) => switch (turns) {
      90 => Point2D(1 - p.y, p.x),
      180 => Point2D(1 - p.x, 1 - p.y),
      270 => Point2D(p.y, 1 - p.x),
      _ => p,
    };
    final points = corners.points.map(rotate).toList();
    return PageCorners(
      topLeft: points[0],
      topRight: points[1],
      bottomRight: points[2],
      bottomLeft: points[3],
    );
  }

  static Point2D _scale(Point2D point, PixelSize size) =>
      Point2D(point.x * size.width, point.y * size.height);
  static double _distance(Point2D a, Point2D b) =>
      math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
  static double _cross(Point2D a, Point2D b, Point2D c) =>
      (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
  static double _signedArea(List<Point2D> points) =>
      0.5 *
      List.generate(
        4,
        (i) =>
            points[i].x * points[(i + 1) % 4].y -
            points[(i + 1) % 4].x * points[i].y,
      ).reduce((a, b) => a + b);
  static bool _finite(Point2D p) => p.x.isFinite && p.y.isFinite;
  static double _sum(Point2D point) => point.x + point.y;
  static double _difference(Point2D point) => point.y - point.x;
  static bool _segmentsIntersect(Point2D a, Point2D b, Point2D c, Point2D d) =>
      _cross(a, b, c) * _cross(a, b, d) < 0 &&
      _cross(c, d, a) * _cross(c, d, b) < 0;
}
