import '../../../../core/utils/result.dart';
import '../entities/company.dart';
import '../entities/company_membership.dart';

abstract interface class CompanyRepository {
  Future<Result<Company>> createCompany({
    required String name,
    required String slug,
  });

  Future<Result<Company>> updateCompany({
    required String companyId,
    required String name,
    required String slug,
  });

  Future<Result<List<CompanyMembership>>> getUserCompanies();
}
