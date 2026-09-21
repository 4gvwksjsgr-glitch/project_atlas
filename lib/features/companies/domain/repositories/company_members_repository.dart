import '../../../../core/permissions/company_role.dart';
import '../../../../core/utils/result.dart';
import '../entities/company_invite.dart';
import '../entities/company_member.dart';
import '../entities/create_invite_result.dart';

abstract class CompanyMembersRepository {
  Future<Result<List<CompanyMember>>> listMembers(String companyId);

  Future<Result<List<CompanyInvite>>> listInvites(String companyId);

  Future<Result<CreateInviteResult>> createInvite(
    String companyId,
    String email,
    CompanyRole role, {
    int? expiresInHours,
  });

  Future<Result<void>> revokeInvite(String inviteId);

  Future<Result<void>> acceptInvite(String token);

  Future<Result<void>> changeMemberRole(
    String companyId,
    String userId,
    CompanyRole role,
  );

  Future<Result<void>> removeMember(String companyId, String userId);
}
