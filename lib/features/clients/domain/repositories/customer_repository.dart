import '../../../../core/utils/result.dart';
import '../entities/customer.dart';

abstract interface class CustomerRepository {
  Future<Result<List<Customer>>> getCustomers({required String companyId});

  Future<Result<Customer>> createCustomer({
    required String companyId,
    required String name,
    String? email,
    String? phone,
    String? notes,
  });

  Future<Result<Customer>> updateCustomer({
    required String companyId,
    required String customerId,
    required String name,
    String? email,
    String? phone,
    String? notes,
  });
}
