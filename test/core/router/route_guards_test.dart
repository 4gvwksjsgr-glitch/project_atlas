import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/router/route_guards.dart';
import 'package:project_atlas/core/router/route_paths.dart';

void main() {
  group('resolveAuthRedirect', () {
    test('recovery attiva ha priorità e reindirizza a update password', () {
      expect(
        resolveAuthRedirect(
          location: RoutePaths.onboardingCompany,
          isAuthenticated: true,
          isPasswordRecoveryActive: true,
        ),
        RoutePaths.updatePassword,
      );
    });

    test('recovery attiva non reindirizza se già su update password', () {
      expect(
        resolveAuthRedirect(
          location: RoutePaths.updatePassword,
          isAuthenticated: true,
          isPasswordRecoveryActive: true,
        ),
        isNull,
      );
    });

    test('recovery attiva blocca redirect verso onboarding da login', () {
      expect(
        resolveAuthRedirect(
          location: RoutePaths.login,
          isAuthenticated: true,
          isPasswordRecoveryActive: true,
        ),
        RoutePaths.updatePassword,
      );
    });

    test('update password senza recovery reindirizza al login', () {
      expect(
        resolveAuthRedirect(
          location: RoutePaths.updatePassword,
          isAuthenticated: false,
          isPasswordRecoveryActive: false,
        ),
        RoutePaths.login,
      );
    });

    test('utente autenticato su login va a onboarding', () {
      expect(
        resolveAuthRedirect(
          location: RoutePaths.login,
          isAuthenticated: true,
          isPasswordRecoveryActive: false,
        ),
        RoutePaths.onboardingCompany,
      );
    });

    test('utente non autenticato su dashboard va al login', () {
      expect(
        resolveAuthRedirect(
          location: RoutePaths.dashboard,
          isAuthenticated: false,
          isPasswordRecoveryActive: false,
        ),
        RoutePaths.login,
      );
    });
  });
}
