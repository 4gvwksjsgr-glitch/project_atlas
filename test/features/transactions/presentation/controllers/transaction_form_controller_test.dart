import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/errors/failures.dart';
import 'package:project_atlas/core/permissions/company_role.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/companies/presentation/controllers/company_onboarding_controller.dart';
import 'package:project_atlas/features/transactions/domain/entities/cash_transaction.dart';
import 'package:project_atlas/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:project_atlas/features/transactions/domain/usecases/create_transaction.dart';
import 'package:project_atlas/features/transactions/domain/usecases/update_transaction.dart';
import 'package:project_atlas/features/transactions/domain/value_objects/money_amount.dart';
import 'package:project_atlas/features/transactions/presentation/controllers/transaction_form_controller.dart';
import 'package:project_atlas/features/transactions/presentation/providers/transaction_providers.dart';

class _Repo implements TransactionRepository {
  _Repo({this.createResult});

  Result<CashTransaction>? createResult;
  final List<String> listCompanyIds = [];
  int createCount = 0;
  int updateCount = 0;

  @override
  Future<Result<List<CashTransaction>>> getTransactions({
    required String companyId,
  }) async {
    listCompanyIds.add(companyId);
    return const Success([]);
  }

  @override
  Future<Result<CashTransaction>> createTransaction({
    required String companyId,
    String? clientId,
    required TransactionKind kind,
    required MoneyAmount amount,
    required DateTime occurredOn,
    required String description,
    String? notes,
  }) async {
    createCount += 1;
    return createResult ??
        Success(
          CashTransaction(
            id: 'new-1',
            companyId: companyId,
            clientId: clientId,
            kind: kind,
            amount: amount,
            occurredOn: occurredOn,
            description: description,
            notes: notes,
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );
  }

  @override
  Future<Result<CashTransaction>> updateTransaction({
    required String companyId,
    required String transactionId,
    String? clientId,
    required TransactionKind kind,
    required MoneyAmount amount,
    required DateTime occurredOn,
    required String description,
    String? notes,
  }) async {
    updateCount += 1;
    return Success(
      CashTransaction(
        id: transactionId,
        companyId: companyId,
        clientId: clientId,
        kind: kind,
        amount: amount,
        occurredOn: occurredOn,
        description: description,
        notes: notes,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 2),
      ),
    );
  }
}

void main() {
  group('TransactionFormController', () {
    test('create invalida solo la lista del companyId usato', () async {
      final repository = _Repo();
      final container = ProviderContainer(
        overrides: [
          transactionRepositoryProvider.overrideWithValue(repository),
          createTransactionUseCaseProvider.overrideWithValue(
            CreateTransaction(repository),
          ),
          updateTransactionUseCaseProvider.overrideWithValue(
            UpdateTransaction(repository),
          ),
          transactionsProvider.overrideWith((ref, companyId) async {
            final result = await repository.getTransactions(
              companyId: companyId,
            );
            return result.when(
              success: (value) => value,
              error: (failure) => throw StateError(failure.message),
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      const key = (companyId: 'company-a', transactionId: 'new');
      final sub = container.listen(
        transactionFormControllerProvider(key),
        (_, _) {},
      );
      addTearDown(sub.close);

      await container
          .read(transactionFormControllerProvider(key).notifier)
          .save(
            kind: TransactionKind.income,
            amount: MoneyAmount.parse('10,00'),
            occurredOn: DateTime(2026, 7, 17),
            description: 'Vendita A',
          );

      expect(
        container.read(transactionFormControllerProvider(key)).actionStatus,
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
          transactionRepositoryProvider.overrideWithValue(repository),
          createTransactionUseCaseProvider.overrideWithValue(
            CreateTransaction(repository),
          ),
        ],
      );
      addTearDown(container.dispose);

      const key = (companyId: 'company-a', transactionId: 'new');
      await container
          .read(transactionFormControllerProvider(key).notifier)
          .save(
            kind: TransactionKind.expense,
            amount: MoneyAmount.parse('5,00'),
            occurredOn: DateTime(2026, 7, 17),
            description: 'X',
          );

      final state = container.read(transactionFormControllerProvider(key));
      expect(state.actionStatus, CompanyActionStatus.error);
      expect(state.errorMessage, isNotNull);
      expect(state.savedTransaction, isNull);
    });
  });

  group('CompanyRole.canManageTransactions', () {
    test('owner admin manager possono gestire, employee no', () {
      expect(CompanyRole.owner.canManageTransactions, isTrue);
      expect(CompanyRole.admin.canManageTransactions, isTrue);
      expect(CompanyRole.manager.canManageTransactions, isTrue);
      expect(CompanyRole.employee.canManageTransactions, isFalse);
    });
  });
}
