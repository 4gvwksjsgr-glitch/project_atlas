import '../entities/active_company_context.dart';
import '../entities/company_membership.dart';
import '../repositories/active_company_repository.dart';
import 'resolve_initial_active_company.dart';

class SelectActiveCompany {
  const SelectActiveCompany(this._repository);

  final ActiveCompanyRepository _repository;

  Future<ActiveCompanyContext> call({
    required String userId,
    required CompanyMembership membership,
  }) async {
    await _repository.persistActiveCompanyId(
      userId: userId,
      companyId: membership.companyId,
    );
    return activeCompanyContextFromMembership(membership);
  }
}
