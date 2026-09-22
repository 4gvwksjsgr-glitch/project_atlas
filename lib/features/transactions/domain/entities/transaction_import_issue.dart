enum TransactionImportIssueSeverity { error, warning }

/// Problema localizzabile di una riga import. [code] non contiene mai dati
/// del movimento.
class TransactionImportIssue {
  const TransactionImportIssue({
    required this.severity,
    required this.code,
    this.sourceRow,
  });

  final TransactionImportIssueSeverity severity;
  final int? sourceRow;
  final String code;

  @override
  String toString() {
    return 'TransactionImportIssue('
        'severity: $severity, sourceRow: $sourceRow, code: $code)';
  }
}
