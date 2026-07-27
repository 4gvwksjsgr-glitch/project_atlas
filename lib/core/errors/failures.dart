/// Errori di dominio/infrastruttura mappati verso la UI.
sealed class Failure {
  const Failure(this.message);

  final String message;
}

final class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Errore di rete. Riprova.']);
}

final class AuthFailure extends Failure {
  const AuthFailure([super.message = 'Errore di autenticazione.']);
}

final class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

final class UnknownFailure extends Failure {
  const UnknownFailure([
    super.message = 'Si è verificato un errore imprevisto.',
  ]);
}

/// Storage eliminato (o già assente) ma metadata ancora presenti.
final class IncompleteDocumentDeletionFailure extends Failure {
  const IncompleteDocumentDeletionFailure([
    super.message =
        'Il file è stato rimosso, ma i dati del documento non sono stati '
        'eliminati. Riprova.',
  ]);
}

/// Storage DELETE no-op: HTTP ok ma oggetto ancora presente.
final class DocumentStorageDeleteNoOpFailure extends Failure {
  const DocumentStorageDeleteNoOpFailure([
    super.message = 'Non è stato possibile eliminare il file.',
  ]);
}

/// Metadata DELETE no-op / permesso insufficiente.
final class DocumentMetadataDeleteNoOpFailure extends Failure {
  const DocumentMetadataDeleteNoOpFailure([
    super.message = 'Non hai i permessi per eliminare questo documento.',
  ]);
}
