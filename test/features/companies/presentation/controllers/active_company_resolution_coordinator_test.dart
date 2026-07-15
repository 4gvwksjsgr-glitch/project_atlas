import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/permissions/company_role.dart';
import 'package:project_atlas/core/router/route_guards.dart';
import 'package:project_atlas/core/router/route_paths.dart';
import 'package:project_atlas/core/router/user_companies_route_state.dart';
import 'package:project_atlas/core/storage/app_shared_preferences.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/auth/domain/entities/auth_user.dart';
import 'package:project_atlas/features/auth/domain/entities/sign_up_result.dart';
import 'package:project_atlas/features/auth/domain/repositories/auth_repository.dart';
import 'package:project_atlas/features/auth/domain/usecases/sign_in.dart';
import 'package:project_atlas/features/auth/domain/usecases/sign_out.dart';
import 'package:project_atlas/features/auth/presentation/controllers/auth_controller.dart';
import 'package:project_atlas/features/auth/presentation/providers/auth_providers.dart';
import 'package:project_atlas/features/companies/data/datasource/active_company_local_datasource.dart';
import 'package:project_atlas/features/companies/domain/entities/company.dart';
import 'package:project_atlas/features/companies/domain/entities/company_membership.dart';
import 'package:project_atlas/features/companies/presentation/controllers/active_company_controller.dart';
import 'package:project_atlas/features/companies/presentation/controllers/active_company_resolution_coordinator.dart';
import 'package:project_atlas/features/companies/presentation/providers/company_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../../../../test_helpers/shared_preferences_test_helper.dart';

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

class _AuthRepositoryStub implements AuthRepository {
  _AuthRepositoryStub({required this.onSignIn, required this.onSignOut});

  final Future<void> Function() onSignIn;
  final Future<void> Function() onSignOut;

  @override
  Future<Result<AuthUser>> signIn({
    required String email,
    required String password,
  }) async {
    await onSignIn();
    return const Success(AuthUser(id: 'user-1', email: 'user@example.com'));
  }

  @override
  Future<Result<void>> signOut() async {
    await onSignOut();
    return const Success(null);
  }

  @override
  Future<Result<SignUpResult>> signUp({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<Result<void>> resetPassword({required String email}) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> updatePassword({required String password}) =>
      throw UnimplementedError();

  @override
  Future<Result<AuthUser?>> getCurrentSession() => throw UnimplementedError();
}

class _ContainerHolder {
  ProviderContainer? value;
}

void main() {
  setUp(() async {
    await setUpMockSharedPreferences();
  });

  group('ActiveCompanyResolutionCoordinator', () {
    test(
      'regressione relogin: nessuna mutazione provider durante init route state',
      () async {
        const userId = 'user-1';
        final session = _testSession(userId: userId);
        final authEvents = StreamController<AuthStateSnapshot>.broadcast();
        final testAuthSessionProvider = StateProvider<Session?>(
          (ref) => session,
        );
        final containerHolder = _ContainerHolder();

        await ActiveCompanyLocalDataSource(
          appSharedPreferences!,
        ).persistActiveCompanyId(userId: userId, companyId: 'c1');

        late final ProviderContainer container;
        container = ProviderContainer(
          overrides: [
            signInUseCaseProvider.overrideWithValue(
              SignIn(
                _AuthRepositoryStub(
                  onSignIn: () async {
                    containerHolder.value!
                            .read(testAuthSessionProvider.notifier)
                            .state =
                        session;
                    authEvents.add(AuthStateSnapshot(session: session));
                  },
                  onSignOut: () async {},
                ),
              ),
            ),
            signOutUseCaseProvider.overrideWithValue(
              SignOut(
                _AuthRepositoryStub(
                  onSignIn: () async {},
                  onSignOut: () async {
                    containerHolder.value!
                            .read(testAuthSessionProvider.notifier)
                            .state =
                        null;
                    authEvents.add(const AuthStateSnapshot(session: null));
                  },
                ),
              ),
            ),
            authStateChangesProvider.overrideWith((ref) => authEvents.stream),
            authSessionProvider.overrideWith(
              (ref) => ref.watch(testAuthSessionProvider),
            ),
            isAuthenticatedProvider.overrideWith(
              (ref) => ref.watch(testAuthSessionProvider) != null,
            ),
            userCompaniesProvider.overrideWith((ref) async {
              if (!ref.watch(isAuthenticatedProvider)) {
                return <CompanyMembership>[];
              }
              await Future<void>.delayed(const Duration(milliseconds: 20));
              return [_membership()];
            }),
          ],
        );
        containerHolder.value = container;
        addTearDown(() async {
          await authEvents.close();
          container.dispose();
        });

        container.read(activeCompanyResolutionCoordinatorProvider);
        authEvents.add(AuthStateSnapshot(session: session));

        await container.read(userCompaniesProvider.future);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          container.read(userCompaniesRouteStateProvider),
          isA<UserCompaniesReady>(),
        );
        expect(container.read(activeCompanyProvider)?.companyId, 'c1');

        await container.read(authControllerProvider.notifier).signOut();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(container.read(isAuthenticatedProvider), isFalse);
        expect(container.read(activeCompanyProvider), isNull);

        final signInFuture = container
            .read(authControllerProvider.notifier)
            .signIn(email: 'user@example.com', password: 'password123');

        expect(() {
          container.read(isAuthenticatedProvider);
          container.read(userCompaniesRouteStateProvider);
          container.read(activeCompanyProvider);
        }, returnsNormally);

        await signInFuture;
        container.read(authControllerProvider.notifier).resetActionState();

        expect(
          () => container.read(userCompaniesRouteStateProvider),
          returnsNormally,
        );

        await container.read(userCompaniesProvider.future);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final routeState = container.read(userCompaniesRouteStateProvider);
        expect(routeState, isA<UserCompaniesReady>());
        expect(container.read(activeCompanyProvider)?.companyId, 'c1');
        expect(
          resolveAuthRedirect(
            location: RoutePaths.login,
            isAuthenticated: true,
            isPasswordRecoveryActive: false,
            companiesState: routeState,
          ),
          RoutePaths.dashboard,
        );
      },
    );
  });
}
