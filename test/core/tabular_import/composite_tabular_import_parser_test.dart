import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/tabular_import/composite_tabular_import_parser.dart';
import 'package:project_atlas/core/tabular_import/tabular_import_source.dart';

Uint8List _csv(String content) => Uint8List.fromList(utf8.encode(content));

Uint8List _workbook(void Function(Excel excel) build) {
  final excel = Excel.createExcel();
  build(excel);
  final bytes = excel.encode();
  expect(bytes, isNotNull);
  return Uint8List.fromList(bytes!);
}

void main() {
  const parser = CompositeTabularImportParser();

  group('CompositeTabularImportParser instradamento', () {
    test('estensione .csv usa l adapter CSV', () async {
      final source = await parser.parseBytes(
        fileName: 'movimenti.csv',
        bytes: _csv('Data,Descrizione,Importo\n2026-03-04,Incasso,10.00\n'),
      );

      expect(source.kind, TabularImportSourceKind.csv);
      expect(source.selectedTable.headers, [
        'Data',
        'Descrizione',
        'Importo',
      ]);
      expect(source.selectedTable.rowCount, 1);
      expect(source.selectedSheet, 'CSV');
    });

    test('estensione .xlsx usa l adapter XLSX', () async {
      final bytes = _workbook((excel) {
        final sheet = excel['Sheet1'];
        sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('Data');
        sheet.cell(CellIndex.indexByString('A2')).value = TextCellValue(
          '2026-03-04',
        );
      });

      final source = await parser.parseBytes(
        fileName: 'movimenti.xlsx',
        bytes: bytes,
      );

      expect(source.kind, TabularImportSourceKind.xlsx);
      expect(source.selectedTable.headers, ['Data']);
    });

    test('estensione riconosciuta senza distinzione di maiuscole', () async {
      final source = await parser.parseBytes(
        fileName: 'MOVIMENTI.CSV',
        bytes: _csv('Data,Importo\n2026-03-04,10.00\n'),
      );

      expect(source.kind, TabularImportSourceKind.csv);
    });

    test('estensione non supportata rifiutata', () {
      expect(
        () => parser.parseBytes(
          fileName: 'movimenti.pdf',
          bytes: _csv('Data\n2026-03-04\n'),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'code',
            'unsupportedExtension',
          ),
        ),
      );
    });

    test('nome senza estensione rifiutato', () {
      expect(
        () => parser.parseBytes(
          fileName: 'movimenti',
          bytes: _csv('Data\n2026-03-04\n'),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'code',
            'unsupportedExtension',
          ),
        ),
      );
    });
  });

  group('CompositeTabularImportParser limiti', () {
    test('oltre 2 MB rifiutato prima di qualsiasi lettura', () {
      final tooLarge = Uint8List(TabularImportSource.maxFileBytes + 1);

      expect(
        () => parser.parseBytes(fileName: 'grande.csv', bytes: tooLarge),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'code',
            'fileTooLarge',
          ),
        ),
      );
    });

    test('esattamente al limite di dimensione accettato', () async {
      final header = 'Data,Importo\n';
      final row = '2026-03-04,10.00\n';
      final filler = row * 10;
      final content = header + filler;
      expect(
        utf8.encode(content).length,
        lessThan(TabularImportSource.maxFileBytes),
      );

      final source = await parser.parseBytes(
        fileName: 'ok.csv',
        bytes: _csv(content),
      );
      expect(source.selectedTable.rowCount, 10);
    });

    test('oltre 500 righe segnalato come problema di vincolo', () async {
      final rows = List.generate(
        TabularImportSource.maxDataRows + 1,
        (i) => '2026-03-04,Movimento $i,10.00',
      ).join('\n');

      final source = await parser.parseBytes(
        fileName: 'molte.csv',
        bytes: _csv('Data,Descrizione,Importo\n$rows\n'),
      );

      expect(
        source.constraintIssues.map((issue) => issue.code),
        contains('tooManyRows'),
      );
      expect(
        source.constraintIssues
            .where((issue) => issue.code == 'tooManyRows')
            .single
            .severity,
        TabularImportIssueSeverity.error,
      );
    });

    test('esattamente 500 righe senza problemi di vincolo', () async {
      final rows = List.generate(
        TabularImportSource.maxDataRows,
        (i) => '2026-03-04,Movimento $i,10.00',
      ).join('\n');

      final source = await parser.parseBytes(
        fileName: 'limite.csv',
        bytes: _csv('Data,Descrizione,Importo\n$rows\n'),
      );

      expect(source.selectedTable.rowCount, TabularImportSource.maxDataRows);
      expect(source.constraintIssues, isEmpty);
    });
  });

  group('CompositeTabularImportParser selezione foglio', () {
    Uint8List multiSheetWorkbook() {
      return _workbook((excel) {
        excel.rename('Sheet1', 'Gennaio');
        final first = excel['Gennaio'];
        first.cell(CellIndex.indexByString('A1')).value = TextCellValue('Data');
        first.cell(CellIndex.indexByString('A2')).value = TextCellValue(
          '2026-01-10',
        );

        final second = excel['Febbraio'];
        second.cell(CellIndex.indexByString('A1')).value = TextCellValue('Data');
        second.cell(CellIndex.indexByString('A2')).value = TextCellValue(
          '2026-02-10',
        );
        second.cell(CellIndex.indexByString('A3')).value = TextCellValue(
          '2026-02-11',
        );
      });
    }

    test('elenca i fogli disponibili', () async {
      final source = await parser.parseBytes(
        fileName: 'anno.xlsx',
        bytes: multiSheetWorkbook(),
      );

      expect(
        source.sheets.map((sheet) => sheet.name),
        containsAll(['Gennaio', 'Febbraio']),
      );
    });

    test('preferredSheet seleziona il foglio richiesto', () async {
      final source = await parser.parseBytes(
        fileName: 'anno.xlsx',
        bytes: multiSheetWorkbook(),
        preferredSheet: 'Febbraio',
      );

      expect(source.selectedSheet, 'Febbraio');
      expect(source.selectedTable.rowCount, 2);
    });

    test('preferredSheet ignorato per il CSV a foglio unico', () async {
      final source = await parser.parseBytes(
        fileName: 'movimenti.csv',
        bytes: _csv('Data,Importo\n2026-03-04,10.00\n'),
        preferredSheet: 'Inesistente',
      );

      expect(source.selectedSheet, 'CSV');
      expect(source.sheets, hasLength(1));
    });
  });
}
