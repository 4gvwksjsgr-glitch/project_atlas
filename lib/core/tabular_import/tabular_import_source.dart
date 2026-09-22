import 'tabular_import_sheet.dart';
import 'tabular_import_table.dart';

enum TabularImportSourceKind { csv, xlsx }

enum TabularImportIssueSeverity { error, warning }

/// Problema localizzabile: [code] non contiene mai dati dell'utente.
class TabularImportIssue {
  const TabularImportIssue({required this.severity, required this.code});

  final TabularImportIssueSeverity severity;
  final String code;

  @override
  String toString() =>
      'TabularImportIssue(severity: $severity, code: $code)';
}

/// File tabellare già decodificato, con il foglio selezionato e i suoi limiti.
class TabularImportSource {
  TabularImportSource({
    required this.fileName,
    required this.byteLength,
    required this.kind,
    required List<TabularImportSheet> sheets,
    required this.selectedTable,
    this.selectedSheet,
  }) : sheets = List.unmodifiable(sheets);

  static const int maxFileBytes = 2 * 1024 * 1024;
  static const int maxDataRows = 500;
  static const int maxSheets = 20;

  final String fileName;
  final int byteLength;
  final TabularImportSourceKind kind;
  final List<TabularImportSheet> sheets;
  final String? selectedSheet;
  final TabularImportTable selectedTable;

  List<TabularImportIssue> get constraintIssues {
    final issues = <TabularImportIssue>[];
    if (byteLength > maxFileBytes) {
      issues.add(
        const TabularImportIssue(
          severity: TabularImportIssueSeverity.error,
          code: 'fileTooLarge',
        ),
      );
    }
    if (sheets.length > maxSheets) {
      issues.add(
        const TabularImportIssue(
          severity: TabularImportIssueSeverity.error,
          code: 'tooManySheets',
        ),
      );
    }
    if (selectedTable.rowCount > maxDataRows) {
      issues.add(
        const TabularImportIssue(
          severity: TabularImportIssueSeverity.error,
          code: 'tooManyRows',
        ),
      );
    }
    return List.unmodifiable(issues);
  }

  @override
  String toString() {
    return 'TabularImportSource(byteLength: $byteLength, kind: $kind, '
        'sheetCount: ${sheets.length}, rowCount: ${selectedTable.rowCount})';
  }
}
