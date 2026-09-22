import '../value_objects/money_amount.dart';
import 'cash_transaction.dart';
import 'transaction_import_issue.dart';

enum TransactionImportRowStatus {
  valid,
  invalid,
  possibleDuplicate,
  duplicateInFile,
}

/// Riga del file dopo l'applicazione del mapping e delle regole di dominio.
class TransactionImportRow {
  TransactionImportRow({
    required this.sourceRow,
    required List<String?> rawCells,
    required this.status,
    this.occurredOn,
    this.kind,
    this.amount,
    this.description,
    this.notes,
    this.reference,
    this.rowFingerprint,
    this.selectedForImport = false,
    this.needsNumberFormatSelection = false,
    this.needsDateFormatSelection = false,
    List<TransactionImportIssue> issues = const [],
  }) : rawCells = List.unmodifiable(rawCells),
       issues = List.unmodifiable(issues);

  /// Numero di riga nel foglio (l'intestazione è la riga 1).
  final int sourceRow;
  final List<String?> rawCells;
  final TransactionImportRowStatus status;
  final DateTime? occurredOn;
  final TransactionKind? kind;
  final MoneyAmount? amount;
  final String? description;
  final String? notes;
  final String? reference;

  /// SHA-256 della forma canonica della riga; `null` se la riga non è valida.
  final String? rowFingerprint;
  final bool selectedForImport;
  final bool needsNumberFormatSelection;
  final bool needsDateFormatSelection;
  final List<TransactionImportIssue> issues;

  bool get hasErrors => issues.any(
    (issue) => issue.severity == TransactionImportIssueSeverity.error,
  );

  TransactionImportRow copyWith({
    TransactionImportRowStatus? status,
    bool? selectedForImport,
    List<TransactionImportIssue>? issues,
  }) {
    return TransactionImportRow(
      sourceRow: sourceRow,
      rawCells: rawCells,
      status: status ?? this.status,
      occurredOn: occurredOn,
      kind: kind,
      amount: amount,
      description: description,
      notes: notes,
      reference: reference,
      rowFingerprint: rowFingerprint,
      selectedForImport: selectedForImport ?? this.selectedForImport,
      needsNumberFormatSelection: needsNumberFormatSelection,
      needsDateFormatSelection: needsDateFormatSelection,
      issues: issues ?? this.issues,
    );
  }

  @override
  String toString() {
    return 'TransactionImportRow(sourceRow: $sourceRow, status: $status, '
        'cellCount: ${rawCells.length}, issueCount: ${issues.length}, '
        'selectedForImport: $selectedForImport)';
  }
}
