import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/features/categories/data/models/transaction_category_model.dart';
import 'package:project_atlas/features/transactions/domain/entities/cash_transaction.dart';

void main() {
  group('TransactionCategoryModel', () {
    test('fromJson mappa kind e is_active', () {
      final model = TransactionCategoryModel.fromJson({
        'id': 'cat-1',
        'company_id': 'c1',
        'name': 'Software',
        'kind': 'expense',
        'is_active': true,
        'created_at': '2026-07-24T10:00:00.000Z',
        'updated_at': '2026-07-24T11:00:00.000Z',
      });

      expect(model.id, 'cat-1');
      expect(model.companyId, 'c1');
      expect(model.name, 'Software');
      expect(model.kind, TransactionKind.expense);
      expect(model.isActive, isTrue);
      expect(model.toEntity().name, 'Software');
    });

    test('fromJson mappa categoria archiviata income', () {
      final model = TransactionCategoryModel.fromJson({
        'id': 'cat-2',
        'company_id': 'c1',
        'name': 'Vendite',
        'kind': 'income',
        'is_active': false,
        'created_at': '2026-07-24T10:00:00.000Z',
        'updated_at': '2026-07-24T11:00:00.000Z',
      });

      expect(model.kind, TransactionKind.income);
      expect(model.isActive, isFalse);
    });
  });
}
