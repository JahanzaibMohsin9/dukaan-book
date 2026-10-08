sealed class AppError {
  const AppError(this.message, {this.cause});

  final String message;
  final Object? cause;
}

class ValidationError extends AppError {
  const ValidationError(super.message, {super.cause});
}

class StorageError extends AppError {
  const StorageError(super.message, {super.cause});
}

class NetworkError extends AppError {
  const NetworkError(super.message, {super.cause});
}

sealed class AppResult<T> {
  const AppResult();
}

class AppSuccess<T> extends AppResult<T> {
  const AppSuccess(this.value);

  final T value;
}

class AppFailure<T> extends AppResult<T> {
  const AppFailure(this.error);

  final AppError error;
}
