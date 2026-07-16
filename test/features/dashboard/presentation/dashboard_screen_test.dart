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
import 'package:project_atlas/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:project_atlas/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:project_atlas/features/dashboard/domain/usecases/get_dashboard_summary.dart';
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

class _ToggleFailRepository implements DashboardRepository {
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

  void switchTo(ActiveCompanyContext context) {
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

  group('DashboardScreen', () {
    testWidgets('mostra loading nella card membri', (tester) async {
      final repository = _FakeDashboardRepository(
        countsByCompanyId: {'c1': 2},
        delay: const Duration(milliseconds: 100),
      );

      await pumpDashboard(
        tester,
        overrides: [
          authControllerProvider.overrideWith(_IdleAuthController.new),
          activeCompanyControllerProvider.overrideWith(
            () => _SwitchableActiveCompany(
              _context(companyId: 'c1', name: 'Acme', slug: 'acme'),
            ),
          ),
          getDashboardSummaryUseCaseProvider.overrideWithValue(
            GetDashboardSummary(repository),
          ),
        ],
      );
      await tester.pump();

      expect(find.textContaining('Azienda: Acme'), findsOneWidget);
      expect(find.textContaining('Slug: acme'), findsOneWidget);
      expect(find.textContaining('Ruolo:'), findsOneWidget);
      expect(find.text('Caricamento membri...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('2 membri'), findsOneWidget);
    });

    testWidgets('mostra conteggio membri in data', (tester) async {
      await pumpDashboard(
        tester,
        overrides: [
          authControllerProvider.overrideWith(_IdleAuthController.new),
          activeCompanyControllerProvider.overrideWith(
            () => _SwitchableActiveCompany(
              _context(companyId: 'c1', name: 'Acme', slug: 'acme'),
            ),
          ),
          getDashboardSummaryUseCaseProvider.overrideWithValue(
            GetDashboardSummary(
              _FakeDashboardRepository(countsByCompanyId: {'c1': 5}),
            ),
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.text('5 membri'), findsOneWidget);
      expect(find.byIcon(Icons.insights_outlined), findsNothing);
    });

    testWidgets('mostra errore e Riprova', (tester) async {
      final repository = _ToggleFailRepository();

      await pumpDashboard(
        tester,
        overrides: [
          authControllerProvider.overrideWith(_IdleAuthController.new),
          activeCompanyControllerProvider.overrideWith(
            () => _SwitchableActiveCompany(
              _context(companyId: 'c1', name: 'Acme', slug: 'acme'),
            ),
          ),
          getDashboardSummaryUseCaseProvider.overrideWithValue(
            GetDashboardSummary(repository),
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Caricamento membri non riuscito. Riprova.'),
        findsOneWidget,
      );
      expect(find.text('Riprova'), findsOneWidget);

      repository.shouldFail = false;
      await tester.tap(find.text('Riprova'));
      await tester.pumpAndSettle();

      expect(find.text('1 membro'), findsOneWidget);
      expect(repository.callCount, 2);
    });

    testWidgets('stato difensivo senza azienda attiva', (tester) async {
      await pumpDashboard(
        tester,
        overrides: [
          authControllerProvider.overrideWith(_IdleAuthController.new),
          activeCompanyControllerProvider.overrideWith(
            () => _SwitchableActiveCompany(null),
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Nessuna azienda attiva'), findsOneWidget);
      expect(find.text('Membri'), findsNothing);
    });

    testWidgets(
      'cambio azienda A→B richiede nuovo ID e non mostra conteggio A',
      (tester) async {
        final repository = _FakeDashboardRepository(
          countsByCompanyId: {'company-a': 10, 'company-b': 2},
          delay: const Duration(milliseconds: 50),
        );
        late _SwitchableActiveCompany controller;

        await pumpDashboard(
          tester,
          overrides: [
            authControllerProvider.overrideWith(_IdleAuthController.new),
            activeCompanyControllerProvider.overrideWith(() {
              controller = _SwitchableActiveCompany(
                _context(companyId: 'company-a', name: 'Alpha', slug: 'alpha'),
              );
              return controller;
            }),
            getDashboardSummaryUseCaseProvider.overrideWithValue(
              GetDashboardSummary(repository),
            ),
          ],
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('Azienda: Alpha'), findsOneWidget);
        expect(find.text('10 membri'), findsOneWidget);
        expect(repository.requestedCompanyIds, ['company-a']);

        controller.switchTo(
          _context(companyId: 'company-b', name: 'Beta', slug: 'beta'),
        );
        await tester.pump();

        expect(find.textContaining('Azienda: Beta'), findsOneWidget);
        expect(find.textContaining('Slug: beta'), findsOneWidget);
        expect(find.text('10 membri'), findsNothing);
        expect(find.text('Caricamento membri...'), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 60));
        await tester.pumpAndSettle();

        expect(find.text('2 membri'), findsOneWidget);
        expect(find.text('10 membri'), findsNothing);
        expect(repository.requestedCompanyIds, ['company-a', 'company-b']);
      },
    );
  });
}
