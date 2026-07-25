import '../../domain/entities/cash_transaction.dart';
import '../../domain/value_objects/calendar_date.dart';
import '../../domain/value_objects/money_amount.dart';

class CashTransactionModel {
  const CashTransactionModel({
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
  final DateTime occurredOn;
  final String description;
  final String? notes;
  final String? categoryId;
  final String? categoryName;
  final bool? categoryIsActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Select con embed esplicito sulla FK Step 12B (evita ambiguità PostgREST).
  static const selectColumns =
      'id, company_id, client_id, kind, amount, occurred_on, '
      'description, notes, category_id, created_at, updated_at, '
      'category:transaction_categories!transactions_category_same_company_kind('
      'id, name, kind, is_active'
      ')';

  factory CashTransactionModel.fromJson(Map<String, dynamic> json) {
    final amountRaw = json['amount'];
    final amountString = amountRaw is String ? amountRaw : amountRaw.toString();

    final categoryId = json['category_id'] as String?;
    String? categoryName;
    bool? categoryIsActive;
    final categoryRaw = json['category'];
    if (categoryRaw is Map) {
      final category = Map<String, dynamic>.from(categoryRaw);
      categoryName = category['name'] as String?;
      categoryIsActive = category['is_active'] as bool?;
    }

    return CashTransactionModel(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      clientId: json['client_id'] as String?,
      kind: TransactionKind.fromDbValue(json['kind'] as String),
      amount: MoneyAmount.fromCanonicalDecimal(amountString),
      occurredOn: CalendarDate.parseIsoDate(
        _dateOnlyString(json['occurred_on']),
      ),
      description: json['description'] as String,
      notes: json['notes'] as String?,
      categoryId: categoryId,
      categoryName: categoryName,
      categoryIsActive: categoryIsActive,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  CashTransaction toEntity() {
    return CashTransaction(
      id: id,
      companyId: companyId,
      clientId: clientId,
      kind: kind,
      amount: amount,
      occurredOn: occurredOn,
      description: description,
      notes: notes,
      categoryId: categoryId,
      categoryName: categoryName,
      categoryIsActive: categoryIsActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static String _dateOnlyString(Object? raw) {
    if (raw is String) {
      // Supabase può restituire 'YYYY-MM-DD' o un timestamp ISO.
      if (raw.length >= 10) {
        return raw.substring(0, 10);
      }
      return raw;
    }
    throw FormatException('occurred_on non valido', raw);
  }
}
