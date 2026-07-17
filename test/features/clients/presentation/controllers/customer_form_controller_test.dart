import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/errors/failures.dart';
import 'package:project_atlas/core/permissions/company_role.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/clients/domain/entities/customer.dart';
import 'package:project_atlas/features/clients/domain/repositories/customer_repository.dart';
import 'package:project_atlas/features/clients/domain/usecases/create_customer.dart';
import 'package:project_atlas/features/clients/domain/usecases/update_customer.dart';
import 'package:project_atlas/features/clients/presentation/controllers/customer_form_controller.dart';
import 'package:project_atlas/features/clients/presentation/providers/customer_providers.dart';
import 'package:project_atlas/features/companies/presentation/controllers/company_onboarding_controller.dart';

class _Repo implements CustomerRepository {
  _Repo({this.createResult});

  Result<Customer>? createResult;
  final List<String> listCompanyIds = [];
  int createCount = 0;
  int updateCount = 0;

  @override
  Future<Result<List<Customer>>> getCustomers({
    required String companyId,
  }) async {
    listCompanyIds.add(companyId);
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
    createCount += 1;
    return createResult ??
        Success(
          Customer(
            id: 'new-1',
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
    updateCount += 1;
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
  group('CustomerFormController', () {
    test('create invalida solo la lista del companyId usato', () async {
      final repository = _Repo();
      final container = ProviderContainer(
        overrides: [
          customerRepositoryProvider.overrideWithValue(repository),
          createCustomerUseCaseProvider.overrideWithValue(
            CreateCustomer(repository),
          ),
          updateCustomerUseCaseProvider.overrideWithValue(
            UpdateCustomer(repository),
          ),
          customersProvider.overrideWith((ref, companyId) async {
            final result = await repository.getCustomers(companyId: companyId);
            return result.when(
              success: (value) => value,
              error: (failure) => throw StateError(failure.message),
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      const key = (companyId: 'company-a', customerId: 'new');
      final sub = container.listen(
        customerFormControllerProvider(key),
        (_, _) {},
      );
      addTearDown(sub.close);

      await container
          .read(customerFormControllerProvider(key).notifier)
          .save(name: 'Cliente A');

      expect(
        container.read(customerFormControllerProvider(key)).actionStatus,
        CompanyActionStatus.success,
      );
      expect(repository.createCount, 1);
      expect(repository.listCompanyIds, contains('company-a'));
      expect(repository.listCompanyIds, isNot(contains('company-b')));
    });

    test('errore conserva stato error senza successo', () async {
      final repository = _Repo(createResult: const Error(NetworkFailure()));
      final container = ProviderContainer(
        overrides: [
          customerRepositoryProvider.overrideWithValue(repository),
          createCustomerUseCaseProvider.overrideWithValue(
            CreateCustomer(repository),
          ),
        ],
      );
      addTearDown(container.dispose);

      const key = (companyId: 'company-a', customerId: 'new');
      await container
          .read(customerFormControllerProvider(key).notifier)
          .save(name: 'X');

      final state = container.read(customerFormControllerProvider(key));
      expect(state.actionStatus, CompanyActionStatus.error);
      expect(state.errorMessage, isNotNull);
    });
  });

  group('CompanyRole.canManageCustomers', () {
    test('owner admin manager possono gestire, employee no', () {
      expect(CompanyRole.owner.canManageCustomers, isTrue);
      expect(CompanyRole.admin.canManageCustomers, isTrue);
      expect(CompanyRole.manager.canManageCustomers, isTrue);
      expect(CompanyRole.employee.canManageCustomers, isFalse);
    });
  });
}
