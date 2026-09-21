import '../../../../core/permissions/company_role.dart';
import '../../../../core/utils/result.dart';
import '../repositories/company_members_repository.dart';

class ChangeCompanyMemberRole {
  const ChangeCompanyMemberRole(this._repository);

  final CompanyMembersRepository _repository;

  Future<Result<void>> call({
    required String companyId,
    required String userId,
    required CompanyRole role,
  }) {
    return _repository.changeMemberRole(companyId, userId, role);
  }
}
