import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../data/datasource/customer_remote_datasource.dart';
import '../../data/repositories/customer_repository_impl.dart';
import '../../domain/entities/customer.dart';
import '../../domain/repositories/customer_repository.dart';
import '../../domain/usecases/create_customer.dart';
import '../../domain/usecases/get_customers.dart';
import '../../domain/usecases/update_customer.dart';

final customerRemoteDataSourceProvider = Provider<CustomerRemoteDataSource>((
  ref,
) {
  return CustomerRemoteDataSource(ref.watch(supabaseClientProvider));
});

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  return CustomerRepositoryImpl(ref.watch(customerRemoteDataSourceProvider));
});

final getCustomersUseCaseProvider = Provider<GetCustomers>((ref) {
  return GetCustomers(ref.watch(customerRepositoryProvider));
});

final createCustomerUseCaseProvider = Provider<CreateCustomer>((ref) {
  return CreateCustomer(ref.watch(customerRepositoryProvider));
});

final updateCustomerUseCaseProvider = Provider<UpdateCustomer>((ref) {
  return UpdateCustomer(ref.watch(customerRepositoryProvider));
});

/// Lista clienti keyed per azienda attiva: al cambio companyId parte una nuova query.
final customersProvider = FutureProvider.autoDispose
    .family<List<Customer>, String>((ref, companyId) async {
      final result = await ref
          .read(getCustomersUseCaseProvider)
          .call(companyId: companyId);

      return result.when(
        success: (customers) => customers,
        error: (failure) => throw StateError(failure.message),
      );
    });
