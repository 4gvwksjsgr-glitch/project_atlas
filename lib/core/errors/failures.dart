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

final class SubscriptionNotFoundFailure extends Failure {
  const SubscriptionNotFoundFailure([
    super.message =
        'Non è stato possibile trovare l\'abbonamento dell\'azienda.',
  ]);
}

final class SubscriptionPlanNotFoundFailure extends Failure {
  const SubscriptionPlanNotFoundFailure([
    super.message = 'Il piano associato all\'azienda non è disponibile.',
  ]);
}

final class DocumentQuotaExceededFailure extends Failure {
  const DocumentQuotaExceededFailure([
    super.message = 'Hai raggiunto il limite di documenti del mese.',
  ]);
}

/// Quota rifiutata dal DB e cleanup Storage non riuscito / no-op.
final class DocumentQuotaExceededCleanupFailedFailure extends Failure {
  const DocumentQuotaExceededCleanupFailedFailure([
    super.message =
        'Hai raggiunto il limite di documenti del mese. '
        'Il file caricato non è stato rimosso completamente. Riprova.',
  ]);
}

final class AtlasCompanyIdRequiredFailure extends Failure {
  const AtlasCompanyIdRequiredFailure([
    super.message = 'Non è stata selezionata un\'azienda valida.',
  ]);
}

final class AtlasNotCompanyOwnerFailure extends Failure {
  const AtlasNotCompanyOwnerFailure([
    super.message = 'Solo il proprietario può attivare la prova Premium.',
  ]);
}

final class AtlasTrialAlreadyActiveFailure extends Failure {
  const AtlasTrialAlreadyActiveFailure([
    super.message = 'La prova Premium è già attiva.',
  ]);
}

final class AtlasAlreadyPremiumFailure extends Failure {
  const AtlasAlreadyPremiumFailure([
    super.message = 'L\'azienda utilizza già il piano Premium.',
  ]);
}

final class AtlasTrialAlreadyUsedFailure extends Failure {
  const AtlasTrialAlreadyUsedFailure([
    super.message = 'La prova Premium è già stata utilizzata.',
  ]);
}

final class AtlasPremiumUnavailableFailure extends Failure {
  const AtlasPremiumUnavailableFailure([
    super.message = 'La prova Premium non è disponibile in questo momento.',
  ]);
}

final class AtlasBillingLinkedFailure extends Failure {
  const AtlasBillingLinkedFailure([
    super.message =
        'La prova Premium non è disponibile perché risulta un collegamento '
        'di fatturazione per questa azienda.',
  ]);
}

final class AtlasBillingSyncPendingFailure extends Failure {
  const AtlasBillingSyncPendingFailure([
    super.message =
        'Sincronizzazione fatturazione in corso. Riprova tra poco.',
  ]);
}
