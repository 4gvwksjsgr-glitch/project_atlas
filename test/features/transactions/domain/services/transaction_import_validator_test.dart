import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/tabular_import/tabular_import_sheet.dart';
import 'package:project_atlas/core/tabular_import/tabular_import_source.dart';
import 'package:project_atlas/core/tabular_import/tabular_import_table.dart';
import 'package:project_atlas/features/transactions/domain/entities/cash_transaction.dart';
import 'package:project_atlas/features/transactions/domain/entities/transaction_import_mapping.dart';
import 'package:project_atlas/features/transactions/domain/entities/transaction_import_plan.dart';
import 'package:project_atlas/features/transactions/domain/entities/transaction_import_row.dart';
import 'package:project_atlas/features/transactions/domain/entities/transaction_import_source.dart';
import 'package:project_atlas/features/transactions/domain/services/transaction_import_validator.dart';
import 'package:project_atlas/features/transactions/domain/value_objects/money_amount.dart';
import 'package:project_atlas/features/transactions/domain/value_objects/transaction_import_field.dart';
import 'package:project_atlas/features/transactions/domain/value_objects/transaction_import_formats.dart';

const _validator = TransactionImportValidator();

/// Mapping standard: Data | Descrizione | Importo con segno.
final _signedMapping = TransactionImportMapping(const {
  0: TransactionImportField.date,
  1: TransactionImportField.description,
  2: TransactionImportField.signedAmount,
});

/// Mapping Data | Descrizione | Dare | Avere.
final _debitCreditMapping = TransactionImportMapping(const {
  0: TransactionImportField.date,
  1: TransactionImportField.description,
  2: TransactionImportField.debit,
  3: TransactionImportField.credit,
});

TransactionImportSource _source(
  List<List<String?>> dataRows, {
  List<String> headers = const ['Data', 'Descrizione', 'Importo'],
}) {
  final table = TabularImportTable(headers: headers, dataRows: dataRows);
  return TabularImportSource(
    fileName: 'movimenti.csv',
    byteLength: 128,
    kind: TabularImportSourceKind.csv,
    sheets: [TabularImportSheet(name: 'CSV', rowCount: table.rowCount)],
    selectedSheet: 'CSV',
    selectedTable: table,
  );
}

