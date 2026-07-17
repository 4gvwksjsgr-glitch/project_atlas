import '../../../../core/utils/result.dart';
import '../entities/cash_transaction.dart';
import '../repositories/transaction_repository.dart';
import '../value_objects/calendar_date.dart';
import '../value_objects/money_amount.dart';

class UpdateTransaction {
  const UpdateTransaction(this._repository);

  final TransactionRepository _repository;

  Future<Result<CashTransaction>> call({
    required String companyId,
    required String transactionId,
    String? clientId,
    required TransactionKind kind,
    required MoneyAmount amount,
    required DateTime occurredOn,
    required String description,
    String? notes,
  }) {
    return _repository.updateTransaction(
      companyId: companyId,
      transactionId: transactionId,
      clientId: _normalizeOptionalId(clientId),
      kind: kind,
      amount: amount,
      occurredOn: CalendarDate.dateOnly(occurredOn),
      description: description.trim(),
      notes: _normalizeOptional(notes),
    );
  }

  static String? _normalizeOptional(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _normalizeOptionalId(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
