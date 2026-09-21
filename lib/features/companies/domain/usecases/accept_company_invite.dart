import '../../../../core/utils/result.dart';
import '../repositories/company_members_repository.dart';

class AcceptCompanyInvite {
  const AcceptCompanyInvite(this._repository);

  final CompanyMembersRepository _repository;

  Future<Result<void>> call(String token) {
    return _repository.acceptInvite(token.trim());
  }
}
