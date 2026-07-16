import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/features/companies/data/datasource/company_remote_datasource.dart';
import 'package:project_atlas/features/companies/data/models/company_model.dart';

void main() {
  group('CompanyRemoteDataSource.updateCompany', () {
    test('esegue UPDATE filtrato per companyId e mappa la Company', () async {
      String? filteredCompanyId;
      Map<String, dynamic>? updatePayload;

      final dataSource = CompanyRemoteDataSource.test(
        updateExecutor:
            ({
              required String companyId,
              required String name,
              required String slug,
            }) async {
              filteredCompanyId = companyId;
              updatePayload = {'name': name, 'slug': slug};
              return {
                'id': companyId,
                'name': name,
                'slug': slug,
                'created_at': '2026-01-01T00:00:00.000Z',
                'updated_at': '2026-01-02T00:00:00.000Z',
              };
            },
      );

      final company = await dataSource.updateCompany(
        companyId: 'company-42',
        name: 'Nuovo Nome',
        slug: 'nuovo-slug',
      );

      expect(filteredCompanyId, 'company-42');
      expect(updatePayload, {'name': 'Nuovo Nome', 'slug': 'nuovo-slug'});
      expect(company, isA<CompanyModel>());
      expect(company.id, 'company-42');
      expect(company.name, 'Nuovo Nome');
      expect(company.slug, 'nuovo-slug');
      expect(
        CompanyRemoteDataSource.updateSelectColumns,
        'id, name, slug, created_at, updated_at',
      );
    });

    test('rifiuta companyId vuoto prima di qualsiasi UPDATE', () async {
      var executorCalled = false;
      final dataSource = CompanyRemoteDataSource.test(
        updateExecutor:
            ({
              required String companyId,
              required String name,
              required String slug,
            }) async {
              executorCalled = true;
              return {};
            },
      );

      expect(
        () =>
            dataSource.updateCompany(companyId: '', name: 'Acme', slug: 'acme'),
        throwsA(isA<ArgumentError>()),
      );
      expect(executorCalled, isFalse);
    });
  });
}
