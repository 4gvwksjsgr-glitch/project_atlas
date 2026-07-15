import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:project_atlas/core/permissions/company_role.dart';
import 'package:project_atlas/core/router/route_paths.dart';
import 'package:project_atlas/features/auth/presentation/providers/auth_providers.dart';
import 'package:project_atlas/features/companies/domain/entities/company.dart';
import 'package:project_atlas/features/companies/domain/entities/company_membership.dart';
import 'package:project_atlas/features/companies/presentation/controllers/active_company_controller.dart';
import 'package:project_atlas/features/companies/presentation/controllers/active_company_resolution_coordinator.dart';
import 'package:project_atlas/features/companies/presentation/providers/company_providers.dart';
import 'package:project_atlas/features/companies/presentation/screens/company_selector_screen.dart';
import 'package:project_atlas/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:project_atlas/l10n/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../test_helpers/shared_preferences_test_helper.dart';

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
      slug: name.toLowerCase(),
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

void main() {
  setUp(() async {
    await setUpMockSharedPreferences();
  });

  group('CompanySelectorScreen', () {
    testWidgets('mostra le aziende disponibili', (tester) async {
      final memberships = [
        _membership(companyId: 'c1', name: 'Acme'),
        _membership(companyId: 'c2', name: 'Beta'),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWithValue(_testSession()),
            isAuthenticatedProvider.overrideWithValue(true),
            userCompaniesProvider.overrideWith((ref) async => memberships),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('it'),
            home: const CompanySelectorScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Seleziona azienda'), findsOneWidget);
      expect(find.text('Acme'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
    });

    testWidgets('tap su azienda imposta contesto attivo', (tester) async {
      final memberships = [
        _membership(companyId: 'c1', name: 'Acme'),
        _membership(companyId: 'c2', name: 'Beta'),
      ];

      late ProviderContainer container;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container = ProviderContainer(
            overrides: [
              authSessionProvider.overrideWithValue(_testSession()),
              isAuthenticatedProvider.overrideWithValue(true),
              userCompaniesProvider.overrideWith((ref) async => memberships),
            ],
          ),
          child: Consumer(
            builder: (context, ref, _) {
              ref.watch(activeCompanyResolutionCoordinatorProvider);
              final router = GoRouter(
                initialLocation: RoutePaths.selectCompany,
                routes: [
                  GoRoute(
                    path: RoutePaths.selectCompany,
                    builder: (context, state) => const CompanySelectorScreen(),
                  ),
                  GoRoute(
                    path: RoutePaths.dashboard,
                    builder: (context, state) => const DashboardScreen(),
                  ),
                ],
              );

              return MaterialApp.router(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                locale: const Locale('it'),
                routerConfig: router,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      container.listen(activeCompanyControllerProvider, (_, _) {});

      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();

      expect(container.read(activeCompanyProvider)?.companyName, 'Beta');
      expect(container.read(activeCompanyProvider)?.companyId, 'c2');
      expect(find.text('Azienda: Beta'), findsOneWidget);
      addTearDown(container.dispose);
    });
  });
}
