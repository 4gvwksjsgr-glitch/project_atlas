import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:project_atlas/core/permissions/company_role.dart';
import 'package:project_atlas/core/router/route_guards.dart';
import 'package:project_atlas/core/router/route_paths.dart';
import 'package:project_atlas/core/router/shell_scaffold.dart';
import 'package:project_atlas/core/storage/app_shared_preferences.dart';
import 'package:project_atlas/features/auth/presentation/providers/auth_providers.dart';
import 'package:project_atlas/features/clients/presentation/screens/customers_screen.dart';
import 'package:project_atlas/features/companies/data/datasource/active_company_local_datasource.dart';
import 'package:project_atlas/features/companies/domain/entities/company.dart';
import 'package:project_atlas/features/companies/domain/entities/company_membership.dart';
import 'package:project_atlas/features/companies/presentation/controllers/active_company_controller.dart';
import 'package:project_atlas/features/companies/presentation/controllers/active_company_resolution_coordinator.dart';
import 'package:project_atlas/features/companies/presentation/providers/company_providers.dart';
import 'package:project_atlas/features/companies/presentation/screens/company_selector_screen.dart';
import 'package:project_atlas/features/companies/presentation/screens/company_settings_screen.dart';
import 'package:project_atlas/features/companies/presentation/widgets/active_company_chip.dart';
import 'package:project_atlas/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:project_atlas/features/documents/presentation/screens/documents_screen.dart';
import 'package:project_atlas/features/transactions/domain/usecases/get_transactions.dart';
import 'package:project_atlas/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:project_atlas/features/transactions/presentation/screens/transactions_screen.dart';
import 'package:project_atlas/l10n/app_localizations.dart';
import 'package:project_atlas/shared/constants/app_ui_constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../test_helpers/empty_transaction_repository.dart';
import '../../test_helpers/shared_preferences_test_helper.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _dashboardNavigatorKey = GlobalKey<NavigatorState>();
final _clientsNavigatorKey = GlobalKey<NavigatorState>();
final _transactionsNavigatorKey = GlobalKey<NavigatorState>();
final _documentsNavigatorKey = GlobalKey<NavigatorState>();
final _settingsNavigatorKey = GlobalKey<NavigatorState>();

