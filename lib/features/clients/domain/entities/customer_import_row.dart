import 'customer_import_issue.dart';

/// A row after a column mapping has been applied.
class CustomerImportRow {
  CustomerImportRow({
    required this.sourceRow,
    required List<String?> rawCells,
    this.name,
    this.email,
    this.phone,
    this.notes,
    List<CustomerImportIssue> issues = const [],
    this.wasNumericPhone = false,
  }) : rawCells = List.unmodifiable(rawCells),
       issues = List.unmodifiable(issues);

  /// One-based spreadsheet row number. The header is row 1.
  final int sourceRow;
  final List<String?> rawCells;
  final String? name;
  final String? email;
  final String? phone;
  final String? notes;
  final List<CustomerImportIssue> issues;
  final bool wasNumericPhone;

  bool get hasErrors => issues.any(
    (issue) => issue.severity == CustomerImportIssueSeverity.error,
  );

  @override
  String toString() {
    return 'CustomerImportRow(sourceRow: $sourceRow, '
        'cellCount: ${rawCells.length}, issueCount: ${issues.length}, '
        'wasNumericPhone: $wasNumericPhone)';
  }
}
