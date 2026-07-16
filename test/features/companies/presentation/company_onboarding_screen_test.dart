import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:project_atlas/core/errors/failures.dart';
import 'package:project_atlas/core/permissions/company_role.dart';
import 'package:project_atlas/core/router/route_guards.dart';
import 'package:project_atlas/core/router/route_paths.dart';
import 'package:project_atlas/core/router/user_companies_route_state.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/auth/presentation/providers/auth_providers.dart';
import 'package:project_atlas/features/companies/domain/entities/company.dart';
import 'package:project_atlas/features/companies/domain/entities/company_membership.dart';
import 'package:project_atlas/features/companies/domain/repositories/company_repository.dart';
import 'package:project_atlas/features/companies/domain/usecases/create_company.dart';
import 'package:project_atlas/features/companies/presentation/controllers/active_company_resolution_coordinator.dart';
import 'package:project_atlas/features/companies/presentation/providers/company_providers.dart';
import 'package:project_atlas/features/companies/presentation/screens/company_onboarding_screen.dart';
import 'package:project_atlas/l10n/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../test_helpers/shared_preferences_test_helper.dart';

const _duplicateSlugMessage = 'Questo slug è già in uso. Scegline un altro.';

class _DelayedCreateCompanyRepository implements CompanyRepository {
  int callCount = 0;

  @override
  Future<Result<Company>> createCompany({
    required String name,
    required String slug,
  }) async {
    callCount += 1;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return Success(
      Company(
        id: 'company-1',
        name: name,
        slug: slug,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
  }

  @override
  Future<Result<List<CompanyMembership>>> getUserCompanies() =>
      throw UnimplementedError();

  @override
  Future<Result<Company>> updateCompany({
    required String companyId,
    required String name,
    required String slug,
  }) => throw UnimplementedError();
}

class _DuplicateSlugRepository implements CompanyRepository {
  int callCount = 0;

  @override
  Future<Result<Company>> createCompany({
    required String name,
    required String slug,
  }) async {
    callCount += 1;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return const Error(ValidationFailure(_duplicateSlugMessage));
  }

  @override
  Future<Result<List<CompanyMembership>>> getUserCompanies() =>
      throw UnimplementedError();

  @override
  Future<Result<Company>> updateCompany({
    required String companyId,
    required String name,
    required String slug,
  }) => throw UnimplementedError();
}

class _SuccessCreateCompanyRepository implements CompanyRepository {
  int callCount = 0;

  @override
  Future<Result<Company>> createCompany({
    required String name,
    required String slug,
  }) async {
    callCount += 1;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return Success(
      Company(
        id: 'company-1',
        name: name,
        slug: slug,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
  }

  @override
  Future<Result<List<CompanyMembership>>> getUserCompanies() =>
      throw UnimplementedError();

  @override
  Future<Result<Company>> updateCompany({
    required String companyId,
    required String name,
    required String slug,
  }) => throw UnimplementedError();
}

CompanyMembership _membershipFor(Company company) {
  return CompanyMembership(
    id: 'membership-1',
    companyId: company.id,
    role: CompanyRole.owner,
    joinedAt: DateTime.utc(2026, 1, 1),
    company: company,
  );
}

Session _testSession({String userId = 'user-1'}) {
  return Session(
    accessToken: 'token',
    tokenType: 'bearer',
    user: User(
      id: userId,
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: DateTime.utc(2026).toIso8601String(),
    ),
  );
}

Future<void> _pumpOnboardingScreen(
  WidgetTester tester, {
  required List<Override> overrides,
  bool enableRedirect = false,
}) async {
  if (enableRedirect) {
    late ProviderContainer container;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container = ProviderContainer(overrides: overrides),
        child: Consumer(
          builder: (context, ref, _) {
            ref.watch(activeCompanyResolutionCoordinatorProvider);
            final router = GoRouter(
              initialLocation: RoutePaths.onboardingCompany,
              refreshListenable: ref.watch(goRouterAuthRefreshProvider),
              redirect: (context, state) {
                return resolveAuthRedirect(
                  location: state.matchedLocation,
                  isAuthenticated: ref.read(isAuthenticatedProvider),
                  isPasswordRecoveryActive: ref.read(
                    isPasswordRecoveryActiveProvider,
                  ),
                  companiesState: ref.read(userCompaniesRouteStateProvider),
                );
              },
              routes: [
                GoRoute(
                  path: RoutePaths.onboardingCompany,
                  builder: (context, state) => const CompanyOnboardingScreen(),
                ),
                GoRoute(
                  path: RoutePaths.dashboard,
                  builder: (context, state) =>
                      const Scaffold(body: Text('Dashboard')),
                ),
              ],
            );

            return MaterialApp.router(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('it'),
              routerConfig: router,
            );
          },
        ),
      ),
    );
    addTearDown(container.dispose);
  } else {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('it'),
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: RoutePaths.onboardingCompany,
                builder: (context, state) => const CompanyOnboardingScreen(),
              ),
              GoRoute(
                path: RoutePaths.dashboard,
                builder: (context, state) =>
                    const Scaffold(body: Text('Dashboard')),
              ),
            ],
            initialLocation: RoutePaths.onboardingCompany,
          ),
        ),
      ),
    );
  }
  await tester.pumpAndSettle();
}

