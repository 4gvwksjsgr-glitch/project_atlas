import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/categories/domain/entities/transaction_category.dart';
import 'package:project_atlas/features/transactions/domain/entities/cash_transaction.dart';
import 'package:project_atlas/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:project_atlas/features/transactions/domain/usecases/create_transaction.dart';
import 'package:project_atlas/features/transactions/domain/usecases/get_transactions.dart';
import 'package:project_atlas/features/transactions/domain/usecases/update_transaction.dart';
import 'package:project_atlas/features/transactions/domain/value_objects/money_amount.dart';
import 'package:project_atlas/features/transactions/domain/value_objects/transaction_filters.dart';

import '../../helpers/fake_category_repository.dart';

class _TransactionRepositorySpy implements TransactionRepository {
  String? lastCompanyId;
  TransactionFilters? lastFilters;
  String? lastTransactionId;
  String? lastClientId;
  String? lastCategoryId;
  TransactionKind? lastKind;
  MoneyAmount? lastAmount;
  DateTime? lastOccurredOn;
  String? lastDescription;
  String? lastNotes;

  @override
  Future<Result<List<CashTransaction>>> getTransactions({
    required String companyId,
    TransactionFilters filters = const TransactionFilters(),
  }) async {
    lastCompanyId = companyId;
    lastFilters = filters;
    return const Success([]);
  }

