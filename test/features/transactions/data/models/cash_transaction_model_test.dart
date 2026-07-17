import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/features/transactions/data/models/cash_transaction_model.dart';
import 'package:project_atlas/features/transactions/domain/entities/cash_transaction.dart';

void main() {
  group('CashTransactionModel.fromJson', () {
    test('mappa kind income e amount da stringa', () {
      final model = CashTransactionModel.fromJson({
        'id': 't1',
        'company_id': 'co1',
        'client_id': 'cl1',
        'kind': 'income',
        'amount': '150.00',
        'occurred_on': '2026-07-17',
        'description': 'Vendita merce',
        'notes': 'Pagato in contanti',
        'created_at': '2026-07-17T00:00:00.000Z',
        'updated_at': '2026-07-17T00:00:00.000Z',
      });

      expect(model.kind, TransactionKind.income);
      expect(model.amount.cents, 15000);
      expect(model.clientId, 'cl1');
    });

    test('mappa kind expense e amount da stringa', () {
      final model = CashTransactionModel.fromJson({
        'id': 't2',
        'company_id': 'co1',
        'client_id': null,
        'kind': 'expense',
        'amount': '12.99',
        'occurred_on': '2026-07-01',
        'description': 'Materiale ufficio',
        'notes': null,
        'created_at': '2026-07-01T00:00:00.000Z',
        'updated_at': '2026-07-01T00:00:00.000Z',
      });

      expect(model.kind, TransactionKind.expense);
      expect(model.amount.cents, 1299);
      expect(model.clientId, isNull);
    });

    test('occurred_on viene interpretato come data pura (YYYY-MM-DD)', () {
      final model = CashTransactionModel.fromJson({
        'id': 't3',
        'company_id': 'co1',
        'kind': 'income',
        'amount': '10.00',
        'occurred_on': '2026-07-17',
        'description': 'Test',
        'created_at': '2026-07-17T00:00:00.000Z',
        'updated_at': '2026-07-17T00:00:00.000Z',
      });

      expect(model.occurredOn, DateTime(2026, 7, 17));
      expect(model.occurredOn.hour, 0);
    });

    test('occurred_on come timestamp completo viene troncato alla data', () {
      final model = CashTransactionModel.fromJson({
        'id': 't4',
        'company_id': 'co1',
        'kind': 'income',
        'amount': '10.00',
        'occurred_on': '2026-07-17T00:00:00+00:00',
        'description': 'Test',
        'created_at': '2026-07-17T00:00:00.000Z',
        'updated_at': '2026-07-17T00:00:00.000Z',
      });

      expect(model.occurredOn, DateTime(2026, 7, 17));
    });

    test('amount numerico (non stringa) viene convertito comunque', () {
      final model = CashTransactionModel.fromJson({
        'id': 't5',
        'company_id': 'co1',
        'kind': 'income',
        'amount': 42.5,
        'occurred_on': '2026-07-17',
        'description': 'Test',
        'created_at': '2026-07-17T00:00:00.000Z',
        'updated_at': '2026-07-17T00:00:00.000Z',
      });

      expect(model.amount.cents, 4250);
    });
  });

  group('CashTransactionModel.toEntity', () {
    test('converte tutti i campi in CashTransaction', () {
      final model = CashTransactionModel.fromJson({
        'id': 't1',
        'company_id': 'co1',
        'client_id': 'cl1',
        'kind': 'income',
        'amount': '150.00',
        'occurred_on': '2026-07-17',
        'description': 'Vendita merce',
        'notes': 'Pagato in contanti',
        'created_at': '2026-07-17T08:00:00.000Z',
        'updated_at': '2026-07-18T09:00:00.000Z',
      });

      final entity = model.toEntity();
      expect(entity, isA<CashTransaction>());
      expect(entity.id, 't1');
      expect(entity.companyId, 'co1');
      expect(entity.clientId, 'cl1');
      expect(entity.kind, TransactionKind.income);
      expect(entity.amount.cents, 15000);
      expect(entity.occurredOn, DateTime(2026, 7, 17));
      expect(entity.description, 'Vendita merce');
      expect(entity.notes, 'Pagato in contanti');
      expect(entity.createdAt, DateTime.parse('2026-07-17T08:00:00.000Z'));
      expect(entity.updatedAt, DateTime.parse('2026-07-18T09:00:00.000Z'));
    });
  });
}
