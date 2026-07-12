import '../errors/failures.dart';

/// Risultato di un'operazione che può avere successo o fallire.
sealed class Result<T> {
  const Result();

  bool get isSuccess => this is Success<T>;
  bool get isError => this is Error<T>;

  R when<R>({
    required R Function(T value) success,
    required R Function(Failure failure) error,
  }) {
    return switch (this) {
      Success<T>(:final value) => success(value),
      Error<T>(:final failure) => error(failure),
    };
  }
}

final class Success<T> extends Result<T> {
  const Success(this.value);

  final T value;
}

final class Error<T> extends Result<T> {
  const Error(this.failure);

  final Failure failure;
}
