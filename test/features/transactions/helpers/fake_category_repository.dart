import 'package:project_atlas/core/errors/failures.dart';
import 'package:project_atlas/core/utils/result.dart';
import 'package:project_atlas/features/categories/domain/entities/transaction_category.dart';
import 'package:project_atlas/features/categories/domain/repositories/category_repository.dart';
import 'package:project_atlas/features/transactions/domain/entities/cash_transaction.dart';

/// Fake categories repo for transaction tests that non passano categoryId.
class PassthroughCategoryRepository implements CategoryRepository {
  const PassthroughCategoryRepository();

  @override
  Future<Result<List<TransactionCategory>>> getCategories({
    required String companyId,
  }) async => const Success([]);

  @override
  Future<Result<TransactionCategory>> getCategory({
    required String companyId,
    required String categoryId,
  }) async => const Error(
    ValidationFailure(
      'La categoria selezionata non è valida per questo movimento.',
    ),
  );

  @override
  Future<Result<TransactionCategory>> createCategory({
    required String companyId,
    required String name,
    required TransactionKind kind,
  }) async => throw UnimplementedError();

  @override
  Future<Result<TransactionCategory>> renameCategory({
    required String companyId,
    required String categoryId,
    required String name,
  }) async => throw UnimplementedError();

  @override
  Future<Result<TransactionCategory>> setCategoryActive({
    required String companyId,
    required String categoryId,
    required bool isActive,
  }) async => throw UnimplementedError();
}

class StubCategoryRepository implements CategoryRepository {
  StubCategoryRepository({this.category});

  TransactionCategory? category;
  String? lastGetCategoryId;
  String? lastGetCompanyId;

  @override
  Future<Result<List<TransactionCategory>>> getCategories({
    required String companyId,
  }) async {
    if (category == null) {
      return const Success([]);
    }
    return Success([category!]);
  }

  @override
  Future<Result<TransactionCategory>> getCategory({
    required String companyId,
    required String categoryId,
  }) async {
    lastGetCompanyId = companyId;
    lastGetCategoryId = categoryId;
    final value = category;
    if (value == null ||
        value.id != categoryId ||
        value.companyId != companyId) {
      return const Error(
        ValidationFailure(
          'La categoria selezionata non è valida per questo movimento.',
        ),
      );
    }
    return Success(value);
  }

  @override
  Future<Result<TransactionCategory>> createCategory({
    required String companyId,
    required String name,
    required TransactionKind kind,
  }) async => throw UnimplementedError();

  @override
  Future<Result<TransactionCategory>> renameCategory({
    required String companyId,
    required String categoryId,
    required String name,
  }) async => throw UnimplementedError();

  @override
  Future<Result<TransactionCategory>> setCategoryActive({
    required String companyId,
    required String categoryId,
    required bool isActive,
  }) async => throw UnimplementedError();
}
