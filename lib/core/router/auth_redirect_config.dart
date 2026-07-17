import 'route_paths.dart';

/// Configurazione centralizzata delle rotte usate dai guard auth.
abstract final class AuthRedirectConfig {
  static const publicAuthRoutes = {
    RoutePaths.login,
    RoutePaths.signup,
    RoutePaths.forgotPassword,
    RoutePaths.checkEmail,
    RoutePaths.updatePassword,
  };

  static const restrictedAuthRoutes = {
    RoutePaths.login,
    RoutePaths.signup,
    RoutePaths.forgotPassword,
  };

  static const protectedRoutes = {
    RoutePaths.dashboard,
    RoutePaths.clients,
    RoutePaths.transactions,
    RoutePaths.settingsCompany,
    RoutePaths.onboardingCompany,
    RoutePaths.selectCompany,
  };

  static bool isPublicAuthRoute(String location) {
    return publicAuthRoutes.contains(location);
  }

  static bool isRestrictedAuthRoute(String location) {
    return restrictedAuthRoutes.contains(location);
  }

  /// Dashboard, Clienti, Movimenti (e sottorotte) e Impostazioni.
  static bool isTenantShellRoute(String location) {
    return location == RoutePaths.dashboard ||
        location == RoutePaths.settingsCompany ||
        location == RoutePaths.clients ||
        location.startsWith('${RoutePaths.clients}/') ||
        location == RoutePaths.transactions ||
        location.startsWith('${RoutePaths.transactions}/');
  }

  static bool isProtectedRoute(String location) {
    return protectedRoutes.contains(location) ||
        location.startsWith('${RoutePaths.clients}/') ||
        location.startsWith('${RoutePaths.transactions}/');
  }
}
