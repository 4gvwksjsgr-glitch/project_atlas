import 'dart:io';

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
import 'package:project_atlas/features/clients/domain/entities/customer.dart';
import 'package:project_atlas/features/clients/presentation/providers/customer_providers.dart';
import 'package:project_atlas/features/clients/presentation/screens/customers_screen.dart';
import 'package:project_atlas/features/companies/data/datasource/active_company_local_datasource.dart';
import 'package:project_atlas/features/companies/domain/entities/company.dart';
import 'package:project_atlas/features/companies/domain/entities/company_membership.dart';
import 'package:project_atlas/features/companies/presentation/controllers/active_company_resolution_coordinator.dart';
import 'package:project_atlas/features/companies/presentation/providers/company_providers.dart';
import 'package:project_atlas/features/companies/presentation/screens/company_selector_screen.dart';
import 'package:project_atlas/features/companies/presentation/screens/company_settings_screen.dart';
import 'package:project_atlas/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:project_atlas/features/documents/presentation/screens/documents_screen.dart';
import 'package:project_atlas/features/transactions/domain/entities/cash_transaction.dart';
import 'package:project_atlas/features/transactions/domain/entities/transaction_import_issue.dart';
import 'package:project_atlas/features/transactions/domain/entities/transaction_import_payload_row.dart';
import 'package:project_atlas/features/transactions/domain/entities/transaction_import_result.dart';
import 'package:project_atlas/features/transactions/domain/entities/transaction_import_row.dart';
import 'package:project_atlas/features/transactions/domain/usecases/get_transactions.dart';
import 'package:project_atlas/features/transactions/domain/value_objects/money_amount.dart';
import 'package:project_atlas/features/transactions/presentation/providers/transaction_import_providers.dart';
import 'package:project_atlas/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:project_atlas/features/transactions/presentation/screens/transaction_form_screen.dart';
import 'package:project_atlas/features/transactions/presentation/screens/transaction_import_screen.dart';
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

