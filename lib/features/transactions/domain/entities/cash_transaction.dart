import '../value_objects/money_amount.dart';

enum TransactionKind {
  income,
  expense;

  String get dbValue => name;

  static TransactionKind fromDbValue(String value) {
    return TransactionKind.values.firstWhere(
      (kind) => kind.name == value,
      orElse: () => throw FormatException('transaction_kind non valido', value),
    );
  }
}

class CashTransaction {
  const CashTransaction({
    required this.id,
    required this.companyId,
    this.clientId,
    required this.kind,
    required this.amount,
    required this.occurredOn,
    required this.description,
    this.notes,
    this.categoryId,
    this.categoryName,
    this.categoryIsActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String companyId;
  final String? clientId;
  final TransactionKind kind;
  final MoneyAmount amount;

  /// Solo data locale (anno/mese/giorno); l'orario non è significativo.
  final DateTime occurredOn;
  final String description;
  final String? notes;
  final String? categoryId;
  final String? categoryName;
  final bool? categoryIsActive;
  final DateTime createdAt;
  final DateTime updatedAt;
}
