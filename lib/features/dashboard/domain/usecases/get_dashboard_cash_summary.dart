import '../../../../core/utils/result.dart';
import '../../../transactions/domain/value_objects/calendar_date.dart';
import '../entities/dashboard_cash_summary.dart';
import '../repositories/dashboard_cash_repository.dart';

class GetDashboardCashSummary {
  const GetDashboardCashSummary(this._repository);

  final DashboardCashRepository _repository;

  Future<Result<DashboardCashSummary>> call({
    required String companyId,
    DateTime? now,
  }) {
    final bounds = CalendarDate.currentMonthBounds(now);
    return _repository.getCashSummary(
      companyId: companyId,
      monthStart: bounds.monthStart,
      nextMonthStart: bounds.nextMonthStart,
    );
  }
}
