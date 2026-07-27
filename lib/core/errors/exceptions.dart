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

/// Storage DELETE no-op: risposta vuota ma oggetto ancora presente.
final class DocumentStorageDeleteNoOpException extends AppException {
  const DocumentStorageDeleteNoOpException([
    super.message = 'Non è stato possibile eliminare il file.',
  ]);
}

/// Metadata DELETE no-op / permesso insufficiente.
final class DocumentMetadataDeleteNoOpException extends AppException {
  const DocumentMetadataDeleteNoOpException([
    super.message = 'Non hai i permessi per eliminare questo documento.',
  ]);
}
