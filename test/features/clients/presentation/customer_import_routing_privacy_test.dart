import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:project_atlas/core/errors/failures.dart';
import 'package:project_atlas/core/permissions/company_role.dart';
import 'package:project_atlas/core/router/route_guards.dart';
import 'package:project_atlas/core/router/route_paths.dart';
import 'package:project_atlas/core/router/shell_scaffold.dart';
import 'package:project_atlas/core/storage/app_shared_preferences.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/auth/presentation/providers/auth_providers.dart';
import 'package:project_atlas/features/clients/domain/entities/customer.dart';
import 'package:project_atlas/features/clients/domain/entities/customer_import_issue.dart';
import 'package:project_atlas/features/clients/domain/entities/customer_import_payload_row.dart';
import 'package:project_atlas/features/clients/domain/entities/customer_import_result.dart';
import 'package:project_atlas/features/clients/domain/repositories/customer_repository.dart';
import 'package:project_atlas/features/clients/domain/usecases/create_customer.dart';
import 'package:project_atlas/features/clients/domain/usecases/get_customers.dart';
import 'package:project_atlas/features/clients/domain/usecases/update_customer.dart';
import 'package:project_atlas/features/clients/presentation/providers/customer_providers.dart';
import 'package:project_atlas/features/clients/presentation/screens/customer_form_screen.dart';
import 'package:project_atlas/features/clients/presentation/screens/customer_import_screen.dart';
import 'package:project_atlas/features/clients/presentation/screens/customers_screen.dart';
import 'package:project_atlas/features/companies/data/datasource/active_company_local_datasource.dart';
import 'package:project_atlas/features/companies/domain/entities/company.dart';
import 'package:project_atlas/features/companies/domain/entities/company_membership.dart';
import 'package:project_atlas/features/companies/presentation/controllers/active_company_resolution_coordinator.dart';
import 'package:project_atlas/features/companies/presentation/providers/company_providers.dart';
import 'package:project_atlas/features/companies/presentation/screens/company_selector_screen.dart';
import 'package:project_atlas/features/companies/presentation/screens/company_settings_screen.dart';
import 'package:project_atlas/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:project_atlas/features/transactions/domain/usecases/get_transactions.dart';
import 'package:project_atlas/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:project_atlas/features/transactions/presentation/screens/transactions_screen.dart';
import 'package:project_atlas/l10n/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../test_helpers/empty_transaction_repository.dart';
import '../../../test_helpers/shared_preferences_test_helper.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _dashboardNavigatorKey = GlobalKey<NavigatorState>();
final _clientsNavigatorKey = GlobalKey<NavigatorState>();
final _transactionsNavigatorKey = GlobalKey<NavigatorState>();
final _settingsNavigatorKey = GlobalKey<NavigatorState>();

