import '../../../../core/utils/result.dart';
import '../entities/company_member.dart';
import '../repositories/company_members_repository.dart';

class ListCompanyMembers {
  const ListCompanyMembers(this._repository);

  final CompanyMembersRepository _repository;

  Future<Result<List<CompanyMember>>> call(String companyId) {
    return _repository.listMembers(companyId);
  }
}
