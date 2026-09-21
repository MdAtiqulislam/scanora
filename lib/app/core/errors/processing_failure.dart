import 'app_failure.dart';

class ProcessingInputFailure extends ProcessingFailure {
  const ProcessingInputFailure(super.message, {super.cause, super.stackTrace});
}

class ProcessingCancelledFailure extends ProcessingFailure {
  const ProcessingCancelledFailure([String message = 'Processing cancelled'])
    : super(message);
}

class UnsupportedProcessingProfileFailure extends ProcessingFailure {
  const UnsupportedProcessingProfileFailure(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}

class ProcessingStageFailure extends ProcessingFailure {
  const ProcessingStageFailure(super.message, {super.cause, super.stackTrace});
}

class ProcessingEncodingFailure extends ProcessingFailure {
  const ProcessingEncodingFailure(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}

class ProcessingPersistenceFailure extends ProcessingFailure {
  const ProcessingPersistenceFailure(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}
