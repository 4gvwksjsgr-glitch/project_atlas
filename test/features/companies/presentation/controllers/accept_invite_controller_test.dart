import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/permissions/company_role.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/companies/domain/entities/active_company_context.dart';
import 'package:project_atlas/features/companies/domain/entities/company_invite.dart';
import 'package:project_atlas/features/companies/domain/entities/company_member.dart';
import 'package:project_atlas/features/companies/domain/entities/create_invite_result.dart';
import 'package:project_atlas/features/companies/domain/repositories/company_members_repository.dart';
import 'package:project_atlas/features/companies/domain/usecases/accept_company_invite.dart';
import 'package:project_atlas/features/companies/presentation/controllers/accept_invite_controller.dart';
import 'package:project_atlas/features/companies/presentation/controllers/active_company_controller.dart';
import 'package:project_atlas/features/companies/presentation/controllers/company_onboarding_controller.dart';
import 'package:project_atlas/features/companies/presentation/providers/company_providers.dart';

import '../../../../test_helpers/shared_preferences_test_helper.dart';

class _SuccessAcceptInviteRepository implements CompanyMembersRepository {
  int acceptCount = 0;

  @override
  Future<Result<void>> acceptInvite(String token) async {
    acceptCount += 1;
    return const Success(null);
  }

  @override
  Future<Result<CreateInviteResult>> createInvite(
    String companyId,
    String email,
    CompanyRole role, {
    int? expiresInHours,
  }) => throw UnimplementedError();

  @override
  Future<Result<List<CompanyInvite>>> listInvites(String companyId) =>
      throw UnimplementedError();

  @override
  Future<Result<List<CompanyMember>>> listMembers(String companyId) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> revokeInvite(String inviteId) =>
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
}

void main() {
  setUp(() async {
    await setUpMockSharedPreferences();
  });

  group('AcceptInviteController', () {
    test(
      'success without active company marks resolving then refreshes then success',
      () async {
        final repository = _SuccessAcceptInviteRepository();
        var membershipLoadCount = 0;
        var resolvedFalseWhenSuccessExposed = false;

        final container = ProviderContainer(
          overrides: [
            acceptCompanyInviteUseCaseProvider.overrideWithValue(
              AcceptCompanyInvite(repository),
            ),
            userCompaniesProvider.overrideWith((ref) async {
              membershipLoadCount += 1;
              return [];
            }),
          ],
        );
        addTearDown(container.dispose);

        // Simulate resolved-empty runtime so markResolving is observable.
        container.read(activeCompanyControllerProvider.notifier).clearRuntime();
        expect(container.read(activeCompanyProvider), isNull);
        expect(container.read(activeCompanyResolvedProvider), isTrue);

        container.listen(acceptInviteControllerProvider, (previous, next) {
          if (next.isSuccess && previous?.isSuccess != true) {
            resolvedFalseWhenSuccessExposed = !container
                .read(activeCompanyResolvedProvider);
          }
        });

        await container
            .read(acceptInviteControllerProvider.notifier)
            .accept('invite-token');

        final inviteState = container.read(acceptInviteControllerProvider);
        expect(inviteState.actionStatus, CompanyActionStatus.success);
        expect(repository.acceptCount, 1);

        final activeState = container.read(activeCompanyControllerProvider);
        expect(activeState.context, isNull);
        expect(activeState.resolved, isFalse);
        expect(membershipLoadCount, greaterThanOrEqualTo(1));
        expect(resolvedFalseWhenSuccessExposed, isTrue);
      },
    );

    test(
      'success with active company does not clear resolved active context',
      () async {
        final repository = _SuccessAcceptInviteRepository();

        final container = ProviderContainer(
          overrides: [
            acceptCompanyInviteUseCaseProvider.overrideWithValue(
              AcceptCompanyInvite(repository),
            ),
            userCompaniesProvider.overrideWith((ref) async => []),
          ],
        );
        addTearDown(container.dispose);

        container
            .read(activeCompanyControllerProvider.notifier)
            .applyResolution(
              context: const ActiveCompanyContext(
                companyId: 'company-1',
                companyName: 'Acme',
                companySlug: 'acme',
                role: CompanyRole.owner,
                membershipId: 'membership-1',
              ),
              resolved: true,
            );

        container.listen(acceptInviteControllerProvider, (_, _) {});

        await container
            .read(acceptInviteControllerProvider.notifier)
            .accept('invite-token');

        final inviteState = container.read(acceptInviteControllerProvider);
        expect(inviteState.actionStatus, CompanyActionStatus.success);

        final activeState = container.read(activeCompanyControllerProvider);
        expect(activeState.resolved, isTrue);
        expect(activeState.context?.companyId, 'company-1');
      },
    );
  });
}
