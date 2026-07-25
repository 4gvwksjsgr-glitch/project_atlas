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
import 'package:project_atlas/features/categories/domain/entities/transaction_category.dart';
import 'package:project_atlas/features/categories/domain/repositories/category_repository.dart';
import 'package:project_atlas/features/categories/domain/usecases/category_usecases.dart';
import 'package:project_atlas/features/categories/presentation/providers/category_providers.dart';
import 'package:project_atlas/features/categories/presentation/screens/categories_screen.dart';
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
import 'package:project_atlas/features/transactions/domain/entities/cash_transaction.dart';
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

TransactionCategory _category({
  required String id,
  required String companyId,
  required String name,
  required TransactionKind kind,
  bool isActive = true,
}) {
  return TransactionCategory(
    id: id,
    companyId: companyId,
    name: name,
    kind: kind,
    isActive: isActive,
    createdAt: DateTime.utc(2026, 7, 24),
    updatedAt: DateTime.utc(2026, 7, 24),
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

class _CategoriesRepo implements CategoryRepository {
  _CategoriesRepo(this.byCompany, {this.listError});

  final Map<String, List<TransactionCategory>> byCompany;
  final Failure? listError;
  int createCount = 0;
  String? lastCreateCompanyId;

  @override
  Future<Result<List<TransactionCategory>>> getCategories({
    required String companyId,
  }) async {
    if (listError != null) {
      return Error(listError!);
    }
    return Success(List.of(byCompany[companyId] ?? const []));
  }

  @override
  Future<Result<TransactionCategory>> createCategory({
    required String companyId,
    required String name,
    required TransactionKind kind,
  }) async {
    createCount++;
    lastCreateCompanyId = companyId;
    final created = _category(
      id: 'new-$createCount',
      companyId: companyId,
      name: name,
      kind: kind,
    );
    byCompany.putIfAbsent(companyId, () => []).add(created);
    return Success(created);
  }

  @override
  Future<Result<TransactionCategory>> renameCategory({
    required String companyId,
    required String categoryId,
    required String name,
  }) async {
    final list = byCompany[companyId]!;
    final index = list.indexWhere((c) => c.id == categoryId);
    final updated = _category(
      id: categoryId,
      companyId: companyId,
      name: name,
      kind: list[index].kind,
      isActive: list[index].isActive,
    );
    list[index] = updated;
    return Success(updated);
  }

  @override
  Future<Result<TransactionCategory>> setCategoryActive({
    required String companyId,
    required String categoryId,
    required bool isActive,
  }) async {
    final list = byCompany[companyId]!;
    final index = list.indexWhere((c) => c.id == categoryId);
    final current = list[index];
    final updated = _category(
      id: categoryId,
      companyId: companyId,
      name: current.name,
      kind: current.kind,
      isActive: isActive,
    );
    list[index] = updated;
    return Success(updated);
  }
}

Future<(ProviderContainer, GoRouter)> _pumpCategories({
  required WidgetTester tester,
  required List<CompanyMembership> memberships,
  required CategoryRepository repository,
  String initialCompanyId = 'c1',
  String initialLocation = RoutePaths.settingsCategories,
}) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

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
          categoryRepositoryProvider.overrideWithValue(repository),
          getCategoriesUseCaseProvider.overrideWithValue(
            GetCategories(repository),
          ),
          createCategoryUseCaseProvider.overrideWithValue(
            CreateCategory(repository),
          ),
          renameCategoryUseCaseProvider.overrideWithValue(
            RenameCategory(repository),
          ),
          setCategoryActiveUseCaseProvider.overrideWithValue(
            SetCategoryActive(repository),
          ),
          transactionRepositoryProvider.overrideWithValue(
            EmptyTransactionRepository(),
          ),
          getTransactionsUseCaseProvider.overrideWithValue(
            GetTransactions(EmptyTransactionRepository()),
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
                        routes: [
                          GoRoute(
                            path: 'categories',
                            builder: (context, state) =>
                                const CategoriesScreen(),
                          ),
                        ],
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

  group('CategoriesScreen', () {
    testWidgets('mostra empty state e nuova categoria per owner', (
      tester,
    ) async {
      final repository = _CategoriesRepo({'c1': []});
      final (container, _) = await _pumpCategories(
        tester: tester,
        memberships: [_membership(companyId: 'c1', name: 'Acme')],
        repository: repository,
      );
      addTearDown(container.dispose);

      expect(find.text('Categorie'), findsWidgets);
      expect(
        find.text(
          'Nessuna categoria ancora. Aggiungi la prima categoria operativa.',
        ),
        findsOneWidget,
      );
      expect(find.text('Nuova categoria'), findsOneWidget);
    });

    testWidgets('employee non vede Nuova categoria ma vede elenco', (
      tester,
    ) async {
      final repository = _CategoriesRepo({
        'c1': [
          _category(
            id: 'i1',
            companyId: 'c1',
            name: 'Vendite',
            kind: TransactionKind.income,
          ),
        ],
      });
      final (container, _) = await _pumpCategories(
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

      expect(find.text('Vendite'), findsOneWidget);
      expect(find.text('Nuova categoria'), findsNothing);
      expect(
        find.text('Puoi visualizzare le categorie, ma non modificarle.'),
        findsOneWidget,
      );
    });

    testWidgets('loading errore e retry', (tester) async {
      final repository = _CategoriesRepo({
        'c1': [],
      }, listError: const UnknownFailure('boom categorie'));
      final (container, _) = await _pumpCategories(
        tester: tester,
        memberships: [_membership(companyId: 'c1', name: 'Acme')],
        repository: repository,
      );
      addTearDown(container.dispose);

      expect(find.text('boom categorie'), findsOneWidget);
      await tester.tap(find.text('Riprova'));
      await tester.pumpAndSettle();
      expect(find.text('boom categorie'), findsOneWidget);
    });

    testWidgets('separa Entrate e Uscite e mostra archiviate', (tester) async {
      final repository = _CategoriesRepo({
        'c1': [
          _category(
            id: 'i1',
            companyId: 'c1',
            name: 'Vendite',
            kind: TransactionKind.income,
          ),
          _category(
            id: 'e1',
            companyId: 'c1',
            name: 'Software',
            kind: TransactionKind.expense,
          ),
          _category(
            id: 'e2',
            companyId: 'c1',
            name: 'Vecchio',
            kind: TransactionKind.expense,
            isActive: false,
          ),
        ],
      });
      final (container, _) = await _pumpCategories(
        tester: tester,
        memberships: [_membership(companyId: 'c1', name: 'Acme')],
        repository: repository,
      );
      addTearDown(container.dispose);

      expect(find.text('Entrate'), findsOneWidget);
      expect(find.text('Uscite'), findsOneWidget);
      expect(find.text('Vendite'), findsOneWidget);
      expect(find.text('Software'), findsOneWidget);
      expect(find.text('Vecchio'), findsOneWidget);
      expect(find.text('Archiviata'), findsOneWidget);
    });

    testWidgets('cambio A → B non mostra categorie di A', (tester) async {
      final repository = _CategoriesRepo({
        'c1': [
          _category(
            id: 'a1',
            companyId: 'c1',
            name: 'Solo A',
            kind: TransactionKind.income,
          ),
        ],
        'c2': [
          _category(
            id: 'b1',
            companyId: 'c2',
            name: 'Solo B',
            kind: TransactionKind.expense,
          ),
        ],
      });
      final (container, _) = await _pumpCategories(
        tester: tester,
        memberships: [
          _membership(companyId: 'c1', name: 'Acme'),
          _membership(companyId: 'c2', name: 'Beta'),
        ],
        repository: repository,
      );
      addTearDown(container.dispose);

      expect(find.text('Solo A'), findsOneWidget);

      await tester.tap(find.byType(ActiveCompanyChip));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();
      // Dopo switch si atterra sulla Dashboard: torna a Categorie via Impostazioni.
      await tester.tap(find.text('Impostazioni'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gestisci le categorie dei movimenti'));
      await tester.pumpAndSettle();

      expect(find.text('Solo A'), findsNothing);
      expect(find.text('Solo B'), findsOneWidget);
    });
  });
}
