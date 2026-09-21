import '../../../../core/utils/result.dart';
import '../repositories/company_members_repository.dart';

class RevokeCompanyInvite {
  const RevokeCompanyInvite(this._repository);

  final CompanyMembersRepository _repository;

  Future<Result<void>> call(String inviteId) {
    return _repository.revokeInvite(inviteId);
  }
}
