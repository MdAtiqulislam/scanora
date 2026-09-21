import 'app_failure.dart';

class InvalidGeometryFailure extends AppFailure {
  const InvalidGeometryFailure(super.message, {super.cause, super.stackTrace});
}

class DegenerateQuadrilateralFailure extends InvalidGeometryFailure {
  const DegenerateQuadrilateralFailure(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}

class PerspectiveTransformFailure extends InvalidGeometryFailure {
  const PerspectiveTransformFailure(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}
