import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:project_atlas/core/router/route_paths.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/auth/domain/entities/auth_user.dart';
import 'package:project_atlas/features/auth/domain/entities/sign_up_result.dart';
import 'package:project_atlas/features/auth/domain/repositories/auth_repository.dart';
import 'package:project_atlas/features/auth/domain/usecases/reset_password.dart';
import 'package:project_atlas/features/auth/presentation/providers/auth_providers.dart';
import 'package:project_atlas/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:project_atlas/l10n/app_localizations.dart';

class _DelayedResetPasswordRepository implements AuthRepository {
  int callCount = 0;

  @override
  Future<Result<void>> resetPassword({required String email}) async {
    callCount += 1;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return const Success(null);
  }

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
  Future<Result<void>> signOut() => throw UnimplementedError();

  @override
  Future<Result<void>> updatePassword({required String password}) =>
      throw UnimplementedError();

  @override
  Future<Result<AuthUser?>> getCurrentSession() => throw UnimplementedError();
}

void main() {
  group('ForgotPasswordScreen', () {
    testWidgets(
      'double tap triggers only one resetPassword request while loading',
      (tester) async {
        final repository = _DelayedResetPasswordRepository();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              resetPasswordUseCaseProvider.overrideWithValue(
                ResetPassword(repository),
              ),
              authSessionProvider.overrideWithValue(null),
              isAuthenticatedProvider.overrideWithValue(false),
              isPasswordRecoveryActiveProvider.overrideWithValue(false),
            ],
            child: MaterialApp.router(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('it'),
              routerConfig: GoRouter(
                routes: [
                  GoRoute(
                    path: RoutePaths.forgotPassword,
                    builder: (context, state) => const ForgotPasswordScreen(),
                  ),
                  GoRoute(
                    path: RoutePaths.login,
                    builder: (context, state) =>
                        const Scaffold(body: Text('Login')),
                  ),
                ],
                initialLocation: RoutePaths.forgotPassword,
              ),
            ),
          ),
        );

        await tester.enterText(find.byType(TextFormField), 'user@example.com');

        await tester.tap(find.byType(FilledButton));
        await tester.pump();
        await tester.tap(find.byType(FilledButton));
        await tester.pump();

        await tester.pumpAndSettle(const Duration(milliseconds: 300));

        expect(repository.callCount, 1);
      },
    );
  });
}
