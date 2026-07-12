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
