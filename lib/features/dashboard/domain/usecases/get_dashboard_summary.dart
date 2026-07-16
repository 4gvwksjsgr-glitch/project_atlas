import '../../../../core/utils/result.dart';
import '../entities/dashboard_summary.dart';
import '../repositories/dashboard_repository.dart';

class GetDashboardSummary {
  const GetDashboardSummary(this._repository);

  final DashboardRepository _repository;

  Future<Result<DashboardSummary>> call({required String companyId}) {
    return _repository.getSummary(companyId: companyId);
  }
}
