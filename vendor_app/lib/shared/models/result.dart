sealed class Result<T> {
  const Result();
}

final class Success<T> extends Result<T> {
  const Success(this.data);
  final T data;
}

final class Failure<T> extends Result<T> {
  const Failure(this.error, {this.stackTrace});
  final Object error;
  final StackTrace? stackTrace;
}

extension ResultX<T> on Result<T> {
  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Failure<T>;

  T? get dataOrNull => switch (this) {
        Success<T>(data: final d) => d,
        Failure<T>() => null,
      };

  Object? get errorOrNull => switch (this) {
        Success<T>() => null,
        Failure<T>(error: final e) => e,
      };
}
