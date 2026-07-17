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
import 'package:project_atlas/features/clients/presentation/screens/customers_screen.dart';
import 'package:project_atlas/features/companies/data/datasource/active_company_local_datasource.dart';
import 'package:project_atlas/features/companies/domain/entities/company.dart';
import 'package:project_atlas/features/companies/domain/entities/company_membership.dart';
import 'package:project_atlas/features/companies/domain/repositories/company_repository.dart';
import 'package:project_atlas/features/companies/domain/usecases/update_company.dart';
import 'package:project_atlas/features/companies/presentation/controllers/active_company_controller.dart';
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
final _settingsNavigatorKey = GlobalKey<NavigatorState>();

CompanyMembership _membership({
  required String companyId,
  required String name,
  required String slug,
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
      slug: slug,
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

class _UpdateRepository implements CompanyRepository {
  _UpdateRepository({
    required this.memberships,
    this.result,
    this.delay = Duration.zero,
  });

  Result<Company>? result;
  final Duration delay;
  int callCount = 0;
  List<CompanyMembership> memberships;

  @override
  Future<Result<Company>> createCompany({
    required String name,
    required String slug,
  }) => throw UnimplementedError();

  @override
  Future<Result<Company>> updateCompany({
    required String companyId,
    required String name,
    required String slug,
  }) async {
    callCount += 1;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (result != null) {
      return result!;
    }
    final updated = Company(
      id: companyId,
      name: name,
      slug: slug,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 2),
    );
    memberships = memberships
        .map(
          (m) => m.companyId == companyId
              ? CompanyMembership(
                  id: m.id,
                  companyId: m.companyId,
                  role: m.role,
                  joinedAt: m.joinedAt,
                  company: updated,
                )
              : m,
        )
        .toList();
    return Success(updated);
  }

  @override
  Future<Result<List<CompanyMembership>>> getUserCompanies() async {
    return Success(memberships);
  }
}

Future<(ProviderContainer, GoRouter)> _pumpSettings({
  required WidgetTester tester,
  required CompanyRepository repository,
  String initialCompanyId = 'c1',
  String initialLocation = RoutePaths.settingsCompany,
}) async {
  const userId = 'user-1';
  await ActiveCompanyLocalDataSource(
    appSharedPreferences!,
  ).persistActiveCompanyId(userId: userId, companyId: initialCompanyId);

  late ProviderContainer container;
  GoRouter? router;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWithValue(_testSession()),
          isAuthenticatedProvider.overrideWithValue(true),
          isPasswordRecoveryActiveProvider.overrideWithValue(false),
          companyRepositoryProvider.overrideWithValue(repository),
          updateCompanyUseCaseProvider.overrideWithValue(
            UpdateCompany(repository),
          ),
          userCompaniesProvider.overrideWith((ref) async {
            final result = await repository.getUserCompanies();
            return result.when(
              success: (value) => value,
              error: (failure) => throw StateError(failure.message),
            );
          }),
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

  group('CompanySettingsScreen', () {
    testWidgets('owner vede form modificabile e salva aggiornando il chip', (
      tester,
    ) async {
      final repository = _UpdateRepository(
        memberships: [_membership(companyId: 'c1', name: 'Acme', slug: 'acme')],
      );

      final (container, _) = await _pumpSettings(
        tester: tester,
        repository: repository,
      );
      addTearDown(container.dispose);

      expect(find.text('Acme · Proprietario'), findsOneWidget);
      expect(find.text('Salva modifiche'), findsOneWidget);

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Acme Aggiornata',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'acme-aggiornata',
      );
      await tester.tap(find.text('Salva modifiche'));
      await tester.pumpAndSettle();

      expect(find.text('Azienda aggiornata correttamente.'), findsOneWidget);
      expect(find.text('Acme Aggiornata · Proprietario'), findsOneWidget);
      expect(
        container.read(activeCompanyProvider)?.companySlug,
        'acme-aggiornata',
      );
    });

    testWidgets('manager vede sola lettura senza pulsante salva', (
      tester,
    ) async {
      final repository = _UpdateRepository(
        memberships: [
          _membership(
            companyId: 'c1',
            name: 'Acme',
            slug: 'acme',
            role: CompanyRole.manager,
          ),
        ],
      );

      final (container, _) = await _pumpSettings(
        tester: tester,
        repository: repository,
      );
      addTearDown(container.dispose);

      expect(find.text('Salva modifiche'), findsNothing);
      expect(
        find.textContaining('Non hai i permessi per modificare'),
        findsOneWidget,
      );
    });

    testWidgets('pulsante disabilitato durante il salvataggio', (tester) async {
      final repository = _UpdateRepository(
        memberships: [_membership(companyId: 'c1', name: 'Acme', slug: 'acme')],
        delay: const Duration(milliseconds: 300),
      );

      final (container, _) = await _pumpSettings(
        tester: tester,
        repository: repository,
      );
      addTearDown(container.dispose);

      await tester.enterText(find.byType(TextFormField).at(0), 'Nuovo');
      await tester.tap(find.text('Salva modifiche'));
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);

      await tester.pumpAndSettle();
    });

    testWidgets('errore conserva i valori inseriti', (tester) async {
      final repository = _UpdateRepository(
        memberships: [_membership(companyId: 'c1', name: 'Acme', slug: 'acme')],
        result: const Error(
          ValidationFailure('Questo slug è già in uso. Scegline un altro.'),
        ),
      );

      final (container, _) = await _pumpSettings(
        tester: tester,
        repository: repository,
      );
      addTearDown(container.dispose);

      await tester.enterText(find.byType(TextFormField).at(0), 'Tentativo');
      await tester.enterText(find.byType(TextFormField).at(1), 'slug-preso');
      await tester.tap(find.text('Salva modifiche'));
      await tester.pumpAndSettle();

      expect(
        find.text('Questo slug è già in uso. Scegline un altro.'),
        findsOneWidget,
      );
      expect(find.text('Tentativo'), findsOneWidget);
      expect(find.text('slug-preso'), findsOneWidget);
    });

    testWidgets('cambio A → B ricrea il form senza dati obsoleti', (
      tester,
    ) async {
      final repository = _UpdateRepository(
        memberships: [
          _membership(companyId: 'c1', name: 'Acme', slug: 'acme'),
          _membership(companyId: 'c2', name: 'Beta', slug: 'beta'),
        ],
      );

      final (container, _) = await _pumpSettings(
        tester: tester,
        repository: repository,
      );
      addTearDown(container.dispose);

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Bozza non salvata',
      );
      expect(find.text('Bozza non salvata'), findsOneWidget);

      await tester.tap(find.byType(ActiveCompanyChip));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Impostazioni'));
      await tester.pumpAndSettle();

      expect(find.text('Bozza non salvata'), findsNothing);
      expect(
        (tester.widget<TextFormField>(
          find.byType(TextFormField).at(0),
        )).controller?.text,
        'Beta',
      );
      expect(
        (tester.widget<TextFormField>(
          find.byType(TextFormField).at(1),
        )).controller?.text,
        'beta',
      );
    });

    testWidgets(
      'logout/login ripristina i valori persistiti dalle membership',
      (tester) async {
        final repository = _UpdateRepository(
          memberships: [
            _membership(
              companyId: 'c1',
              name: 'Nome Persistito',
              slug: 'nome-persistito',
            ),
          ],
        );

        final (container, router) = await _pumpSettings(
          tester: tester,
          repository: repository,
        );
        addTearDown(container.dispose);

        expect(
          (tester.widget<TextFormField>(
            find.byType(TextFormField).at(0),
          )).controller?.text,
          'Nome Persistito',
        );
        expect(
          (tester.widget<TextFormField>(
            find.byType(TextFormField).at(1),
          )).controller?.text,
          'nome-persistito',
        );

        // Simula logout (clear runtime) e login con selezione persistita.
        container.read(activeCompanyControllerProvider.notifier).clearRuntime();
        await tester.pumpAndSettle();

        await ActiveCompanyLocalDataSource(
          appSharedPreferences!,
        ).persistActiveCompanyId(userId: 'user-1', companyId: 'c1');

        container.invalidate(userCompaniesProvider);
        await container
            .read(activeCompanyControllerProvider.notifier)
            .selectByCompanyId('c1');
        router.go(RoutePaths.settingsCompany);
        await tester.pumpAndSettle();

        expect(
          container.read(activeCompanyProvider)?.companyName,
          'Nome Persistito',
        );
        expect(
          container.read(activeCompanyProvider)?.companySlug,
          'nome-persistito',
        );
        expect(
          (tester.widget<TextFormField>(
            find.byType(TextFormField).at(0),
          )).controller?.text,
          'Nome Persistito',
        );
        expect(
          (tester.widget<TextFormField>(
            find.byType(TextFormField).at(1),
          )).controller?.text,
          'nome-persistito',
        );
      },
    );
  });
}
