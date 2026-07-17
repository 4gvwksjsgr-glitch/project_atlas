import '../../../../core/utils/result.dart';
import '../entities/customer.dart';
import '../repositories/customer_repository.dart';

class CreateCustomer {
  const CreateCustomer(this._repository);

  final CustomerRepository _repository;

  Future<Result<Customer>> call({
    required String companyId,
    required String name,
    String? email,
    String? phone,
    String? notes,
  }) {
    return _repository.createCustomer(
      companyId: companyId,
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
