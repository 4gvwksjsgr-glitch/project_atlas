import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../../../transactions/domain/entities/cash_transaction.dart';
import '../entities/transaction_category.dart';
import '../repositories/category_repository.dart';
import '../value_objects/category_name.dart';

class GetCategories {
  const GetCategories(this._repository);

  final CategoryRepository _repository;

  Future<Result<List<TransactionCategory>>> call({required String companyId}) {
    return _repository.getCategories(companyId: companyId);
  }
}

class CreateCategory {
  const CreateCategory(this._repository);

  final CategoryRepository _repository;

  Future<Result<TransactionCategory>> call({
    required String companyId,
    required String name,
    required TransactionKind kind,
  }) {
    final normalized = CategoryName.normalize(name);
    final error = CategoryName.validationError(normalized);
    if (error != null) {
      return Future.value(Error(ValidationFailure(error)));
    }
    return _repository.createCategory(
      companyId: companyId,
      name: normalized,
      kind: kind,
    );
  }
}

class RenameCategory {
  const RenameCategory(this._repository);

  final CategoryRepository _repository;

  Future<Result<TransactionCategory>> call({
    required String companyId,
    required String categoryId,
    required String name,
  }) {
    final normalized = CategoryName.normalize(name);
    final error = CategoryName.validationError(normalized);
    if (error != null) {
      return Future.value(Error(ValidationFailure(error)));
    }
    return _repository.renameCategory(
      companyId: companyId,
      categoryId: categoryId,
      name: normalized,
    );
  }
}

class SetCategoryActive {
  const SetCategoryActive(this._repository);

  final CategoryRepository _repository;

  Future<Result<TransactionCategory>> call({
    required String companyId,
    required String categoryId,
    required bool isActive,
  }) {
    return _repository.setCategoryActive(
      companyId: companyId,
      categoryId: categoryId,
      isActive: isActive,
    );
  }
}
