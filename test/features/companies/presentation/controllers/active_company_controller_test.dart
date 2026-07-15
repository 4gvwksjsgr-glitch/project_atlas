import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/permissions/company_role.dart';
import 'package:project_atlas/features/auth/presentation/providers/auth_providers.dart';
import 'package:project_atlas/features/companies/domain/entities/company.dart';
import 'package:project_atlas/features/companies/domain/entities/company_membership.dart';
import 'package:project_atlas/features/companies/presentation/controllers/active_company_controller.dart';
import 'package:project_atlas/features/companies/presentation/controllers/active_company_resolution_coordinator.dart';
import 'package:project_atlas/features/companies/presentation/providers/company_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../test_helpers/shared_preferences_test_helper.dart';

CompanyMembership _membership() {
  return CompanyMembership(
    id: 'membership-1',
    companyId: 'company-1',
    role: CompanyRole.owner,
    joinedAt: DateTime.utc(2026, 1, 1),
    company: Company(
      id: 'company-1',
      name: 'Acme',
      slug: 'acme',
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

  group('ActiveCompanyController', () {
    test('auto-seleziona con una sola membership', () async {
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWithValue(_testSession()),
          isAuthenticatedProvider.overrideWithValue(true),
          userCompaniesProvider.overrideWith((ref) async => [_membership()]),
        ],
      );
      addTearDown(container.dispose);

      container.read(activeCompanyResolutionCoordinatorProvider);
      container.listen(activeCompanyControllerProvider, (_, _) {});
      await container.read(userCompaniesProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(activeCompanyControllerProvider);
      expect(state.resolved, isTrue);
      expect(state.context?.companyId, 'company-1');
    });

    test('clearRuntime azzera contesto senza toccare le preferenze', () async {
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWithValue(_testSession()),
          isAuthenticatedProvider.overrideWithValue(true),
          userCompaniesProvider.overrideWith((ref) async => [_membership()]),
        ],
      );
      addTearDown(container.dispose);

      container.read(activeCompanyResolutionCoordinatorProvider);
      container.listen(activeCompanyControllerProvider, (_, _) {});
      await container.read(userCompaniesProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(activeCompanyProvider), isNotNull);

      container.read(activeCompanyControllerProvider.notifier).clearRuntime();

      expect(container.read(activeCompanyProvider), isNull);
      expect(container.read(activeCompanyControllerProvider).resolved, isTrue);
    });
  });
}
