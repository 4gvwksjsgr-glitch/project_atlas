import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../data/datasource/category_remote_datasource.dart';
import '../../data/repositories/category_repository_impl.dart';
import '../../domain/entities/transaction_category.dart';
import '../../domain/repositories/category_repository.dart';
import '../../domain/usecases/category_usecases.dart';

final categoryRemoteDataSourceProvider = Provider<CategoryRemoteDataSource>((
  ref,
) {
  return CategoryRemoteDataSource(ref.watch(supabaseClientProvider));
});

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return CategoryRepositoryImpl(ref.watch(categoryRemoteDataSourceProvider));
});

final getCategoriesUseCaseProvider = Provider<GetCategories>((ref) {
  return GetCategories(ref.watch(categoryRepositoryProvider));
});

final createCategoryUseCaseProvider = Provider<CreateCategory>((ref) {
  return CreateCategory(ref.watch(categoryRepositoryProvider));
});

final renameCategoryUseCaseProvider = Provider<RenameCategory>((ref) {
  return RenameCategory(ref.watch(categoryRepositoryProvider));
});

final setCategoryActiveUseCaseProvider = Provider<SetCategoryActive>((ref) {
  return SetCategoryActive(ref.watch(categoryRepositoryProvider));
});

/// Lista categorie keyed per azienda attiva.
final categoriesProvider = FutureProvider.autoDispose
    .family<List<TransactionCategory>, String>((ref, companyId) async {
      final result = await ref
          .read(getCategoriesUseCaseProvider)
          .call(companyId: companyId);

      return result.when(
        success: (categories) => categories,
        error: (failure) => throw StateError(failure.message),
      );
    });
