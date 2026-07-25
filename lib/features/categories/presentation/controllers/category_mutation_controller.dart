import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../transactions/domain/entities/cash_transaction.dart';
import '../providers/category_providers.dart';

enum CategoryActionStatus { idle, loading, success, error }

class CategoryMutationState {
  const CategoryMutationState({
    this.actionStatus = CategoryActionStatus.idle,
    this.errorMessage,
  });

  final CategoryActionStatus actionStatus;
  final String? errorMessage;

  bool get isLoading => actionStatus == CategoryActionStatus.loading;

  CategoryMutationState copyWith({
    CategoryActionStatus? actionStatus,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CategoryMutationState(
      actionStatus: actionStatus ?? this.actionStatus,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class CategoryMutationController
    extends AutoDisposeFamilyNotifier<CategoryMutationState, String> {
  @override
  CategoryMutationState build(String companyId) =>
      const CategoryMutationState();

  Future<bool> create({
    required String name,
    required TransactionKind kind,
  }) async {
    if (state.isLoading) {
      return false;
    }
    state = state.copyWith(
      actionStatus: CategoryActionStatus.loading,
      clearError: true,
    );

    final result = await ref
        .read(createCategoryUseCaseProvider)
        .call(companyId: arg, name: name, kind: kind);

    return result.when(
      success: (_) {
        ref.invalidate(categoriesProvider(arg));
        state = state.copyWith(actionStatus: CategoryActionStatus.success);
        return true;
      },
      error: (failure) {
        state = state.copyWith(
          actionStatus: CategoryActionStatus.error,
          errorMessage: failure.message,
        );
        return false;
      },
    );
  }

  Future<bool> rename({
    required String categoryId,
    required String name,
  }) async {
    if (state.isLoading) {
      return false;
    }
    state = state.copyWith(
      actionStatus: CategoryActionStatus.loading,
      clearError: true,
    );

    final result = await ref
        .read(renameCategoryUseCaseProvider)
        .call(companyId: arg, categoryId: categoryId, name: name);

    return result.when(
      success: (_) {
        ref.invalidate(categoriesProvider(arg));
        state = state.copyWith(actionStatus: CategoryActionStatus.success);
        return true;
      },
      error: (failure) {
        state = state.copyWith(
          actionStatus: CategoryActionStatus.error,
          errorMessage: failure.message,
        );
        return false;
      },
    );
  }

  Future<bool> setActive({
    required String categoryId,
    required bool isActive,
  }) async {
    if (state.isLoading) {
      return false;
    }
    state = state.copyWith(
      actionStatus: CategoryActionStatus.loading,
      clearError: true,
    );

    final result = await ref
        .read(setCategoryActiveUseCaseProvider)
        .call(companyId: arg, categoryId: categoryId, isActive: isActive);

    return result.when(
      success: (_) {
        ref.invalidate(categoriesProvider(arg));
        state = state.copyWith(actionStatus: CategoryActionStatus.success);
        return true;
      },
      error: (failure) {
        state = state.copyWith(
          actionStatus: CategoryActionStatus.error,
          errorMessage: failure.message,
        );
        return false;
      },
    );
  }

  void clearFeedback() {
    state = const CategoryMutationState();
  }
}

final categoryMutationControllerProvider = NotifierProvider.autoDispose
    .family<CategoryMutationController, CategoryMutationState, String>(
      CategoryMutationController.new,
    );
