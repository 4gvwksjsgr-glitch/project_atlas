import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/features/transactions/domain/value_objects/money_amount.dart';

void main() {
  group('MoneyAmount.parse', () {
    test('accetta virgola italiana semplice (0,10 -> 10 centesimi)', () {
      final amount = MoneyAmount.parse('0,10');
      expect(amount.cents, 10);
      expect(amount.toCanonicalDecimal(), '0.10');
      expect(amount.formatEuro(), '0,10');
    });

    test('accetta punto decimale semplice (12.99 -> 1299 centesimi)', () {
      final amount = MoneyAmount.parse('12.99');
      expect(amount.cents, 1299);
    });

    test(
      'accetta separatore migliaia italiano (1.234,56 -> 123456 centesimi)',
      () {
        final amount = MoneyAmount.parse('1.234,56');
        expect(amount.cents, 123456);
        expect(amount.toCanonicalDecimal(), '1234.56');
        expect(amount.formatEuro(), '1.234,56');
      },
    );

    test('rifiuta zero', () {
      expect(() => MoneyAmount.parse('0'), throwsFormatException);
      expect(() => MoneyAmount.parse('0,00'), throwsFormatException);
    });

    test('rifiuta importi negativi', () {
      expect(() => MoneyAmount.parse('-5'), throwsFormatException);
      expect(() => MoneyAmount.parse('-5,00'), throwsFormatException);
    });

    test('rifiuta più di due cifre decimali', () {
      expect(() => MoneyAmount.parse('1.234'), throwsFormatException);
      expect(() => MoneyAmount.parse('12,999'), throwsFormatException);
    });

    test('rifiuta notazione scientifica', () {
      expect(() => MoneyAmount.parse('1e2'), throwsFormatException);
      expect(() => MoneyAmount.parse('1E2'), throwsFormatException);
    });

    test('rifiuta valori non numerici', () {
      expect(() => MoneyAmount.parse('abc'), throwsFormatException);
      expect(() => MoneyAmount.parse('12,99€'), throwsFormatException);
    });

    test('rifiuta stringa vuota', () {
      expect(() => MoneyAmount.parse(''), throwsFormatException);
      expect(() => MoneyAmount.parse('   '), throwsFormatException);
    });

    test('accetta il massimo consentito (MoneyAmount.maxCents)', () {
      final amount = MoneyAmount.parse('999999999999,99');
      expect(amount.cents, MoneyAmount.maxCents);
    });

    test('rifiuta un importo superiore al massimo consentito', () {
      expect(
        () => MoneyAmount.parse('1000000000000,00'),
        throwsFormatException,
      );
    });
  });

  group('MoneyAmount.fromCents / maxCents', () {
    test('MoneyAmount.maxCents ha successo', () {
      final amount = MoneyAmount.fromCents(MoneyAmount.maxCents);
      expect(amount.cents, MoneyAmount.maxCents);
    });

    test('MoneyAmount.maxCents + 1 fallisce', () {
      expect(
        () => MoneyAmount.fromCents(MoneyAmount.maxCents + 1),
        throwsArgumentError,
      );
    });

    test('zero o negativo falliscono con fromCents', () {
      expect(() => MoneyAmount.fromCents(0), throwsArgumentError);
      expect(() => MoneyAmount.fromCents(-1), throwsArgumentError);
    });
  });

  group('MoneyAmount.toCanonicalDecimal', () {
    test('serializzazione esatta per il valore massimo', () {
      final amount = MoneyAmount.fromCents(MoneyAmount.maxCents);
      expect(amount.toCanonicalDecimal(), '999999999999.99');
    });

    test('serializzazione esatta per un valore piccolo', () {
      final amount = MoneyAmount.fromCents(5);
      expect(amount.toCanonicalDecimal(), '0.05');
    });
  });

  group('MoneyAmount.fromCanonicalDecimal', () {
    test('interpreta la forma canonica con il punto', () {
      final amount = MoneyAmount.fromCanonicalDecimal('12.99');
      expect(amount.cents, 1299);
    });
  });
}
