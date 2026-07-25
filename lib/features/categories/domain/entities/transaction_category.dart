import '../../../transactions/domain/entities/cash_transaction.dart';

/// Categoria operativa di movimento (non fiscale), scoped per azienda.
class TransactionCategory {
  const TransactionCategory({
    required this.id,
    required this.companyId,
    required this.name,
    required this.kind,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String companyId;
  final String name;
  final TransactionKind kind;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  String toString() =>
      'TransactionCategory(id: $id, companyId: $companyId, kind: $kind, '
      'isActive: $isActive)';
}
