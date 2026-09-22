import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/features/transactions/domain/services/transaction_date_parser.dart';
import 'package:project_atlas/features/transactions/domain/value_objects/transaction_import_formats.dart';

DateTime _parsed(
  String raw, {
  DateFormatPreference preference = DateFormatPreference.auto,
}) {
  final outcome = TransactionDateParser.parse(raw, preference: preference);
  expect(outcome, isA<DateParsed>(), reason: 'Attesa data valida per "$raw"');
  return (outcome as DateParsed).value;
}

String _invalidCode(String raw) {
  final outcome = TransactionDateParser.parse(raw);
  expect(outcome, isA<DateInvalid>(), reason: 'Attesa data invalida: "$raw"');
  return (outcome as DateInvalid).code;
}

void main() {
  group('TransactionDateParser formati non ambigui', () {
    test('ISO YYYY-MM-DD', () {
      expect(_parsed('2026-03-04'), DateTime(2026, 3, 4));
    });

    test('ISO con orario viene troncato al giorno', () {
      expect(_parsed('2026-03-04T10:30:00'), DateTime(2026, 3, 4));
      expect(_parsed('2026-03-04 10:30:00'), DateTime(2026, 3, 4));
    });

    test('nessuna conversione UTC: resta data locale', () {
      final value = _parsed('2026-03-04');
      expect(value.isUtc, isFalse);
      expect(value.hour, 0);
    });

    test('giorno oltre 12 identifica il giorno senza ambiguità', () {
      expect(_parsed('25/12/2026'), DateTime(2026, 12, 25));
      expect(_parsed('25-12-2026'), DateTime(2026, 12, 25));
      expect(_parsed('25.12.2026'), DateTime(2026, 12, 25));
    });

    test('mese oltre 12 in prima posizione ricade su MM/GG', () {
      expect(_parsed('12/25/2026'), DateTime(2026, 12, 25));
    });

    test('giorno uguale al mese non è ambiguo', () {
      expect(_parsed('05/05/2026'), DateTime(2026, 5, 5));
    });
  });

  group('TransactionDateParser ambiguità giorno/mese', () {
    test('03/04/2026 è ambiguo senza preferenza', () {
      expect(
        TransactionDateParser.parse('03/04/2026'),
        isA<DateAmbiguous>(),
      );
    });

    test('preferenza dmy interpreta giorno per primo', () {
      expect(
        _parsed('03/04/2026', preference: DateFormatPreference.dmy),
        DateTime(2026, 4, 3),
      );
    });

    test('preferenza mdy interpreta mese per primo', () {
      expect(
        _parsed('03/04/2026', preference: DateFormatPreference.mdy),
        DateTime(2026, 3, 4),
      );
    });

    test('preferenza dmy su data impossibile resta invalida', () {
      final outcome = TransactionDateParser.parse(
        '25/25/2026',
        preference: DateFormatPreference.dmy,
      );
      expect(outcome, isA<DateInvalid>());
      expect((outcome as DateInvalid).code, 'dateInvalid');
    });
  });

  group('TransactionDateParser celle non valide', () {
    test('cella vuota', () {
      expect(_invalidCode(''), 'dateMissing');
      expect(_invalidCode('  '), 'dateMissing');
    });

    test('anno a due cifre non supportato', () {
      expect(_invalidCode('04/03/26'), 'dateUnsupportedFormat');
    });

    test('formato non riconoscibile', () {
      expect(_invalidCode('4 marzo 2026'), 'dateUnsupportedFormat');
      expect(_invalidCode('2026/03'), 'dateUnsupportedFormat');
    });

    test('31 febbraio rifiutato', () {
      expect(_invalidCode('2026-02-31'), 'dateInvalid');
      expect(_invalidCode('31/02/2026'), 'dateInvalid');
    });

    test('29 febbraio valido solo negli anni bisestili', () {
      expect(_parsed('2024-02-29'), DateTime(2024, 2, 29));
      expect(_invalidCode('2026-02-29'), 'dateInvalid');
    });

    test('anno fuori dai limiti supportati', () {
      expect(_invalidCode('1899-01-01'), 'dateInvalid');
      expect(_invalidCode('3000-01-01'), 'dateInvalid');
    });
  });
}
