/// Persistenza locale dell'azienda attiva per utente.
abstract class ActiveCompanyRepository {
  Future<String?> getPersistedCompanyId(String userId);

  Future<void> persistActiveCompanyId({
    required String userId,
    required String companyId,
  });

  Future<void> clearPersistedCompanyId(String userId);
}
