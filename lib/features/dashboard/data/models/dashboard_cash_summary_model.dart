import '../../domain/entities/dashboard_cash_summary.dart';
import '../../domain/value_objects/money_total.dart';

/// Payload RPC `get_company_cash_summary`. Importi solo come TEXT canonico.
class DashboardCashSummaryModel {
  const DashboardCashSummaryModel({
    required this.totalIncome,
    required this.totalExpense,
    required this.movementCount,
    required this.monthIncome,
    required this.monthExpense,
    required this.monthMovementCount,
  });

  final MoneyTotal totalIncome;
  final MoneyTotal totalExpense;
  final int movementCount;
  final MoneyTotal monthIncome;
  final MoneyTotal monthExpense;
  final int monthMovementCount;

  factory DashboardCashSummaryModel.fromJson(Map<String, dynamic> json) {
    return DashboardCashSummaryModel(
      totalIncome: MoneyTotal.fromCanonicalDecimal(
        _requireCanonicalText(json['total_income'], 'total_income'),
      ),
      totalExpense: MoneyTotal.fromCanonicalDecimal(
        _requireCanonicalText(json['total_expense'], 'total_expense'),
      ),
      movementCount: _requireCount(json['movement_count'], 'movement_count'),
      monthIncome: MoneyTotal.fromCanonicalDecimal(
        _requireCanonicalText(json['month_income'], 'month_income'),
      ),
      monthExpense: MoneyTotal.fromCanonicalDecimal(
        _requireCanonicalText(json['month_expense'], 'month_expense'),
      ),
      monthMovementCount: _requireCount(
        json['month_movement_count'],
        'month_movement_count',
      ),
    );
  }

  DashboardCashSummary toEntity() {
    return DashboardCashSummary(
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      movementCount: movementCount,
      monthIncome: monthIncome,
      monthExpense: monthExpense,
      monthMovementCount: monthMovementCount,
    );
  }

  /// Rifiuta `num`/`double`: gli importi devono arrivare come TEXT.
  static String _requireCanonicalText(Object? raw, String field) {
    if (raw is! String) {
      throw FormatException('$field deve essere una stringa TEXT', raw);
    }
    return raw;
  }

  static int _requireCount(Object? raw, String field) {
    if (raw is int) {
      if (raw < 0) {
        throw FormatException('$field non può essere negativo', raw);
      }
      return raw;
    }
    if (raw is String) {
      final parsed = int.tryParse(raw);
      if (parsed == null || parsed < 0) {
        throw FormatException('$field non valido', raw);
      }
      return parsed;
    }
    throw FormatException('$field non valido', raw);
  }
}
