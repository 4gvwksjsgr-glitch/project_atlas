import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/core/errors/failures.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/categories/domain/entities/transaction_category.dart';
import 'package:project_atlas/features/categories/domain/repositories/category_repository.dart';
import 'package:project_atlas/features/categories/domain/usecases/category_usecases.dart';
import 'package:project_atlas/features/categories/domain/value_objects/category_name.dart';
import 'package:project_atlas/features/transactions/domain/entities/cash_transaction.dart';

class _Repo implements CategoryRepository {
  String? lastName;
  TransactionKind? lastKind;
  bool? lastActive;
  int createCount = 0;
  int renameCount = 0;
  int setActiveCount = 0;

  @override
  Future<Result<List<TransactionCategory>>> getCategories({
    required String companyId,
  }) async => const Success([]);

  @override
  Future<Result<TransactionCategory>> createCategory({
    required String companyId,
    required String name,
    required TransactionKind kind,
  }) async {
    createCount++;
    lastName = name;
    lastKind = kind;
    return Success(
      TransactionCategory(
        id: 'cat-1',
        companyId: companyId,
        name: name,
        kind: kind,
        isActive: true,
        createdAt: DateTime.utc(2026, 7, 24),
        updatedAt: DateTime.utc(2026, 7, 24),
      ),
    );
  }

  @override
  Future<Result<TransactionCategory>> renameCategory({
    required String companyId,
    required String categoryId,
    required String name,
  }) async {
    renameCount++;
    lastName = name;
    return Success(
      TransactionCategory(
        id: categoryId,
        companyId: companyId,
        name: name,
        kind: TransactionKind.expense,
        isActive: true,
        createdAt: DateTime.utc(2026, 7, 24),
        updatedAt: DateTime.utc(2026, 7, 24),
      ),
    );
  }

  @override
  Future<Result<TransactionCategory>> setCategoryActive({
    required String companyId,
    required String categoryId,
    required bool isActive,
  }) async {
    setActiveCount++;
    lastActive = isActive;
    return Success(
      TransactionCategory(
        id: categoryId,
        companyId: companyId,
        name: 'Software',
        kind: TransactionKind.expense,
        isActive: isActive,
        createdAt: DateTime.utc(2026, 7, 24),
        updatedAt: DateTime.utc(2026, 7, 24),
      ),
    );
  }
}

void main() {
  group('CategoryName', () {
    test('normalize esegue trim', () {
      expect(CategoryName.normalize('  Software  '), 'Software');
    });

    test('validationError per vuoto e troppo lungo', () {
      expect(CategoryName.validationError(''), isNotNull);
      expect(CategoryName.validationError('a' * 81), isNotNull);
      expect(CategoryName.validationError('Software'), isNull);
    });
  });

  group('Category use cases', () {
    test('CreateCategory trimma e rifiuta nome vuoto senza repo', () async {
      final repo = _Repo();
      final result = await CreateCategory(
        repo,
      ).call(companyId: 'c1', name: '   ', kind: TransactionKind.expense);
      expect(result, isA<Error<TransactionCategory>>());
      expect(repo.createCount, 0);
    });

    test('CreateCategory inoltra nome normalizzato', () async {
      final repo = _Repo();
      final result = await CreateCategory(repo).call(
        companyId: 'c1',
        name: '  Software  ',
        kind: TransactionKind.expense,
      );
      expect(result, isA<Success<TransactionCategory>>());
      expect(repo.lastName, 'Software');
      expect(repo.lastKind, TransactionKind.expense);
    });

    test('RenameCategory rifiuta oltre 80 caratteri', () async {
      final repo = _Repo();
      final result = await RenameCategory(
        repo,
      ).call(companyId: 'c1', categoryId: 'cat-1', name: 'x' * 81);
      expect(result, isA<Error<TransactionCategory>>());
      expect((result as Error).failure, isA<ValidationFailure>());
      expect(repo.renameCount, 0);
    });

    test('SetCategoryActive archivia e riattiva', () async {
      final repo = _Repo();
      final archive = await SetCategoryActive(
        repo,
      ).call(companyId: 'c1', categoryId: 'cat-1', isActive: false);
      expect(archive, isA<Success<TransactionCategory>>());
      expect(repo.lastActive, isFalse);

      final reactivate = await SetCategoryActive(
        repo,
      ).call(companyId: 'c1', categoryId: 'cat-1', isActive: true);
      expect(reactivate, isA<Success<TransactionCategory>>());
      expect(repo.lastActive, isTrue);
      expect(repo.setActiveCount, 2);
    });
  });
}
