import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/features/transactions/domain/entities/transaction_import_mapping.dart';
import 'package:project_atlas/features/transactions/domain/services/transaction_import_mapper.dart';
import 'package:project_atlas/features/transactions/domain/value_objects/transaction_import_field.dart';

void main() {
  const mapper = TransactionImportMapper();

  group('TransactionImportMapper auto-mapping', () {
    test('sinonimi italiani con colonna importo unica', () {
      final mapping = mapper.autoMap(const [
        'Data',
        'Descrizione',
        'Importo',
        'Riferimento',
        'Note',
      ]);

      expect(mapping.fieldAt(0), TransactionImportField.date);
      expect(mapping.fieldAt(1), TransactionImportField.description);
      expect(mapping.fieldAt(2), TransactionImportField.signedAmount);
      expect(mapping.fieldAt(3), TransactionImportField.reference);
      expect(mapping.fieldAt(4), TransactionImportField.notes);
      expect(mapping.amountMode, TransactionImportAmountMode.signed);
      expect(mapping.isValid, isTrue);
    });

    test('sinonimi inglesi', () {
      final mapping = mapper.autoMap(const [
        'Date',
        'Description',
        'Amount',
        'Reference',
      ]);

      expect(mapping.fieldAt(0), TransactionImportField.date);
      expect(mapping.fieldAt(1), TransactionImportField.description);
      expect(mapping.fieldAt(2), TransactionImportField.signedAmount);
      expect(mapping.fieldAt(3), TransactionImportField.reference);
      expect(mapping.isValid, isTrue);
    });

    test('coppia dare/avere completa', () {
      final mapping = mapper.autoMap(const [
        'Data operazione',
        'Causale',
        'Uscite',
        'Entrate',
      ]);

      expect(mapping.fieldAt(2), TransactionImportField.debit);
      expect(mapping.fieldAt(3), TransactionImportField.credit);
      expect(mapping.amountMode, TransactionImportAmountMode.debitCredit);
      expect(mapping.isValid, isTrue);
    });

    test('intestazioni normalizzate: spazi e maiuscole ignorati', () {
      final mapping = mapper.autoMap(const [
        '  DATA   MOVIMENTO ',
        'DESCRIZIONE Operazione',
        'IMPORTO',
      ]);

      expect(mapping.fieldAt(0), TransactionImportField.date);
      expect(mapping.fieldAt(1), TransactionImportField.description);
      expect(mapping.fieldAt(2), TransactionImportField.signedAmount);
    });

    test('intestazione sconosciuta resta ignorata', () {
      final mapping = mapper.autoMap(const [
        'Data',
        'Descrizione',
        'Importo',
        'Saldo progressivo',
      ]);

      expect(mapping.fieldAt(3), TransactionImportField.ignore);
    });

    test('nessun campo viene assegnato due volte', () {
      final mapping = mapper.autoMap(const [
        'Data',
        'Data valuta',
        'Descrizione',
        'Importo',
      ]);

      expect(mapping.fieldAt(0), TransactionImportField.date);
      expect(mapping.fieldAt(1), TransactionImportField.ignore);
      expect(mapping.isValid, isTrue);
    });

    test('solo sinonimi esatti: nessun match parziale', () {
      final mapping = mapper.autoMap(const [
        'Data di registrazione',
        'Descrizione estesa',
        'Importo netto',
      ]);

      expect(mapping.fieldAt(0), TransactionImportField.ignore);
      expect(mapping.fieldAt(1), TransactionImportField.ignore);
      expect(mapping.fieldAt(2), TransactionImportField.ignore);
      expect(mapping.isValid, isFalse);
    });
  });

  group('TransactionImportMapper esclusione importo con segno / dare-avere', () {
    test('importo con segno vince e dare/avere restano non mappati', () {
      final mapping = mapper.autoMap(const [
        'Data',
        'Descrizione',
        'Importo',
        'Dare',
        'Avere',
      ]);

      expect(mapping.fieldAt(2), TransactionImportField.signedAmount);
      expect(mapping.fieldAt(3), TransactionImportField.ignore);
      expect(mapping.fieldAt(4), TransactionImportField.ignore);
      expect(mapping.amountMode, TransactionImportAmountMode.signed);
    });

    test('solo dare senza avere lascia entrambe non mappate', () {
      final mapping = mapper.autoMap(const ['Data', 'Descrizione', 'Dare']);

      expect(mapping.fieldAt(2), TransactionImportField.ignore);
      expect(mapping.amountMode, TransactionImportAmountMode.none);
      expect(mapping.validationCodes, contains('amountMappingRequired'));
    });

    test('solo avere senza dare lascia entrambe non mappate', () {
      final mapping = mapper.autoMap(const ['Data', 'Descrizione', 'Avere']);

      expect(mapping.fieldAt(2), TransactionImportField.ignore);
      expect(mapping.amountMode, TransactionImportAmountMode.none);
    });
  });

  group('TransactionImportMapping validazione', () {
    test('data mancante segnalata', () {
      final mapping = TransactionImportMapping(const {
        0: TransactionImportField.description,
        1: TransactionImportField.signedAmount,
      });

      expect(mapping.validationCodes, contains('dateMustBeMappedOnce'));
      expect(mapping.isValid, isFalse);
    });

    test('descrizione mancante segnalata', () {
      final mapping = TransactionImportMapping(const {
        0: TransactionImportField.date,
        1: TransactionImportField.signedAmount,
      });

      expect(
        mapping.validationCodes,
        contains('descriptionMustBeMappedOnce'),
      );
    });

    test('data mappata due volte segnalata', () {
      final mapping = TransactionImportMapping(const {
        0: TransactionImportField.date,
        1: TransactionImportField.date,
        2: TransactionImportField.description,
        3: TransactionImportField.signedAmount,
      });

      expect(mapping.validationCodes, contains('dateMustBeMappedOnce'));
    });

    test('campo opzionale mappato due volte segnalato', () {
      final mapping = TransactionImportMapping(const {
        0: TransactionImportField.date,
        1: TransactionImportField.description,
        2: TransactionImportField.signedAmount,
        3: TransactionImportField.notes,
        4: TransactionImportField.notes,
      });

      expect(mapping.validationCodes, contains('fieldMappedMoreThanOnce'));
    });

    test('importo con segno e dare/avere insieme non sono un modo valido', () {
      final mapping = TransactionImportMapping(const {
        0: TransactionImportField.date,
        1: TransactionImportField.description,
        2: TransactionImportField.signedAmount,
        3: TransactionImportField.debit,
        4: TransactionImportField.credit,
      });

      expect(mapping.amountMode, TransactionImportAmountMode.none);
      expect(mapping.validationCodes, contains('amountMappingRequired'));
    });

    test('headerIndexOf restituisce la colonna associata', () {
      final mapping = TransactionImportMapping(const {
        0: TransactionImportField.date,
        1: TransactionImportField.description,
        2: TransactionImportField.signedAmount,
      });

      expect(mapping.headerIndexOf(TransactionImportField.description), 1);
      expect(mapping.headerIndexOf(TransactionImportField.notes), isNull);
    });
  });
}
