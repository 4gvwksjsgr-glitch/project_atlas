import '../value_objects/money_total.dart';
import '../value_objects/signed_money_value.dart';

/// Riepilogo economico Dashboard per l'azienda attiva.
class DashboardCashSummary {
  const DashboardCashSummary({
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

  SignedMoneyValue get totalBalance => SignedMoneyValue.fromDifference(
    income: totalIncome,
    expense: totalExpense,
  );

  SignedMoneyValue get monthBalance => SignedMoneyValue.fromDifference(
    income: monthIncome,
    expense: monthExpense,
  );

  bool get hasNoMovements => movementCount == 0;
}
