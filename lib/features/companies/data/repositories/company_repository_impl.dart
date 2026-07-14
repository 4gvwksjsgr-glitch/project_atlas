import '../../../../core/errors/company_error_mapper.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/company.dart';
import '../../domain/entities/company_membership.dart';
import '../../domain/repositories/company_repository.dart';
import '../datasource/company_remote_datasource.dart';

class CompanyRepositoryImpl implements CompanyRepository {
  const CompanyRepositoryImpl(this._remoteDataSource);

  final CompanyRemoteDataSource _remoteDataSource;

  @override
  Future<Result<Company>> createCompany({
    required String name,
    required String slug,
  }) async {
    try {
      final company = await _remoteDataSource.createCompany(
        name: name,
        slug: slug,
      );
      return Success(company.toEntity());
    } on Object catch (error) {
      return Error(
        CompanyErrorMapper.mapException(error, CompanyOperation.createCompany),
      );
    }
  }

  @override
  Future<Result<List<CompanyMembership>>> getUserCompanies() async {
    try {
      final memberships = await _remoteDataSource.getUserCompanies();
      return Success(memberships.map((model) => model.toEntity()).toList());
    } on Object catch (error) {
      return Error(
        CompanyErrorMapper.mapException(
          error,
          CompanyOperation.getUserCompanies,
        ),
      );
    }
  }
}
