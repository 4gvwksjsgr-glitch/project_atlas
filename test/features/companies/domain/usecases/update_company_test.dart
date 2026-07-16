import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/companies/domain/entities/company.dart';
import 'package:project_atlas/features/companies/domain/entities/company_membership.dart';
import 'package:project_atlas/features/companies/domain/repositories/company_repository.dart';
import 'package:project_atlas/features/companies/domain/usecases/update_company.dart';

class _CompanyRepositorySpy implements CompanyRepository {
  String? lastCompanyId;
  String? lastName;
  String? lastSlug;

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
    lastCompanyId = companyId;
    lastName = name;
    lastSlug = slug;
    return Success(
      Company(
        id: companyId,
        name: name,
        slug: slug,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 2),
      ),
    );
  }

  @override
  Future<Result<List<CompanyMembership>>> getUserCompanies() =>
      throw UnimplementedError();
}

void main() {
  group('UpdateCompany', () {
    test('inoltra companyId, name e slug normalizzati', () async {
      final repository = _CompanyRepositorySpy();
      final useCase = UpdateCompany(repository);

      final result = await useCase.call(
        companyId: 'company-1',
        name: '  Acme Corp  ',
        slug: '  ACME-CORP  ',
      );

      expect(repository.lastCompanyId, 'company-1');
      expect(repository.lastName, 'Acme Corp');
      expect(repository.lastSlug, 'acme-corp');
      expect(result.isSuccess, isTrue);
      result.when(
        success: (company) {
          expect(company.id, 'company-1');
          expect(company.name, 'Acme Corp');
          expect(company.slug, 'acme-corp');
        },
        error: (_) => fail('Expected success'),
      );
    });
  });
}
