import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/features/transactions/domain/entities/cash_transaction.dart';
import 'package:project_atlas/features/transactions/domain/value_objects/transaction_filters.dart';

void main() {
  group('TransactionFilters', () {
    test('hasActiveFilters falso quando vuoto', () {
      expect(const TransactionFilters().hasActiveFilters, isFalse);
    });

    test('hasActiveFilters vero per ciascun campo', () {
      expect(
        TransactionFilters(fromDate: DateTime(2026, 1, 1)).hasActiveFilters,
        isTrue,
      );
      expect(
        TransactionFilters(toDate: DateTime(2026, 1, 31)).hasActiveFilters,
        isTrue,
      );
      expect(
        const TransactionFilters(kind: TransactionKind.income).hasActiveFilters,
        isTrue,
      );
      expect(const TransactionFilters(clientId: 'c1').hasActiveFilters, isTrue);
      expect(
        const TransactionFilters(descriptionQuery: 'affitto').hasActiveFilters,
        isTrue,
      );
    });

    test('validationError quando from > to', () {
      final filters = TransactionFilters(
        fromDate: DateTime(2026, 2, 1),
        toDate: DateTime(2026, 1, 1),
      );
      expect(filters.validationError, isNotNull);
    });

    test('validationError null per intervallo valido', () {
      final filters = TransactionFilters(
        fromDate: DateTime(2026, 1, 1),
        toDate: DateTime(2026, 1, 31),
      );
      expect(filters.validationError, isNull);
    });

    test('clear azzera tutti i campi', () {
      final cleared = const TransactionFilters(
        kind: TransactionKind.expense,
        clientId: 'c1',
        descriptionQuery: 'x',
      ).clear();
      expect(cleared.hasActiveFilters, isFalse);
      expect(cleared.kind, isNull);
      expect(cleared.clientId, isNull);
      expect(cleared.descriptionQuery, isEmpty);
    });

    test('toString senza PII di descrizione completa', () {
      const filters = TransactionFilters(
        descriptionQuery: 'pagamento Mario Rossi',
      );
      expect(filters.toString(), isNot(contains('Mario')));
      expect(filters.toString(), contains('queryLength:'));
    });
  });
}
