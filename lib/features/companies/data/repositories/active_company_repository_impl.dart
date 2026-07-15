import '../../domain/repositories/active_company_repository.dart';
import '../datasource/active_company_local_datasource.dart';

class ActiveCompanyRepositoryImpl implements ActiveCompanyRepository {
  const ActiveCompanyRepositoryImpl(this._localDataSource);

  final ActiveCompanyLocalDataSource _localDataSource;

  @override
  Future<String?> getPersistedCompanyId(String userId) async {
    return _localDataSource.getPersistedCompanyId(userId);
  }

  @override
  Future<void> persistActiveCompanyId({
    required String userId,
    required String companyId,
  }) async {
    await _localDataSource.persistActiveCompanyId(
      userId: userId,
      companyId: companyId,
    );
  }

  @override
  Future<void> clearPersistedCompanyId(String userId) async {
    await _localDataSource.clearPersistedCompanyId(userId);
  }
}