CompanyMembership _membership({
  required String companyId,
  required String name,
}) {
  return CompanyMembership(
    id: 'membership-$companyId',
    companyId: companyId,
    role: CompanyRole.owner,
    joinedAt: DateTime.utc(2026, 1, 1),
    company: Company(
      id: companyId,
      name: name,
      slug: name.toLowerCase().replaceAll(' ', '-'),
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

void _configureView(
  WidgetTester tester, {
  required Size logicalSize,
  required double topInset,
}) {
  tester.view.physicalSize = logicalSize;
  tester.view.devicePixelRatio = 1.0;
  tester.view.padding = FakeViewPadding(top: topInset);
  tester.view.viewPadding = FakeViewPadding(top: topInset);
  addTearDown(tester.view.reset);
}

Future<(ProviderContainer, GoRouter)> _pumpShell({
  required WidgetTester tester,
  required List<CompanyMembership> memberships,
  String userId = 'user-1',
  String initialCompanyId = 'c1',
}) async {
  await ActiveCompanyLocalDataSource(
    appSharedPreferences!,
  ).persistActiveCompanyId(userId: userId, companyId: initialCompanyId);

  late ProviderContainer container;
  GoRouter? router;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWithValue(_testSession(userId: userId)),
          isAuthenticatedProvider.overrideWithValue(true),
          isPasswordRecoveryActiveProvider.overrideWithValue(false),
          userCompaniesProvider.overrideWith((ref) async => memberships),
          transactionRepositoryProvider.overrideWithValue(
            const EmptyTransactionRepository(),
          ),
          getTransactionsUseCaseProvider.overrideWithValue(
            GetTransactions(const EmptyTransactionRepository()),
          ),
        ],
      ),
      child: Consumer(
        builder: (context, ref, _) {
          ref.watch(activeCompanyResolutionCoordinatorProvider);
          router ??= GoRouter(
            navigatorKey: _rootNavigatorKey,
            initialLocation: RoutePaths.dashboard,
            refreshListenable: ref.watch(goRouterAuthRefreshProvider),
            redirect: (context, state) {
              return resolveAuthRedirect(
                location: state.matchedLocation,
                isAuthenticated: ref.read(isAuthenticatedProvider),
                isPasswordRecoveryActive: ref.read(
                  isPasswordRecoveryActiveProvider,
                ),
                companiesState: ref.read(userCompaniesRouteStateProvider),
              );
            },
            routes: [
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
                      ),
                    ],
                  ),
                  StatefulShellBranch(
                    navigatorKey: _transactionsNavigatorKey,
                    routes: [
                      GoRoute(
                        path: RoutePaths.transactions,
                        builder: (context, state) => const TransactionsScreen(),
                      ),
                    ],
                  ),
                  StatefulShellBranch(
                    navigatorKey: _documentsNavigatorKey,
                    routes: [
                      GoRoute(
                        path: RoutePaths.documents,
                        builder: (context, state) => const DocumentsScreen(),
                      ),
                    ],
                  ),
                  StatefulShellBranch(
                    navigatorKey: _settingsNavigatorKey,
                    routes: [
                      GoRoute(
                        path: RoutePaths.settingsCompany,
                        builder: (context, state) =>
                            const CompanySettingsScreen(),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          );

          return MaterialApp.router(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('it'),
            routerConfig: router!,
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(container.dispose);
  return (container, router!);
}

void main() {
  setUp(() async {
    await setUpMockSharedPreferences();
  });

  group('ShellScaffold company chip SafeArea', () {
    testWidgets(
      'portrait Android-like: chip sotto status bar e tap apre selettore',
      (tester) async {
        const topInset = 48.0;
        _configureView(
          tester,
          logicalSize: const Size(390, 844),
          topInset: topInset,
        );

        final memberships = [
          _membership(companyId: 'c1', name: 'Atlas Test'),
          _membership(companyId: 'c2', name: 'Beta Co'),
        ];
        final (container, router) = await _pumpShell(
          tester: tester,
          memberships: memberships,
        );

        expect(
          MediaQuery.sizeOf(tester.element(find.byType(ShellScaffold))).width,
          lessThan(AppUiConstants.shellBreakpoint),
        );
        expect(find.byType(NavigationRail), findsNothing);
        expect(find.byType(NavigationBar), findsOneWidget);

        expect(find.byType(ActiveCompanyChip), findsOneWidget);
        final chip = tester.widget<ActiveCompanyChip>(
          find.byType(ActiveCompanyChip),
        );
        expect(chip.canSwitch, isTrue);

        // SafeArea removes padding from descendants; compare against view inset.
        final viewPaddingTop = MediaQuery.viewPaddingOf(
          tester.element(find.byType(ShellScaffold)),
        ).top;
        expect(viewPaddingTop, topInset);
        final chipRect = tester.getRect(find.byType(ActiveCompanyChip));
        expect(chipRect.top, greaterThanOrEqualTo(viewPaddingTop));

        await tester.tap(find.byType(ActiveCompanyChip));
        await tester.pumpAndSettle();

        expect(find.text('Seleziona azienda'), findsOneWidget);
        expect(router.state.uri.path, RoutePaths.selectCompany);
        expect(
          container.read(activeCompanyProvider)?.companyName,
          'Atlas Test',
        );
      },
    );

    testWidgets(
      'landscape: chip sotto inset, NavigationRail e tap apre selettore',
      (tester) async {
        const topInset = 24.0;
        _configureView(
          tester,
          logicalSize: const Size(844, 390),
          topInset: topInset,
        );

        final memberships = [
          _membership(companyId: 'c1', name: 'Atlas Test'),
          _membership(companyId: 'c2', name: 'Beta Co'),
        ];
        final (container, router) = await _pumpShell(
          tester: tester,
          memberships: memberships,
        );

        expect(
          MediaQuery.sizeOf(tester.element(find.byType(ShellScaffold))).width,
          greaterThanOrEqualTo(AppUiConstants.shellBreakpoint),
        );
        expect(find.byType(NavigationRail), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);

        expect(find.byType(ActiveCompanyChip), findsOneWidget);
        final chip = tester.widget<ActiveCompanyChip>(
          find.byType(ActiveCompanyChip),
        );
        expect(chip.canSwitch, isTrue);

        final viewPaddingTop = MediaQuery.viewPaddingOf(
          tester.element(find.byType(ShellScaffold)),
        ).top;
        expect(viewPaddingTop, topInset);
        final chipRect = tester.getRect(find.byType(ActiveCompanyChip));
        expect(chipRect.top, greaterThanOrEqualTo(viewPaddingTop));

        await tester.tap(find.byType(ActiveCompanyChip));
        await tester.pumpAndSettle();

        expect(find.text('Seleziona azienda'), findsOneWidget);
        expect(router.state.uri.path, RoutePaths.selectCompany);
        expect(container.read(activeCompanyProvider)?.companyId, 'c1');
      },
    );

    testWidgets('una sola azienda: chip visibile ma non apre selettore', (
      tester,
    ) async {
      const topInset = 48.0;
      _configureView(
        tester,
        logicalSize: const Size(390, 844),
        topInset: topInset,
      );

      final memberships = [_membership(companyId: 'c1', name: 'Atlas Test')];
      final (container, router) = await _pumpShell(
        tester: tester,
        memberships: memberships,
      );

      expect(find.byType(ActiveCompanyChip), findsOneWidget);
      final chip = tester.widget<ActiveCompanyChip>(
        find.byType(ActiveCompanyChip),
      );
      expect(chip.canSwitch, isFalse);

      final viewPaddingTop = MediaQuery.viewPaddingOf(
        tester.element(find.byType(ShellScaffold)),
      ).top;
      expect(viewPaddingTop, topInset);
      final chipRect = tester.getRect(find.byType(ActiveCompanyChip));
      expect(chipRect.top, greaterThanOrEqualTo(viewPaddingTop));

      await tester.tap(find.byType(ActiveCompanyChip));
      await tester.pumpAndSettle();

      expect(find.text('Seleziona azienda'), findsNothing);
      expect(router.state.uri.path, RoutePaths.dashboard);
      expect(container.read(activeCompanyProvider)?.companyName, 'Atlas Test');
    });
  });
}