CompanyMembership _membership({required CompanyRole role}) {
  return CompanyMembership(
    id: 'membership-${role.name}',
    companyId: 'c1',
    role: role,
    joinedAt: DateTime.utc(2026, 1, 1),
    company: Company(
      id: 'c1',
      name: 'Acme',
      slug: 'acme',
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
            (ref) async => [_membership(role: role)],
          ),
          transactionRepositoryProvider.overrideWithValue(
            const EmptyTransactionRepository(),
          ),
          getTransactionsUseCaseProvider.overrideWithValue(
            GetTransactions(const EmptyTransactionRepository()),
          ),
          transactionImportExistingTransactionsProvider.overrideWith(
            (ref, companyId) async => <CashTransaction>[],
          ),
          customersProvider.overrideWith((ref, companyId) async => <Customer>[]),
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
                          // Stesso ordine dell'app: 'import' prima dell'id.
                          GoRoute(
                            path: 'import',
                            builder: (context, state) =>
                                const TransactionImportScreen(),
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

  group('Permessi sulla rotta di import movimenti', () {
    testWidgets('employee non vede il pulsante Importa movimenti', (
      tester,
    ) async {
      await _pump(
        tester: tester,
        role: CompanyRole.employee,
        initialLocation: RoutePaths.transactions,
      );

      expect(find.text('Importa movimenti'), findsNothing);
    });

    testWidgets('owner vede il pulsante Importa movimenti', (tester) async {
      await _pump(
        tester: tester,
        role: CompanyRole.owner,
        initialLocation: RoutePaths.transactions,
      );

      expect(find.text('Importa movimenti'), findsOneWidget);
    });

    testWidgets('accesso diretto respinto per employee', (tester) async {
      final router = await _pump(
        tester: tester,
        role: CompanyRole.employee,
        initialLocation: RoutePaths.transactionsImport,
        settle: false,
      );

      expect(
        find.text('Non hai i permessi per importare movimenti.'),
        findsOneWidget,
      );

      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        RoutePaths.transactions,
      );
      expect(find.text('Importa movimenti'), findsNothing);
    });

    for (final role in const [
      CompanyRole.owner,
      CompanyRole.admin,
      CompanyRole.manager,
    ]) {
      testWidgets('${role.name} può aprire la rotta di import', (tester) async {
        await _pump(
          tester: tester,
          role: role,
          initialLocation: RoutePaths.transactionsImport,
        );

        expect(find.byType(TransactionImportScreen), findsOneWidget);
        expect(find.text('Seleziona file CSV o XLSX'), findsOneWidget);
        expect(
          find.text('Non hai i permessi per importare movimenti.'),
          findsNothing,
        );
      });
    }
  });

  group('Ordine delle rotte annidate sotto /transactions', () {
    testWidgets('/transactions/import apre l import, non il form', (
      tester,
    ) async {
      await _pump(
        tester: tester,
        role: CompanyRole.owner,
        initialLocation: RoutePaths.transactionsImport,
      );

      expect(find.byType(TransactionImportScreen), findsOneWidget);
      expect(find.byType(TransactionFormScreen), findsNothing);
    });

    testWidgets('un id reale continua ad aprire il form di modifica', (
      tester,
    ) async {
      await _pump(
        tester: tester,
        role: CompanyRole.owner,
        initialLocation: RoutePaths.transactionEdit('tx-123'),
      );

      expect(find.byType(TransactionFormScreen), findsOneWidget);
      expect(find.byType(TransactionImportScreen), findsNothing);
    });

    test('il percorso di import non collide con quello di modifica', () {
      expect(RoutePaths.transactionsImport, '/transactions/import');
      expect(
        RoutePaths.transactionEdit('import'),
        isNot(RoutePaths.transactionsImport),
      );
    });
  });

  group('Privacy dei dati di import movimenti', () {
    test('il payload di riga non espone descrizione, note o riferimento', () {
      final row = TransactionImportPayloadRow(
        sourceRow: 7,
        occurredOn: '2026-03-04',
        kind: 'expense',
        amount: '1234.56',
        description: 'Bonifico a Mario Rossi',
        notes: 'nota riservata',
        reference: 'FT-0001',
        rowFingerprint: 'a' * 64,
      );

      final text = row.toString();
      expect(text, contains('sourceRow: 7'));
      expect(text, isNot(contains('Mario Rossi')));
      expect(text, isNot(contains('nota riservata')));
      expect(text, isNot(contains('FT-0001')));
      expect(text, isNot(contains('1234.56')));
    });

    test('la riga di anteprima non espone importi né testi', () {
      final row = TransactionImportRow(
        sourceRow: 9,
        rawCells: const ['2026-03-04', 'Bonifico a Mario Rossi', '-1234,56'],
        status: TransactionImportRowStatus.valid,
        occurredOn: DateTime(2026, 3, 4),
        kind: TransactionKind.expense,
        amount: MoneyAmount.parse('1234,56'),
        description: 'Bonifico a Mario Rossi',
        notes: 'nota riservata',
        reference: 'FT-0001',
        rowFingerprint: 'b' * 64,
        selectedForImport: true,
      );

      final text = row.toString();
      expect(text, contains('sourceRow: 9'));
      expect(text, isNot(contains('Mario Rossi')));
      expect(text, isNot(contains('nota riservata')));
      expect(text, isNot(contains('1234')));
    });

    test('il risultato espone soltanto conteggi e identificativi', () {
      final result = TransactionImportResult(
        batchId: '11111111-1111-4111-8111-111111111111',
        importedCount: 3,
        skippedInvalidCount: 1,
        skippedDuplicateCount: 2,
        transactionIds: const ['tx-1', 'tx-2', 'tx-3'],
      );

      final text = result.toString();
      expect(text, contains('importedCount: 3'));
      expect(text, contains('transactionIdCount: 3'));
      expect(text, isNot(contains('tx-1')));
    });

    test('il codice di problema non contiene dati del movimento', () {
      const issue = TransactionImportIssue(
        severity: TransactionImportIssueSeverity.error,
        code: 'amountNotNumeric',
        sourceRow: 4,
      );

      final text = issue.toString();
      expect(text, contains('sourceRow: 4'));
      expect(text, contains('amountNotNumeric'));
      expect(text, isNot(contains('€')));
    });

    test('nessun debugPrint nel feature movimenti', () {
      final dartFiles = Directory('lib/features/transactions')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      for (final file in dartFiles) {
        expect(
          file.readAsStringSync(),
          isNot(contains('debugPrint(')),
          reason: file.path,
        );
      }
    });
  });

  group('Vincoli lato database', () {
    final sql = File(
      'supabase/migrations/20260922120002_import_transactions_rpc.sql',
    ).readAsStringSync();

    test('la RPC rifiuta employee anche aggirando la UI', () {
      expect(sql, contains("ARRAY['owner', 'admin', 'manager']"));
      expect(sql, contains('ATLAS_INSUFFICIENT_PRIVILEGES'));
      expect(sql, isNot(contains("'employee'")));
    });

    test('la RPC applica lo stesso limite di 500 righe del client', () {
      expect(sql, contains('ATLAS_IMPORT_TOO_MANY_ROWS'));
      expect(sql, contains('> 500'));
    });

    test('la RPC rifiuta righe con company_id o id', () {
      expect(
        sql,
        contains("v_elem ? 'company_id' OR v_elem ? 'id'"),
      );
    });

    test('la risposta espone soltanto conteggi e identificativi', () {
      expect(sql, contains('imported_count BIGINT'));
      expect(sql, contains('skipped_invalid_count BIGINT'));
      expect(sql, contains('skipped_duplicate_count BIGINT'));
      expect(sql, contains('transaction_ids UUID[]'));
    });
  });
}
