import 'customer_import_issue.dart';
import 'customer_import_payload_row.dart';
import 'customer_import_row.dart';

class CustomerImportExcludedDuplicate {
  const CustomerImportExcludedDuplicate({required this.sourceRow});

  final int sourceRow;

  @override
  String toString() => 'CustomerImportExcludedDuplicate(sourceRow: $sourceRow)';
}

class CustomerImportPlan {
  CustomerImportPlan({
    required this.readCount,
    required this.validToImport,
    required this.skippedDuplicates,
    required this.errorRows,
    required this.emptyIgnored,
    required this.warnings,
    required List<CustomerImportPayloadRow> rowsToImport,
    required List<CustomerImportExcludedDuplicate> excludedDuplicates,
    required List<CustomerImportRow> rows,
    List<CustomerImportIssue> sourceIssues = const [],
  }) : rowsToImport = List.unmodifiable(rowsToImport),
       excludedDuplicates = List.unmodifiable(excludedDuplicates),
       rows = List.unmodifiable(rows),
       sourceIssues = List.unmodifiable(sourceIssues);

  final int readCount;
  final int validToImport;
  final int skippedDuplicates;
  final int errorRows;
  final int emptyIgnored;
  final int warnings;
  final List<CustomerImportPayloadRow> rowsToImport;
  final List<CustomerImportExcludedDuplicate> excludedDuplicates;
  final List<CustomerImportRow> rows;
  final List<CustomerImportIssue> sourceIssues;

  bool get hasBlockingIssues => sourceIssues.any(
    (issue) => issue.severity == CustomerImportIssueSeverity.error,
  );

  @override
  String toString() {
    return 'CustomerImportPlan(readCount: $readCount, '
        'validToImport: $validToImport, skippedDuplicates: $skippedDuplicates, '
        'errorRows: $errorRows, emptyIgnored: $emptyIgnored, '
        'warnings: $warnings)';
  }
}