Future<void> _fillAndSubmitCompanyForm(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).at(0), 'Acme Corp');
  await tester.enterText(find.byType(TextFormField).at(1), 'acme-corp');
  await tester.tap(find.byType(FilledButton));
}

void main() {
  setUp(() async {
    await setUpMockSharedPreferences();
  });

  group('CompanyOnboardingScreen', () {
    testWidgets(
      'double tap triggers only one createCompany request while loading',
      (tester) async {
        final repository = _DelayedCreateCompanyRepository();

        await _pumpOnboardingScreen(
          tester,
          overrides: [
            createCompanyUseCaseProvider.overrideWithValue(
              CreateCompany(repository),
            ),
            authSessionProvider.overrideWithValue(null),
            isAuthenticatedProvider.overrideWithValue(true),
            isPasswordRecoveryActiveProvider.overrideWithValue(false),
            userCompaniesProvider.overrideWith((ref) async => []),
            userCompaniesRouteStateProvider.overrideWithValue(
              const UserCompaniesEmpty(),
            ),
          ],
        );

        await _fillAndSubmitCompanyForm(tester);
        await tester.pump();
        await tester.tap(find.byType(FilledButton));
        await tester.pump();

        await tester.pumpAndSettle(const Duration(milliseconds: 300));

        expect(repository.callCount, 1);
      },
    );

    testWidgets('single tap with duplicate slug shows error immediately', (
      tester,
    ) async {
      final repository = _DuplicateSlugRepository();

      await _pumpOnboardingScreen(
        tester,
        overrides: [
          createCompanyUseCaseProvider.overrideWithValue(
            CreateCompany(repository),
          ),
          authSessionProvider.overrideWithValue(null),
          isAuthenticatedProvider.overrideWithValue(true),
          isPasswordRecoveryActiveProvider.overrideWithValue(false),
          userCompaniesProvider.overrideWith((ref) async => []),
          userCompaniesRouteStateProvider.overrideWithValue(
            const UserCompaniesEmpty(),
          ),
        ],
      );

      await _fillAndSubmitCompanyForm(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(repository.callCount, 1);
      expect(find.text(_duplicateSlugMessage), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets(
      'single tap with valid slug creates company and navigates to dashboard',
      (tester) async {
        final repository = _SuccessCreateCompanyRepository();
        final company = Company(
          id: 'company-1',
          name: 'Acme Corp',
          slug: 'acme-corp',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        );

        var membershipLoadCount = 0;

        await _pumpOnboardingScreen(
          tester,
          enableRedirect: true,
          overrides: [
            createCompanyUseCaseProvider.overrideWithValue(
              CreateCompany(repository),
            ),
            authSessionProvider.overrideWithValue(_testSession()),
            isAuthenticatedProvider.overrideWithValue(true),
            isPasswordRecoveryActiveProvider.overrideWithValue(false),
            userCompaniesProvider.overrideWith((ref) async {
              if (!ref.watch(isAuthenticatedProvider)) {
                return [];
              }
              membershipLoadCount += 1;
              if (membershipLoadCount == 1) {
                return [];
              }
              return [_membershipFor(company)];
            }),
          ],
        );

        await _fillAndSubmitCompanyForm(tester);
        await tester.pumpAndSettle();

        expect(repository.callCount, 1);
        expect(find.text('Dashboard'), findsOneWidget);
      },
    );

    testWidgets(
      'membership refresh failure shows error and stops loading spinner',
      (tester) async {
        const refreshErrorMessage =
            'Caricamento aziende non riuscito. Riprova.';
        final repository = _SuccessCreateCompanyRepository();

        await _pumpOnboardingScreen(
          tester,
          overrides: [
            createCompanyUseCaseProvider.overrideWithValue(
              CreateCompany(repository),
            ),
            authSessionProvider.overrideWithValue(null),
            isAuthenticatedProvider.overrideWithValue(true),
            isPasswordRecoveryActiveProvider.overrideWithValue(false),
            userCompaniesProvider.overrideWith(
              (ref) async => throw StateError(refreshErrorMessage),
            ),
            userCompaniesRouteStateProvider.overrideWithValue(
              const UserCompaniesEmpty(),
            ),
          ],
        );

        await _fillAndSubmitCompanyForm(tester);
        await tester.pumpAndSettle();

        expect(repository.callCount, 1);
        expect(find.text(refreshErrorMessage), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );
  });
}
