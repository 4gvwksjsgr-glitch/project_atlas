import '../../../../core/utils/result.dart';
import '../entities/dashboard_cash_summary.dart';

abstract class DashboardCashRepository {
  Future<Result<DashboardCashSummary>> getCashSummary({
    required String companyId,
    required DateTime monthStart,
    required DateTime nextMonthStart,
  });
}
