import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/transactions/domain/entities/cash_transaction.dart';
import 'package:project_atlas/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:project_atlas/features/transactions/domain/usecases/create_transaction.dart';
import 'package:project_atlas/features/transactions/domain/usecases/get_transactions.dart';
import 'package:project_atlas/features/transactions/domain/usecases/update_transaction.dart';
import 'package:project_atlas/features/transactions/domain/value_objects/money_amount.dart';

class _TransactionRepositorySpy implements TransactionRepository {
  String? lastCompanyId;
  String? lastTransactionId;
  String? lastClientId;
  TransactionKind? lastKind;
  MoneyAmount? lastAmount;
  DateTime? lastOccurredOn;
  String? lastDescription;
  String? lastNotes;

  @override
  Future<Result<List<CashTransaction>>> getTransactions({
    required String companyId,
  }) async {
    lastCompanyId = companyId;
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
    lastCompanyId = companyId;
    lastClientId = clientId;
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
    lastCompanyId = companyId;
    lastTransactionId = transactionId;
    lastClientId = clientId;
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
    });
  });

  group('CreateTransaction', () {
    test('normalizza note vuote a null', () async {
      final repository = _TransactionRepositorySpy();
      final amount = MoneyAmount.parse('10,00');
      await CreateTransaction(repository).call(
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
      await CreateTransaction(repository).call(
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
      await CreateTransaction(repository).call(
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
      await CreateTransaction(repository).call(
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
      await CreateTransaction(repository).call(
        companyId: 'company-1',
        kind: TransactionKind.income,
        amount: amount,
        occurredOn: DateTime(2026, 7, 17, 23, 59, 59),
        description: 'Vendita',
      );

      expect(repository.lastOccurredOn, DateTime(2026, 7, 17));
    });
  });

  group('UpdateTransaction', () {
    test('inoltra companyId, transactionId e normalizza opzionali', () async {
      final repository = _TransactionRepositorySpy();
      final amount = MoneyAmount.parse('50,00');
      await UpdateTransaction(repository).call(
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
  });
}
