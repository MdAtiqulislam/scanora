import '../errors/app_failure.dart';

sealed class Result<T> {
  const Result();

  bool get isSuccess => this is Success<T>;

  T? get valueOrNull => switch (this) {
    Success<T>(:final value) => value,
    Failure<T>() => null,
  };
}

final class Success<T> extends Result<T> {
  final T value;

  const Success(this.value);
}

final class Failure<T> extends Result<T> {
  final AppFailure error;

  const Failure(this.error);
}
