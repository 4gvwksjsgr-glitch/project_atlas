import 'transaction_import_issue.dart';
import 'transaction_import_payload_row.dart';
import 'transaction_import_row.dart';

class TransactionImportPlan {
  TransactionImportPlan({
    required this.total,
    required this.valid,
    required this.invalid,
    required this.possibleDuplicate,
    required this.duplicateInFile,
    required this.selectedForImport,
    required this.emptyIgnored,
    required this.warnings,
    required this.needsNumberFormatSelection,
    required this.needsDateFormatSelection,
    required List<TransactionImportRow> rows,
    required List<TransactionImportPayloadRow> rowsToImport,
    List<TransactionImportIssue> sourceIssues = const [],
  }) : rows = List.unmodifiable(rows),
       rowsToImport = List.unmodifiable(rowsToImport),
       sourceIssues = List.unmodifiable(sourceIssues);

  /// Righe non vuote lette dal foglio.
  final int total;
  final int valid;
  final int invalid;
  final int possibleDuplicate;
  final int duplicateInFile;
  final int selectedForImport;
  final int emptyIgnored;
  final int warnings;

  /// Il file contiene separatori decimali ambigui non ancora risolti.
  final bool needsNumberFormatSelection;

  /// Il file contiene date giorno/mese ambigue non ancora risolte.
  final bool needsDateFormatSelection;

  final List<TransactionImportRow> rows;
  final List<TransactionImportPayloadRow> rowsToImport;
  final List<TransactionImportIssue> sourceIssues;

  bool get hasBlockingIssues =>
      sourceIssues.any(
        (issue) => issue.severity == TransactionImportIssueSeverity.error,
      ) ||
      needsNumberFormatSelection ||
      needsDateFormatSelection;

  @override
  String toString() {
    return 'TransactionImportPlan(total: $total, valid: $valid, '
        'invalid: $invalid, possibleDuplicate: $possibleDuplicate, '
        'duplicateInFile: $duplicateInFile, '
        'selectedForImport: $selectedForImport)';
  }
}
