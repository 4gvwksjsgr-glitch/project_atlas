import '../../../../core/permissions/company_role.dart';
import '../../../../core/utils/result.dart';
import '../entities/create_invite_result.dart';
import '../repositories/company_members_repository.dart';

class CreateCompanyInvite {
  const CreateCompanyInvite(this._repository);

  final CompanyMembersRepository _repository;

  Future<Result<CreateInviteResult>> call({
    required String companyId,
    required String email,
    required CompanyRole role,
    int? expiresInHours,
  }) {
    return _repository.createInvite(
      companyId,
      email.trim(),
      role,
      expiresInHours: expiresInHours,
    );
  }
}
