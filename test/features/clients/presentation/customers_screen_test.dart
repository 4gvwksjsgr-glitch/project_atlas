import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:project_atlas/core/errors/failures.dart';
import 'package:project_atlas/core/permissions/company_role.dart';
import 'package:project_atlas/core/router/route_guards.dart';
import 'package:project_atlas/core/router/route_paths.dart';
import 'package:project_atlas/core/router/shell_scaffold.dart';
import 'package:project_atlas/features/documents/presentation/screens/documents_screen.dart';
import 'package:project_atlas/core/storage/app_shared_preferences.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/auth/presentation/providers/auth_providers.dart';
import 'package:project_atlas/features/clients/domain/entities/customer.dart';
import 'package:project_atlas/features/clients/domain/repositories/customer_repository.dart';
import 'package:project_atlas/features/clients/domain/usecases/create_customer.dart';
import 'package:project_atlas/features/clients/domain/usecases/get_customers.dart';
import 'package:project_atlas/features/clients/domain/usecases/update_customer.dart';
import 'package:project_atlas/features/clients/presentation/providers/customer_providers.dart';
import 'package:project_atlas/features/clients/presentation/screens/customer_form_screen.dart';
import 'package:project_atlas/features/clients/presentation/screens/customers_screen.dart';
import 'package:project_atlas/features/companies/data/datasource/active_company_local_datasource.dart';
import 'package:project_atlas/features/companies/domain/entities/company.dart';
import 'package:project_atlas/features/companies/domain/entities/company_membership.dart';
import 'package:project_atlas/features/companies/presentation/controllers/active_company_resolution_coordinator.dart';
import 'package:project_atlas/features/companies/presentation/providers/company_providers.dart';
import 'package:project_atlas/features/companies/presentation/screens/company_selector_screen.dart';
import 'package:project_atlas/features/companies/presentation/screens/company_settings_screen.dart';
import 'package:project_atlas/features/companies/presentation/widgets/active_company_chip.dart';
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
final _documentsNavigatorKey = GlobalKey<NavigatorState>();
final _settingsNavigatorKey = GlobalKey<NavigatorState>();

