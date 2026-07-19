import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/features/dashboard/domain/value_objects/money_total.dart';
import 'package:project_atlas/features/dashboard/domain/value_objects/signed_money_value.dart';
import 'package:project_atlas/features/transactions/domain/value_objects/money_amount.dart';

void main() {
  group('MoneyTotal', () {
    test('accetta zero e stringhe canoniche senza double', () {
      expect(MoneyTotal.fromCanonicalDecimal('0').cents, 0);
      expect(MoneyTotal.fromCanonicalDecimal('0.00').cents, 0);
      expect(MoneyTotal.fromCanonicalDecimal('12.5').cents, 1250);
      expect(MoneyTotal.fromCanonicalDecimal('12.99').cents, 1299);
      expect(MoneyTotal.zero.cents, 0);
    });

    test('rifiuta virgola, scientific notation e negativi', () {
      expect(
        () => MoneyTotal.fromCanonicalDecimal('12,99'),
        throwsFormatException,
      );
      expect(
        () => MoneyTotal.fromCanonicalDecimal('1e2'),
        throwsFormatException,
      );
      expect(
        () => MoneyTotal.fromCanonicalDecimal('-1.00'),
        throwsFormatException,
      );
    });

    test('formatta euro UI senza usare double', () {
      expect(MoneyTotal.fromCents(0).formatEuro(), '0,00');
      expect(MoneyTotal.fromCents(1299).formatEuro(), '12,99');
      expect(MoneyTotal.fromCents(123456).formatEuro(), '1.234,56');
    });

    test('MoneyAmount continua a rifiutare zero', () {
      expect(() => MoneyAmount.fromCents(0), throwsArgumentError);
      expect(
        () => MoneyAmount.fromCanonicalDecimal('0.00'),
        throwsFormatException,
      );
    });
  });

  group('SignedMoneyValue', () {
    test('saldo positivo, zero e negativo', () {
      final positive = SignedMoneyValue.fromDifference(
        income: MoneyTotal.fromCents(1299),
        expense: MoneyTotal.zero,
      );
      final zero = SignedMoneyValue.fromDifference(
        income: MoneyTotal.fromCents(1000),
        expense: MoneyTotal.fromCents(1000),
      );
      final negative = SignedMoneyValue.fromDifference(
        income: MoneyTotal.fromCents(1000),
        expense: MoneyTotal.fromCents(3550),
      );

      expect(positive.formatEuroSigned(), '+12,99 €');
      expect(zero.formatEuroSigned(), '0,00 €');
      expect(negative.formatEuroSigned(), '−25,50 €');
    });
  });
}
