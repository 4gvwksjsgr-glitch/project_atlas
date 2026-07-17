import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/clients/domain/entities/customer.dart';
import 'package:project_atlas/features/clients/domain/repositories/customer_repository.dart';
import 'package:project_atlas/features/clients/domain/usecases/create_customer.dart';
import 'package:project_atlas/features/clients/domain/usecases/get_customers.dart';
import 'package:project_atlas/features/clients/domain/usecases/update_customer.dart';

class _CustomerRepositorySpy implements CustomerRepository {
  String? lastCompanyId;
  String? lastCustomerId;
  String? lastName;
  String? lastEmail;
  String? lastPhone;
  String? lastNotes;

  @override
  Future<Result<List<Customer>>> getCustomers({
    required String companyId,
  }) async {
    lastCompanyId = companyId;
    return const Success([]);
  }

  @override
  Future<Result<Customer>> createCustomer({
    required String companyId,
    required String name,
    String? email,
    String? phone,
    String? notes,
  }) async {
    lastCompanyId = companyId;
    lastName = name;
    lastEmail = email;
    lastPhone = phone;
    lastNotes = notes;
    return Success(
      Customer(
        id: 'cust-1',
        companyId: companyId,
        name: name,
        email: email,
        phone: phone,
        notes: notes,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
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
    lastCompanyId = companyId;
    lastCustomerId = customerId;
    lastName = name;
    lastEmail = email;
    lastPhone = phone;
    lastNotes = notes;
    return Success(
      Customer(
        id: customerId,
        companyId: companyId,
        name: name,
        email: email,
        phone: phone,
        notes: notes,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 2),
      ),
    );
  }
}

void main() {
  group('GetCustomers', () {
    test('inoltra companyId al repository', () async {
      final repository = _CustomerRepositorySpy();
      await GetCustomers(repository).call(companyId: 'company-1');
      expect(repository.lastCompanyId, 'company-1');
    });
  });

  group('CreateCustomer', () {
    test(
      'inoltra companyId e normalizza campi opzionali vuoti a null',
      () async {
        final repository = _CustomerRepositorySpy();
        await CreateCustomer(repository).call(
          companyId: 'company-1',
          name: '  Acme  ',
          email: '  ',
          phone: '',
          notes: '  note  ',
        );

        expect(repository.lastCompanyId, 'company-1');
        expect(repository.lastName, 'Acme');
        expect(repository.lastEmail, isNull);
        expect(repository.lastPhone, isNull);
        expect(repository.lastNotes, 'note');
      },
    );
  });

  group('UpdateCustomer', () {
    test('inoltra companyId, customerId e normalizza opzionali', () async {
      final repository = _CustomerRepositorySpy();
      await UpdateCustomer(repository).call(
        companyId: 'company-1',
        customerId: 'cust-9',
        name: 'Beta',
        email: 'beta@example.com',
        phone: '  ',
        notes: null,
      );

      expect(repository.lastCompanyId, 'company-1');
      expect(repository.lastCustomerId, 'cust-9');
      expect(repository.lastName, 'Beta');
      expect(repository.lastEmail, 'beta@example.com');
      expect(repository.lastPhone, isNull);
      expect(repository.lastNotes, isNull);
    });
  });
}
