import '../../../../core/errors/category_error_mapper.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../../../transactions/domain/entities/cash_transaction.dart';
import '../../domain/entities/transaction_category.dart';
import '../../domain/repositories/category_repository.dart';
import '../datasource/category_remote_datasource.dart';

class CategoryRepositoryImpl implements CategoryRepository {
  const CategoryRepositoryImpl(this._remoteDataSource);

  final CategoryRemoteDataSource _remoteDataSource;

  @override
  Future<Result<List<TransactionCategory>>> getCategories({
    required String companyId,
  }) async {
    if (companyId.isEmpty) {
      return const Error(ValidationFailure('Azienda non valida.'));
    }

    try {
      final categories = await _remoteDataSource.getCategories(
        companyId: companyId,
      );
      return Success(categories.map((model) => model.toEntity()).toList());
    } on Object catch (error) {
      return Error(
        CategoryErrorMapper.mapException(
          error,
          CategoryOperation.getCategories,
        ),
      );
    }
  }

  @override
  Future<Result<TransactionCategory>> createCategory({
    required String companyId,
    required String name,
    required TransactionKind kind,
  }) async {
    if (companyId.isEmpty) {
      return const Error(ValidationFailure('Azienda non valida.'));
    }

    try {
      final category = await _remoteDataSource.createCategory(
        companyId: companyId,
        name: name,
        kind: kind,
      );
      return Success(category.toEntity());
    } on Object catch (error) {
      return Error(
        CategoryErrorMapper.mapException(
          error,
          CategoryOperation.createCategory,
        ),
      );
    }
  }

  @override
  Future<Result<TransactionCategory>> renameCategory({
    required String companyId,
    required String categoryId,
    required String name,
  }) async {
    if (companyId.isEmpty) {
      return const Error(ValidationFailure('Azienda non valida.'));
    }
    if (categoryId.isEmpty) {
      return const Error(ValidationFailure('Categoria non valida.'));
    }

    try {
      final category = await _remoteDataSource.renameCategory(
        companyId: companyId,
        categoryId: categoryId,
        name: name,
      );
      return Success(category.toEntity());
    } on Object catch (error) {
      return Error(
        CategoryErrorMapper.mapException(
          error,
          CategoryOperation.renameCategory,
        ),
      );
    }
  }

  @override
  Future<Result<TransactionCategory>> setCategoryActive({
    required String companyId,
    required String categoryId,
    required bool isActive,
  }) async {
    if (companyId.isEmpty) {
      return const Error(ValidationFailure('Azienda non valida.'));
    }
    if (categoryId.isEmpty) {
      return const Error(ValidationFailure('Categoria non valida.'));
    }

    try {
      final category = await _remoteDataSource.setCategoryActive(
        companyId: companyId,
        categoryId: categoryId,
        isActive: isActive,
      );
      return Success(category.toEntity());
    } on Object catch (error) {
      return Error(
        CategoryErrorMapper.mapException(
          error,
          CategoryOperation.setCategoryActive,
        ),
      );
    }
  }
}
