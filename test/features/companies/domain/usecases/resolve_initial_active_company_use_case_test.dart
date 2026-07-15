import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/permissions/company_role.dart';
import 'package:project_atlas/core/storage/app_shared_preferences.dart';
import 'package:project_atlas/features/companies/data/datasource/active_company_local_datasource.dart';
import 'package:project_atlas/features/companies/data/repositories/active_company_repository_impl.dart';
import 'package:project_atlas/features/companies/domain/entities/company.dart';
import 'package:project_atlas/features/companies/domain/entities/company_membership.dart';
import 'package:project_atlas/features/companies/domain/usecases/resolve_initial_active_company.dart';

import '../../../../test_helpers/shared_preferences_test_helper.dart';

CompanyMembership _membership({
  required String companyId,
  required String name,
  required String slug,
}) {
  return CompanyMembership(
    id: 'membership-$companyId',
    companyId: companyId,
    role: CompanyRole.owner,
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

String _storageKey(String userId) =>
    ActiveCompanyLocalDataSource.storageKeyForUser(userId);

void main() {
  setUp(() async {
    await setUpMockSharedPreferences();
  });

  group('ResolveInitialActiveCompany', () {
    late ResolveInitialActiveCompany useCase;
    late ActiveCompanyLocalDataSource dataSource;

    setUp(() {
      final preferences = appSharedPreferences!;
      dataSource = ActiveCompanyLocalDataSource(preferences);
      useCase = ResolveInitialActiveCompany(
        ActiveCompanyRepositoryImpl(dataSource),
      );
    });

    Future<void> seedStalePersistedId({
      required String userId,
      required String companyId,
    }) async {
      await dataSource.persistActiveCompanyId(
        userId: userId,
        companyId: companyId,
      );
    }

    test('ID obsoleto con zero membership elimina la preferenza', () async {
      const userId = 'user-1';
      await seedStalePersistedId(userId: userId, companyId: 'stale-id');

      final result = await useCase.call(userId: userId, memberships: []);

      expect(result, isA<InitialActiveCompanyEmpty>());
      expect(appSharedPreferences!.getString(_storageKey(userId)), isNull);
    });

    test('ID obsoleto con una membership elimina e auto-seleziona', () async {
      const userId = 'user-1';
      await seedStalePersistedId(userId: userId, companyId: 'stale-id');
      final memberships = [
        _membership(companyId: 'c1', name: 'Acme', slug: 'acme'),
      ];

      final result = await useCase.call(
        userId: userId,
        memberships: memberships,
      );

      expect(result, isA<InitialActiveCompanyResolved>());
      final resolved = result as InitialActiveCompanyResolved;
      expect(resolved.context.companyId, 'c1');
      expect(resolved.persistSelection, isTrue);
      expect(appSharedPreferences!.getString(_storageKey(userId)), isNull);
    });

    test(
      'ID obsoleto con più membership elimina e richiede selector',
      () async {
        const userId = 'user-1';
        await seedStalePersistedId(userId: userId, companyId: 'stale-id');
        final memberships = [
          _membership(companyId: 'c1', name: 'Acme', slug: 'acme'),
          _membership(companyId: 'c2', name: 'Beta', slug: 'beta'),
        ];

        final result = await useCase.call(
          userId: userId,
          memberships: memberships,
        );

        expect(result, isA<InitialActiveCompanyNeedsSelection>());
        expect(appSharedPreferences!.getString(_storageKey(userId)), isNull);
      },
    );

    test('ID persistito valido non viene eliminato', () async {
      const userId = 'user-1';
      await seedStalePersistedId(userId: userId, companyId: 'c2');
      final memberships = [
        _membership(companyId: 'c1', name: 'Acme', slug: 'acme'),
        _membership(companyId: 'c2', name: 'Beta', slug: 'beta'),
      ];

      final result = await useCase.call(
        userId: userId,
        memberships: memberships,
      );

      expect(result, isA<InitialActiveCompanyResolved>());
      expect(appSharedPreferences!.getString(_storageKey(userId)), 'c2');
    });
  });
}
