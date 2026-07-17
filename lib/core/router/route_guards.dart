import 'auth_redirect_config.dart';
import 'route_paths.dart';
import 'user_companies_route_state.dart';

/// Risolve il redirect auth con priorità alla sessione di recovery password.
String? resolveAuthRedirect({
  required String location,
  required bool isAuthenticated,
  required bool isPasswordRecoveryActive,
  required UserCompaniesRouteState companiesState,
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

  if (!isAuthenticated) {
    return null;
  }

  return switch (companiesState) {
    UserCompaniesLoading() => null,
    UserCompaniesEmpty() => _redirectWithoutCompanies(location),
    UserCompaniesNeedsSelection() => _redirectNeedsSelection(location),
    UserCompaniesReady() => _redirectWithActiveCompany(location),
    UserCompaniesError() => _redirectOnCompaniesError(location),
  };
}

String? _redirectWithoutCompanies(String location) {
  if (AuthRedirectConfig.isTenantShellRoute(location) ||
      location == RoutePaths.selectCompany) {
    return RoutePaths.onboardingCompany;
  }

  if (AuthRedirectConfig.isRestrictedAuthRoute(location)) {
    return RoutePaths.onboardingCompany;
  }

  if (location == RoutePaths.checkEmail) {
    return RoutePaths.onboardingCompany;
  }

  return null;
}

String? _redirectNeedsSelection(String location) {
  if (location == RoutePaths.selectCompany) {
    return null;
  }

  if (AuthRedirectConfig.isTenantShellRoute(location) ||
      location == RoutePaths.onboardingCompany ||
      AuthRedirectConfig.isRestrictedAuthRoute(location) ||
      location == RoutePaths.checkEmail) {
    return RoutePaths.selectCompany;
  }

  return null;
}

String? _redirectWithActiveCompany(String location) {
  if (location == RoutePaths.selectCompany) {
    return null;
  }

  if (location == RoutePaths.onboardingCompany) {
    return RoutePaths.dashboard;
  }

  if (AuthRedirectConfig.isRestrictedAuthRoute(location)) {
    return RoutePaths.dashboard;
  }

  if (location == RoutePaths.checkEmail) {
    return RoutePaths.dashboard;
  }

  return null;
}

String? _redirectOnCompaniesError(String location) {
  if (location == RoutePaths.login ||
      AuthRedirectConfig.isTenantShellRoute(location) ||
      location == RoutePaths.selectCompany ||
      AuthRedirectConfig.isRestrictedAuthRoute(location) ||
      location == RoutePaths.checkEmail) {
    return RoutePaths.onboardingCompany;
  }

  return null;
}
