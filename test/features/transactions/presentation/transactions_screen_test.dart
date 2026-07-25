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
import 'package:project_atlas/features/categories/presentation/providers/category_providers.dart';
import 'package:project_atlas/features/clients/presentation/providers/customer_providers.dart';
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
import 'package:project_atlas/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:project_atlas/features/transactions/domain/usecases/create_transaction.dart';
import 'package:project_atlas/features/transactions/domain/usecases/get_transactions.dart';
import 'package:project_atlas/features/transactions/domain/usecases/update_transaction.dart';
import 'package:project_atlas/features/transactions/domain/value_objects/money_amount.dart';
import 'package:project_atlas/features/transactions/domain/value_objects/transaction_filters.dart';
import 'package:project_atlas/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:project_atlas/features/transactions/presentation/screens/transaction_form_screen.dart';
import 'package:project_atlas/features/transactions/presentation/screens/transactions_screen.dart';
import 'package:project_atlas/features/transactions/presentation/widgets/transaction_filters_bar.dart';
import 'package:project_atlas/features/transactions/presentation/widgets/transaction_list_tile.dart';
import 'package:project_atlas/l10n/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../test_helpers/shared_preferences_test_helper.dart';
import '../helpers/fake_category_repository.dart';

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

CashTransaction _transaction({
  required String id,
  required String companyId,
  required String description,
  TransactionKind kind = TransactionKind.expense,
  String amount = '10,00',
  DateTime? occurredOn,
  String? clientId,
  String? categoryId,
  String? notes,
}) {
  return CashTransaction(
    id: id,
    companyId: companyId,
    clientId: clientId,
    categoryId: categoryId,
    kind: kind,
    amount: MoneyAmount.parse(amount),
    occurredOn: occurredOn ?? DateTime(2026, 7, 17),
    description: description,
    notes: notes,
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

class _TransactionsRepo implements TransactionRepository {
  _TransactionsRepo(this.byCompany, {this.createError});

  final Map<String, List<CashTransaction>> byCompany;
  final Failure? createError;
  int createCount = 0;
  String? lastCategoryId;
  TransactionFilters? lastFilters;

  @override
  Future<Result<List<CashTransaction>>> getTransactions({
    required String companyId,
    TransactionFilters filters = const TransactionFilters(),
  }) async {
    lastFilters = filters;
    final all = List<CashTransaction>.from(byCompany[companyId] ?? const []);
    return Success(_applyFilters(all, filters));
  }

  @override
  Future<Result<CashTransaction>> createTransaction({
    required String companyId,
    String? clientId,
    String? categoryId,
    required TransactionKind kind,
    required MoneyAmount amount,
    required DateTime occurredOn,
    required String description,
    String? notes,
  }) async {
    createCount += 1;
    lastCategoryId = categoryId;
    if (createError != null) {
      return Error(createError!);
    }
    final transaction = CashTransaction(
      id: 'created-$createCount',
      companyId: companyId,
      clientId: clientId,
      categoryId: categoryId,
      kind: kind,
      amount: amount,
      occurredOn: occurredOn,
      description: description,
      notes: notes,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    byCompany.putIfAbsent(companyId, () => []).add(transaction);
    return Success(transaction);
  }

  @override
  Future<Result<CashTransaction>> updateTransaction({
    required String companyId,
    required String transactionId,
    String? clientId,
    String? categoryId,
    required TransactionKind kind,
    required MoneyAmount amount,
    required DateTime occurredOn,
    required String description,
    String? notes,
  }) async {
    final list = byCompany[companyId] ?? [];
    final index = list.indexWhere((t) => t.id == transactionId);
    final updated = CashTransaction(
      id: transactionId,
      companyId: companyId,
      clientId: clientId,
      categoryId: categoryId,
      kind: kind,
      amount: amount,
      occurredOn: occurredOn,
      description: description,
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

List<CashTransaction> _applyFilters(
  List<CashTransaction> source,
  TransactionFilters filters,
) {
  return source.where((transaction) {
    if (filters.fromDate != null &&
        transaction.occurredOn.isBefore(filters.fromDate!)) {
      return false;
    }
    if (filters.toDate != null &&
        transaction.occurredOn.isAfter(filters.toDate!)) {
      return false;
    }
    if (filters.kind != null && transaction.kind != filters.kind) {
      return false;
    }
    final clientId = filters.clientId?.trim();
    if (clientId != null &&
        clientId.isNotEmpty &&
        transaction.clientId != clientId) {
      return false;
    }
    final query = filters.descriptionQuery.trim().toLowerCase();
    if (query.isNotEmpty &&
        !transaction.description.toLowerCase().contains(query)) {
      return false;
    }
    return true;
  }).toList();
}

class _FailingThenOkRepo implements TransactionRepository {
  var attempts = 0;

  @override
  Future<Result<List<CashTransaction>>> getTransactions({
    required String companyId,
    TransactionFilters filters = const TransactionFilters(),
  }) async {
    attempts += 1;
    if (attempts == 1) {
      return const Error(NetworkFailure('Caricamento movimenti fallito'));
    }
    return Success([
      _transaction(id: 'ok', companyId: companyId, description: 'Movimento Ok'),
    ]);
  }

  @override
  Future<Result<CashTransaction>> createTransaction({
    required String companyId,
    String? clientId,
    String? categoryId,
    required TransactionKind kind,
    required MoneyAmount amount,
    required DateTime occurredOn,
    required String description,
    String? notes,
  }) => throw UnimplementedError();

  @override
  Future<Result<CashTransaction>> updateTransaction({
    required String companyId,
    required String transactionId,
    String? clientId,
    String? categoryId,
    required TransactionKind kind,
    required MoneyAmount amount,
    required DateTime occurredOn,
    required String description,
    String? notes,
  }) => throw UnimplementedError();
}

Future<(ProviderContainer, GoRouter)> _pumpTransactions({
  required WidgetTester tester,
  required List<CompanyMembership> memberships,
  required TransactionRepository repository,
  String initialCompanyId = 'c1',
  String initialLocation = RoutePaths.transactions,
  bool customersError = false,
  List<TransactionCategory> categories = const [],
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
          transactionRepositoryProvider.overrideWithValue(repository),
          getTransactionsUseCaseProvider.overrideWithValue(
            GetTransactions(repository),
          ),
          createTransactionUseCaseProvider.overrideWithValue(
            CreateTransaction(
              repository,
              const PassthroughCategoryRepository(),
            ),
          ),
          updateTransactionUseCaseProvider.overrideWithValue(
            UpdateTransaction(
              repository,
              const PassthroughCategoryRepository(),
            ),
          ),
          customersProvider.overrideWith((ref, companyId) async {
            if (customersError) {
              throw StateError('Clienti offline');
            }
            return [];
          }),
          categoriesProvider.overrideWith((ref, companyId) async => categories),
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
                        routes: [
                          GoRoute(
                            path: 'new',
                            builder: (context, state) =>
                                const TransactionFormScreen(),
                          ),
                          GoRoute(
                            path: ':transactionId/edit',
                            builder: (context, state) => TransactionFormScreen(
                              transactionId:
                                  state.pathParameters['transactionId'],
                            ),
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

  group('TransactionsScreen', () {
    testWidgets('mostra empty state e nuovo movimento per owner', (
      tester,
    ) async {
      final repository = _TransactionsRepo({'c1': []});
      final (container, _) = await _pumpTransactions(
        tester: tester,
        memberships: [_membership(companyId: 'c1', name: 'Acme')],
        repository: repository,
      );
      addTearDown(container.dispose);

      expect(find.textContaining('Nessun movimento'), findsOneWidget);
      expect(find.text('Nuovo movimento'), findsOneWidget);
    });

    testWidgets('employee non vede Nuovo movimento e apre sola lettura', (
      tester,
    ) async {
      final repository = _TransactionsRepo({
        'c1': [
          _transaction(id: 'txn-1', companyId: 'c1', description: 'Affitto'),
        ],
      });
      final (container, _) = await _pumpTransactions(
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

      expect(find.text('Nuovo movimento'), findsNothing);
      await tester.tap(find.text('Affitto'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Non hai i permessi'), findsOneWidget);
      expect(find.text('Salva'), findsNothing);
    });

    testWidgets('loading errore e retry', (tester) async {
      final repository = _FailingThenOkRepo();
      final (container, _) = await _pumpTransactions(
        tester: tester,
        memberships: [_membership(companyId: 'c1', name: 'Acme')],
        repository: repository,
      );
      addTearDown(container.dispose);

      expect(find.textContaining('fallito'), findsOneWidget);
      await tester.ensureVisible(find.text('Riprova'));
      await tester.tap(find.text('Riprova'));
      await tester.pumpAndSettle();
      expect(find.text('Movimento Ok'), findsOneWidget);
    });

    testWidgets('form conserva valori dopo errore create', (tester) async {
      final repository = _TransactionsRepo({
        'c1': [],
      }, createError: const NetworkFailure('Errore di rete. Riprova.'));
      final (container, router) = await _pumpTransactions(
        tester: tester,
        memberships: [_membership(companyId: 'c1', name: 'Acme')],
        repository: repository,
      );
      addTearDown(container.dispose);

      router.go(RoutePaths.transactionNew);
      await tester.pumpAndSettle();

      expect(find.text('Importo (€)'), findsOneWidget);
      final fields = find.descendant(
        of: find.byType(TransactionFormBody),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(fields.at(0), '12,50');
      await tester.enterText(fields.at(1), 'Bozza movimento');
      await tester.ensureVisible(
        find.byKey(const Key('transaction-save-button')),
      );
      await tester.tap(find.byKey(const Key('transaction-save-button')));
      await tester.pumpAndSettle();

      expect(find.text('Errore di rete. Riprova.'), findsOneWidget);
      expect(find.text('12,50'), findsOneWidget);
      expect(find.text('Bozza movimento'), findsOneWidget);
    });

    testWidgets('cambio A → B non mostra movimenti di A', (tester) async {
      final repository = _TransactionsRepo({
        'c1': [
          _transaction(id: 'a1', companyId: 'c1', description: 'Movimento A'),
        ],
        'c2': [
          _transaction(id: 'b1', companyId: 'c2', description: 'Movimento B'),
        ],
      });
      final (container, _) = await _pumpTransactions(
        tester: tester,
        memberships: [
          _membership(companyId: 'c1', name: 'Acme'),
          _membership(companyId: 'c2', name: 'Beta'),
        ],
        repository: repository,
      );
      addTearDown(container.dispose);

      expect(find.text('Movimento A'), findsOneWidget);
      expect(find.text('Movimento B'), findsNothing);

      await tester.tap(find.byType(ActiveCompanyChip));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Movimenti'));
      await tester.pumpAndSettle();

      expect(find.text('Movimento A'), findsNothing);
      expect(find.text('Movimento B'), findsOneWidget);
    });

    testWidgets('create aggiorna lista del tenant', (tester) async {
      final repository = _TransactionsRepo({'c1': []});
      final (container, router) = await _pumpTransactions(
        tester: tester,
        memberships: [_membership(companyId: 'c1', name: 'Acme')],
        repository: repository,
      );
      addTearDown(container.dispose);

      router.go(RoutePaths.transactionNew);
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(TransactionFormBody),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(fields.at(0), '20,00');
      await tester.enterText(fields.at(1), 'Nuovo movimento salvato');
      await tester.ensureVisible(
        find.byKey(const Key('transaction-save-button')),
      );
      await tester.tap(find.byKey(const Key('transaction-save-button')));
      await tester.pumpAndSettle();

      expect(find.text('Nuovo movimento salvato'), findsOneWidget);
      expect(repository.createCount, 1);
    });

    testWidgets(
      'selezione categoria poi cambio kind azzera categoryId e salva null',
      (tester) async {
        final repository = _TransactionsRepo({'c1': []});
        final (container, router) = await _pumpTransactions(
          tester: tester,
          memberships: [_membership(companyId: 'c1', name: 'Acme')],
          repository: repository,
          categories: [
            TransactionCategory(
              id: 'cat-soft',
              companyId: 'c1',
              name: 'Software',
              kind: TransactionKind.expense,
              isActive: true,
              createdAt: DateTime.utc(2026, 7, 25),
              updatedAt: DateTime.utc(2026, 7, 25),
            ),
          ],
        );
        addTearDown(container.dispose);

        router.go(RoutePaths.transactionNew);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('transaction-category-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Software').last);
        await tester.pumpAndSettle();
        expect(find.text('Software'), findsWidgets);

        await tester.tap(find.text('Entrata'));
        await tester.pumpAndSettle();

        expect(find.text('Nessuna categoria'), findsOneWidget);

        final fields = find.descendant(
          of: find.byType(TransactionFormBody),
          matching: find.byType(TextFormField),
        );
        await tester.enterText(fields.at(0), '15,00');
        await tester.enterText(fields.at(1), 'Dopo cambio kind');
        await tester.ensureVisible(
          find.byKey(const Key('transaction-save-button')),
        );
        await tester.tap(find.byKey(const Key('transaction-save-button')));
        await tester.pumpAndSettle();

        expect(repository.createCount, 1);
        expect(repository.lastCategoryId, isNull);
        expect(find.text('Dopo cambio kind'), findsOneWidget);
      },
    );

    testWidgets('form salvabile senza cliente se clienti in errore', (
      tester,
    ) async {
      final repository = _TransactionsRepo({'c1': []});
      final (container, router) = await _pumpTransactions(
        tester: tester,
        memberships: [_membership(companyId: 'c1', name: 'Acme')],
        repository: repository,
        customersError: true,
      );
      addTearDown(container.dispose);

      router.go(RoutePaths.transactionNew);
      await tester.pumpAndSettle();

      expect(find.textContaining('Clienti non disponibili'), findsOneWidget);

      final fields = find.descendant(
        of: find.byType(TransactionFormBody),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(fields.at(0), '5,00');
      await tester.enterText(fields.at(1), 'Senza cliente');
      await tester.ensureVisible(
        find.byKey(const Key('transaction-save-button')),
      );
      await tester.tap(find.byKey(const Key('transaction-save-button')));
      await tester.pumpAndSettle();

      expect(find.text('Senza cliente'), findsOneWidget);
      expect(repository.createCount, 1);
    });

    testWidgets('mostra contatore risultati e filtri', (tester) async {
      final repository = _TransactionsRepo({
        'c1': [
          _transaction(
            id: 'i1',
            companyId: 'c1',
            description: 'Incasso',
            kind: TransactionKind.income,
          ),
          _transaction(
            id: 'e1',
            companyId: 'c1',
            description: 'Affitto',
            kind: TransactionKind.expense,
          ),
        ],
      });
      final (container, _) = await _pumpTransactions(
        tester: tester,
        memberships: [_membership(companyId: 'c1', name: 'Acme')],
        repository: repository,
      );
      addTearDown(container.dispose);

      expect(find.text('Filtri'), findsOneWidget);
      expect(find.text('Cancella filtri'), findsOneWidget);
      expect(find.text('Risultati trovati: 2'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TransactionListTile &&
              widget.transaction.description == 'Incasso',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TransactionListTile &&
              widget.transaction.description == 'Affitto',
        ),
        findsOneWidget,
      );
    });

    testWidgets('filtro entrate AND ricerca descrizione', (tester) async {
      final repository = _TransactionsRepo({
        'c1': [
          _transaction(
            id: 'i1',
            companyId: 'c1',
            description: 'Incasso negozio',
            kind: TransactionKind.income,
          ),
          _transaction(
            id: 'i2',
            companyId: 'c1',
            description: 'Rimborso',
            kind: TransactionKind.income,
          ),
          _transaction(
            id: 'e1',
            companyId: 'c1',
            description: 'Incasso errato uscita',
            kind: TransactionKind.expense,
          ),
        ],
      });
      final (container, _) = await _pumpTransactions(
        tester: tester,
        memberships: [_membership(companyId: 'c1', name: 'Acme')],
        repository: repository,
      );
      addTearDown(container.dispose);

      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedButton<TransactionKind?>),
          matching: find.text('Entrata'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('transaction-description-filter')),
        'Incasso',
      );
      await tester.pump(TransactionFiltersBar.descriptionDebounce);
      await tester.pumpAndSettle();

      expect(find.text('Incasso negozio'), findsOneWidget);
      expect(find.text('Rimborso'), findsNothing);
      expect(find.text('Incasso errato uscita'), findsNothing);
      expect(find.text('Risultati trovati: 1'), findsOneWidget);
      expect(repository.lastFilters?.kind, TransactionKind.income);
      expect(repository.lastFilters?.descriptionQuery, 'Incasso');
    });

    testWidgets(
      'ricerca descrizione mantiene il focus durante la digitazione',
      (tester) async {
        final repository = _TransactionsRepo({
          'c1': [
            _transaction(
              id: 'i1',
              companyId: 'c1',
              description: 'Incasso negozio',
              kind: TransactionKind.income,
            ),
            _transaction(
              id: 'i2',
              companyId: 'c1',
              description: 'Rimborso',
              kind: TransactionKind.income,
            ),
          ],
        });
        final (container, _) = await _pumpTransactions(
          tester: tester,
          memberships: [_membership(companyId: 'c1', name: 'Acme')],
          repository: repository,
        );
        addTearDown(container.dispose);

        final field = find.byKey(const Key('transaction-description-filter'));
        await tester.tap(field);
        await tester.pump();

        await tester.enterText(field, 'I');
        await tester.pump();
        expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);

        await tester.enterText(field, 'In');
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
        expect(repository.lastFilters?.descriptionQuery ?? '', isEmpty);

        await tester.enterText(field, 'Inc');
        await tester.pump(TransactionFiltersBar.descriptionDebounce);
        await tester.pumpAndSettle();

        expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
        expect(repository.lastFilters?.descriptionQuery, 'Inc');
        expect(find.text('Incasso negozio'), findsOneWidget);
        expect(find.text('Rimborso'), findsNothing);
      },
    );

    testWidgets('Cancella filtri ripristina lista completa', (tester) async {
      final repository = _TransactionsRepo({
        'c1': [
          _transaction(
            id: 'i1',
            companyId: 'c1',
            description: 'Entrata A',
            kind: TransactionKind.income,
          ),
          _transaction(
            id: 'e1',
            companyId: 'c1',
            description: 'Uscita B',
            kind: TransactionKind.expense,
          ),
        ],
      });
      final (container, _) = await _pumpTransactions(
        tester: tester,
        memberships: [_membership(companyId: 'c1', name: 'Acme')],
        repository: repository,
      );
      addTearDown(container.dispose);

      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedButton<TransactionKind?>),
          matching: find.text('Uscita'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Entrata A'), findsNothing);
      expect(find.text('Uscita B'), findsOneWidget);

      await tester.ensureVisible(find.text('Cancella filtri'));
      await tester.tap(find.text('Cancella filtri'));
      await tester.pumpAndSettle();
      expect(find.text('Entrata A'), findsOneWidget);
      expect(find.text('Uscita B'), findsOneWidget);
      expect(repository.lastFilters?.hasActiveFilters, isFalse);
    });

    testWidgets('cambio azienda resetta i filtri', (tester) async {
      final repository = _TransactionsRepo({
        'c1': [
          _transaction(
            id: 'a1',
            companyId: 'c1',
            description: 'Solo A entrata',
            kind: TransactionKind.income,
          ),
          _transaction(
            id: 'a2',
            companyId: 'c1',
            description: 'Solo A uscita',
            kind: TransactionKind.expense,
          ),
        ],
        'c2': [
          _transaction(
            id: 'b1',
            companyId: 'c2',
            description: 'Movimento B entrata',
            kind: TransactionKind.income,
          ),
          _transaction(
            id: 'b2',
            companyId: 'c2',
            description: 'Movimento B uscita',
            kind: TransactionKind.expense,
          ),
        ],
      });
      final (container, _) = await _pumpTransactions(
        tester: tester,
        memberships: [
          _membership(companyId: 'c1', name: 'Acme'),
          _membership(companyId: 'c2', name: 'Beta'),
        ],
        repository: repository,
      );
      addTearDown(container.dispose);

      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedButton<TransactionKind?>),
          matching: find.text('Entrata'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Solo A uscita'), findsNothing);

      await tester.tap(find.byType(ActiveCompanyChip));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Movimenti'));
      await tester.pumpAndSettle();

      expect(find.text('Movimento B entrata'), findsOneWidget);
      expect(find.text('Movimento B uscita'), findsOneWidget);
      expect(find.text('Risultati trovati: 2'), findsOneWidget);
      expect(
        container.read(transactionFiltersProvider('c2')).hasActiveFilters,
        isFalse,
      );
    });
  });
}
