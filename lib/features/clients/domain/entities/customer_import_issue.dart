enum CustomerImportIssueSeverity { error, warning }

/// A localizable import issue. [code] deliberately contains no customer data.
class CustomerImportIssue {
  const CustomerImportIssue({
    required this.severity,
    required this.code,
    this.sourceRow,
  });

  final CustomerImportIssueSeverity severity;
  final int? sourceRow;
  final String code;

  @override
  String toString() {
    return 'CustomerImportIssue('
        'severity: $severity, sourceRow: $sourceRow, code: $code)';
  }
}
