import '../../../../core/errors/failures.dart';
import '../../../../core/errors/transaction_error_mapper.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/cash_transaction.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../../domain/value_objects/money_amount.dart';
import '../../domain/value_objects/transaction_filters.dart';
import '../datasource/transaction_remote_datasource.dart';

class TransactionRepositoryImpl implements TransactionRepository {
  const TransactionRepositoryImpl(this._remoteDataSource);

  final TransactionRemoteDataSource _remoteDataSource;

  @override
  Future<Result<List<CashTransaction>>> getTransactions({
    required String companyId,
    TransactionFilters filters = const TransactionFilters(),
  }) async {
    if (companyId.isEmpty) {
      return const Error(ValidationFailure('Azienda non valida.'));
    }
    final validationError = filters.validationError;
    if (validationError != null) {
      return Error(ValidationFailure(validationError));
    }

    try {
      final rows = await _remoteDataSource.getTransactions(
        companyId: companyId,
        filters: filters,
      );
      return Success(rows.map((model) => model.toEntity()).toList());
    } on Object catch (error) {
      return Error(
        TransactionErrorMapper.mapException(
          error,
          TransactionOperation.getTransactions,
        ),
      );
    }
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
    if (companyId.isEmpty) {
      return const Error(ValidationFailure('Azienda non valida.'));
    }
    if (description.trim().isEmpty) {
      return const Error(ValidationFailure('La descrizione è obbligatoria.'));
    }

    try {
      final row = await _remoteDataSource.createTransaction(
        companyId: companyId,
        clientId: clientId,
        categoryId: categoryId,
        kind: kind,
        amount: amount,
        occurredOn: occurredOn,
        description: description,
        notes: notes,
      );
      return Success(row.toEntity());
    } on Object catch (error) {
      return Error(
        TransactionErrorMapper.mapException(
          error,
          TransactionOperation.createTransaction,
        ),
      );
    }
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
    if (companyId.isEmpty) {
      return const Error(ValidationFailure('Azienda non valida.'));
    }
    if (transactionId.isEmpty) {
      return const Error(ValidationFailure('Movimento non valido.'));
    }
    if (description.trim().isEmpty) {
      return const Error(ValidationFailure('La descrizione è obbligatoria.'));
    }

    try {
      final row = await _remoteDataSource.updateTransaction(
        companyId: companyId,
        transactionId: transactionId,
        clientId: clientId,
        categoryId: categoryId,
        kind: kind,
        amount: amount,
        occurredOn: occurredOn,
        description: description,
        notes: notes,
      );
      return Success(row.toEntity());
    } on Object catch (error) {
      return Error(
        TransactionErrorMapper.mapException(
          error,
          TransactionOperation.updateTransaction,
        ),
      );
    }
  }
}