CompanyMembership _membership({
  required String companyId,
  required String name,
  CompanyRole role = CompanyRole.owner,
}) {
  return CompanyMembership(
    id: 'membership-$companyId',
    companyId: companyId,
    role: role,
    joinedAt: DateTime.utc(2026, 1, 1),
    company: Company(
      id: companyId,
      name: name,
      slug: name.toLowerCase(),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
  );
}

Customer _customer({
  required String id,
  required String companyId,
  required String name,
}) {
  return Customer(
    id: id,
    companyId: companyId,
    name: name,
    email: null,
    phone: null,
    notes: null,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
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

class _CustomersRepo implements CustomerRepository {
  _CustomersRepo(this.byCompany, {this.createError});

  final Map<String, List<Customer>> byCompany;
  final Failure? createError;
  int createCount = 0;

  @override
  Future<Result<List<Customer>>> getCustomers({
    required String companyId,
  }) async {
    return Success(List<Customer>.from(byCompany[companyId] ?? const []));
  }

  @override
  Future<Result<Customer>> createCustomer({
    required String companyId,
    required String name,
    String? email,
    String? phone,
    String? notes,
  }) async {
    createCount += 1;
    if (createError != null) {
      return Error(createError!);
    }
    final customer = _customer(
      id: 'created-$createCount',
      companyId: companyId,
      name: name,
    );
    byCompany.putIfAbsent(companyId, () => []).add(customer);
    return Success(customer);
  }

  @override
  Future<Result<Customer>> updateCustomer({
    required String companyId,
    required String customerId,
    required String name,
    String? email,
    String? phone,
    String? notes,
  }) async {
    final list = byCompany[companyId] ?? [];
    final index = list.indexWhere((c) => c.id == customerId);
    final updated = Customer(
      id: customerId,
      companyId: companyId,
      name: name,
      email: email,
      phone: phone,
      notes: notes,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 2),
    );
    if (index >= 0) {
      list[index] = updated;
    }
    return Success(updated);
  }
}

Future<(ProviderContainer, GoRouter)> _pumpClients({
  required WidgetTester tester,
  required List<CompanyMembership> memberships,
  required CustomerRepository repository,
  String initialCompanyId = 'c1',
  String initialLocation = RoutePaths.clients,
}) async {
  await ActiveCompanyLocalDataSource(
    appSharedPreferences!,
  ).persistActiveCompanyId(userId: 'user-1', companyId: initialCompanyId);

  late ProviderContainer container;
  GoRouter? router;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWithValue(_testSession()),
          isAuthenticatedProvider.overrideWithValue(true),
          isPasswordRecoveryActiveProvider.overrideWithValue(false),
          userCompaniesProvider.overrideWith((ref) async => memberships),
          customerRepositoryProvider.overrideWithValue(repository),
          getCustomersUseCaseProvider.overrideWithValue(
            GetCustomers(repository),
          ),
          createCustomerUseCaseProvider.overrideWithValue(
            CreateCustomer(repository),
          ),
          updateCustomerUseCaseProvider.overrideWithValue(
            UpdateCustomer(repository),
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
  return (container, router!);
}

void main() {
  setUp(() async {
    await setUpMockSharedPreferences();
  });

  group('CustomersScreen', () {
    testWidgets('mostra empty state e nuovo cliente per owner', (tester) async {
      final repository = _CustomersRepo({'c1': []});
      final (container, _) = await _pumpClients(
        tester: tester,
        memberships: [_membership(companyId: 'c1', name: 'Acme')],
        repository: repository,
      );
      addTearDown(container.dispose);

      expect(find.textContaining('Nessun cliente'), findsOneWidget);
      expect(find.text('Nuovo cliente'), findsOneWidget);
      expect(find.text('Importa clienti'), findsOneWidget);
    });

    testWidgets('employee non vede Nuovo cliente né Importa clienti', (
      tester,
    ) async {
      final repository = _CustomersRepo({
        'c1': [_customer(id: 'cust-1', companyId: 'c1', name: 'Rossi')],
      });
      final (container, _) = await _pumpClients(
        tester: tester,
        memberships: [
          _membership(
            companyId: 'c1',
            name: 'Acme',
            role: CompanyRole.employee,
          ),
        ],
        repository: repository,
      );
      addTearDown(container.dispose);

      expect(find.text('Nuovo cliente'), findsNothing);
      expect(find.text('Importa clienti'), findsNothing);
      await tester.tap(find.text('Rossi'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Non hai i permessi'), findsOneWidget);
      expect(find.text('Salva'), findsNothing);
    });

    testWidgets('loading errore e retry', (tester) async {
      final repository = _FailingThenOkRepo();
      final (container, _) = await _pumpClients(
        tester: tester,
        memberships: [_membership(companyId: 'c1', name: 'Acme')],
        repository: repository,
      );
      addTearDown(container.dispose);

      expect(find.textContaining('fallito'), findsOneWidget);
      await tester.tap(find.text('Riprova'));
      await tester.pumpAndSettle();
      expect(find.text('Cliente Ok'), findsOneWidget);
    });

    testWidgets('form conserva valori dopo errore create', (tester) async {
      final repository = _CustomersRepo({
        'c1': [],
      }, createError: const NetworkFailure('Errore di rete. Riprova.'));
      final (container, router) = await _pumpClients(
        tester: tester,
        memberships: [_membership(companyId: 'c1', name: 'Acme')],
        repository: repository,
      );
      addTearDown(container.dispose);

      router.go(RoutePaths.customerNew);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'Bozza Nome');
      await tester.enterText(find.byType(TextFormField).at(1), 'a@b.com');
      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();

      expect(find.text('Errore di rete. Riprova.'), findsOneWidget);
      expect(find.text('Bozza Nome'), findsOneWidget);
      expect(find.text('a@b.com'), findsOneWidget);
    });

    testWidgets('cambio A → B non mostra clienti di A', (tester) async {
      final repository = _CustomersRepo({
        'c1': [_customer(id: 'a1', companyId: 'c1', name: 'Cliente A')],
        'c2': [_customer(id: 'b1', companyId: 'c2', name: 'Cliente B')],
      });
      final (container, _) = await _pumpClients(
        tester: tester,
        memberships: [
          _membership(companyId: 'c1', name: 'Acme'),
          _membership(companyId: 'c2', name: 'Beta'),
        ],
        repository: repository,
      );
      addTearDown(container.dispose);

      expect(find.text('Cliente A'), findsOneWidget);
      expect(find.text('Cliente B'), findsNothing);

      await tester.tap(find.byType(ActiveCompanyChip));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clienti'));
      await tester.pumpAndSettle();

      expect(find.text('Cliente A'), findsNothing);
      expect(find.text('Cliente B'), findsOneWidget);
    });

    testWidgets('create aggiorna lista del tenant', (tester) async {
      final repository = _CustomersRepo({'c1': []});
      final (container, router) = await _pumpClients(
        tester: tester,
        memberships: [_membership(companyId: 'c1', name: 'Acme')],
        repository: repository,
      );
      addTearDown(container.dispose);

      router.go(RoutePaths.customerNew);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Nuovo Cliente');
      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();

      expect(find.text('Nuovo Cliente'), findsOneWidget);
      expect(repository.createCount, 1);
    });
  });
}

class _FailingThenOkRepo implements CustomerRepository {
  var attempts = 0;

  @override
  Future<Result<List<Customer>>> getCustomers({
    required String companyId,
  }) async {
    attempts += 1;
    if (attempts == 1) {
      return const Error(NetworkFailure('Caricamento clienti fallito'));
    }
    return Success([
      _customer(id: 'ok', companyId: companyId, name: 'Cliente Ok'),
    ]);
  }

  @override
  Future<Result<Customer>> createCustomer({
    required String companyId,
    required String name,
    String? email,
    String? phone,
    String? notes,
  }) => throw UnimplementedError();

  @override
  Future<Result<Customer>> updateCustomer({
    required String companyId,
    required String customerId,
    required String name,
    String? email,
    String? phone,
    String? notes,
  }) => throw UnimplementedError();
}
