import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/features/dashboard/data/models/dashboard_cash_summary_model.dart';

void main() {
  group('DashboardCashSummaryModel', () {
    test('parsing esatto da TEXT senza double', () {
      final model = DashboardCashSummaryModel.fromJson({
        'total_income': '100.50',
        'total_expense': '25.25',
        'movement_count': 4,
        'month_income': '10.00',
        'month_expense': '0',
        'month_movement_count': 1,
      });

      expect(model.totalIncome.cents, 10050);
      expect(model.totalExpense.cents, 2525);
      expect(model.movementCount, 4);
      expect(model.monthIncome.cents, 1000);
      expect(model.monthExpense.cents, 0);
      expect(model.monthMovementCount, 1);

      final entity = model.toEntity();
      expect(entity.totalBalance.cents, 7525);
      expect(entity.monthBalance.cents, 1000);
    });

    test('totale zero valido', () {
      final model = DashboardCashSummaryModel.fromJson({
        'total_income': '0',
        'total_expense': '0.00',
        'movement_count': 0,
        'month_income': '0',
        'month_expense': '0',
        'month_movement_count': 0,
      });

      expect(model.movementCount, 0);
      expect(model.toEntity().hasNoMovements, isTrue);
      expect(model.toEntity().totalBalance.cents, 0);
    });

    test('rifiuta importi non TEXT (num/double)', () {
      expect(
        () => DashboardCashSummaryModel.fromJson({
          'total_income': 12.99,
          'total_expense': '0',
          'movement_count': 1,
          'month_income': '0',
          'month_expense': '0',
          'month_movement_count': 0,
        }),
        throwsFormatException,
      );
      expect(
        () => DashboardCashSummaryModel.fromJson({
          'total_income': 12,
          'total_expense': '0',
          'movement_count': 1,
          'month_income': '0',
          'month_expense': '0',
          'month_movement_count': 0,
        }),
        throwsFormatException,
      );
    });
  });
}
