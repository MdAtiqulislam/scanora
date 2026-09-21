import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:scanora/app/core/result/result.dart';
import 'package:scanora/app/domain/geometry/geometry_models.dart';
import 'package:scanora/app/domain/value_objects/point.dart';
import 'package:scanora/app/infrastructure/processing/plain_geometry_engine.dart';

void main() {
  const engine = PlainGeometryEngine();
  final rectangle = [
    const Point2D(0, 0),
    const Point2D(1, 0),
    const Point2D(1, 1),
    const Point2D(0, 1),
  ];

  test('identity geometry is finite and maps image dimensions', () {
    final corners = engine.canonicalize(rectangle).valueOrNull!;
    final result = engine.calculate(
      corners: corners,
      sourceSize: const PixelSize(1920, 1080),
    );
    expect(result, isA<Success<GeometryResult>>());
    final geometry = (result as Success<GeometryResult>).value;
    expect(geometry.destinationSize.width, 1920);
    expect(geometry.destinationSize.height, 1080);
    expect(geometry.transform.isFinite, isTrue);
  });

  test('canonicalizes major point permutations deterministically', () {
    final permutations = [
      [rectangle[2], rectangle[0], rectangle[3], rectangle[1]],
      [rectangle[1], rectangle[3], rectangle[0], rectangle[2]],
      [rectangle[3], rectangle[2], rectangle[1], rectangle[0]],
    ];
    for (final permutation in permutations) {
      final result = engine.canonicalize(permutation);
      expect(result.valueOrNull!.points, rectangle);
    }
  });

  test('mild and strong perspective produce finite positive geometry', () {
    for (final points in [
      [
        const Point2D(0.1, 0.1),
        const Point2D(0.9, 0.08),
        const Point2D(0.95, 0.92),
        const Point2D(0.05, 0.9),
      ],
      [
        const Point2D(0.3, 0.1),
        const Point2D(0.95, 0.2),
        const Point2D(0.8, 0.95),
        const Point2D(0.05, 0.8),
      ],
    ]) {
      final corners = engine.canonicalize(points).valueOrNull!;
      final geometry =
          (engine.calculate(
                    corners: corners,
                    sourceSize: const PixelSize(4000, 3000),
                  )
                  as Success<GeometryResult>)
              .value;
      expect(geometry.destinationSize.isValid, isTrue);
      expect(
        geometry.transform.coefficients.every((value) => value.isFinite),
        isTrue,
      );
    }
  });

  test('rotation metadata is normalized without changing source assets', () {
    final corners = engine.canonicalize(rectangle).valueOrNull!;
    for (final rotation in [0, 90, 180, 270, -90]) {
      final result = engine.calculate(
        corners: corners,
        sourceSize: const PixelSize(100, 200),
        rotationDegrees: rotation,
      );
      expect(result, isA<Success<GeometryResult>>());
    }
  });

  test('invalid geometry returns typed failures', () {
    final cases = [
      [
        const Point2D(0, 0),
        const Point2D(0, 0),
        const Point2D(1, 1),
        const Point2D(0, 1),
      ],
      [
        const Point2D(0, 0),
        const Point2D(1, 0),
        const Point2D(0.2, 0.2),
        const Point2D(0, 1),
      ],
      [
        const Point2D(0, 0),
        const Point2D(0.000000001, 0),
        const Point2D(0.000000001, 0.000000001),
        const Point2D(0, 0.000000001),
      ],
    ];
    for (final points in cases) {
      final corners = engine.canonicalize(points);
      if (corners case Success()) {
        expect(
          engine.calculate(
            corners: (corners as Success).value,
            sourceSize: const PixelSize(100, 100),
          ),
          isA<Failure>(),
        );
      } else {
        expect(corners, isA<Failure>());
      }
    }
  });

  test('determinism and dimensions reflect edge geometry', () {
    final corners =
        engine.canonicalize([
          const Point2D(0.1, 0.1),
          const Point2D(0.8, 0.1),
          const Point2D(0.9, 0.9),
          const Point2D(0.05, 0.9),
        ]).valueOrNull!;
    final first =
        (engine.calculate(
                  corners: corners,
                  sourceSize: const PixelSize(1000, 1000),
                )
                as Success<GeometryResult>)
            .value;
    final second =
        (engine.calculate(
                  corners: corners,
                  sourceSize: const PixelSize(1000, 1000),
                )
                as Success<GeometryResult>)
            .value;
    expect(
      first.destinationSize.width,
      greaterThan(first.destinationSize.height),
    );
    expect(first.transform.coefficients, second.transform.coefficients);
    expect(
      math.min(first.destinationSize.width, first.destinationSize.height),
      greaterThan(0),
    );
  });
}
