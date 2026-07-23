import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../entities/cash_transaction.dart';
import '../repositories/transaction_repository.dart';
import '../value_objects/transaction_filters.dart';

class GetTransactions {
  const GetTransactions(this._repository);

  final TransactionRepository _repository;

  Future<Result<List<CashTransaction>>> call({
    required String companyId,
    TransactionFilters filters = const TransactionFilters(),
  }) {
    final validationError = filters.validationError;
    if (validationError != null) {
      return Future.value(Error(ValidationFailure(validationError)));
    }
    return _repository.getTransactions(companyId: companyId, filters: filters);
  }
}
