import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/permissions/company_role.dart';
import 'package:project_atlas/core/router/route_guards.dart';
import 'package:project_atlas/core/router/route_paths.dart';
import 'package:project_atlas/core/router/user_companies_route_state.dart';
import 'package:project_atlas/features/auth/presentation/providers/auth_providers.dart';
import 'package:project_atlas/features/companies/domain/entities/company.dart';
import 'package:project_atlas/features/companies/domain/entities/company_membership.dart';
import 'package:project_atlas/features/companies/presentation/controllers/active_company_resolution_coordinator.dart';
import 'package:project_atlas/features/companies/presentation/providers/company_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../test_helpers/shared_preferences_test_helper.dart';

CompanyMembership _membership() {
  return CompanyMembership(
    id: 'membership-c1',
    companyId: 'c1',
    role: CompanyRole.owner,
    joinedAt: DateTime.utc(2026, 1, 1),
    company: Company(
      id: 'c1',
      name: 'Acme',
      slug: 'acme',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
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

void main() {
  setUp(() async {
    await setUpMockSharedPreferences();
  });

  group('Login redirect flow', () {
    test(
      'goRouterAuthRefresh notifica al cambio di authSessionProvider',
      () async {
        final testAuthSessionProvider = StateProvider<Session?>((ref) => null);
        final container = ProviderContainer(
          overrides: [
            authSessionProvider.overrideWith(
              (ref) => ref.watch(testAuthSessionProvider),
            ),
          ],
        );
        addTearDown(container.dispose);

        final refresh = container.read(goRouterAuthRefreshProvider);
        var notifications = 0;
        refresh.addListener(() => notifications++);

        container.read(authSessionProvider);
        container.read(testAuthSessionProvider.notifier).state = _testSession();
        container.read(authSessionProvider);
        await Future<void>.delayed(Duration.zero);

        expect(notifications, greaterThanOrEqualTo(1));
      },
    );

    test(
      'secondo refresh dopo risoluzione azienda produce redirect a /dashboard',
      () async {
        final session = _testSession();
        final testAuthSessionProvider = StateProvider<Session?>((ref) => null);

        final container = ProviderContainer(
          overrides: [
            authSessionProvider.overrideWith(
              (ref) => ref.watch(testAuthSessionProvider),
            ),
            isAuthenticatedProvider.overrideWith(
              (ref) => ref.watch(testAuthSessionProvider) != null,
            ),
            isPasswordRecoveryActiveProvider.overrideWithValue(false),
            userCompaniesProvider.overrideWith((ref) async {
              if (!ref.watch(isAuthenticatedProvider)) {
                return <CompanyMembership>[];
              }
              await Future<void>.delayed(const Duration(milliseconds: 20));
              return [_membership()];
            }),
          ],
        );
        addTearDown(container.dispose);

        container.read(activeCompanyResolutionCoordinatorProvider);
        final refresh = container.read(goRouterAuthRefreshProvider);
        var refreshCount = 0;
        refresh.addListener(() => refreshCount++);

        expect(
          resolveAuthRedirect(
            location: RoutePaths.login,
            isAuthenticated: false,
            isPasswordRecoveryActive: false,
            companiesState: const UserCompaniesEmpty(),
          ),
          isNull,
        );

        container.read(testAuthSessionProvider.notifier).state = session;
        container.invalidate(authSessionProvider);
        await Future<void>.delayed(Duration.zero);

        expect(container.read(isAuthenticatedProvider), isTrue);
        final loadingState = container.read(userCompaniesRouteStateProvider);
        expect(loadingState, isA<UserCompaniesLoading>());
        expect(
          resolveAuthRedirect(
            location: RoutePaths.login,
            isAuthenticated: true,
            isPasswordRecoveryActive: false,
            companiesState: loadingState,
          ),
          isNull,
        );
        final refreshAfterAuth = refreshCount;

        await container.read(userCompaniesProvider.future);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await Future<void>.delayed(Duration.zero);

        final readyState = container.read(userCompaniesRouteStateProvider);
        expect(readyState, isA<UserCompaniesReady>());
        expect(refreshCount, greaterThan(refreshAfterAuth));
        expect(
          resolveAuthRedirect(
            location: RoutePaths.login,
            isAuthenticated: true,
            isPasswordRecoveryActive: false,
            companiesState: readyState,
          ),
          RoutePaths.dashboard,
        );
      },
    );
  });
}
