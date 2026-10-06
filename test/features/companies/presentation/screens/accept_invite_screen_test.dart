import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:project_atlas/core/permissions/company_role.dart';
import 'package:project_atlas/core/router/route_paths.dart';
import 'package:project_atlas/core/router/user_companies_route_state.dart';
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

final _testCompaniesRouteStateProvider = StateProvider<UserCompaniesRouteState>(
  (ref) => const UserCompaniesLoading(),
);

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

Future<ProviderContainer> _pumpAcceptInviteScreen(
  WidgetTester tester, {
  required UserCompaniesRouteState initialRouteState,
}) async {
  final container = ProviderContainer(
    overrides: [
      acceptCompanyInviteUseCaseProvider.overrideWithValue(
        AcceptCompanyInvite(_SuccessAcceptInviteRepository()),
      ),
      userCompaniesProvider.overrideWith((ref) async => []),
      _testCompaniesRouteStateProvider.overrideWith((ref) => initialRouteState),
      userCompaniesRouteStateProvider.overrideWith(
        (ref) => ref.watch(_testCompaniesRouteStateProvider),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
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
            GoRoute(
              path: RoutePaths.selectCompany,
              builder: (context, state) =>
                  const Scaffold(body: Text('Company Selector')),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _submitInvite(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField), 'invite-token');
  await tester.tap(find.byType(FilledButton));
  // Advance past accept RPC delay without fully settling navigation.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 30));
}

void main() {
  setUp(() async {
    await setUpMockSharedPreferences();
  });

  group('AcceptInviteScreen post-accept navigation', () {
    testWidgets('success while Loading stays on AcceptInviteScreen', (
      tester,
    ) async {
      await _pumpAcceptInviteScreen(
        tester,
        initialRouteState: const UserCompaniesLoading(),
      );

      await _submitInvite(tester);
      await tester.pump();

      expect(find.byType(AcceptInviteScreen), findsOneWidget);
      expect(find.text('Dashboard'), findsNothing);
      expect(find.text('Company Selector'), findsNothing);
    });

    testWidgets('Loading then Ready navigates to Dashboard', (tester) async {
      final container = await _pumpAcceptInviteScreen(
        tester,
        initialRouteState: const UserCompaniesLoading(),
      );

      await _submitInvite(tester);
      await tester.pump();

      expect(find.byType(AcceptInviteScreen), findsOneWidget);

      container.read(_testCompaniesRouteStateProvider.notifier).state =
          const UserCompaniesReady();
      await tester.pumpAndSettle();

      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.byType(AcceptInviteScreen), findsNothing);
    });

    testWidgets('success when already Ready navigates to Dashboard', (
      tester,
    ) async {
      await _pumpAcceptInviteScreen(
        tester,
        initialRouteState: const UserCompaniesReady(),
      );

      await _submitInvite(tester);
      await tester.pumpAndSettle();

      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.byType(AcceptInviteScreen), findsNothing);
    });

    testWidgets('success then NeedsSelection navigates to Company Selector', (
      tester,
    ) async {
      final container = await _pumpAcceptInviteScreen(
        tester,
        initialRouteState: const UserCompaniesLoading(),
      );

      await _submitInvite(tester);
      await tester.pump();

      expect(find.byType(AcceptInviteScreen), findsOneWidget);

      container.read(_testCompaniesRouteStateProvider.notifier).state =
          const UserCompaniesNeedsSelection();
      await tester.pumpAndSettle();

      expect(find.text('Company Selector'), findsOneWidget);
      expect(find.text('Dashboard'), findsNothing);
      expect(find.byType(AcceptInviteScreen), findsNothing);
    });

    testWidgets('Loading does not navigate to selector or dashboard', (
      tester,
    ) async {
      await _pumpAcceptInviteScreen(
        tester,
        initialRouteState: const UserCompaniesLoading(),
      );

      await _submitInvite(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(AcceptInviteScreen), findsOneWidget);
      expect(find.text('Dashboard'), findsNothing);
      expect(find.text('Company Selector'), findsNothing);
    });
  });
}
