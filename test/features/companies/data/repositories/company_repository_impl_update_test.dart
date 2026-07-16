import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/errors/failures.dart';
import 'package:project_atlas/features/companies/data/datasource/company_remote_datasource.dart';
import 'package:project_atlas/features/companies/data/repositories/company_repository_impl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

void main() {
  group('CompanyRepositoryImpl.updateCompany', () {
    test('mappa la risposta datasource in Company', () async {
      final repository = CompanyRepositoryImpl(
        CompanyRemoteDataSource.test(
          updateExecutor:
              ({
                required String companyId,
                required String name,
                required String slug,
              }) async {
                return {
                  'id': companyId,
                  'name': name,
                  'slug': slug,
                  'created_at': '2026-01-01T00:00:00.000Z',
                  'updated_at': '2026-01-02T00:00:00.000Z',
                };
              },
        ),
      );

      final result = await repository.updateCompany(
        companyId: 'c1',
        name: 'Acme',
        slug: 'acme',
      );

      expect(result.isSuccess, isTrue);
      result.when(
        success: (company) {
          expect(company.id, 'c1');
          expect(company.name, 'Acme');
          expect(company.slug, 'acme');
        },
        error: (_) => fail('Expected success'),
      );
    });

    test('mappa slug duplicato in ValidationFailure', () async {
      final repository = CompanyRepositoryImpl(
        CompanyRemoteDataSource.test(
          updateExecutor:
              ({
                required String companyId,
                required String name,
                required String slug,
              }) async {
                throw const supabase.PostgrestException(
                  message: 'duplicate key value violates unique constraint',
                  code: '23505',
                );
              },
        ),
      );

      final result = await repository.updateCompany(
        companyId: 'c1',
        name: 'Acme',
        slug: 'acme',
      );

      expect(result.isError, isTrue);
      result.when(
        success: (_) => fail('Expected error'),
        error: (failure) {
          expect(failure, isA<ValidationFailure>());
          expect(failure.message, contains('slug'));
        },
      );
    });
  });
}