CompanyMembership _membership({
  required String companyId,
  required CompanyRole role,
}) {
  return CompanyMembership(
    id: 'membership-$companyId-${role.name}',
    companyId: companyId,
    role: role,
    joinedAt: DateTime.utc(2026, 1, 1),
    company: Company(
      id: companyId,
      name: 'Co $companyId',
      slug: 'co-$companyId',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
  );
}

Session _testSession() {
  return Session(
    accessToken: 'token',
    tokenType: 'bearer',
    user: User(
      id: 'user-1',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: DateTime.utc(2026).toIso8601String(),
    ),
  );
}

class _Repo implements CustomerRepository {
  @override
  Future<Result<List<Customer>>> getCustomers({
    required String companyId,
  }) async => const Success([]);

  @override
  Future<Result<Customer>> createCustomer({
    required String companyId,
    required String name,
    String? email,
    String? phone,
    String? notes,
  }) async => const Error(UnknownFailure());

  @override
  Future<Result<Customer>> updateCustomer({
    required String companyId,
    required String customerId,
    required String name,
    String? email,
    String? phone,
    String? notes,
  }) async => const Error(UnknownFailure());
}

Future<GoRouter> _pump({
  required WidgetTester tester,
  required CompanyRole role,
  required String initialLocation,
  bool settle = true,
}) async {
  await ActiveCompanyLocalDataSource(
    appSharedPreferences!,
  ).persistActiveCompanyId(userId: 'user-1', companyId: 'c1');

  late ProviderContainer container;
  GoRouter? router;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWithValue(_testSession()),
          isAuthenticatedProvider.overrideWithValue(true),
          isPasswordRecoveryActiveProvider.overrideWithValue(false),
          userCompaniesProvider.overrideWith(
            (ref) async => [_membership(companyId: 'c1', role: role)],
          ),
          customerRepositoryProvider.overrideWithValue(_Repo()),
          getCustomersUseCaseProvider.overrideWithValue(GetCustomers(_Repo())),
          createCustomerUseCaseProvider.overrideWithValue(
            CreateCustomer(_Repo()),
          ),
          updateCustomerUseCaseProvider.overrideWithValue(
            UpdateCustomer(_Repo()),
          ),
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
            initialLocation: initialLocation,
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
                        routes: [
                          GoRoute(
                            path: 'new',
                            builder: (context, state) =>
                                const CustomerFormScreen(),
                          ),
                          GoRoute(
                            path: 'import',
                            builder: (context, state) =>
                                const CustomerImportScreen(),
                          ),
                          GoRoute(
                            path: ':customerId/edit',
                            builder: (context, state) => CustomerFormScreen(
                              customerId: state.pathParameters['customerId'],
                            ),
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
            locale: const Locale('it'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router!,
          );
        },
      ),
    ),
  );

  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
  addTearDown(container.dispose);
  return router!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await setUpMockSharedPreferences();
  });

  group('Employee e routing import clienti', () {
    testWidgets('employee non vede Importa clienti', (tester) async {
      await _pump(
        tester: tester,
        role: CompanyRole.employee,
        initialLocation: RoutePaths.clients,
      );
      expect(find.text('Importa clienti'), findsNothing);
    });

    testWidgets('accesso diretto /clients/import respinto per employee', (
      tester,
    ) async {
      final router = await _pump(
        tester: tester,
        role: CompanyRole.employee,
        initialLocation: RoutePaths.customersImport,
        settle: false,
      );
      expect(
        find.text('Non hai i permessi per importare clienti.'),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        RoutePaths.clients,
      );
      expect(find.text('Importa clienti'), findsNothing);
    });

    testWidgets('owner può aprire la rotta import', (tester) async {
      await _pump(
        tester: tester,
        role: CompanyRole.owner,
        initialLocation: RoutePaths.customersImport,
      );
      expect(find.text('Importa clienti'), findsWidgets);
    });

    testWidgets('admin può aprire la rotta import', (tester) async {
      await _pump(
        tester: tester,
        role: CompanyRole.admin,
        initialLocation: RoutePaths.customersImport,
      );
      expect(find.text('Importa clienti'), findsWidgets);
    });

    testWidgets('manager può aprire la rotta import', (tester) async {
      await _pump(
        tester: tester,
        role: CompanyRole.manager,
        initialLocation: RoutePaths.customersImport,
      );
      expect(find.text('Importa clienti'), findsWidgets);
    });

    test('backend rifiuta employee anche aggirando la UI', () {
      final sql = File(
        'supabase/migrations/20260720000001_import_customers_rpc.sql',
      ).readAsStringSync();
      expect(sql, contains("ARRAY['owner', 'admin', 'manager']"));
      expect(sql, contains('Insufficient permissions'));
      expect(sql, isNot(contains("'employee'")));
    });
  });

  group('Privacy entità e messaggi', () {
    test('toString senza nome email telefono note', () {
      final customer = Customer(
        id: 'id-1',
        companyId: 'c1',
        name: 'Mario Rossi',
        email: 'mario@secret.test',
        phone: '3331112222',
        notes: 'nota riservata',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final text = customer.toString();
      expect(text, isNot(contains('Mario')));
      expect(text, isNot(contains('mario@secret.test')));
      expect(text, isNot(contains('3331112222')));
      expect(text, isNot(contains('nota riservata')));

      const row = CustomerImportPayloadRow(
        sourceRow: 2,
        name: 'Mario Rossi',
        email: 'mario@secret.test',
        phone: '3331112222',
        notes: 'nota riservata',
      );
      expect(row.toString(), isNot(contains('Mario')));
      expect(row.toString(), isNot(contains('mario@secret.test')));

      final result = CustomerImportResult(
        insertedCount: 1,
        skippedDuplicateCount: 0,
        skippedSourceRows: const [2],
      );
      expect(result.toString(), isNot(contains('Mario')));
      expect(result.toString(), contains('insertedCount'));

      const issue = CustomerImportIssue(
        severity: CustomerImportIssueSeverity.error,
        code: 'missingName',
        sourceRow: 4,
      );
      expect(issue.toString(), contains('sourceRow: 4'));
      expect(issue.toString(), contains('missingName'));
      expect(issue.toString(), isNot(contains('@')));
    });

    test(
      'nessun print/debugPrint/logger con dati cliente nel feature clients',
      () {
        final dartFiles = Directory('lib/features/clients')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'));
        for (final file in dartFiles) {
          final content = file.readAsStringSync();
          expect(content, isNot(contains('debugPrint(')), reason: file.path);
          expect(
            content.contains('print(') && content.contains('email'),
            isFalse,
            reason: file.path,
          );
        }
      },
    );

    test('RPC result model solo conteggi e source_row', () {
      final sql = File(
        'supabase/migrations/20260720000001_import_customers_rpc.sql',
      ).readAsStringSync();
      expect(sql, contains('inserted_count BIGINT'));
      expect(sql, contains('skipped_duplicate_count BIGINT'));
      expect(sql, contains('skipped_source_rows INTEGER[]'));
      expect(sql, isNot(contains('RETURNS TABLE (\n  name')));
    });
  });
}
