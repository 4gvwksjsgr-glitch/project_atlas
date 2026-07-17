import '../../../../core/utils/result.dart';
import '../entities/customer.dart';
import '../repositories/customer_repository.dart';

class GetCustomers {
  const GetCustomers(this._repository);

  final CustomerRepository _repository;

  Future<Result<List<Customer>>> call({required String companyId}) {
    return _repository.getCustomers(companyId: companyId);
  }
}
