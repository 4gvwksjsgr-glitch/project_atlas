/// Normalizzazione e validazione del nome categoria operativa.
abstract final class CategoryName {
  static const int maxLength = 80;

  /// Trim; stringa vuota se solo spazi.
  static String normalize(String raw) => raw.trim();

  /// Messaggio di errore IT, oppure `null` se valido.
  static String? validationError(String normalized) {
    if (normalized.isEmpty) {
      return 'Il nome della categoria è obbligatorio.';
    }
    if (normalized.length > maxLength) {
      return 'Il nome della categoria non può superare i $maxLength caratteri.';
    }
    return null;
  }
}
