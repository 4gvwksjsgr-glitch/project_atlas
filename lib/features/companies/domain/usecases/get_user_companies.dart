import '../../../../core/utils/result.dart';
import '../entities/company_membership.dart';
import '../repositories/company_repository.dart';

class GetUserCompanies {
  const GetUserCompanies(this._repository);

  final CompanyRepository _repository;

  Future<Result<List<CompanyMembership>>> call() {
    return _repository.getUserCompanies();
  }
}
