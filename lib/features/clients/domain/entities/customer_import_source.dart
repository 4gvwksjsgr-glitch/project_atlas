import 'customer_import_issue.dart';
import 'customer_import_sheet.dart';

enum CustomerImportSourceKind { csv, xlsx }

class CustomerImportTable {
  CustomerImportTable({
    required List<String> headers,
    required List<List<String?>> dataRows,
    List<int>? sourceRows,
  }) : headers = List.unmodifiable(headers),
       dataRows = List.unmodifiable(dataRows.map(List<String?>.unmodifiable)),
       sourceRows = List.unmodifiable(
         sourceRows ??
             List<int>.generate(dataRows.length, (index) => index + 2),
       ) {
    if (this.sourceRows.length != this.dataRows.length) {
      throw ArgumentError.value(
        sourceRows,
        'sourceRows',
        'Must have one source row for each data row.',
      );
    }
  }

  final List<String> headers;
  final List<List<String?>> dataRows;
  final List<int> sourceRows;

  int get rowCount => dataRows.length;

  @override
  String toString() =>
      'CustomerImportTable(headerCount: ${headers.length}, rowCount: $rowCount)';
}

class CustomerImportSource {
  CustomerImportSource({
    required this.fileName,
    required this.byteLength,
    required this.kind,
    required List<CustomerImportSheet> sheets,
    required this.selectedTable,
    this.selectedSheet,
  }) : sheets = List.unmodifiable(sheets);

  static const int maxFileBytes = 2 * 1024 * 1024;
  static const int maxDataRows = 500;
  static const int maxSheets = 20;

  final String fileName;
  final int byteLength;
  final CustomerImportSourceKind kind;
  final List<CustomerImportSheet> sheets;
  final String? selectedSheet;
  final CustomerImportTable selectedTable;

  List<CustomerImportIssue> get constraintIssues {
    final issues = <CustomerImportIssue>[];
    if (byteLength > maxFileBytes) {
      issues.add(
        const CustomerImportIssue(
          severity: CustomerImportIssueSeverity.error,
          code: 'fileTooLarge',
        ),
      );
    }
    if (sheets.length > maxSheets) {
      issues.add(
        const CustomerImportIssue(
          severity: CustomerImportIssueSeverity.error,
          code: 'tooManySheets',
        ),
      );
    }
    if (selectedTable.rowCount > maxDataRows) {
      issues.add(
        const CustomerImportIssue(
          severity: CustomerImportIssueSeverity.error,
          code: 'tooManyRows',
        ),
      );
    }
    return List.unmodifiable(issues);
  }

  @override
  String toString() {
    return 'CustomerImportSource(byteLength: $byteLength, kind: $kind, '
        'sheetCount: ${sheets.length}, rowCount: ${selectedTable.rowCount})';
  }
}
