import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/permissions/company_role.dart';
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

  group('Logout relogin flow', () {
    test(
      'clearRuntime non lascia route state bloccato dopo logout/login',
      () async {
        final authEvents = StreamController<AuthStateSnapshot>.broadcast();
        final testAuthSessionProvider = StateProvider<Session?>(
          (ref) => _testSession(),
        );

        final container = ProviderContainer(
          overrides: [
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
        addTearDown(() async {
          await authEvents.close();
          container.dispose();
        });

        authEvents.add(AuthStateSnapshot(session: _testSession()));
        container.read(activeCompanyResolutionCoordinatorProvider);
        container.listen(activeCompanyControllerProvider, (_, _) {});

        await container.read(userCompaniesProvider.future);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        container.read(activeCompanyControllerProvider.notifier).clearRuntime();
        container.read(testAuthSessionProvider.notifier).state = null;
        authEvents.add(const AuthStateSnapshot(session: null));
        await Future<void>.delayed(const Duration(milliseconds: 20));

        container.read(testAuthSessionProvider.notifier).state = _testSession();
        authEvents.add(AuthStateSnapshot(session: _testSession()));
        await container.read(userCompaniesProvider.future);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          container.read(userCompaniesRouteStateProvider),
          isA<UserCompaniesReady>(),
        );
        expect(container.read(activeCompanyProvider)?.companyId, 'c1');
      },
    );

    test(
      'logout e relogin ripristinano azienda persistita senza loading permanente',
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

        authEvents.add(AuthStateSnapshot(session: session));
        container.read(activeCompanyResolutionCoordinatorProvider);
        container.listen(activeCompanyControllerProvider, (_, _) {});

        await container.read(userCompaniesProvider.future);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          container.read(userCompaniesRouteStateProvider),
          isA<UserCompaniesReady>(),
        );
        expect(container.read(activeCompanyProvider)?.companyId, 'c1');

        await container.read(authControllerProvider.notifier).signOut();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(container.read(authControllerProvider).isLoading, isFalse);
        expect(container.read(isAuthenticatedProvider), isFalse);
        expect(container.read(activeCompanyProvider), isNull);

        await container
            .read(authControllerProvider.notifier)
            .signIn(email: 'user@example.com', password: 'password123');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        container.read(authControllerProvider.notifier).resetActionState();
        await container.read(userCompaniesProvider.future);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(container.read(authControllerProvider).isLoading, isFalse);
        expect(container.read(isAuthenticatedProvider), isTrue);
        expect(
          container.read(userCompaniesRouteStateProvider),
          isA<UserCompaniesReady>(),
        );
        expect(container.read(activeCompanyProvider)?.companyId, 'c1');
        expect(
          appSharedPreferences!.getString(
            ActiveCompanyLocalDataSource.storageKeyForUser(userId),
          ),
          'c1',
        );
      },
    );
  });
}
