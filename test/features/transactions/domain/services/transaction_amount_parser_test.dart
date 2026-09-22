import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/features/transactions/domain/services/transaction_amount_parser.dart';
import 'package:project_atlas/features/transactions/domain/value_objects/transaction_import_formats.dart';

({int cents, bool isNegative}) _parsed(
  String raw, {
  NumberFormatPreference preference = NumberFormatPreference.auto,
}) {
  final outcome = TransactionAmountParser.parse(raw, preference: preference);
  expect(
    outcome,
    isA<AmountParsed>(),
    reason: 'Atteso importo interpretabile per "$raw"',
  );
  final parsed = outcome as AmountParsed;
  return (cents: parsed.cents, isNegative: parsed.isNegative);
}

String _invalidCode(String raw) {
  final outcome = TransactionAmountParser.parse(raw);
  expect(outcome, isA<AmountInvalid>(), reason: 'Atteso invalido per "$raw"');
  return (outcome as AmountInvalid).code;
}

void main() {
  group('TransactionAmountParser formati non ambigui', () {
    test('decimale con punto', () {
      expect(_parsed('1234.56'), (cents: 123456, isNegative: false));
    });

    test('decimale con virgola', () {
      expect(_parsed('1234,56'), (cents: 123456, isNegative: false));
    });

    test('migliaia con virgola e decimale con punto', () {
      expect(_parsed('1,234.56'), (cents: 123456, isNegative: false));
    });

    test('migliaia con punto e decimale con virgola', () {
      expect(_parsed('1.234,56'), (cents: 123456, isNegative: false));
    });

    test('separatore migliaia ripetuto non è ambiguo', () {
      expect(_parsed('1.234.567'), (cents: 123456700, isNegative: false));
      expect(_parsed('1,234,567'), (cents: 123456700, isNegative: false));
    });

    test('intero senza separatori', () {
      expect(_parsed('42'), (cents: 4200, isNegative: false));
    });

    test('un solo separatore con due decimali resta decimale', () {
      expect(_parsed('12,5'), (cents: 1250, isNegative: false));
      expect(_parsed('0,10'), (cents: 10, isNegative: false));
    });
  });

  group('TransactionAmountParser segno', () {
    test('meno iniziale', () {
      expect(_parsed('-123,45'), (cents: 12345, isNegative: true));
    });

    test('meno tipografico unicode', () {
      expect(_parsed('\u2212123,45'), (cents: 12345, isNegative: true));
    });

    test('parentesi contabili', () {
      expect(_parsed('(123,45)'), (cents: 12345, isNegative: true));
    });

    test('parentesi più meno si combinano', () {
      expect(_parsed('(-123,45)'), (cents: 12345, isNegative: false));
    });

    test('più iniziale resta positivo', () {
      expect(_parsed('+123,45'), (cents: 12345, isNegative: false));
    });
  });

  group('TransactionAmountParser pulizia valuta e spazi', () {
    test('simbolo euro e spazi rimossi', () {
      expect(_parsed('€ 1.234,56'), (cents: 123456, isNegative: false));
    });

    test('sigla EUR rimossa senza distinzione di caso', () {
      expect(_parsed('1234,56 EUR'), (cents: 123456, isNegative: false));
      expect(_parsed('1234,56 eur'), (cents: 123456, isNegative: false));
    });

    test('spazi non separabili e apostrofo svizzero rimossi', () {
      expect(_parsed('1\u00A0234,56'), (cents: 123456, isNegative: false));
      expect(_parsed("1'234,56"), (cents: 123456, isNegative: false));
    });
  });

  group('TransactionAmountParser ambiguità', () {
    test('separatore singolo con tre decimali è ambiguo in auto', () {
      expect(
        TransactionAmountParser.parse('1.234'),
        isA<AmountAmbiguous>(),
      );
      expect(
        TransactionAmountParser.parse('1,234'),
        isA<AmountAmbiguous>(),
      );
    });

    test('preferenza punto decimale legge 1,234 come migliaia', () {
      expect(
        _parsed('1,234', preference: NumberFormatPreference.dotDecimal),
        (cents: 123400, isNegative: false),
      );
    });

    test('preferenza virgola decimale legge 1.234 come migliaia', () {
      expect(
        _parsed('1.234', preference: NumberFormatPreference.commaDecimal),
        (cents: 123400, isNegative: false),
      );
    });

    test('con separatore decimale scelto tre cifre restano troppe', () {
      // `1,234` con virgola decimale sarebbe un importo a tre decimali:
      // viene rifiutato invece di essere troncato.
      final commaOutcome = TransactionAmountParser.parse(
        '1,234',
        preference: NumberFormatPreference.commaDecimal,
      );
      expect(commaOutcome, isA<AmountInvalid>());
      expect(
        (commaOutcome as AmountInvalid).code,
        'amountTooManyDecimals',
      );

      final dotOutcome = TransactionAmountParser.parse(
        '1.234',
        preference: NumberFormatPreference.dotDecimal,
      );
      expect(dotOutcome, isA<AmountInvalid>());
      expect((dotOutcome as AmountInvalid).code, 'amountTooManyDecimals');
    });

    test('la preferenza non altera i formati già non ambigui', () {
      expect(
        _parsed('1.234,56', preference: NumberFormatPreference.dotDecimal),
        (cents: 123456, isNegative: false),
      );
      expect(
        _parsed('1,234.56', preference: NumberFormatPreference.commaDecimal),
        (cents: 123456, isNegative: false),
      );
    });
  });

  group('TransactionAmountParser celle non valide', () {
    test('cella vuota', () {
      expect(_invalidCode(''), 'amountMissing');
      expect(_invalidCode('   '), 'amountMissing');
    });

    test('solo segno', () {
      expect(_invalidCode('-'), 'amountMissing');
    });

    test('testo non numerico', () {
      expect(_invalidCode('abc'), 'amountNotNumeric');
      expect(_invalidCode('12a,00'), 'amountNotNumeric');
    });

    test('più di due decimali', () {
      expect(_invalidCode('12,3456'), 'amountTooManyDecimals');
    });

    test('gruppo migliaia malformato', () {
      expect(_invalidCode('12.34.567'), 'amountNotNumeric');
    });

    test('oltre il massimo consentito', () {
      expect(_invalidCode('999999999999999,99'), 'amountOutOfRange');
    });

    test('zero è interpretabile: il verso lo decide il chiamante', () {
      final outcome = TransactionAmountParser.parse('0,00');
      expect(outcome, isA<AmountParsed>());
      expect((outcome as AmountParsed).isZero, isTrue);
    });
  });
}
