import '../../../../core/utils/result.dart';
import '../entities/company_invite.dart';
import '../repositories/company_members_repository.dart';

class ListCompanyInvites {
  const ListCompanyInvites(this._repository);

  final CompanyMembersRepository _repository;

  Future<Result<List<CompanyInvite>>> call(String companyId) {
    return _repository.listInvites(companyId);
  }
}
