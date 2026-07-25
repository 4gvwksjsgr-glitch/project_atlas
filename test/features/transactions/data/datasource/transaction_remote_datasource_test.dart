import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/features/transactions/data/datasource/transaction_remote_datasource.dart';
import 'package:project_atlas/features/transactions/data/models/cash_transaction_model.dart';
import 'package:project_atlas/features/transactions/domain/entities/cash_transaction.dart';
import 'package:project_atlas/features/transactions/domain/value_objects/calendar_date.dart';
import 'package:project_atlas/features/transactions/domain/value_objects/money_amount.dart';
import 'package:project_atlas/features/transactions/domain/value_objects/transaction_filters.dart';

void main() {
  group('TransactionRemoteDataSource', () {
    test('lista filtra sempre per company_id', () async {
      String? filteredCompanyId;

      final dataSource = TransactionRemoteDataSource.test(
        listExecutor: ({required String companyId, required filters}) async {
          filteredCompanyId = companyId;
          return [
            {
              'id': 't1',
              'company_id': companyId,
              'client_id': null,
              'category_id': null,
              'kind': 'income',
              'amount': '10.00',
              'occurred_on': '2026-07-17',
              'description': 'Vendita',
              'notes': null,
              'created_at': '2026-07-17T00:00:00.000Z',
              'updated_at': '2026-07-17T00:00:00.000Z',
            },
          ];
        },
      );

      final transactions = await dataSource.getTransactions(
        companyId: 'company-42',
      );

      expect(filteredCompanyId, 'company-42');
      expect(transactions, hasLength(1));
      expect(transactions.first, isA<CashTransactionModel>());
      expect(transactions.first.companyId, 'company-42');
    });

    test('rifiuta companyId vuoto sulla lista', () async {
      var called = false;
      final dataSource = TransactionRemoteDataSource.test(
        listExecutor: ({required String companyId, required filters}) async {
          called = true;
          return [];
        },
      );

      expect(
        () => dataSource.getTransactions(companyId: ''),
        throwsA(isA<ArgumentError>()),
      );
      expect(called, isFalse);
    });

    test(
      'create include company_id, amount canonico, occurred_on YYYY-MM-DD e notes null',
      () async {
        Map<String, dynamic>? payload;

        final dataSource = TransactionRemoteDataSource.test(
          createExecutor:
              ({
                required String companyId,
                String? clientId,
                String? categoryId,
                required TransactionKind kind,
                required MoneyAmount amount,
                required DateTime occurredOn,
                required String description,
                String? notes,
              }) async {
                payload = {
                  'company_id': companyId,
                  'client_id': clientId,
                  'category_id': categoryId,
                  'kind': kind.dbValue,
                  'amount': amount.toCanonicalDecimal(),
                  'occurred_on': CalendarDate.toIsoDate(occurredOn),
                  'description': description,
                  'notes': notes,
                };
                return {
                  'id': 'new-1',
                  'company_id': companyId,
                  'client_id': clientId,
                  'category_id': categoryId,
                  'kind': kind.dbValue,
                  'amount': amount.toCanonicalDecimal(),
                  'occurred_on': CalendarDate.toIsoDate(occurredOn),
                  'description': description,
                  'notes': notes,
                  'created_at': '2026-07-17T00:00:00.000Z',
                  'updated_at': '2026-07-17T00:00:00.000Z',
                };
              },
        );

        final transaction = await dataSource.createTransaction(
          companyId: 'company-7',
          kind: TransactionKind.expense,
          amount: MoneyAmount.parse('12,99'),
          occurredOn: DateTime(2026, 7, 17, 15, 30),
          description: 'Materiale ufficio',
          notes: null,
        );

        expect(payload?['company_id'], 'company-7');
        expect(payload?['amount'], '12.99');
        expect(payload?['occurred_on'], '2026-07-17');
        expect(payload?['notes'], isNull);
        expect(payload?['category_id'], isNull);
        expect(transaction.id, 'new-1');
        expect(transaction, isA<CashTransactionModel>());
      },
    );

    test('create include category_id quando fornito', () async {
      Map<String, dynamic>? payload;

      final dataSource = TransactionRemoteDataSource.test(
        createExecutor:
            ({
              required String companyId,
              String? clientId,
              String? categoryId,
              required TransactionKind kind,
              required MoneyAmount amount,
              required DateTime occurredOn,
              required String description,
              String? notes,
            }) async {
              payload = {
                'company_id': companyId,
                'client_id': clientId,
                'category_id': categoryId,
                'kind': kind.dbValue,
                'amount': amount.toCanonicalDecimal(),
                'occurred_on': CalendarDate.toIsoDate(occurredOn),
                'description': description,
                'notes': notes,
              };
              return {
                'id': 'new-2',
                'company_id': companyId,
                'client_id': clientId,
                'category_id': categoryId,
                'kind': kind.dbValue,
                'amount': amount.toCanonicalDecimal(),
                'occurred_on': CalendarDate.toIsoDate(occurredOn),
                'description': description,
                'notes': notes,
                'created_at': '2026-07-17T00:00:00.000Z',
                'updated_at': '2026-07-17T00:00:00.000Z',
              };
            },
      );

      await dataSource.createTransaction(
        companyId: 'company-7',
        categoryId: 'cat-9',
        kind: TransactionKind.expense,
        amount: MoneyAmount.parse('12,99'),
        occurredOn: DateTime(2026, 7, 17),
        description: 'Licenza',
      );

      expect(payload?['category_id'], 'cat-9');
    });

    test(
      'update usa doppio filtro id + company_id nel payload query',
      () async {
        String? filteredCompanyId;
        String? filteredTransactionId;

        final dataSource = TransactionRemoteDataSource.test(
          updateExecutor:
              ({
                required String companyId,
                required String transactionId,
                String? clientId,
                String? categoryId,
                required TransactionKind kind,
                required MoneyAmount amount,
                required DateTime occurredOn,
                required String description,
                String? notes,
              }) async {
                filteredCompanyId = companyId;
                filteredTransactionId = transactionId;
                return {
                  'id': transactionId,
                  'company_id': companyId,
                  'client_id': clientId,
                  'category_id': categoryId,
                  'kind': kind.dbValue,
                  'amount': amount.toCanonicalDecimal(),
                  'occurred_on': CalendarDate.toIsoDate(occurredOn),
                  'description': description,
                  'notes': notes,
                  'created_at': '2026-07-17T00:00:00.000Z',
                  'updated_at': '2026-07-18T00:00:00.000Z',
                };
              },
        );

        final transaction = await dataSource.updateTransaction(
          companyId: 'company-7',
          transactionId: 'txn-3',
          kind: TransactionKind.income,
          amount: MoneyAmount.parse('50,00'),
          occurredOn: DateTime(2026, 7, 18),
          description: 'Incasso',
        );

        expect(filteredCompanyId, 'company-7');
        expect(filteredTransactionId, 'txn-3');
        expect(transaction.description, 'Incasso');
      },
    );

    test(
      'il payload di update non deve mai contenere la chiave company_id',
      () async {
        Map<String, dynamic>? capturedPayload;

        final dataSource = TransactionRemoteDataSource.test(
          updateExecutor:
              ({
                required String companyId,
                required String transactionId,
                String? clientId,
                String? categoryId,
                required TransactionKind kind,
                required MoneyAmount amount,
                required DateTime occurredOn,
                required String description,
                String? notes,
              }) async {
                // Mai company_id nel payload di update: solo filtro via id/company_id.
                // category_id deve essere sempre presente (anche null) per consentire la rimozione.
                capturedPayload = {
                  'client_id': clientId,
                  'category_id': categoryId,
                  'kind': kind.dbValue,
                  'amount': amount.toCanonicalDecimal(),
                  'occurred_on': CalendarDate.toIsoDate(occurredOn),
                  'description': description,
                  'notes': notes,
                };
                return {
                  'id': transactionId,
                  'company_id': companyId,
                  'client_id': clientId,
                  'category_id': categoryId,
                  'kind': kind.dbValue,
                  'amount': amount.toCanonicalDecimal(),
                  'occurred_on': CalendarDate.toIsoDate(occurredOn),
                  'description': description,
                  'notes': notes,
                  'created_at': '2026-07-17T00:00:00.000Z',
                  'updated_at': '2026-07-18T00:00:00.000Z',
                };
              },
        );

        await dataSource.updateTransaction(
          companyId: 'company-7',
          transactionId: 'txn-3',
          kind: TransactionKind.expense,
          amount: MoneyAmount.parse('20,00'),
          occurredOn: DateTime(2026, 7, 18),
          description: 'Aggiornato',
        );

        expect(capturedPayload, isNotNull);
        expect(capturedPayload!.containsKey('company_id'), isFalse);
        expect(capturedPayload!.containsKey('category_id'), isTrue);
        expect(capturedPayload!['category_id'], isNull);
      },
    );

    test(
      'update con categoryId null include esplicitamente category_id',
      () async {
        Map<String, dynamic>? capturedPayload;

        final dataSource = TransactionRemoteDataSource.test(
          updateExecutor:
              ({
                required String companyId,
                required String transactionId,
                String? clientId,
                String? categoryId,
                required TransactionKind kind,
                required MoneyAmount amount,
                required DateTime occurredOn,
                required String description,
                String? notes,
              }) async {
                capturedPayload = {
                  'client_id': clientId,
                  'category_id': categoryId,
                  'kind': kind.dbValue,
                  'amount': amount.toCanonicalDecimal(),
                  'occurred_on': CalendarDate.toIsoDate(occurredOn),
                  'description': description,
                  'notes': notes,
                };
                return {
                  'id': transactionId,
                  'company_id': companyId,
                  'client_id': clientId,
                  'category_id': categoryId,
                  'kind': kind.dbValue,
                  'amount': amount.toCanonicalDecimal(),
                  'occurred_on': CalendarDate.toIsoDate(occurredOn),
                  'description': description,
                  'notes': notes,
                  'created_at': '2026-07-17T00:00:00.000Z',
                  'updated_at': '2026-07-18T00:00:00.000Z',
                };
              },
        );

        await dataSource.updateTransaction(
          companyId: 'company-7',
          transactionId: 'txn-3',
          categoryId: null,
          kind: TransactionKind.expense,
          amount: MoneyAmount.parse('20,00'),
          occurredOn: DateTime(2026, 7, 18),
          description: 'Senza categoria',
        );

        expect(capturedPayload!.containsKey('category_id'), isTrue);
        expect(capturedPayload!['category_id'], isNull);
      },
    );

    test('rifiuta companyId vuoto sulla create', () async {
      expect(
        () => TransactionRemoteDataSource.test().createTransaction(
          companyId: '',
          kind: TransactionKind.income,
          amount: MoneyAmount.parse('1,00'),
          occurredOn: DateTime(2026, 1, 1),
          description: 'Test',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rifiuta transactionId vuoto sulla update', () async {
      expect(
        () => TransactionRemoteDataSource.test().updateTransaction(
          companyId: 'company-1',
          transactionId: '',
          kind: TransactionKind.income,
          amount: MoneyAmount.parse('1,00'),
          occurredOn: DateTime(2026, 1, 1),
          description: 'Test',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('lista inoltra filtri AND all executor', () async {
      TransactionFilters? received;
      final dataSource = TransactionRemoteDataSource.test(
        listExecutor: ({required String companyId, required filters}) async {
          received = filters;
          return const [];
        },
      );

      final filters = TransactionFilters(
        fromDate: DateTime(2026, 1, 1),
        toDate: DateTime(2026, 1, 31),
        kind: TransactionKind.expense,
        clientId: 'client-1',
        descriptionQuery: 'bolletta',
      );
      await dataSource.getTransactions(
        companyId: 'company-42',
        filters: filters,
      );
      expect(received, filters);
    });

    test('escapeIlikePattern protegge % e _', () {
      expect(
        TransactionRemoteDataSource.escapeIlikePattern(r'100%_off'),
        r'100\%\_off',
      );
    });
  });
}
