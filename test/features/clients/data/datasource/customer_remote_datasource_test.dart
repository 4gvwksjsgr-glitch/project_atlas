import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/features/clients/data/datasource/customer_remote_datasource.dart';
import 'package:project_atlas/features/clients/data/models/customer_model.dart';

void main() {
  group('CustomerRemoteDataSource', () {
    test('lista filtra sempre per company_id', () async {
      String? filteredCompanyId;

      final dataSource = CustomerRemoteDataSource.test(
        listExecutor: ({required String companyId}) async {
          filteredCompanyId = companyId;
          return [
            {
              'id': 'c1',
              'company_id': companyId,
              'name': 'Acme',
              'email': null,
              'phone': null,
              'notes': null,
              'created_at': '2026-01-01T00:00:00.000Z',
              'updated_at': '2026-01-01T00:00:00.000Z',
            },
          ];
        },
      );

      final customers = await dataSource.getCustomers(companyId: 'company-42');
      expect(filteredCompanyId, 'company-42');
      expect(customers, hasLength(1));
      expect(customers.first, isA<CustomerModel>());
      expect(customers.first.companyId, 'company-42');
    });

    test('create include company_id nel payload', () async {
      Map<String, dynamic>? payload;

      final dataSource = CustomerRemoteDataSource.test(
        createExecutor:
            ({
              required String companyId,
              required String name,
              String? email,
              String? phone,
              String? notes,
            }) async {
              payload = {
                'company_id': companyId,
                'name': name,
                'email': email,
                'phone': phone,
                'notes': notes,
              };
              return {
                'id': 'new-1',
                'company_id': companyId,
                'name': name,
                'email': email,
                'phone': phone,
                'notes': notes,
                'created_at': '2026-01-01T00:00:00.000Z',
                'updated_at': '2026-01-01T00:00:00.000Z',
              };
            },
      );

      final customer = await dataSource.createCustomer(
        companyId: 'company-7',
        name: 'Cliente',
        email: null,
        phone: '123',
        notes: null,
      );

      expect(payload?['company_id'], 'company-7');
      expect(customer.id, 'new-1');
      expect(customer.phone, '123');
    });

    test('update usa doppio filtro id + company_id', () async {
      String? filteredCompanyId;
      String? filteredCustomerId;

      final dataSource = CustomerRemoteDataSource.test(
        updateExecutor:
            ({
              required String companyId,
              required String customerId,
              required String name,
              String? email,
              String? phone,
              String? notes,
            }) async {
              filteredCompanyId = companyId;
              filteredCustomerId = customerId;
              return {
                'id': customerId,
                'company_id': companyId,
                'name': name,
                'email': email,
                'phone': phone,
                'notes': notes,
                'created_at': '2026-01-01T00:00:00.000Z',
                'updated_at': '2026-01-02T00:00:00.000Z',
              };
            },
      );

      final customer = await dataSource.updateCustomer(
        companyId: 'company-7',
        customerId: 'cust-3',
        name: 'Aggiornato',
      );

      expect(filteredCompanyId, 'company-7');
      expect(filteredCustomerId, 'cust-3');
      expect(customer.name, 'Aggiornato');
    });

    test('rifiuta companyId vuoto sulla lista', () async {
      var called = false;
      final dataSource = CustomerRemoteDataSource.test(
        listExecutor: ({required String companyId}) async {
          called = true;
          return [];
        },
      );

      expect(
        () => dataSource.getCustomers(companyId: ''),
        throwsA(isA<ArgumentError>()),
      );
      expect(called, isFalse);
    });
  });
}
