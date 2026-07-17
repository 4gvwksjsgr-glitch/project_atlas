import '../../../../core/errors/customer_error_mapper.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/customer.dart';
import '../../domain/repositories/customer_repository.dart';
import '../datasource/customer_remote_datasource.dart';

class CustomerRepositoryImpl implements CustomerRepository {
  const CustomerRepositoryImpl(this._remoteDataSource);

  final CustomerRemoteDataSource _remoteDataSource;

  @override
  Future<Result<List<Customer>>> getCustomers({
    required String companyId,
  }) async {
    if (companyId.isEmpty) {
      return const Error(ValidationFailure('Azienda non valida.'));
    }

    try {
      final customers = await _remoteDataSource.getCustomers(
        companyId: companyId,
      );
      return Success(customers.map((model) => model.toEntity()).toList());
    } on Object catch (error) {
      return Error(
        CustomerErrorMapper.mapException(error, CustomerOperation.getCustomers),
      );
    }
  }

  @override
  Future<Result<Customer>> createCustomer({
    required String companyId,
    required String name,
    String? email,
    String? phone,
    String? notes,
  }) async {
    if (companyId.isEmpty) {
      return const Error(ValidationFailure('Azienda non valida.'));
    }

    try {
      final customer = await _remoteDataSource.createCustomer(
        companyId: companyId,
        name: name,
        email: email,
        phone: phone,
        notes: notes,
      );
      return Success(customer.toEntity());
    } on Object catch (error) {
      return Error(
        CustomerErrorMapper.mapException(
          error,
          CustomerOperation.createCustomer,
        ),
      );
    }
  }

  @override
  Future<Result<Customer>> updateCustomer({
    required String companyId,
    required String customerId,
    required String name,
    String? email,
    String? phone,
    String? notes,
  }) async {
    if (companyId.isEmpty) {
      return const Error(ValidationFailure('Azienda non valida.'));
    }
    if (customerId.isEmpty) {
      return const Error(ValidationFailure('Cliente non valido.'));
    }

    try {
      final customer = await _remoteDataSource.updateCustomer(
        companyId: companyId,
        customerId: customerId,
        name: name,
        email: email,
        phone: phone,
        notes: notes,
      );
      return Success(customer.toEntity());
    } on Object catch (error) {
      return Error(
        CustomerErrorMapper.mapException(
          error,
          CustomerOperation.updateCustomer,
        ),
      );
    }
  }
}
