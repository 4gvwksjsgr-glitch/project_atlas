import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:project_atlas/core/router/route_paths.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/auth/domain/entities/auth_user.dart';
import 'package:project_atlas/features/auth/domain/entities/sign_up_result.dart';
import 'package:project_atlas/features/auth/domain/repositories/auth_repository.dart';
import 'package:project_atlas/features/auth/domain/usecases/sign_out.dart';
import 'package:project_atlas/features/auth/domain/usecases/update_password.dart';
import 'package:project_atlas/features/auth/presentation/providers/auth_providers.dart';
import 'package:project_atlas/features/auth/presentation/screens/update_password_screen.dart';
import 'package:project_atlas/l10n/app_localizations.dart';

class _DelayedUpdatePasswordRepository implements AuthRepository {
  int updateCallCount = 0;

  @override
  Future<Result<void>> updatePassword({required String password}) async {
    updateCallCount += 1;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return const Success(null);
  }

  @override
  Future<Result<void>> signOut() async => const Success(null);

  @override
  Future<Result<SignUpResult>> signUp({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<Result<AuthUser>> signIn({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<Result<void>> resetPassword({required String email}) =>
      throw UnimplementedError();

  @override
  Future<Result<AuthUser?>> getCurrentSession() => throw UnimplementedError();
}

void main() {
  group('UpdatePasswordScreen', () {
    testWidgets(
      'double tap triggers only one updatePassword request while loading',
      (tester) async {
        final repository = _DelayedUpdatePasswordRepository();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              updatePasswordUseCaseProvider.overrideWithValue(
                UpdatePassword(repository),
              ),
              signOutUseCaseProvider.overrideWithValue(SignOut(repository)),
              authSessionProvider.overrideWithValue(null),
              isAuthenticatedProvider.overrideWithValue(false),
              isPasswordRecoveryActiveProvider.overrideWithValue(true),
            ],
            child: MaterialApp.router(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('it'),
              routerConfig: GoRouter(
                routes: [
                  GoRoute(
                    path: RoutePaths.updatePassword,
                    builder: (context, state) => const UpdatePasswordScreen(),
                  ),
                  GoRoute(
                    path: RoutePaths.login,
                    builder: (context, state) =>
                        const Scaffold(body: Text('Login')),
                  ),
                ],
                initialLocation: RoutePaths.updatePassword,
              ),
            ),
          ),
        );

        await tester.enterText(
          find.byType(TextFormField).at(0),
          'newpassword123',
        );
        await tester.enterText(
          find.byType(TextFormField).at(1),
          'newpassword123',
        );

        await tester.tap(find.byType(FilledButton));
        await tester.pump();
        await tester.tap(find.byType(FilledButton));
        await tester.pump();

        await tester.pumpAndSettle(const Duration(milliseconds: 300));

        expect(repository.updateCallCount, 1);
      },
    );
  });
}
