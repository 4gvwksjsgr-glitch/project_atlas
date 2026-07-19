import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/errors/failures.dart';
import 'package:project_atlas/core/permissions/company_role.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/auth/presentation/controllers/auth_controller.dart';
import 'package:project_atlas/features/companies/domain/entities/active_company_context.dart';
import 'package:project_atlas/features/companies/presentation/controllers/active_company_controller.dart';
import 'package:project_atlas/features/companies/presentation/controllers/active_company_state.dart';
import 'package:project_atlas/features/dashboard/domain/entities/dashboard_cash_summary.dart';
import 'package:project_atlas/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:project_atlas/features/dashboard/domain/repositories/dashboard_cash_repository.dart';
import 'package:project_atlas/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:project_atlas/features/dashboard/domain/usecases/get_dashboard_cash_summary.dart';
import 'package:project_atlas/features/dashboard/domain/usecases/get_dashboard_summary.dart';
import 'package:project_atlas/features/dashboard/domain/value_objects/money_total.dart';
import 'package:project_atlas/features/dashboard/presentation/providers/dashboard_cash_providers.dart';
import 'package:project_atlas/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:project_atlas/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:project_atlas/l10n/app_localizations.dart';

ActiveCompanyContext _context({
  required String companyId,
  required String name,
  required String slug,
}) {
  return ActiveCompanyContext(
    companyId: companyId,
    companyName: name,
    companySlug: slug,
    role: CompanyRole.owner,
    membershipId: 'membership-$companyId',
  );
}

DashboardCashSummary _cashSummary({
  MoneyTotal? totalIncome,
  MoneyTotal? totalExpense,
  int movementCount = 2,
  MoneyTotal? monthIncome,
  MoneyTotal? monthExpense,
  int monthMovementCount = 1,
}) {
  return DashboardCashSummary(
    totalIncome: totalIncome ?? MoneyTotal.fromCents(10000),
    totalExpense: totalExpense ?? MoneyTotal.fromCents(2500),
    movementCount: movementCount,
    monthIncome: monthIncome ?? MoneyTotal.fromCents(5000),
    monthExpense: monthExpense ?? MoneyTotal.fromCents(1000),
    monthMovementCount: monthMovementCount,
  );
}

class _FakeDashboardRepository implements DashboardRepository {
  _FakeDashboardRepository({
    required this.countsByCompanyId,
    this.delay = Duration.zero,
  });

  final Map<String, int> countsByCompanyId;
  final Duration delay;
  final List<String> requestedCompanyIds = [];

  @override
  Future<Result<DashboardSummary>> getSummary({
    required String companyId,
  }) async {
    requestedCompanyIds.add(companyId);
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    final count = countsByCompanyId[companyId];
    if (count == null) {
      return const Error(UnknownFailure('Azienda sconosciuta'));
    }
    return Success(DashboardSummary(memberCount: count));
  }
}

class _FakeCashRepository implements DashboardCashRepository {
  _FakeCashRepository({
    required this.summariesByCompanyId,
    this.delay = Duration.zero,
    this.failCompanyIds = const {},
  });

  final Map<String, DashboardCashSummary> summariesByCompanyId;
  final Duration delay;
  final Set<String> failCompanyIds;
  final List<String> requestedCompanyIds = [];
  int callCount = 0;
  bool shouldFail = false;

  @override
  Future<Result<DashboardCashSummary>> getCashSummary({
    required String companyId,
    required DateTime monthStart,
    required DateTime nextMonthStart,
  }) async {
    callCount += 1;
    requestedCompanyIds.add(companyId);
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (shouldFail || failCompanyIds.contains(companyId)) {
      return const Error(
        UnknownFailure(
          'Caricamento riepilogo economico non riuscito. Riprova.',
        ),
      );
    }
    final summary = summariesByCompanyId[companyId];
    if (summary == null) {
      return const Error(UnknownFailure('Azienda sconosciuta'));
    }
    return Success(summary);
  }
}

class _ToggleFailMembersRepository implements DashboardRepository {
  bool shouldFail = true;
  int callCount = 0;

  @override
  Future<Result<DashboardSummary>> getSummary({
    required String companyId,
  }) async {
    callCount += 1;
    if (shouldFail) {
      return const Error(
        UnknownFailure('Caricamento membri non riuscito. Riprova.'),
      );
    }
    return const Success(DashboardSummary(memberCount: 1));
  }
}

class _IdleAuthController extends AuthController {
  @override
  AuthControllerState build() => const AuthControllerState();
}

class _SwitchableActiveCompany extends ActiveCompanyController {
  _SwitchableActiveCompany(this._initial);

  final ActiveCompanyContext? _initial;

  @override
  ActiveCompanyState build() {
    return ActiveCompanyState(context: _initial, resolved: true);
  }

  void switchTo(ActiveCompanyContext? context) {
    state = ActiveCompanyState(context: context, resolved: true);
  }
}