CashTransaction _existing({
  required String isoDate,
  required TransactionKind kind,
  required String amount,
  required String description,
}) {
  return CashTransaction(
    id: 'tx-$description',
    companyId: 'company-a',
    kind: kind,
    amount: MoneyAmount.fromCanonicalDecimal(amount),
    occurredOn: DateTime.parse(isoDate),
    description: description,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

List<String> _codesOfRow(TransactionImportPlan plan, int sourceRow) {
  return plan.rows
      .firstWhere((row) => row.sourceRow == sourceRow)
      .issues
      .map((issue) => issue.code)
      .toList();
}

void main() {
  group('TransactionImportValidator righe valide', () {
    test('importo con segno determina entrata e uscita', () {
      final plan = _validator.buildPlan(
        source: _source([
          ['2026-03-04', 'Incasso cliente', '1500.00'],
          ['2026-03-05', 'Affitto ufficio', '-800.00'],
        ]),
        mapping: _signedMapping,
      );

      expect(plan.total, 2);
      expect(plan.valid, 2);
      expect(plan.invalid, 0);
      expect(plan.selectedForImport, 2);
      expect(plan.hasBlockingIssues, isFalse);

      expect(plan.rows[0].kind, TransactionKind.income);
      expect(plan.rows[0].amount!.toCanonicalDecimal(), '1500.00');
      expect(plan.rows[1].kind, TransactionKind.expense);
      expect(plan.rows[1].amount!.toCanonicalDecimal(), '800.00');
    });

    test('la riga sorgente parte da 2 (riga 1 = intestazione)', () {
      final plan = _validator.buildPlan(
        source: _source([
          ['2026-03-04', 'Prima', '10.00'],
          ['2026-03-05', 'Seconda', '20.00'],
        ]),
        mapping: _signedMapping,
      );

      expect(plan.rows.map((row) => row.sourceRow), [2, 3]);
      expect(plan.rowsToImport.map((row) => row.sourceRow), [2, 3]);
    });

    test('dare produce uscita, avere produce entrata', () {
      final plan = _validator.buildPlan(
        source: _source(
          [
            ['2026-03-04', 'Pagamento fornitore', '250.00', null],
            ['2026-03-05', 'Bonifico cliente', null, '900.00'],
          ],
          headers: const ['Data', 'Descrizione', 'Dare', 'Avere'],
        ),
        mapping: _debitCreditMapping,
      );

      expect(plan.valid, 2);
      expect(plan.rows[0].kind, TransactionKind.expense);
      expect(plan.rows[1].kind, TransactionKind.income);
    });

    test('colonne dare/avere a zero contano come vuote', () {
      final plan = _validator.buildPlan(
        source: _source(
          [
            ['2026-03-04', 'Pagamento fornitore', '250.00', '0,00'],
          ],
          headers: const ['Data', 'Descrizione', 'Dare', 'Avere'],
        ),
        mapping: _debitCreditMapping,
      );

      expect(plan.valid, 1);
      expect(plan.rows.single.kind, TransactionKind.expense);
    });

    test('riferimento e note opzionali finiscono nel payload', () {
      final plan = _validator.buildPlan(
        source: _source(
          [
            ['2026-03-04', 'Incasso', '10.00', 'FT-1', 'Nota interna'],
          ],
          headers: const [
            'Data',
            'Descrizione',
            'Importo',
            'Riferimento',
            'Note',
          ],
        ),
        mapping: TransactionImportMapping(const {
          0: TransactionImportField.date,
          1: TransactionImportField.description,
          2: TransactionImportField.signedAmount,
          3: TransactionImportField.reference,
          4: TransactionImportField.notes,
        }),
      );

      final payload = plan.rowsToImport.single;
      expect(payload.reference, 'FT-1');
      expect(payload.notes, 'Nota interna');
      expect(payload.occurredOn, '2026-03-04');
      expect(payload.kind, 'income');
      expect(payload.amount, '10.00');
      expect(payload.rowFingerprint, hasLength(64));
    });

    test('righe completamente vuote sono ignorate, non invalide', () {
      final plan = _validator.buildPlan(
        source: _source([
          ['2026-03-04', 'Incasso', '10.00'],
          [null, null, null],
          ['  ', '', '   '],
        ]),
        mapping: _signedMapping,
      );

      expect(plan.total, 1);
      expect(plan.emptyIgnored, 2);
      expect(plan.invalid, 0);
    });
  });

  group('TransactionImportValidator righe invalide', () {
    test('data mancante o non valida', () {
      final plan = _validator.buildPlan(
        source: _source([
          [null, 'Senza data', '10.00'],
          ['2026-02-31', 'Data impossibile', '10.00'],
        ]),
        mapping: _signedMapping,
      );

      expect(plan.invalid, 2);
      expect(_codesOfRow(plan, 2), contains('dateMissing'));
      expect(_codesOfRow(plan, 3), contains('dateInvalid'));
    });

    test('descrizione mancante e troppo lunga', () {
      final plan = _validator.buildPlan(
        source: _source([
          ['2026-03-04', null, '10.00'],
          ['2026-03-05', 'x' * 501, '10.00'],
        ]),
        mapping: _signedMapping,
      );

      expect(plan.invalid, 2);
      expect(_codesOfRow(plan, 2), contains('descriptionMissing'));
      expect(_codesOfRow(plan, 3), contains('descriptionTooLong'));
    });

    test('importo zero rifiutato: il verso non sarebbe determinabile', () {
      final plan = _validator.buildPlan(
        source: _source([
          ['2026-03-04', 'Movimento nullo', '0,00'],
        ]),
        mapping: _signedMapping,
      );

      expect(plan.invalid, 1);
      expect(_codesOfRow(plan, 2), contains('amountZero'));
    });

    test('dare e avere entrambi valorizzati', () {
      final plan = _validator.buildPlan(
        source: _source(
          [
            ['2026-03-04', 'Doppio verso', '10.00', '20.00'],
          ],
          headers: const ['Data', 'Descrizione', 'Dare', 'Avere'],
        ),
        mapping: _debitCreditMapping,
      );

      expect(_codesOfRow(plan, 2), contains('amountBothDebitAndCredit'));
    });

    test('segno nelle colonne dare/avere rifiutato', () {
      final plan = _validator.buildPlan(
        source: _source(
          [
            ['2026-03-04', 'Segno in dare', '-10.00', null],
          ],
          headers: const ['Data', 'Descrizione', 'Dare', 'Avere'],
        ),
        mapping: _debitCreditMapping,
      );

      expect(_codesOfRow(plan, 2), contains('amountSignNotAllowed'));
    });

    test('dare e avere entrambi vuoti', () {
      final plan = _validator.buildPlan(
        source: _source(
          [
            ['2026-03-04', 'Senza importo', null, null],
          ],
          headers: const ['Data', 'Descrizione', 'Dare', 'Avere'],
        ),
        mapping: _debitCreditMapping,
      );

      expect(_codesOfRow(plan, 2), contains('amountMissing'));
    });

    test('cella formula rifiutata senza essere valutata', () {
      final plan = _validator.buildPlan(
        source: _source([
          ['2026-03-04', '=SOMMA(A1:A2)', '10.00'],
        ]),
        mapping: _signedMapping,
      );

      expect(_codesOfRow(plan, 2), contains('formulaCell'));
      expect(plan.invalid, 1);
    });

    test('note e riferimento troppo lunghi', () {
      final plan = _validator.buildPlan(
        source: _source(
          [
            ['2026-03-04', 'Incasso', '10.00', 'r' * 121, 'n' * 2001],
          ],
          headers: const [
            'Data',
            'Descrizione',
            'Importo',
            'Riferimento',
            'Note',
          ],
        ),
        mapping: TransactionImportMapping(const {
          0: TransactionImportField.date,
          1: TransactionImportField.description,
          2: TransactionImportField.signedAmount,
          3: TransactionImportField.reference,
          4: TransactionImportField.notes,
        }),
      );

      expect(_codesOfRow(plan, 2), contains('referenceTooLong'));
      expect(_codesOfRow(plan, 2), contains('notesTooLong'));
    });

    test('le righe invalide non entrano nel payload', () {
      final plan = _validator.buildPlan(
        source: _source([
          ['2026-03-04', 'Valida', '10.00'],
          [null, 'Invalida', '10.00'],
        ]),
        mapping: _signedMapping,
      );

      expect(plan.valid, 1);
      expect(plan.invalid, 1);
      expect(plan.rowsToImport, hasLength(1));
      expect(plan.rowsToImport.single.description, 'Valida');
    });
  });

  group('TransactionImportValidator duplicati nel file', () {
    test('seconda occorrenza identica esclusa con avviso', () {
      final plan = _validator.buildPlan(
        source: _source([
          ['2026-03-04', 'Incasso cliente', '1500.00'],
          ['2026-03-04', 'Incasso cliente', '1500.00'],
        ]),
        mapping: _signedMapping,
      );

      expect(plan.valid, 1);
      expect(plan.duplicateInFile, 1);
      expect(plan.selectedForImport, 1);
      expect(
        plan.rows[1].status,
        TransactionImportRowStatus.duplicateInFile,
      );
      expect(_codesOfRow(plan, 3), contains('duplicateInFile'));
      expect(plan.warnings, 1);
    });

    test('inclusione esplicita permette entrambe le righe identiche', () {
      final plan = _validator.buildPlan(
        source: _source([
          ['2026-03-04', 'Incasso cliente', '1500.00'],
          ['2026-03-04', 'Incasso cliente', '1500.00'],
        ]),
        mapping: _signedMapping,
        includedDuplicateRows: const {3},
      );

      expect(plan.duplicateInFile, 1);
      expect(plan.selectedForImport, 2);
      expect(plan.rowsToImport, hasLength(2));
      expect(plan.rowsToImport.map((r) => r.sourceRow), [2, 3]);
      expect(
        plan.rowsToImport.map((r) => r.rowFingerprint).toSet(),
        hasLength(1),
      );
    });

    test('descrizione con spazi e maiuscole diverse è lo stesso movimento', () {
      final plan = _validator.buildPlan(
        source: _source([
          ['2026-03-04', 'Incasso  Cliente', '1500.00'],
          ['2026-03-04', 'incasso cliente', '1500.00'],
        ]),
        mapping: _signedMapping,
      );

      expect(plan.duplicateInFile, 1);
    });

    test('riferimento diverso distingue due righe altrimenti identiche', () {
      final plan = _validator.buildPlan(
        source: _source(
          [
            ['2026-03-04', 'Incasso', '1500.00', 'FT-1'],
            ['2026-03-04', 'Incasso', '1500.00', 'FT-2'],
          ],
          headers: const ['Data', 'Descrizione', 'Importo', 'Riferimento'],
        ),
        mapping: TransactionImportMapping(const {
          0: TransactionImportField.date,
          1: TransactionImportField.description,
          2: TransactionImportField.signedAmount,
          3: TransactionImportField.reference,
        }),
      );

      expect(plan.valid, 2);
      expect(plan.duplicateInFile, 0);
    });

    test('verso diverso non è un duplicato', () {
      final plan = _validator.buildPlan(
        source: _source([
          ['2026-03-04', 'Giroconto', '1500.00'],
          ['2026-03-04', 'Giroconto', '-1500.00'],
        ]),
        mapping: _signedMapping,
      );

      expect(plan.valid, 2);
      expect(plan.duplicateInFile, 0);
    });
  });

  group('TransactionImportValidator possibili duplicati in azienda', () {
    final existingKeys = TransactionImportValidator.existingMatchKeys([
      _existing(
        isoDate: '2026-03-04',
        kind: TransactionKind.income,
        amount: '1500.00',
        description: 'Incasso cliente',
      ),
    ]);

    test('segnalato ed escluso per default', () {
      final plan = _validator.buildPlan(
        source: _source([
          ['2026-03-04', 'Incasso cliente', '1500.00'],
        ]),
        mapping: _signedMapping,
        existingKeys: existingKeys,
      );

      expect(plan.possibleDuplicate, 1);
      expect(plan.selectedForImport, 0);
      expect(plan.rowsToImport, isEmpty);
      expect(
        plan.rows.single.status,
        TransactionImportRowStatus.possibleDuplicate,
      );
      expect(
        _codesOfRow(plan, 2),
        contains('possibleDuplicateInDatabase'),
      );
    });

    test('la riga non è bloccante: l utente può proseguire', () {
      final plan = _validator.buildPlan(
        source: _source([
          ['2026-03-04', 'Incasso cliente', '1500.00'],
          ['2026-03-05', 'Altro incasso', '10.00'],
        ]),
        mapping: _signedMapping,
        existingKeys: existingKeys,
      );

      expect(plan.hasBlockingIssues, isFalse);
      expect(plan.selectedForImport, 1);
    });

    test('inclusione esplicita lo riporta nel payload', () {
      final plan = _validator.buildPlan(
        source: _source([
          ['2026-03-04', 'Incasso cliente', '1500.00'],
        ]),
        mapping: _signedMapping,
        existingKeys: existingKeys,
        includedDuplicateRows: const {2},
      );

      expect(plan.possibleDuplicate, 1);
      expect(plan.selectedForImport, 1);
      expect(plan.rowsToImport.single.sourceRow, 2);
    });

    test('inclusione di una riga diversa non tocca la segnalata', () {
      final plan = _validator.buildPlan(
        source: _source([
          ['2026-03-04', 'Incasso cliente', '1500.00'],
        ]),
        mapping: _signedMapping,
        existingKeys: existingKeys,
        includedDuplicateRows: const {99},
      );

      expect(plan.selectedForImport, 0);
    });

    test('il riferimento non evita la segnalazione sul database', () {
      final plan = _validator.buildPlan(
        source: _source(
          [
            ['2026-03-04', 'Incasso cliente', '1500.00', 'FT-9'],
          ],
          headers: const ['Data', 'Descrizione', 'Importo', 'Riferimento'],
        ),
        mapping: TransactionImportMapping(const {
          0: TransactionImportField.date,
          1: TransactionImportField.description,
          2: TransactionImportField.signedAmount,
          3: TransactionImportField.reference,
        }),
        existingKeys: existingKeys,
      );

      expect(plan.possibleDuplicate, 1);
    });

    test('duplicato nel file ha precedenza sul confronto con il database', () {
      final plan = _validator.buildPlan(
        source: _source([
          ['2026-03-04', 'Incasso cliente', '1500.00'],
          ['2026-03-04', 'Incasso cliente', '1500.00'],
        ]),
        mapping: _signedMapping,
        existingKeys: existingKeys,
      );

      expect(
        plan.rows[0].status,
        TransactionImportRowStatus.possibleDuplicate,
      );
      expect(
        plan.rows[1].status,
        TransactionImportRowStatus.duplicateInFile,
      );
    });
  });

  group('TransactionImportValidator ambiguità di formato', () {
    test('importo ambiguo blocca il piano fino alla scelta', () {
      final source = _source([
        ['2026-03-04', 'Incasso', '1.234'],
      ]);

      final ambiguous = _validator.buildPlan(
        source: source,
        mapping: _signedMapping,
      );
      expect(ambiguous.needsNumberFormatSelection, isTrue);
      expect(ambiguous.hasBlockingIssues, isTrue);
      expect(ambiguous.rowsToImport, isEmpty);
      expect(_codesOfRow(ambiguous, 2), contains('needsNumberFormatSelection'));

      // Con la virgola come decimale, `1.234` è un separatore di migliaia.
      final resolved = _validator.buildPlan(
        source: source,
        mapping: _signedMapping,
        numberFormat: NumberFormatPreference.commaDecimal,
      );
      expect(resolved.needsNumberFormatSelection, isFalse);
      expect(resolved.hasBlockingIssues, isFalse);
      expect(resolved.rowsToImport.single.amount, '1234.00');
    });

    test('data ambigua blocca il piano fino alla scelta', () {
      final source = _source([
        ['03/04/2026', 'Incasso', '10.00'],
      ]);

      final ambiguous = _validator.buildPlan(
        source: source,
        mapping: _signedMapping,
      );
      expect(ambiguous.needsDateFormatSelection, isTrue);
      expect(ambiguous.hasBlockingIssues, isTrue);
      expect(ambiguous.rowsToImport, isEmpty);
      expect(_codesOfRow(ambiguous, 2), contains('needsDateFormatSelection'));

      final resolved = _validator.buildPlan(
        source: source,
        mapping: _signedMapping,
        dateFormat: DateFormatPreference.dmy,
      );
      expect(resolved.needsDateFormatSelection, isFalse);
      expect(resolved.rowsToImport.single.occurredOn, '2026-04-03');
    });

    test('una sola riga ambigua blocca tutto il file', () {
      final plan = _validator.buildPlan(
        source: _source([
          ['2026-03-04', 'Chiara', '10.00'],
          ['2026-03-05', 'Ambigua', '1.234'],
        ]),
        mapping: _signedMapping,
      );

      expect(plan.needsNumberFormatSelection, isTrue);
      expect(plan.rowsToImport, isEmpty);
    });
  });

  group('TransactionImportValidator problemi di sorgente e mapping', () {
    test('mapping incompleto diventa un problema bloccante del piano', () {
      final plan = _validator.buildPlan(
        source: _source([
          ['2026-03-04', 'Incasso', '10.00'],
        ]),
        mapping: TransactionImportMapping(const {
          0: TransactionImportField.date,
          1: TransactionImportField.description,
        }),
      );

      expect(plan.hasBlockingIssues, isTrue);
      expect(
        plan.sourceIssues.map((issue) => issue.code),
        contains('amountMappingRequired'),
      );
      expect(plan.rowsToImport, isEmpty);
    });

    test('limite righe della sorgente diventa problema bloccante', () {
      final table = TabularImportTable(
        headers: const ['Data', 'Descrizione', 'Importo'],
        dataRows: [
          for (var i = 0; i < TabularImportSource.maxDataRows + 1; i++)
            ['2026-03-04', 'Movimento $i', '10.00'],
        ],
      );
      final source = TabularImportSource(
        fileName: 'grande.csv',
        byteLength: 1024,
        kind: TabularImportSourceKind.csv,
        sheets: [TabularImportSheet(name: 'CSV', rowCount: table.rowCount)],
        selectedSheet: 'CSV',
        selectedTable: table,
      );

      final plan = _validator.buildPlan(
        source: source,
        mapping: _signedMapping,
      );

      expect(
        plan.sourceIssues.map((issue) => issue.code),
        contains('tooManyRows'),
      );
      expect(plan.hasBlockingIssues, isTrue);
      expect(plan.rowsToImport, isEmpty);
    });
  });

  group('TransactionImportValidator.existingMatchKeys', () {
    test('una chiave per movimento, indipendente dal riferimento', () {
      final keys = TransactionImportValidator.existingMatchKeys([
        _existing(
          isoDate: '2026-03-04',
          kind: TransactionKind.income,
          amount: '1500.00',
          description: 'Incasso cliente',
        ),
        _existing(
          isoDate: '2026-03-04',
          kind: TransactionKind.expense,
          amount: '1500.00',
          description: 'Incasso cliente',
        ),
      ]);

      expect(keys, hasLength(2));
      expect(keys.every((key) => key.length == 64), isTrue);
    });

    test('nessun movimento produce nessuna chiave', () {
      expect(
        TransactionImportValidator.existingMatchKeys(const []),
        isEmpty,
      );
    });
  });
}
