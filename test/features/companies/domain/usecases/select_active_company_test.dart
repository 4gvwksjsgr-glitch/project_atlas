import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/permissions/company_role.dart';
import 'package:project_atlas/core/storage/app_shared_preferences.dart';
import 'package:project_atlas/features/companies/data/datasource/active_company_local_datasource.dart';
import 'package:project_atlas/features/companies/data/repositories/active_company_repository_impl.dart';
import 'package:project_atlas/features/companies/domain/entities/company.dart';
import 'package:project_atlas/features/companies/domain/entities/company_membership.dart';
import 'package:project_atlas/features/companies/domain/usecases/select_active_company.dart';
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

void main() {
  setUp(() async {
    await setUpMockSharedPreferences();
  });

  group('SelectActiveCompany', () {
    test('persiste active_company_id per user_id', () async {
      final preferences = appSharedPreferences!;
      final repository = ActiveCompanyRepositoryImpl(
        ActiveCompanyLocalDataSource(preferences),
      );
      final useCase = SelectActiveCompany(repository);
      const userId = 'user-1';

      final context = await useCase.call(
        userId: userId,
        membership: _membership(
          companyId: 'company-1',
          name: 'Acme',
          slug: 'acme',
        ),
      );

      expect(context.companyId, 'company-1');
      expect(
        preferences.getString(
          ActiveCompanyLocalDataSource.storageKeyForUser(userId),
        ),
        'company-1',
      );
    });

    test('due utenti diversi non condividono la selezione', () async {
      final preferences = appSharedPreferences!;
      final repository = ActiveCompanyRepositoryImpl(
        ActiveCompanyLocalDataSource(preferences),
      );
      final useCase = SelectActiveCompany(repository);

      await useCase.call(
        userId: 'user-1',
        membership: _membership(
          companyId: 'company-a',
          name: 'Acme',
          slug: 'acme',
        ),
      );
      await useCase.call(
        userId: 'user-2',
        membership: _membership(
          companyId: 'company-b',
          name: 'Beta',
          slug: 'beta',
        ),
      );

      expect(
        preferences.getString(
          ActiveCompanyLocalDataSource.storageKeyForUser('user-1'),
        ),
        'company-a',
      );
      expect(
        preferences.getString(
          ActiveCompanyLocalDataSource.storageKeyForUser('user-2'),
        ),
        'company-b',
      );
    });
  });
}
