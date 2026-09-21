import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/permissions/company_role.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/companies/domain/entities/active_company_context.dart';
import 'package:project_atlas/features/companies/domain/entities/company_invite.dart';
import 'package:project_atlas/features/companies/domain/entities/company_member.dart';
import 'package:project_atlas/features/companies/domain/entities/create_invite_result.dart';
import 'package:project_atlas/features/companies/domain/repositories/company_members_repository.dart';
import 'package:project_atlas/features/companies/domain/usecases/create_company_invite.dart';
import 'package:project_atlas/features/companies/domain/usecases/list_company_invites.dart';
import 'package:project_atlas/features/companies/domain/usecases/list_company_members.dart';
import 'package:project_atlas/features/companies/presentation/controllers/active_company_controller.dart';
import 'package:project_atlas/features/companies/presentation/controllers/company_onboarding_controller.dart';
import 'package:project_atlas/features/companies/presentation/controllers/company_team_controller.dart';
import 'package:project_atlas/features/companies/presentation/providers/company_providers.dart';

class _TeamRepositoryFake implements CompanyMembersRepository {
  List<CompanyMember> members = [
    CompanyMember(
      membershipId: 'm1',
      userId: 'u1',
      email: 'owner@example.com',
      fullName: 'Owner',
      role: CompanyRole.owner,
      joinedAt: DateTime.utc(2026, 1, 1),
    ),
  ];

  List<CompanyInvite> invites = const [];

  CreateInviteResult? created;
  int listMembersCalls = 0;
  int createCalls = 0;

  @override
  Future<Result<List<CompanyMember>>> listMembers(String companyId) async {
    listMembersCalls += 1;
    return Success(List.unmodifiable(members));
  }

  @override
  Future<Result<List<CompanyInvite>>> listInvites(String companyId) async {
    return Success(List.unmodifiable(invites));
  }

  @override
  Future<Result<CreateInviteResult>> createInvite(
    String companyId,
    String email,
    CompanyRole role, {
    int? expiresInHours,
  }) async {
    createCalls += 1;
    created = CreateInviteResult(
      inviteId: 'invite-1',
      emailNormalized: email.toLowerCase(),
      role: role,
      expiresAt: DateTime.utc(2026, 10, 1),
      inviteToken: 'one-time-token',
    );
    invites = [
      CompanyInvite(
        inviteId: 'invite-1',
        emailNormalized: email.toLowerCase(),
        role: role,
        invitedBy: 'u1',
        createdAt: DateTime.utc(2026, 9, 1),
        expiresAt: DateTime.utc(2026, 10, 1),
        status: CompanyInviteStatus.pending,
      ),
    ];
    return Success(created!);
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
  Future<Result<void>> removeMember(String companyId, String userId) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> revokeInvite(String inviteId) =>
      throw UnimplementedError();
}

ProviderContainer _container(_TeamRepositoryFake repository) {
  final container = ProviderContainer(
    overrides: [
      companyMembersRepositoryProvider.overrideWithValue(repository),
      listCompanyMembersUseCaseProvider.overrideWithValue(
        ListCompanyMembers(repository),
      ),
      listCompanyInvitesUseCaseProvider.overrideWithValue(
        ListCompanyInvites(repository),
      ),
      createCompanyInviteUseCaseProvider.overrideWithValue(
        CreateCompanyInvite(repository),
      ),
    ],
  );

  container.read(activeCompanyControllerProvider.notifier).applyResolution(
        context: const ActiveCompanyContext(
          companyId: 'company-1',
          companyName: 'Acme',
          companySlug: 'acme',
          role: CompanyRole.owner,
          membershipId: 'm1',
        ),
        resolved: true,
      );

  return container;
}

void main() {
  group('CompanyTeamController', () {
    test('load popola members e invites', () async {
      final repository = _TeamRepositoryFake();
      final container = _container(repository);
      addTearDown(container.dispose);

      final notifier = container.read(
        companyTeamControllerProvider('company-1').notifier,
      );
      await notifier.load();

      final state = container.read(companyTeamControllerProvider('company-1'));
      expect(repository.listMembersCalls, 1);
      expect(state.members, hasLength(1));
      expect(state.members.first.email, 'owner@example.com');
      expect(state.actionStatus, CompanyActionStatus.success);
      expect(state.isLoading, isFalse);
    });

    test('createInvite espone lastCreatedInviteToken', () async {
      final repository = _TeamRepositoryFake();
      final container = _container(repository);
      addTearDown(container.dispose);

      final notifier = container.read(
        companyTeamControllerProvider('company-1').notifier,
      );
      await notifier.load();
      await notifier.createInvite(
        email: 'new@example.com',
        role: CompanyRole.employee,
      );

      final state = container.read(companyTeamControllerProvider('company-1'));
      expect(repository.createCalls, 1);
      expect(state.lastCreatedInviteToken, 'one-time-token');
      expect(state.invites, hasLength(1));
      expect(state.actionStatus, CompanyActionStatus.success);
    });
  });
}
