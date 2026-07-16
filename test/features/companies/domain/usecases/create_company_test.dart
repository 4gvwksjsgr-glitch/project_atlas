import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/companies/domain/entities/company.dart';
import 'package:project_atlas/features/companies/domain/entities/company_membership.dart';
import 'package:project_atlas/features/companies/domain/repositories/company_repository.dart';
import 'package:project_atlas/features/companies/domain/usecases/create_company.dart';

class _CompanyRepositorySpy implements CompanyRepository {
  String? lastName;
  String? lastSlug;

  @override
  Future<Result<Company>> createCompany({
    required String name,
    required String slug,
  }) async {
    lastName = name;
    lastSlug = slug;
    return Success(
      Company(
        id: 'company-1',
        name: 'Acme',
        slug: 'acme',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
  }

  @override
  Future<Result<Company>> updateCompany({
    required String companyId,
    required String name,
    required String slug,
  }) => throw UnimplementedError();

  @override
  Future<Result<List<CompanyMembership>>> getUserCompanies() =>
      throw UnimplementedError();
}

void main() {
  group('CreateCompany', () {
    test('normalizza name e slug prima del repository', () async {
      final repository = _CompanyRepositorySpy();
      final useCase = CreateCompany(repository);

      await useCase.call(name: '  Acme Corp  ', slug: '  ACME-CORP  ');

      expect(repository.lastName, 'Acme Corp');
      expect(repository.lastSlug, 'acme-corp');
    });
  });
}
