class Point2D {
  final double x;
  final double y;

  const Point2D(this.x, this.y);

  Map<String, double> toMap() => {'x': x, 'y': y};

  factory Point2D.fromMap(Map<String, dynamic> map) =>
      Point2D((map['x'] as num).toDouble(), (map['y'] as num).toDouble());

  @override
  bool operator ==(Object other) =>
      other is Point2D && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}
