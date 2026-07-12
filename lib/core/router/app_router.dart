import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/auth/presentation/screens/check_email_screen.dart';
import '../../features/auth/presentation/screens/company_onboarding_placeholder_screen.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/signup_screen.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import 'route_paths.dart';
import 'shell_scaffold.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final isAuthenticated = ref.watch(isAuthenticatedProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: RoutePaths.login,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final isPublicAuthRoute = _isPublicAuthRoute(location);
      final isProtectedRoute = _isProtectedRoute(location);

      if (!isAuthenticated && isProtectedRoute) {
        return RoutePaths.login;
      }

      if (isAuthenticated && _isRestrictedAuthRoute(location)) {
        return RoutePaths.onboardingCompany;
      }

      if (isAuthenticated && location == RoutePaths.checkEmail) {
        return RoutePaths.onboardingCompany;
      }

      if (!isAuthenticated && !isPublicAuthRoute && !isProtectedRoute) {
        return RoutePaths.login;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: RoutePaths.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: RoutePaths.signup,
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: RoutePaths.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: RoutePaths.checkEmail,
        builder: (context, state) {
          final email = state.extra as String?;
          return CheckEmailScreen(email: email);
        },
      ),
      GoRoute(
        path: RoutePaths.onboardingCompany,
        builder: (context, state) => const CompanyOnboardingPlaceholderScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return ShellScaffold(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            navigatorKey: _shellNavigatorKey,
            routes: [
              GoRoute(
                path: RoutePaths.dashboard,
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

bool _isPublicAuthRoute(String location) {
  return location == RoutePaths.login ||
      location == RoutePaths.signup ||
      location == RoutePaths.forgotPassword ||
      location == RoutePaths.checkEmail;
}

bool _isRestrictedAuthRoute(String location) {
  return location == RoutePaths.login ||
      location == RoutePaths.signup ||
      location == RoutePaths.forgotPassword;
}

bool _isProtectedRoute(String location) {
  return location == RoutePaths.dashboard ||
      location == RoutePaths.onboardingCompany;
}
