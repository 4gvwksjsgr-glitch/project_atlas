import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:project_atlas/core/permissions/company_role.dart';
import 'package:project_atlas/core/router/route_paths.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/companies/domain/entities/company_invite.dart';
import 'package:project_atlas/features/companies/domain/entities/company_member.dart';
import 'package:project_atlas/features/companies/domain/entities/create_invite_result.dart';
import 'package:project_atlas/features/companies/domain/repositories/company_members_repository.dart';
import 'package:project_atlas/features/companies/domain/usecases/accept_company_invite.dart';
import 'package:project_atlas/features/companies/presentation/providers/company_providers.dart';
import 'package:project_atlas/features/companies/presentation/screens/accept_invite_screen.dart';
import 'package:project_atlas/l10n/app_localizations.dart';

import '../../../../test_helpers/shared_preferences_test_helper.dart';

class _SuccessAcceptInviteRepository implements CompanyMembersRepository {
  @override
  Future<Result<void>> acceptInvite(String token) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
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

  testWidgets('successful accept navigates to dashboard', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          acceptCompanyInviteUseCaseProvider.overrideWithValue(
            AcceptCompanyInvite(_SuccessAcceptInviteRepository()),
          ),
          userCompaniesProvider.overrideWith((ref) async => []),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('it'),
          routerConfig: GoRouter(
            initialLocation: RoutePaths.acceptInvite,
            routes: [
              GoRoute(
                path: RoutePaths.acceptInvite,
                builder: (context, state) => const AcceptInviteScreen(),
              ),
              GoRoute(
                path: RoutePaths.dashboard,
                builder: (context, state) =>
                    const Scaffold(body: Text('Dashboard')),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'invite-token');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsOneWidget);
  });
}
