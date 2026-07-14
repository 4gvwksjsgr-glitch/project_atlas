import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/permissions/company_role.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/companies/domain/entities/company.dart';
import 'package:project_atlas/features/companies/domain/entities/company_membership.dart';
import 'package:project_atlas/features/companies/domain/repositories/company_repository.dart';
import 'package:project_atlas/features/companies/domain/usecases/get_user_companies.dart';

class _CompanyRepositorySpy implements CompanyRepository {
  @override
  Future<Result<Company>> createCompany({
    required String name,
    required String slug,
  }) => throw UnimplementedError();

  @override
  Future<Result<List<CompanyMembership>>> getUserCompanies() async {
    return Success([
      CompanyMembership(
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
      ),
    ]);
  }
}

void main() {
  group('GetUserCompanies', () {
    test('restituisce le membership dal repository', () async {
      final repository = _CompanyRepositorySpy();
      final useCase = GetUserCompanies(repository);

      final result = await useCase.call();

      expect(result.isSuccess, isTrue);
      result.when(
        success: (memberships) {
          expect(memberships, hasLength(1));
          expect(memberships.first.company.name, 'Acme');
        },
        error: (_) => fail('Expected success'),
      );
    });
  });
}
