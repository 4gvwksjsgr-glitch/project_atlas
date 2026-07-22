import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/auth/presentation/screens/check_email_screen.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/signup_screen.dart';
import '../../features/auth/presentation/screens/update_password_screen.dart';
import '../../features/clients/presentation/screens/customer_form_screen.dart';
import '../../features/clients/presentation/screens/customer_import_screen.dart';
import '../../features/clients/presentation/screens/customers_screen.dart';
import '../../features/companies/presentation/providers/company_providers.dart';
import '../../features/companies/presentation/screens/company_onboarding_screen.dart';
import '../../features/companies/presentation/screens/company_selector_screen.dart';
import '../../features/companies/presentation/screens/company_settings_screen.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/transactions/presentation/screens/transaction_form_screen.dart';
import '../../features/transactions/presentation/screens/transactions_screen.dart';
import 'route_guards.dart';
import 'route_paths.dart';
import 'shell_scaffold.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _dashboardNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'dashboard',
);
final _clientsNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'clients');
final _transactionsNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'transactions',
);
final _settingsNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'settings');

final routerProvider = Provider<GoRouter>((ref) {
  final refreshListenable = ref.watch(goRouterAuthRefreshProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: RoutePaths.login,
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final isAuthenticated = ref.read(isAuthenticatedProvider);
      final isPasswordRecoveryActive = ref.read(
        isPasswordRecoveryActiveProvider,
      );
      final companiesState = ref.read(userCompaniesRouteStateProvider);

      return resolveAuthRedirect(
        location: state.matchedLocation,
        isAuthenticated: isAuthenticated,
        isPasswordRecoveryActive: isPasswordRecoveryActive,
        companiesState: companiesState,
      );
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
        path: RoutePaths.updatePassword,
        builder: (context, state) => const UpdatePasswordScreen(),
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
        builder: (context, state) => const CompanyOnboardingScreen(),
      ),
      GoRoute(
        path: RoutePaths.selectCompany,
        builder: (context, state) => const CompanySelectorScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return ShellScaffold(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            navigatorKey: _dashboardNavigatorKey,
            routes: [
              GoRoute(
                path: RoutePaths.dashboard,
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _clientsNavigatorKey,
            routes: [
              GoRoute(
                path: RoutePaths.clients,
                builder: (context, state) => const CustomersScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    builder: (context, state) => const CustomerFormScreen(),
                  ),
                  GoRoute(
                    path: 'import',
                    builder: (context, state) => const CustomerImportScreen(),
                  ),
                  GoRoute(
                    path: ':customerId/edit',
                    builder: (context, state) {
                      final customerId = state.pathParameters['customerId'];
                      return CustomerFormScreen(customerId: customerId);
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _transactionsNavigatorKey,
            routes: [
              GoRoute(
                path: RoutePaths.transactions,
                builder: (context, state) => const TransactionsScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    builder: (context, state) => const TransactionFormScreen(),
                  ),
                  GoRoute(
                    path: ':transactionId/edit',
                    builder: (context, state) {
                      final transactionId =
                          state.pathParameters['transactionId'];
                      return TransactionFormScreen(
                        transactionId: transactionId,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _settingsNavigatorKey,
            routes: [
              GoRoute(
                path: RoutePaths.settingsCompany,
                builder: (context, state) => const CompanySettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
