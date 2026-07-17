import '../../../../core/utils/result.dart';
import '../entities/customer.dart';
import '../repositories/customer_repository.dart';

class UpdateCustomer {
  const UpdateCustomer(this._repository);

  final CustomerRepository _repository;

  Future<Result<Customer>> call({
    required String companyId,
    required String customerId,
    required String name,
    String? email,
    String? phone,
    String? notes,
  }) {
    return _repository.updateCustomer(
      companyId: companyId,
      customerId: customerId,
      name: name.trim(),
      email: _normalizeOptional(email),
      phone: _normalizeOptional(phone),
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
}
