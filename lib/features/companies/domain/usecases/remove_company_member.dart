import '../../../../core/utils/result.dart';
import '../repositories/company_members_repository.dart';

class RemoveCompanyMember {
  const RemoveCompanyMember(this._repository);

  final CompanyMembersRepository _repository;

  Future<Result<void>> call({
    required String companyId,
    required String userId,
  }) {
    return _repository.removeMember(companyId, userId);
  }
}
