import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/errors/failures.dart';
import 'package:project_atlas/core/permissions/company_role.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/companies/presentation/controllers/company_onboarding_controller.dart';
import 'package:project_atlas/features/dashboard/domain/entities/dashboard_cash_summary.dart';
import 'package:project_atlas/features/dashboard/domain/repositories/dashboard_cash_repository.dart';
import 'package:project_atlas/features/dashboard/domain/usecases/get_dashboard_cash_summary.dart';
import 'package:project_atlas/features/dashboard/domain/value_objects/money_total.dart';
import 'package:project_atlas/features/dashboard/presentation/providers/dashboard_cash_providers.dart';
import 'package:project_atlas/features/transactions/domain/entities/cash_transaction.dart';
import 'package:project_atlas/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:project_atlas/features/transactions/domain/usecases/create_transaction.dart';
import 'package:project_atlas/features/transactions/domain/usecases/update_transaction.dart';
import 'package:project_atlas/features/transactions/domain/value_objects/money_amount.dart';
import 'package:project_atlas/features/transactions/domain/value_objects/transaction_filters.dart';
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
    TransactionFilters filters = const TransactionFilters(),
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

class _CashRepo implements DashboardCashRepository {
  final List<String> requestedCompanyIds = [];

  @override
  Future<Result<DashboardCashSummary>> getCashSummary({
    required String companyId,
    required DateTime monthStart,
    required DateTime nextMonthStart,
  }) async {
    requestedCompanyIds.add(companyId);
    return Success(
      DashboardCashSummary(
        totalIncome: MoneyTotal.fromCents(1000),
        totalExpense: MoneyTotal.zero,
        movementCount: 1,
        monthIncome: MoneyTotal.fromCents(1000),
        monthExpense: MoneyTotal.zero,
        monthMovementCount: 1,
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

    test(
      'create/update invalida soltanto il riepilogo economico di quell\'azienda',
      () async {
        final repository = _Repo();
        final cashRepo = _CashRepo();
        final container = ProviderContainer(
          overrides: [
            transactionRepositoryProvider.overrideWithValue(repository),
            createTransactionUseCaseProvider.overrideWithValue(
              CreateTransaction(repository),
            ),
            updateTransactionUseCaseProvider.overrideWithValue(
              UpdateTransaction(repository),
            ),
            getDashboardCashSummaryUseCaseProvider.overrideWithValue(
              GetDashboardCashSummary(cashRepo),
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

        final cashSubA = container.listen(
          dashboardCashSummaryProvider('company-a'),
          (_, _) {},
        );
        final cashSubB = container.listen(
          dashboardCashSummaryProvider('company-b'),
          (_, _) {},
        );
        addTearDown(cashSubA.close);
        addTearDown(cashSubB.close);

        await container.read(dashboardCashSummaryProvider('company-a').future);
        await container.read(dashboardCashSummaryProvider('company-b').future);
        expect(cashRepo.requestedCompanyIds, ['company-a', 'company-b']);

        const createKey = (companyId: 'company-a', transactionId: 'new');
        await container
            .read(transactionFormControllerProvider(createKey).notifier)
            .save(
              kind: TransactionKind.income,
              amount: MoneyAmount.parse('10,00'),
              occurredOn: DateTime(2026, 7, 17),
              description: 'Vendita',
            );

        await container.read(dashboardCashSummaryProvider('company-a').future);
        expect(
          cashRepo.requestedCompanyIds.where((id) => id == 'company-a').length,
          2,
        );
        expect(
          cashRepo.requestedCompanyIds.where((id) => id == 'company-b').length,
          1,
        );

        const updateKey = (companyId: 'company-a', transactionId: 'tx-1');
        await container
            .read(transactionFormControllerProvider(updateKey).notifier)
            .save(
              kind: TransactionKind.expense,
              amount: MoneyAmount.parse('5,00'),
              occurredOn: DateTime(2026, 7, 18),
              description: 'Spesa',
            );

        await container.read(dashboardCashSummaryProvider('company-a').future);
        expect(
          cashRepo.requestedCompanyIds.where((id) => id == 'company-a').length,
          3,
        );
        expect(
          cashRepo.requestedCompanyIds.where((id) => id == 'company-b').length,
          1,
        );
        expect(repository.updateCount, 1);
      },
    );

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

  group('CompanyRole.canManageCategories', () {
    test('owner admin manager possono gestire, employee no', () {
      expect(CompanyRole.owner.canManageCategories, isTrue);
      expect(CompanyRole.admin.canManageCategories, isTrue);
      expect(CompanyRole.manager.canManageCategories, isTrue);
      expect(CompanyRole.employee.canManageCategories, isFalse);
    });
  });
}
