import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:project_atlas/core/router/route_paths.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/auth/domain/entities/auth_user.dart';
import 'package:project_atlas/features/auth/domain/entities/sign_up_result.dart';
import 'package:project_atlas/features/auth/domain/repositories/auth_repository.dart';
import 'package:project_atlas/features/auth/domain/usecases/sign_up.dart';
import 'package:project_atlas/features/auth/presentation/providers/auth_providers.dart';
import 'package:project_atlas/features/auth/presentation/screens/signup_screen.dart';
import 'package:project_atlas/l10n/app_localizations.dart';

class _DelayedAuthRepository implements AuthRepository {
  int callCount = 0;

  @override
  Future<Result<SignUpResult>> signUp({
    required String email,
    required String password,
  }) async {
    callCount += 1;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return Success(
      SignUpResult(
        user: AuthUser(id: 'user-1', email: email),
        status: SignUpStatus.emailConfirmationRequired,
      ),
    );
  }
}

void main() {
  group('SignupScreen', () {
    testWidgets('shows validation errors and blocks invalid submit', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('it'),
            home: const SignupScreen(),
          ),
        ),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Registrati'));
      await tester.pump();

      expect(find.text('Inserisci l\'email'), findsOneWidget);
      expect(find.text('Inserisci la password'), findsOneWidget);
    });

    testWidgets('double tap triggers only one signUp request while loading', (
      tester,
    ) async {
      final repository = _DelayedAuthRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            signUpUseCaseProvider.overrideWithValue(SignUp(repository)),
            authSessionProvider.overrideWith((ref) => Stream.value(null)),
            isAuthenticatedProvider.overrideWithValue(false),
          ],
          child: MaterialApp.router(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('it'),
            routerConfig: GoRouter(
              routes: [
                GoRoute(
                  path: RoutePaths.signup,
                  builder: (context, state) => const SignupScreen(),
                ),
                GoRoute(
                  path: RoutePaths.checkEmail,
                  builder: (context, state) =>
                      const Scaffold(body: Text('Check email')),
                ),
              ],
              initialLocation: RoutePaths.signup,
            ),
          ),
        ),
      );

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'user@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'password123');
      await tester.enterText(find.byType(TextFormField).at(2), 'password123');

      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      expect(repository.callCount, 1);
    });
  });
}
