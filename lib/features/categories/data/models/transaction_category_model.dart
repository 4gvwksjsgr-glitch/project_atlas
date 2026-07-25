import '../../domain/entities/transaction_category.dart';
import '../../../transactions/domain/entities/cash_transaction.dart';

class TransactionCategoryModel {
  const TransactionCategoryModel({
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

  static const selectColumns =
      'id, company_id, name, kind, is_active, created_at, updated_at';

  factory TransactionCategoryModel.fromJson(Map<String, dynamic> json) {
    return TransactionCategoryModel(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      name: json['name'] as String,
      kind: TransactionKind.fromDbValue(json['kind'] as String),
      isActive: json['is_active'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  TransactionCategory toEntity() {
    return TransactionCategory(
      id: id,
      companyId: companyId,
      name: name,
      kind: kind,
      isActive: isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
