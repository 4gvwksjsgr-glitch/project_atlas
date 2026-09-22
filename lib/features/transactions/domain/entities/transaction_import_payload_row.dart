/// Riga inviata alla RPC `import_transactions`.
///
/// Non contiene mai `company_id` né `id`: il server li deriva dai parametri
/// della RPC.
class TransactionImportPayloadRow {
  const TransactionImportPayloadRow({
    required this.sourceRow,
    required this.occurredOn,
    required this.kind,
    required this.amount,
    required this.description,
    required this.rowFingerprint,
    this.notes,
    this.reference,
  });

  final int sourceRow;

  /// `YYYY-MM-DD`.
  final String occurredOn;

  /// `income` | `expense`.
  final String kind;

  /// Decimale canonico, es. `1234.56`.
  final String amount;
  final String description;
  final String rowFingerprint;
  final String? notes;
  final String? reference;

  Map<String, dynamic> toJson() => {
    'source_row': sourceRow,
    'occurred_on': occurredOn,
    'kind': kind,
    'amount': amount,
    'description': description,
    if (notes != null) 'notes': notes,
    if (reference != null) 'reference': reference,
    'row_fingerprint': rowFingerprint,
  };

  @override
  String toString() => 'TransactionImportPayloadRow(sourceRow: $sourceRow)';
}
