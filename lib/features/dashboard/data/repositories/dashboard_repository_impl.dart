import '../../../../core/errors/company_error_mapper.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/dashboard_summary.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../datasource/dashboard_remote_datasource.dart';

class DashboardRepositoryImpl implements DashboardRepository {
  const DashboardRepositoryImpl(this._remoteDataSource);

  final DashboardRemoteDataSource _remoteDataSource;

  @override
  Future<Result<DashboardSummary>> getSummary({
    required String companyId,
  }) async {
    if (companyId.isEmpty) {
      return const Error(ValidationFailure('Azienda non valida.'));
    }

    try {
      final memberCount = await _remoteDataSource.countCompanyMembers(
        companyId: companyId,
      );
      return Success(DashboardSummary(memberCount: memberCount));
    } on Object catch (error) {
      return Error(
        CompanyErrorMapper.mapException(
          error,
          CompanyOperation.countCompanyMembers,
        ),
      );
    }
  }
}
