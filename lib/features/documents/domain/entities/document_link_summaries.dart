/// Sintesi leggera del cliente collegato (non è [Customer]).
class DocumentClientSummary {
  const DocumentClientSummary({required this.id, required this.name});

  final String id;
  final String name;
}

enum DocumentTransactionKind {
  income,
  expense;

  static DocumentTransactionKind fromDbValue(String value) {
    return DocumentTransactionKind.values.firstWhere(
      (kind) => kind.name == value,
      orElse: () => throw FormatException('transaction_kind non valido', value),
    );
  }
}

/// Sintesi leggera del movimento collegato (non è [CashTransaction]).
class DocumentTransactionSummary {
  const DocumentTransactionSummary({
    required this.id,
    required this.description,
    required this.amountCents,
    required this.occurredOn,
    required this.kind,
  });

  final String id;
  final String description;

  /// Importo in centesimi (allineato a NUMERIC(14,2)).
  final int amountCents;
  final DateTime occurredOn;
  final DocumentTransactionKind kind;

  String formatEuro() {
    final whole = amountCents ~/ 100;
    final fraction = (amountCents % 100).toString().padLeft(2, '0');
    return '$whole,$fraction';
  }
}
