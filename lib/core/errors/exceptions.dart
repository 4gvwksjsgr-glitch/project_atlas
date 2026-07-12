/// Eccezione generica del data layer.
sealed class AppException implements Exception {
  const AppException(this.message);

  final String message;
}

final class AuthException extends AppException {
  const AuthException(super.message, {this.code});

  final String? code;
}

final class NetworkException extends AppException {
  const NetworkException([super.message = 'Errore di rete']);
}
