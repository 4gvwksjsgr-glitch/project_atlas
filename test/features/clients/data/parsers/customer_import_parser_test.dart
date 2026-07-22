import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/features/clients/data/parsers/composite_customer_import_file_parser.dart';
import 'package:project_atlas/features/clients/data/parsers/xlsx_customer_import_parser.dart';
import 'package:project_atlas/features/clients/domain/entities/customer_import_mapping.dart';
import 'package:project_atlas/features/clients/domain/entities/customer_import_payload_row.dart';
import 'package:project_atlas/features/clients/domain/entities/customer_import_sheet.dart';
import 'package:project_atlas/features/clients/domain/entities/customer_import_source.dart';
import 'package:project_atlas/features/clients/domain/services/customer_import_mapper.dart';
import 'package:project_atlas/features/clients/domain/services/customer_import_validator.dart';
import 'package:project_atlas/features/clients/domain/value_objects/customer_import_field.dart';

Uint8List _csv(String content) => Uint8List.fromList(utf8.encode(content));

void main() {
  group('CsvCustomerImportParser', () {
    const parser = CsvCustomerImportParser();

    test('parse CSV con virgola', () {
      final source = parser.parse(
        fileName: 'c.csv',
        bytes: _csv('Nome,Email\nAcme,a@test.com\n'),
      );
      expect(source.selectedTable.headers, ['Nome', 'Email']);
      expect(source.selectedTable.rowCount, 1);
      expect(source.selectedTable.dataRows.first[0], 'Acme');
    });

    test('parse CSV con punto e virgola e BOM UTF-8', () {
      final content = utf8.encode('Nome;Email\nBeta;b@test.com\n');
      final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...content]);
      final source = parser.parse(fileName: 'c.csv', bytes: bytes);
      expect(source.selectedTable.headers.first, 'Nome');
      expect(source.selectedTable.dataRows.first[1], 'b@test.com');
    });

    test('parse CSV con tab', () {
      final source = parser.parse(
        fileName: 'c.csv',
        bytes: _csv('Nome\tTelefono\nGamma\t123\n'),
      );
      expect(source.selectedTable.headers, ['Nome', 'Telefono']);
    });

    test('campo tra virgolette contenente virgola', () {
      final source = parser.parse(
        fileName: 'c.csv',
        bytes: _csv('Nome,Note\n"Acme, Srl",ciao\n'),
      );
      expect(source.selectedTable.dataRows.first[0], 'Acme, Srl');
    });

    test('campo tra virgolette contenente punto e virgola', () {
      final source = parser.parse(
        fileName: 'c.csv',
        bytes: _csv('Nome;Note\n"Acme; Srl";ciao\n'),
      );
      expect(source.selectedTable.dataRows.first[0], 'Acme; Srl');
    });

    test('virgolette escaped', () {
      final source = parser.parse(
        fileName: 'c.csv',
        bytes: _csv('Nome,Note\n"Lui ""detto"" X",ok\n'),
      );
      expect(source.selectedTable.dataRows.first[0], 'Lui "detto" X');
    });

    test('CRLF e LF', () {
      final crlf = parser.parse(
        fileName: 'c.csv',
        bytes: _csv('Nome,Email\r\nA,a@t.com\r\n'),
      );
      final lf = parser.parse(
        fileName: 'c.csv',
        bytes: _csv('Nome,Email\nB,b@t.com\n'),
      );
      expect(crlf.selectedTable.rowCount, 1);
      expect(lf.selectedTable.rowCount, 1);
    });

    test('righe completamente vuote restano nel table (skip in validator)', () {
      final source = parser.parse(
        fileName: 'c.csv',
        bytes: _csv('Nome,Email\nAcme,a@t.com\n\n\nBeta,b@t.com\n'),
      );
      expect(source.selectedTable.rowCount, greaterThanOrEqualTo(2));
    });

    test('righe con più colonne dell header: extra ignorate', () {
      final source = parser.parse(
        fileName: 'c.csv',
        bytes: _csv('Nome,Email\nAcme,a@t.com,EXTRA,MORE\n'),
      );
      expect(source.selectedTable.dataRows.first.length, 2);
      expect(source.selectedTable.dataRows.first[0], 'Acme');
    });

    test('righe con meno colonne dell header: pad null', () {
      final source = parser.parse(
        fileName: 'c.csv',
        bytes: _csv('Nome,Email,Telefono\nSoloNome\n'),
      );
      expect(source.selectedTable.dataRows.first.length, 3);
      expect(source.selectedTable.dataRows.first[0], 'SoloNome');
      expect(source.selectedTable.dataRows.first[1], isNull);
    });

    test('header vuoto rifiutato', () {
      expect(
        () => parser.parse(fileName: 'c.csv', bytes: _csv('Nome,\nA,B\n')),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'emptyHeader',
          ),
        ),
      );
    });

    test('header duplicati dopo trim e lowercase', () {
      expect(
        () => parser.parse(
          fileName: 'c.csv',
          bytes: _csv('Nome,  nome  \nx,y\n'),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'duplicateHeaders',
          ),
        ),
      );
    });

    test('file con solo header', () {
      expect(
        () => parser.parse(fileName: 'c.csv', bytes: _csv('Nome,Email\n')),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'noDataRows',
          ),
        ),
      );
    });

    test('delimitatore ambiguo: errore deterministico, nessun silent pick', () {
      // Stesso conteggio di separatori non quotati su , e ;
      expect(
        () => parser.parse(fileName: 'c.csv', bytes: _csv('A,B;C\n1,2;3\n')),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'ambiguousDelimiter',
          ),
        ),
      );
    });

    test('rifiuta codifica non UTF-8', () {
      expect(
        () => parser.parse(
          fileName: 'c.csv',
          bytes: Uint8List.fromList([0xFF, 0xFE, 0x00, 0x41]),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'undecodableEncoding',
          ),
        ),
      );
    });

    test('colonna singola senza separatore è valida', () {
      final source = parser.parse(
        fileName: 'c.csv',
        bytes: _csv('Nome\nSolo\n'),
      );
      expect(source.selectedTable.headers, ['Nome']);
      expect(source.selectedTable.dataRows.first[0], 'Solo');
    });

    test('validator ignora righe completamente vuote', () {
      final source = parser.parse(
        fileName: 'c.csv',
        bytes: _csv('Nome,Email\nAcme,a@t.com\n\n\nBeta,b@t.com\n'),
      );
      const mapper = CustomerImportMapper();
      const validator = CustomerImportValidator();
      final plan = validator.buildPlan(
        source: source,
        mapping: mapper.autoMap(source.selectedTable.headers),
        existingEmailsNormalized: {},
      );
      expect(plan.emptyIgnored, greaterThan(0));
      expect(plan.validToImport, 2);
    });
  });

  group('CompositeCustomerImportFileParser', () {
    const parser = CompositeCustomerImportFileParser();

    test('rifiuta estensione non supportata', () async {
      await expectLater(
        parser.parseBytes(fileName: 'x.txt', bytes: _csv('Nome\nA\n')),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'unsupportedExtension',
          ),
        ),
      );
    });

    test('instrada .csv e .xlsx', () async {
      final csv = await parser.parseBytes(
        fileName: 'c.csv',
        bytes: _csv('Nome\nA\n'),
      );
      expect(csv.kind, CustomerImportSourceKind.csv);

      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];
      sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('Nome');
      sheet.cell(CellIndex.indexByString('A2')).value = TextCellValue('B');
      final xlsx = await parser.parseBytes(
        fileName: 'w.xlsx',
        bytes: Uint8List.fromList(excel.encode()!),
      );
      expect(xlsx.kind, CustomerImportSourceKind.xlsx);
    });
  });

  group('XlsxCustomerImportParser (excel 4.0.6)', () {
    const parser = XlsxCustomerImportParser();

    Uint8List encodeWorkbook(Excel excel) {
      final bytes = excel.encode();
      expect(bytes, isNotNull);
      return Uint8List.fromList(bytes!);
    }

    Excel workbook(void Function(Excel excel) build) {
      final excel = Excel.createExcel();
      // Default sheet exists; customize via callback.
      build(excel);
      return excel;
    }

    test('un foglio valido', () {
      final excel = workbook((e) {
        final sheet = e['Sheet1'];
        sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('Nome');
        sheet.cell(CellIndex.indexByString('B1')).value = TextCellValue(
          'Email',
        );
        sheet.cell(CellIndex.indexByString('A2')).value = TextCellValue('Acme');
        sheet.cell(CellIndex.indexByString('B2')).value = TextCellValue(
          'a@test.com',
        );
      });
      final source = parser.parse(
        fileName: 'w.xlsx',
        bytes: encodeWorkbook(excel),
      );
      expect(source.sheets.length, 1);
      expect(source.selectedTable.dataRows.first[0], 'Acme');
    });

    test(
      'più fogli validi; fogli vuoti esclusi; selezione di un solo foglio',
      () {
        final excel = workbook((e) {
          final s1 = e['Sheet1'];
          s1.cell(CellIndex.indexByString('A1')).value = TextCellValue('Nome');
          s1.cell(CellIndex.indexByString('A2')).value = TextCellValue('Uno');

          e.copy('Sheet1', 'Due');
          final s2 = e['Due'];
          s2.cell(CellIndex.indexByString('A2')).value = TextCellValue(
            'DueNome',
          );

          e.copy('Sheet1', 'Vuoto');
          // Leave Vuoto empty after clear if needed — create empty by new sheet
          e.rename('Vuoto', 'EmptyCandidate');
        });
        // Ensure an empty sheet exists without cells
        excel['ReallyEmpty'];

        final all = parser.parse(
          fileName: 'w.xlsx',
          bytes: encodeWorkbook(excel),
        );
        expect(all.sheets.length, greaterThanOrEqualTo(2));
        expect(all.sheets.any((s) => s.name == 'ReallyEmpty'), isFalse);

        final selected = parser.parse(
          fileName: 'w.xlsx',
          bytes: encodeWorkbook(excel),
          preferredSheet: 'Due',
        );
        expect(selected.selectedSheet, 'Due');
        expect(selected.selectedTable.dataRows.first[0], 'DueNome');
      },
    );

    test('foglio con solo intestazioni', () {
      final excel = workbook((e) {
        final sheet = e['Sheet1'];
        sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('Nome');
      });
      expect(
        () => parser.parse(fileName: 'w.xlsx', bytes: encodeWorkbook(excel)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'noDataRows',
          ),
        ),
      );
    });

    test('header duplicati', () {
      final excel = workbook((e) {
        final sheet = e['Sheet1'];
        sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('Nome');
        sheet.cell(CellIndex.indexByString('B1')).value = TextCellValue('nome');
        sheet.cell(CellIndex.indexByString('A2')).value = TextCellValue('X');
      });
      expect(
        () => parser.parse(fileName: 'w.xlsx', bytes: encodeWorkbook(excel)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'duplicateHeaders',
          ),
        ),
      );
    });

    test('formula, bool, data, intero, decimale; telefono numerico', () {
      final excel = workbook((e) {
        final sheet = e['Sheet1'];
        sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('Nome');
        sheet.cell(CellIndex.indexByString('B1')).value = TextCellValue(
          'Telefono',
        );
        sheet.cell(CellIndex.indexByString('C1')).value = TextCellValue('Note');
        sheet.cell(CellIndex.indexByString('D1')).value = TextCellValue('Flag');
        sheet.cell(CellIndex.indexByString('E1')).value = TextCellValue('Data');

        sheet.cell(CellIndex.indexByString('A2')).value = TextCellValue(
          'NumericPhone',
        );
        sheet.cell(CellIndex.indexByString('B2')).value = IntCellValue(
          3331234567,
        );
        sheet.cell(CellIndex.indexByString('C2')).value = DoubleCellValue(12.5);
        sheet.cell(CellIndex.indexByString('D2')).value = const BoolCellValue(
          true,
        );
        sheet.cell(CellIndex.indexByString('E2')).value = const DateCellValue(
          year: 2026,
          month: 7,
          day: 20,
        );

        sheet.cell(CellIndex.indexByString('A3')).value = FormulaCellValue(
          'A2',
        );
        sheet.cell(CellIndex.indexByString('B3')).value = TextCellValue('x');
      });

      final source = parser.parse(
        fileName: 'w.xlsx',
        bytes: encodeWorkbook(excel),
      );
      final row = source.selectedTable.dataRows.first;
      expect(row[1], '3331234567'); // no leading-zero reconstruction
      expect(row[2], '12.5');
      expect(row[3], 'true');
      expect(row[4], '2026-07-20');
      expect(source.selectedTable.dataRows[1][0], startsWith('='));

      const mapper = CustomerImportMapper();
      const validator = CustomerImportValidator();
      final plan = validator.buildPlan(
        source: source,
        mapping: mapper.autoMap(source.selectedTable.headers),
        existingEmailsNormalized: {},
      );
      expect(
        plan.rows.any((r) => r.issues.any((i) => i.code == 'leadingZeroRisk')),
        isTrue,
      );
      expect(
        plan.rows.any((r) => r.issues.any((i) => i.code == 'formulaCell')),
        isTrue,
      );
    });

    test('oltre 500 righe: constraint tooManyRows', () {
      final excel = workbook((e) {
        final sheet = e['Sheet1'];
        sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('Nome');
        for (var i = 0; i < 501; i++) {
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1))
              .value = TextCellValue(
            'N$i',
          );
        }
      });
      final source = parser.parse(
        fileName: 'w.xlsx',
        bytes: encodeWorkbook(excel),
      );
      expect(
        source.constraintIssues.any((i) => i.code == 'tooManyRows'),
        isTrue,
      );
    });

    test('più di 20 fogli rifiutati', () {
      final excel = Excel.createExcel();
      excel.rename('Sheet1', 'S0');
      final first = excel['S0'];
      first.cell(CellIndex.indexByString('A1')).value = TextCellValue('Nome');
      first.cell(CellIndex.indexByString('A2')).value = TextCellValue('A');
      for (var i = 1; i < 21; i++) {
        excel.copy('S0', 'S$i');
      }
      expect(
        () => parser.parse(fileName: 'w.xlsx', bytes: encodeWorkbook(excel)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'tooManySheets',
          ),
        ),
      );
    });

    test('workbook vuoto rifiutato', () {
      final excel = Excel.createExcel();
      // Default sheet left empty (no cells with values).
      expect(
        () => parser.parse(fileName: 'w.xlsx', bytes: encodeWorkbook(excel)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'emptyWorkbook',
          ),
        ),
      );
    });

    test('numero decimale senza notazione scientifica evitabile', () {
      final excel = workbook((e) {
        final sheet = e['Sheet1'];
        sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('Nome');
        sheet.cell(CellIndex.indexByString('B1')).value = TextCellValue(
          'Valore',
        );
        sheet.cell(CellIndex.indexByString('A2')).value = TextCellValue('N');
        sheet.cell(CellIndex.indexByString('B2')).value = DoubleCellValue(
          1234567.89,
        );
      });
      final source = parser.parse(
        fileName: 'w.xlsx',
        bytes: encodeWorkbook(excel),
      );
      final value = source.selectedTable.dataRows.first[1]!;
      expect(value.contains('e'), isFalse);
      expect(value.contains('E'), isFalse);
      expect(value, contains('1234567'));
    });

    test('telefono numerico non ricostruisce zero iniziale', () {
      final excel = workbook((e) {
        final sheet = e['Sheet1'];
        sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('Nome');
        sheet.cell(CellIndex.indexByString('B1')).value = TextCellValue(
          'Telefono',
        );
        sheet.cell(CellIndex.indexByString('A2')).value = TextCellValue('N');
        sheet.cell(CellIndex.indexByString('B2')).value = IntCellValue(391234);
      });
      final source = parser.parse(
        fileName: 'w.xlsx',
        bytes: encodeWorkbook(excel),
      );
      expect(source.selectedTable.dataRows.first[1], '391234');
      expect(source.selectedTable.dataRows.first[1], isNot(startsWith('0')));
    });
  });

  group('CustomerImportMapper / Validator', () {
    const mapper = CustomerImportMapper();
    const validator = CustomerImportValidator();

    test('riconosce sinonimi italiani', () {
      final mapping = mapper.autoMap([
        'Ragione sociale',
        'Mail',
        'Cellulare',
        'Annotazioni',
      ]);
      expect(mapping.fieldAt(0), CustomerImportField.name);
      expect(mapping.fieldAt(1), CustomerImportField.email);
      expect(mapping.fieldAt(2), CustomerImportField.phone);
      expect(mapping.fieldAt(3), CustomerImportField.notes);
    });

    test('mapping duplicato dello stesso campo non è valido se forzato', () {
      final mapping = CustomerImportMapping({
        0: CustomerImportField.name,
        1: CustomerImportField.name,
      });
      expect(mapping.isValid, isFalse);
      expect(mapping.validationCodes, contains('nameMustBeMappedOnce'));
    });

    test(
      'deduplicazione best effort dello Step 10A: file + tenant; senza email ok',
      () {
        // Non è garanzia database: nessun unique index; CRUD senza advisory lock.
        final source = CustomerImportSource(
          fileName: 'c.csv',
          byteLength: 10,
          kind: CustomerImportSourceKind.csv,
          sheets: const [CustomerImportSheet(name: 'CSV', rowCount: 4)],
          selectedSheet: 'CSV',
          selectedTable: CustomerImportTable(
            headers: const ['Nome', 'Email'],
            dataRows: const [
              ['Uno', 'dup@test.com'],
              ['Due', 'dup@test.com'],
              ['Tre', 'exist@test.com'],
              ['Gemello', null],
              ['Gemello', null],
            ],
          ),
        );
        final mapping = mapper.autoMap(source.selectedTable.headers);
        final plan = validator.buildPlan(
          source: source,
          mapping: mapping,
          existingEmailsNormalized: {'exist@test.com'},
        );

        expect(plan.skippedDuplicates, 2);
        expect(plan.validToImport, 3);
        expect(plan.warnings, greaterThan(0));
        expect(
          plan.rowsToImport.any((r) => r.email == 'exist@test.com'),
          isFalse,
        );
        expect(plan.rowsToImport.where((r) => r.name == 'Gemello').length, 2);
      },
    );

    test('payload toJson include source_row e non company_id', () {
      const row = CustomerImportPayloadRow(
        sourceRow: 2,
        name: 'Acme',
        email: 'a@test.com',
      );
      final json = row.toJson();
      expect(json['source_row'], 2);
      expect(json.containsKey('company_id'), isFalse);
      expect(json['name'], 'Acme');
    });

    test('toString senza PII', () {
      const row = CustomerImportPayloadRow(
        sourceRow: 3,
        name: 'Segreto',
        email: 'secret@test.com',
      );
      expect(row.toString(), isNot(contains('Segreto')));
      expect(row.toString(), isNot(contains('secret@test.com')));
    });
  });
}
