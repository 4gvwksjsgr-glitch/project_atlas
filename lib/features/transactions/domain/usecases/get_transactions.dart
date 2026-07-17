import '../../../../core/utils/result.dart';
import '../entities/cash_transaction.dart';
import '../repositories/transaction_repository.dart';

class GetTransactions {
  const GetTransactions(this._repository);

  final TransactionRepository _repository;

  Future<Result<List<CashTransaction>>> call({required String companyId}) {
    return _repository.getTransactions(companyId: companyId);
  }
}