void main() {
  Future<void> pumpDashboard(
    WidgetTester tester, {
    required List<Override> overrides,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('it'),
          home: Scaffold(body: DashboardScreen()),
        ),
      ),
    );
  }

  List<Override> baseOverrides({
    required DashboardRepository membersRepo,
    required DashboardCashRepository cashRepo,
    required ActiveCompanyContext? company,
    _SwitchableActiveCompany Function()? companyFactory,
  }) {
    return [
      authControllerProvider.overrideWith(_IdleAuthController.new),
      activeCompanyControllerProvider.overrideWith(
        companyFactory ?? () => _SwitchableActiveCompany(company),
      ),
      getDashboardSummaryUseCaseProvider.overrideWithValue(
        GetDashboardSummary(membersRepo),
      ),
      getDashboardCashSummaryUseCaseProvider.overrideWithValue(
        GetDashboardCashSummary(cashRepo),
      ),
    ];
  }

  group('DashboardScreen', () {
    testWidgets('mostra loading nella card membri', (tester) async {
      final membersRepo = _FakeDashboardRepository(
        countsByCompanyId: {'c1': 2},
        delay: const Duration(milliseconds: 100),
      );
      final cashRepo = _FakeCashRepository(
        summariesByCompanyId: {'c1': _cashSummary()},
      );

      await pumpDashboard(
        tester,
        overrides: baseOverrides(
          membersRepo: membersRepo,
          cashRepo: cashRepo,
          company: _context(companyId: 'c1', name: 'Acme', slug: 'acme'),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Azienda: Acme'), findsOneWidget);
      expect(find.text('Caricamento membri...'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('2 membri'), findsOneWidget);
    });

    testWidgets('mostra conteggio membri in data', (tester) async {
      await pumpDashboard(
        tester,
        overrides: baseOverrides(
          membersRepo: _FakeDashboardRepository(countsByCompanyId: {'c1': 5}),
          cashRepo: _FakeCashRepository(
            summariesByCompanyId: {'c1': _cashSummary()},
          ),
          company: _context(companyId: 'c1', name: 'Acme', slug: 'acme'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('5 membri'), findsOneWidget);
      expect(find.byIcon(Icons.insights_outlined), findsNothing);
    });

    testWidgets('mostra errore e Riprova membri', (tester) async {
      final repository = _ToggleFailMembersRepository();

      await pumpDashboard(
        tester,
        overrides: baseOverrides(
          membersRepo: repository,
          cashRepo: _FakeCashRepository(
            summariesByCompanyId: {'c1': _cashSummary()},
          ),
          company: _context(companyId: 'c1', name: 'Acme', slug: 'acme'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Caricamento membri non riuscito. Riprova.'),
        findsOneWidget,
      );

      repository.shouldFail = false;
      final retry = find.descendant(
        of: find.widgetWithText(Card, 'Membri'),
        matching: find.widgetWithText(OutlinedButton, 'Riprova'),
      );
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(find.text('1 membro'), findsOneWidget);
      expect(repository.callCount, 2);
    });

    testWidgets('stato difensivo senza azienda attiva', (tester) async {
      await pumpDashboard(
        tester,
        overrides: baseOverrides(
          membersRepo: _FakeDashboardRepository(countsByCompanyId: {}),
          cashRepo: _FakeCashRepository(summariesByCompanyId: {}),
          company: null,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Nessuna azienda attiva'), findsOneWidget);
      expect(find.text('Membri'), findsNothing);
      expect(find.text('Riepilogo economico'), findsNothing);
    });

    testWidgets(
      'cambio azienda A→B richiede nuovo ID e non mostra conteggio A',
      (tester) async {
        final repository = _FakeDashboardRepository(
          countsByCompanyId: {'company-a': 10, 'company-b': 2},
          delay: const Duration(milliseconds: 50),
        );
        final cashRepo = _FakeCashRepository(
          summariesByCompanyId: {
            'company-a': _cashSummary(movementCount: 99),
            'company-b': _cashSummary(movementCount: 3),
          },
          delay: const Duration(milliseconds: 50),
        );
        late _SwitchableActiveCompany controller;

        await pumpDashboard(
          tester,
          overrides: baseOverrides(
            membersRepo: repository,
            cashRepo: cashRepo,
            company: null,
            companyFactory: () {
              controller = _SwitchableActiveCompany(
                _context(companyId: 'company-a', name: 'Alpha', slug: 'alpha'),
              );
              return controller;
            },
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('10 membri'), findsOneWidget);
        expect(find.text('99'), findsWidgets);

        controller.switchTo(
          _context(companyId: 'company-b', name: 'Beta', slug: 'beta'),
        );
        await tester.pump();

        expect(find.text('10 membri'), findsNothing);
        expect(find.text('99'), findsNothing);
        expect(find.text('Caricamento membri...'), findsOneWidget);
        expect(find.text('Caricamento riepilogo economico...'), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 60));
        await tester.pumpAndSettle();

        expect(find.text('2 membri'), findsOneWidget);
        expect(find.text('3'), findsWidgets);
        expect(find.text('10 membri'), findsNothing);
        expect(repository.requestedCompanyIds, ['company-a', 'company-b']);
        expect(cashRepo.requestedCompanyIds, ['company-a', 'company-b']);
      },
    );
  });

  group('DashboardCashCard', () {
    testWidgets('loading, data e empty della sola card economica', (
      tester,
    ) async {
      final cashRepo = _FakeCashRepository(
        summariesByCompanyId: {
          'c1': _cashSummary(
            totalIncome: MoneyTotal.zero,
            totalExpense: MoneyTotal.zero,
            movementCount: 0,
            monthIncome: MoneyTotal.zero,
            monthExpense: MoneyTotal.zero,
            monthMovementCount: 0,
          ),
        },
        delay: const Duration(milliseconds: 80),
      );

      await pumpDashboard(
        tester,
        overrides: baseOverrides(
          membersRepo: _FakeDashboardRepository(
            countsByCompanyId: {'c1': 1},
            delay: const Duration(milliseconds: 80),
          ),
          cashRepo: cashRepo,
          company: _context(companyId: 'c1', name: 'Acme', slug: 'acme'),
        ),
      );
      await tester.pump();

      expect(find.text('Caricamento riepilogo economico...'), findsOneWidget);
      expect(find.text('Caricamento membri...'), findsOneWidget);
      expect(find.text('Nessun movimento ancora'), findsNothing);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.text('Riepilogo economico'), findsOneWidget);
      expect(find.text('Nessun movimento ancora'), findsOneWidget);
      expect(find.text('0,00 €'), findsWidgets);
      expect(find.text('Totale'), findsOneWidget);
      expect(find.text('Mese corrente'), findsOneWidget);
      expect(find.text('1 membro'), findsOneWidget);
    });

    testWidgets('errore e retry solo della card economica', (tester) async {
      final cashRepo = _FakeCashRepository(
        summariesByCompanyId: {'c1': _cashSummary()},
      )..shouldFail = true;
      final membersRepo = _FakeDashboardRepository(
        countsByCompanyId: {'c1': 4},
      );

      await pumpDashboard(
        tester,
        overrides: baseOverrides(
          membersRepo: membersRepo,
          cashRepo: cashRepo,
          company: _context(companyId: 'c1', name: 'Acme', slug: 'acme'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Caricamento riepilogo economico non riuscito. Riprova.'),
        findsOneWidget,
      );
      expect(find.text('4 membri'), findsOneWidget);

      cashRepo.shouldFail = false;
      final retry = find.descendant(
        of: find.widgetWithText(Card, 'Riepilogo economico'),
        matching: find.widgetWithText(OutlinedButton, 'Riprova'),
      );
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(find.text('Riepilogo economico'), findsOneWidget);
      expect(find.text('100,00 €'), findsOneWidget);
      expect(find.text('4 membri'), findsOneWidget);
      expect(cashRepo.callCount, 2);
      expect(membersRepo.requestedCompanyIds, ['c1']);
    });

    testWidgets('errore economico non rompe la card Membri', (tester) async {
      await pumpDashboard(
        tester,
        overrides: baseOverrides(
          membersRepo: _FakeDashboardRepository(countsByCompanyId: {'c1': 7}),
          cashRepo: _FakeCashRepository(
            summariesByCompanyId: {},
            failCompanyIds: {'c1'},
          ),
          company: _context(companyId: 'c1', name: 'Acme', slug: 'acme'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('7 membri'), findsOneWidget);
      expect(
        find.text('Caricamento riepilogo economico non riuscito. Riprova.'),
        findsOneWidget,
      );
      expect(find.text('Membri'), findsOneWidget);
    });

    testWidgets('logout nasconde card economiche e membri', (tester) async {
      late _SwitchableActiveCompany controller;

      await pumpDashboard(
        tester,
        overrides: baseOverrides(
          membersRepo: _FakeDashboardRepository(countsByCompanyId: {'c1': 2}),
          cashRepo: _FakeCashRepository(
            summariesByCompanyId: {'c1': _cashSummary()},
          ),
          company: null,
          companyFactory: () {
            controller = _SwitchableActiveCompany(
              _context(companyId: 'c1', name: 'Acme', slug: 'acme'),
            );
            return controller;
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Riepilogo economico'), findsOneWidget);
      expect(find.text('2 membri'), findsOneWidget);

      controller.switchTo(null);
      await tester.pumpAndSettle();

      expect(find.textContaining('Nessuna azienda attiva'), findsOneWidget);
      expect(find.text('Riepilogo economico'), findsNothing);
      expect(find.text('Membri'), findsNothing);

      controller.switchTo(
        _context(companyId: 'c1', name: 'Acme', slug: 'acme'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Riepilogo economico'), findsOneWidget);
      expect(find.text('2 membri'), findsOneWidget);
    });
  });
}
