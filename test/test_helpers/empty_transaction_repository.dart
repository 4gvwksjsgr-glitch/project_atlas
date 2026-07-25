import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/transactions/domain/entities/cash_transaction.dart';
import 'package:project_atlas/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:project_atlas/features/transactions/domain/value_objects/money_amount.dart';
import 'package:project_atlas/features/transactions/domain/value_objects/transaction_filters.dart';

/// Repository stub per test che montano lo shell (indexedStack).
class EmptyTransactionRepository implements TransactionRepository {
  const EmptyTransactionRepository();

  @override
  Future<Result<List<CashTransaction>>> getTransactions({
    required String companyId,
    TransactionFilters filters = const TransactionFilters(),
  }) async {
    return const Success([]);
  }

  @override
  Future<Result<CashTransaction>> createTransaction({
    required String companyId,
    String? clientId,
    String? categoryId,
    required TransactionKind kind,
    required MoneyAmount amount,
    required DateTime occurredOn,
    required String description,
    String? notes,
  }) async {
    throw UnsupportedError('create non usato in questo stub');
  }

  @override
  Future<Result<CashTransaction>> updateTransaction({
    required String companyId,
    required String transactionId,
    String? clientId,
    String? categoryId,
    required TransactionKind kind,
    required MoneyAmount amount,
    required DateTime occurredOn,
    required String description,
    String? notes,
  }) async {
    throw UnsupportedError('update non usato in questo stub');
  }
}
