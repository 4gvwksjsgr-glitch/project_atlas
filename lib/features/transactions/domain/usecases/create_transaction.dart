import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../../../categories/domain/entities/transaction_category.dart';
import '../../../categories/domain/repositories/category_repository.dart';
import '../entities/cash_transaction.dart';
import '../repositories/transaction_repository.dart';
import '../value_objects/calendar_date.dart';
import '../value_objects/money_amount.dart';

class CreateTransaction {
  const CreateTransaction(this._repository, this._categoryRepository);

  final TransactionRepository _repository;
  final CategoryRepository _categoryRepository;

  Future<Result<CashTransaction>> call({
    required String companyId,
    String? clientId,
    String? categoryId,
    required TransactionKind kind,
    required MoneyAmount amount,
    required DateTime occurredOn,
    required String description,
    String? notes,
  }) async {
    final normalizedCategoryId = _normalizeOptionalId(categoryId);
    if (normalizedCategoryId != null) {
      final categoryError = await _validateCategoryAssignment(
        companyId: companyId,
        categoryId: normalizedCategoryId,
        kind: kind,
      );
      if (categoryError != null) {
        return Error(ValidationFailure(categoryError));
      }
    }

    return _repository.createTransaction(
      companyId: companyId,
      clientId: _normalizeOptionalId(clientId),
      categoryId: normalizedCategoryId,
      kind: kind,
      amount: amount,
      occurredOn: CalendarDate.dateOnly(occurredOn),
      description: description.trim(),
      notes: _normalizeOptional(notes),
    );
  }

  static String? _normalizeOptional(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _normalizeOptionalId(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Controlla esistenza + tenant + kind.
  /// `is_active` è regola di selezione UI (picker), non vincolo di salvataggio.
  Future<String?> _validateCategoryAssignment({
    required String companyId,
    required String categoryId,
    required TransactionKind kind,
  }) async {
    final result = await _categoryRepository.getCategory(
      companyId: companyId,
      categoryId: categoryId,
    );
    switch (result) {
      case Error(:final failure):
        return failure.message;
      case Success(:final value):
        return _checkCategory(
          category: value,
          companyId: companyId,
          kind: kind,
        );
    }
  }

  static String? _checkCategory({
    required TransactionCategory category,
    required String companyId,
    required TransactionKind kind,
  }) {
    if (category.companyId != companyId) {
      return 'La categoria selezionata non è valida per questo movimento.';
    }
    if (category.kind != kind) {
      return 'La categoria selezionata non è valida per questo movimento.';
    }
    return null;
  }
}
