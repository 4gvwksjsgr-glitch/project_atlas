import '../../../../core/errors/company_error_mapper.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/dashboard_cash_summary.dart';
import '../../domain/repositories/dashboard_cash_repository.dart';
import '../datasource/dashboard_cash_remote_datasource.dart';

class DashboardCashRepositoryImpl implements DashboardCashRepository {
  const DashboardCashRepositoryImpl(this._remoteDataSource);

  final DashboardCashRemoteDataSource _remoteDataSource;

  @override
  Future<Result<DashboardCashSummary>> getCashSummary({
    required String companyId,
    required DateTime monthStart,
    required DateTime nextMonthStart,
  }) async {
    if (companyId.isEmpty) {
      return const Error(ValidationFailure('Azienda non valida.'));
    }

    try {
      final model = await _remoteDataSource.getCashSummary(
        companyId: companyId,
        monthStart: monthStart,
        nextMonthStart: nextMonthStart,
      );
      return Success(model.toEntity());
    } on FormatException catch (error) {
      return Error(ValidationFailure(error.message));
    } on Object catch (error) {
      return Error(
        CompanyErrorMapper.mapException(
          error,
          CompanyOperation.getCompanyCashSummary,
        ),
      );
    }
  }
}
