import 'auth_redirect_config.dart';
import 'route_paths.dart';

/// Risolve il redirect auth con priorità alla sessione di recovery password.
String? resolveAuthRedirect({
  required String location,
  required bool isAuthenticated,
  required bool isPasswordRecoveryActive,
}) {
  if (isPasswordRecoveryActive) {
    if (location != RoutePaths.updatePassword) {
      return RoutePaths.updatePassword;
    }
    return null;
  }

  if (!isPasswordRecoveryActive && location == RoutePaths.updatePassword) {
    return RoutePaths.login;
  }

  if (!isAuthenticated && AuthRedirectConfig.isProtectedRoute(location)) {
    return RoutePaths.login;
  }

  if (isAuthenticated && AuthRedirectConfig.isRestrictedAuthRoute(location)) {
    return RoutePaths.onboardingCompany;
  }

  if (isAuthenticated && location == RoutePaths.checkEmail) {
    return RoutePaths.onboardingCompany;
  }

  return null;
}
