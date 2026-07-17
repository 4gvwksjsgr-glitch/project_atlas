import '../../../../core/utils/result.dart';
import '../entities/cash_transaction.dart';
import '../value_objects/money_amount.dart';

abstract class TransactionRepository {
  Future<Result<List<CashTransaction>>> getTransactions({
    required String companyId,
  });

  Future<Result<CashTransaction>> createTransaction({
    required String companyId,
    String? clientId,
    required TransactionKind kind,
    required MoneyAmount amount,
    required DateTime occurredOn,
    required String description,
    String? notes,
  });

  Future<Result<CashTransaction>> updateTransaction({
    required String companyId,
    required String transactionId,
    String? clientId,
    required TransactionKind kind,
    required MoneyAmount amount,
    required DateTime occurredOn,
    required String description,
    String? notes,
  });
}