  @override
  Future<Result<CashTransaction>> createTransaction({
    required String companyId,
    String? clientId,
    String? categoryId,
    required TransactionKind kind,
    required MoneyAmount amount,
    required DateTime occurredOn,
    required String description,
    String? notes,
  }) async {
    lastCompanyId = companyId;
    lastClientId = clientId;
    lastCategoryId = categoryId;
    lastKind = kind;
    lastAmount = amount;
    lastOccurredOn = occurredOn;
    lastDescription = description;
    lastNotes = notes;
    return Success(
      CashTransaction(
        id: 'txn-1',
        companyId: companyId,
        clientId: clientId,
        categoryId: categoryId,
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
    String? categoryId,
    required TransactionKind kind,
    required MoneyAmount amount,
    required DateTime occurredOn,
    required String description,
    String? notes,
  }) async {
    lastCompanyId = companyId;
    lastTransactionId = transactionId;
    lastClientId = clientId;
    lastCategoryId = categoryId;
    lastKind = kind;
    lastAmount = amount;
    lastOccurredOn = occurredOn;
    lastDescription = description;
    lastNotes = notes;
    return Success(
      CashTransaction(
        id: transactionId,
        companyId: companyId,
        clientId: clientId,
        categoryId: categoryId,
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
  group('GetTransactions', () {
    test('inoltra companyId al repository', () async {
      final repository = _TransactionRepositorySpy();
      await GetTransactions(repository).call(companyId: 'company-1');
      expect(repository.lastCompanyId, 'company-1');
      expect(repository.lastFilters, const TransactionFilters());
    });

    test('inoltra filtri AND al repository', () async {
      final repository = _TransactionRepositorySpy();
      final filters = TransactionFilters(
        fromDate: DateTime(2026, 1, 1),
        toDate: DateTime(2026, 1, 31),
        kind: TransactionKind.income,
        clientId: 'client-9',
        descriptionQuery: 'affitto',
      );
      await GetTransactions(
        repository,
      ).call(companyId: 'company-1', filters: filters);
      expect(repository.lastFilters, filters);
    });

    test(
      'rifiuta intervallo date invertito senza chiamare il repository',
      () async {
        final repository = _TransactionRepositorySpy();
        final result = await GetTransactions(repository).call(
          companyId: 'company-1',
          filters: TransactionFilters(
            fromDate: DateTime(2026, 3, 1),
            toDate: DateTime(2026, 1, 1),
          ),
        );
        expect(result.isError, isTrue);
        expect(repository.lastCompanyId, isNull);
      },
    );
  });

  group('CreateTransaction', () {
    test('normalizza note vuote a null', () async {
      final repository = _TransactionRepositorySpy();
      final amount = MoneyAmount.parse('10,00');
      await CreateTransaction(
        repository,
        const PassthroughCategoryRepository(),
      ).call(
        companyId: 'company-1',
        kind: TransactionKind.income,
        amount: amount,
        occurredOn: DateTime(2026, 7, 17),
        description: 'Vendita',
        notes: '   ',
      );

      expect(repository.lastNotes, isNull);
    });

    test('esegue il trim della descrizione', () async {
      final repository = _TransactionRepositorySpy();
      final amount = MoneyAmount.parse('10,00');
      await CreateTransaction(
        repository,
        const PassthroughCategoryRepository(),
      ).call(
        companyId: 'company-1',
        kind: TransactionKind.expense,
        amount: amount,
        occurredOn: DateTime(2026, 7, 17),
        description: '  Materiale ufficio  ',
      );

      expect(repository.lastDescription, 'Materiale ufficio');
    });

    test('inoltra MoneyAmount e kind senza alterarli', () async {
      final repository = _TransactionRepositorySpy();
      final amount = MoneyAmount.parse('1.234,56');
      await CreateTransaction(
        repository,
        const PassthroughCategoryRepository(),
      ).call(
        companyId: 'company-1',
        kind: TransactionKind.income,
        amount: amount,
        occurredOn: DateTime(2026, 7, 17),
        description: 'Incasso grande',
        notes: '  nota valida  ',
      );

      expect(repository.lastKind, TransactionKind.income);
      expect(repository.lastAmount, amount);
      expect(repository.lastAmount?.cents, 123456);
      expect(repository.lastNotes, 'nota valida');
      expect(repository.lastCompanyId, 'company-1');
    });

    test('normalizza clientId vuoto a null', () async {
      final repository = _TransactionRepositorySpy();
      final amount = MoneyAmount.parse('10,00');
      await CreateTransaction(
        repository,
        const PassthroughCategoryRepository(),
      ).call(
        companyId: 'company-1',
        clientId: '   ',
        kind: TransactionKind.income,
        amount: amount,
        occurredOn: DateTime(2026, 7, 17),
        description: 'Vendita',
      );

      expect(repository.lastClientId, isNull);
    });

    test('normalizza la data rimuovendo l\'orario', () async {
      final repository = _TransactionRepositorySpy();
      final amount = MoneyAmount.parse('10,00');
      await CreateTransaction(
        repository,
        const PassthroughCategoryRepository(),
      ).call(
        companyId: 'company-1',
        kind: TransactionKind.income,
        amount: amount,
        occurredOn: DateTime(2026, 7, 17, 23, 59, 59),
        description: 'Vendita',
      );

      expect(repository.lastOccurredOn, DateTime(2026, 7, 17));
    });

    test(
      'is_active non vincola il salvataggio: categoria attiva e compatibile consentita',
      () async {
        final repository = _TransactionRepositorySpy();
        final categories = StubCategoryRepository(
          category: TransactionCategory(
            id: 'cat-1',
            companyId: 'company-1',
            name: 'Software',
            kind: TransactionKind.expense,
            isActive: true,
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );
        final amount = MoneyAmount.parse('10,00');
        await CreateTransaction(repository, categories).call(
          companyId: 'company-1',
          categoryId: 'cat-1',
          kind: TransactionKind.expense,
          amount: amount,
          occurredOn: DateTime(2026, 7, 17),
          description: 'Licenza',
        );

        expect(repository.lastCategoryId, 'cat-1');
        expect(categories.lastGetCategoryId, 'cat-1');
      },
    );

    test(
      'is_active non vincola il salvataggio: archiviata dopo selezione ma company/kind validi consentita',
      () async {
        final repository = _TransactionRepositorySpy();
        final categories = StubCategoryRepository(
          category: TransactionCategory(
            id: 'cat-1',
            companyId: 'company-1',
            name: 'Software',
            kind: TransactionKind.expense,
            isActive: false,
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );
        final result = await CreateTransaction(repository, categories).call(
          companyId: 'company-1',
          categoryId: 'cat-1',
          kind: TransactionKind.expense,
          amount: MoneyAmount.parse('10,00'),
          occurredOn: DateTime(2026, 7, 17),
          description: 'Licenza',
        );

        expect(result.isSuccess, isTrue);
        expect(repository.lastCategoryId, 'cat-1');
      },
    );

    test('rifiuta categoria di altra azienda', () async {
      final repository = _TransactionRepositorySpy();
      final categories = StubCategoryRepository(
        category: TransactionCategory(
          id: 'cat-1',
          companyId: 'company-other',
          name: 'Software',
          kind: TransactionKind.expense,
          isActive: true,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final result = await CreateTransaction(repository, categories).call(
        companyId: 'company-1',
        categoryId: 'cat-1',
        kind: TransactionKind.expense,
        amount: MoneyAmount.parse('10,00'),
        occurredOn: DateTime(2026, 7, 17),
        description: 'Licenza',
      );

      expect(result.isError, isTrue);
      expect(repository.lastCategoryId, isNull);
    });

    test('rifiuta categoria di kind incompatibile', () async {
      final repository = _TransactionRepositorySpy();
      final categories = StubCategoryRepository(
        category: TransactionCategory(
          id: 'cat-1',
          companyId: 'company-1',
          name: 'Vendite',
          kind: TransactionKind.income,
          isActive: true,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final result = await CreateTransaction(repository, categories).call(
        companyId: 'company-1',
        categoryId: 'cat-1',
        kind: TransactionKind.expense,
        amount: MoneyAmount.parse('10,00'),
        occurredOn: DateTime(2026, 7, 17),
        description: 'Licenza',
      );

      expect(result.isError, isTrue);
      expect(repository.lastCategoryId, isNull);
    });

    test('rifiuta categoria inesistente', () async {
      final repository = _TransactionRepositorySpy();
      final categories = StubCategoryRepository();
      final result = await CreateTransaction(repository, categories).call(
        companyId: 'company-1',
        categoryId: 'missing',
        kind: TransactionKind.expense,
        amount: MoneyAmount.parse('10,00'),
        occurredOn: DateTime(2026, 7, 17),
        description: 'Licenza',
      );

      expect(result.isError, isTrue);
      expect(repository.lastCategoryId, isNull);
    });
  });

  group('UpdateTransaction', () {
    test('inoltra companyId, transactionId e normalizza opzionali', () async {
      final repository = _TransactionRepositorySpy();
      final amount = MoneyAmount.parse('50,00');
      await UpdateTransaction(
        repository,
        const PassthroughCategoryRepository(),
      ).call(
        companyId: 'company-1',
        transactionId: 'txn-9',
        kind: TransactionKind.expense,
        amount: amount,
        occurredOn: DateTime(2026, 7, 18),
        description: '  Aggiornamento  ',
        notes: '',
      );

      expect(repository.lastCompanyId, 'company-1');
      expect(repository.lastTransactionId, 'txn-9');
      expect(repository.lastDescription, 'Aggiornamento');
      expect(repository.lastNotes, isNull);
      expect(repository.lastKind, TransactionKind.expense);
      expect(repository.lastAmount, amount);
    });

    test(
      'is_active non vincola il salvataggio: mantenimento categoria archiviata corrente consentito',
      () async {
        final repository = _TransactionRepositorySpy();
        final categories = StubCategoryRepository(
          category: TransactionCategory(
            id: 'cat-1',
            companyId: 'company-1',
            name: 'Software',
            kind: TransactionKind.expense,
            isActive: false,
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await UpdateTransaction(repository, categories).call(
          companyId: 'company-1',
          transactionId: 'txn-9',
          categoryId: 'cat-1',
          kind: TransactionKind.expense,
          amount: MoneyAmount.parse('10,00'),
          occurredOn: DateTime(2026, 7, 18),
          description: 'Licenza',
        );

        expect(repository.lastCategoryId, 'cat-1');
      },
    );

    test(
      'is_active non vincola il salvataggio: archiviata dopo selezione ma company/kind validi consentita',
      () async {
        final repository = _TransactionRepositorySpy();
        final categories = StubCategoryRepository(
          category: TransactionCategory(
            id: 'cat-2',
            companyId: 'company-1',
            name: 'Hardware',
            kind: TransactionKind.expense,
            isActive: false,
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );
        final result = await UpdateTransaction(repository, categories).call(
          companyId: 'company-1',
          transactionId: 'txn-9',
          categoryId: 'cat-2',
          kind: TransactionKind.expense,
          amount: MoneyAmount.parse('10,00'),
          occurredOn: DateTime(2026, 7, 18),
          description: 'Licenza',
        );

        expect(result.isSuccess, isTrue);
        expect(repository.lastCategoryId, 'cat-2');
      },
    );

    test('imposta categoryId null per rimozione', () async {
      final repository = _TransactionRepositorySpy();
      await UpdateTransaction(
        repository,
        const PassthroughCategoryRepository(),
      ).call(
        companyId: 'company-1',
        transactionId: 'txn-9',
        categoryId: null,
        kind: TransactionKind.expense,
        amount: MoneyAmount.parse('10,00'),
        occurredOn: DateTime(2026, 7, 18),
        description: 'Licenza',
      );

      expect(repository.lastCategoryId, isNull);
    });

    test('rifiuta categoria di altra azienda', () async {
      final repository = _TransactionRepositorySpy();
      final categories = StubCategoryRepository(
        category: TransactionCategory(
          id: 'cat-1',
          companyId: 'company-other',
          name: 'Software',
          kind: TransactionKind.expense,
          isActive: true,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final result = await UpdateTransaction(repository, categories).call(
        companyId: 'company-1',
        transactionId: 'txn-9',
        categoryId: 'cat-1',
        kind: TransactionKind.expense,
        amount: MoneyAmount.parse('10,00'),
        occurredOn: DateTime(2026, 7, 18),
        description: 'Licenza',
      );

      expect(result.isError, isTrue);
      expect(repository.lastCategoryId, isNull);
    });

    test('rifiuta categoria di kind incompatibile', () async {
      final repository = _TransactionRepositorySpy();
      final categories = StubCategoryRepository(
        category: TransactionCategory(
          id: 'cat-1',
          companyId: 'company-1',
          name: 'Vendite',
          kind: TransactionKind.income,
          isActive: true,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final result = await UpdateTransaction(repository, categories).call(
        companyId: 'company-1',
        transactionId: 'txn-9',
        categoryId: 'cat-1',
        kind: TransactionKind.expense,
        amount: MoneyAmount.parse('10,00'),
        occurredOn: DateTime(2026, 7, 18),
        description: 'Licenza',
      );

      expect(result.isError, isTrue);
      expect(repository.lastCategoryId, isNull);
    });
  });
}
