import '../../core/errors/app_failure.dart';
import 'point.dart';

class PageCorners {
  final Point2D topLeft;
  final Point2D topRight;
  final Point2D bottomRight;
  final Point2D bottomLeft;

  PageCorners({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  }) {
    _validate();
  }

  void _validate() {
    final points = [topLeft, topRight, bottomRight, bottomLeft];
    if (points.any(
      (point) =>
          !point.x.isFinite ||
          !point.y.isFinite ||
          point.x < 0 ||
          point.x > 1 ||
          point.y < 0 ||
          point.y > 1,
    )) {
      throw const ValidationFailure('Page corners must contain finite points');
    }
    if (topLeft == topRight ||
        topRight == bottomRight ||
        bottomRight == bottomLeft ||
        bottomLeft == topLeft) {
      throw const ValidationFailure('Page corners must be distinct');
    }
    final area =
        0.5 *
        ((topLeft.x * topRight.y +
                    topRight.x * bottomRight.y +
                    bottomRight.x * bottomLeft.y +
                    bottomLeft.x * topLeft.y) -
                (topLeft.y * topRight.x +
                    topRight.y * bottomRight.x +
                    bottomRight.y * bottomLeft.x +
                    bottomLeft.y * topLeft.x))
            .abs();
    if (area <= 0) {
      throw const ValidationFailure(
        'Page corners must form a non-degenerate quad',
      );
    }
  }

  List<Point2D> get points => [topLeft, topRight, bottomRight, bottomLeft];

  Map<String, dynamic> toMap() => {
    'topLeft': topLeft.toMap(),
    'topRight': topRight.toMap(),
    'bottomRight': bottomRight.toMap(),
    'bottomLeft': bottomLeft.toMap(),
  };

  factory PageCorners.fromMap(Map<String, dynamic> map) => PageCorners(
    topLeft: Point2D.fromMap(map['topLeft'] as Map<String, dynamic>),
    topRight: Point2D.fromMap(map['topRight'] as Map<String, dynamic>),
    bottomRight: Point2D.fromMap(map['bottomRight'] as Map<String, dynamic>),
    bottomLeft: Point2D.fromMap(map['bottomLeft'] as Map<String, dynamic>),
  );

  @override
  bool operator ==(Object other) =>
      other is PageCorners &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomRight == bottomRight &&
      other.bottomLeft == bottomLeft;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomRight, bottomLeft);
}
