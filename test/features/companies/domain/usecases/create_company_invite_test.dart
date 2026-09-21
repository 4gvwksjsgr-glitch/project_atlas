import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/permissions/company_role.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/companies/domain/entities/company_invite.dart';
import 'package:project_atlas/features/companies/domain/entities/company_member.dart';
import 'package:project_atlas/features/companies/domain/entities/create_invite_result.dart';
import 'package:project_atlas/features/companies/domain/repositories/company_members_repository.dart';
import 'package:project_atlas/features/companies/domain/usecases/create_company_invite.dart';

class _MembersRepositorySpy implements CompanyMembersRepository {
  String? lastCompanyId;
  String? lastEmail;
  CompanyRole? lastRole;
  int? lastExpiresInHours;

  @override
  Future<Result<CreateInviteResult>> createInvite(
    String companyId,
    String email,
    CompanyRole role, {
    int? expiresInHours,
  }) async {
    lastCompanyId = companyId;
    lastEmail = email;
    lastRole = role;
    lastExpiresInHours = expiresInHours;
    return Success(
      CreateInviteResult(
        inviteId: 'invite-1',
        emailNormalized: email.trim().toLowerCase(),
        role: role,
        expiresAt: DateTime.utc(2026, 10, 1),
        inviteToken: 'token-once',
      ),
    );
  }

  @override
  Future<Result<void>> acceptInvite(String token) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> changeMemberRole(
    String companyId,
    String userId,
    CompanyRole role,
  ) => throw UnimplementedError();

  @override
  Future<Result<List<CompanyInvite>>> listInvites(String companyId) =>
      throw UnimplementedError();

  @override
  Future<Result<List<CompanyMember>>> listMembers(String companyId) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> removeMember(String companyId, String userId) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> revokeInvite(String inviteId) =>
      throw UnimplementedError();
}

void main() {
  group('CreateCompanyInvite', () {
    test('trimma email prima del repository', () async {
      final repository = _MembersRepositorySpy();
      final useCase = CreateCompanyInvite(repository);

      await useCase.call(
        companyId: 'company-1',
        email: '  User@Example.com  ',
        role: CompanyRole.manager,
        expiresInHours: 48,
      );

      expect(repository.lastCompanyId, 'company-1');
      expect(repository.lastEmail, 'User@Example.com');
      expect(repository.lastRole, CompanyRole.manager);
      expect(repository.lastExpiresInHours, 48);
    });
  });
}
