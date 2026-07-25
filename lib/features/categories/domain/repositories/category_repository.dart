import '../../../../core/utils/result.dart';
import '../../../transactions/domain/entities/cash_transaction.dart';
import '../entities/transaction_category.dart';

abstract class CategoryRepository {
  Future<Result<List<TransactionCategory>>> getCategories({
    required String companyId,
  });

  Future<Result<TransactionCategory>> createCategory({
    required String companyId,
    required String name,
    required TransactionKind kind,
  });

  Future<Result<TransactionCategory>> renameCategory({
    required String companyId,
    required String categoryId,
    required String name,
  });

  Future<Result<TransactionCategory>> setCategoryActive({
    required String companyId,
    required String categoryId,
    required bool isActive,
  });
}
