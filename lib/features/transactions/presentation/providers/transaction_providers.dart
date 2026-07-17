import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../data/datasource/transaction_remote_datasource.dart';
import '../../data/repositories/transaction_repository_impl.dart';
import '../../domain/entities/cash_transaction.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../../domain/usecases/create_transaction.dart';
import '../../domain/usecases/get_transactions.dart';
import '../../domain/usecases/update_transaction.dart';

final transactionRemoteDataSourceProvider =
    Provider<TransactionRemoteDataSource>((ref) {
      return TransactionRemoteDataSource(ref.watch(supabaseClientProvider));
    });

final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  return TransactionRepositoryImpl(
    ref.watch(transactionRemoteDataSourceProvider),
  );
});

final getTransactionsUseCaseProvider = Provider<GetTransactions>((ref) {
  return GetTransactions(ref.watch(transactionRepositoryProvider));
});

final createTransactionUseCaseProvider = Provider<CreateTransaction>((ref) {
  return CreateTransaction(ref.watch(transactionRepositoryProvider));
});

final updateTransactionUseCaseProvider = Provider<UpdateTransaction>((ref) {
  return UpdateTransaction(ref.watch(transactionRepositoryProvider));
});

/// Lista movimenti keyed per azienda attiva: al cambio companyId parte una nuova query.
final transactionsProvider = FutureProvider.autoDispose
    .family<List<CashTransaction>, String>((ref, companyId) async {
      final result = await ref
          .read(getTransactionsUseCaseProvider)
          .call(companyId: companyId);

      return result.when(
        success: (transactions) => transactions,
        error: (failure) => throw StateError(failure.message),
      );
    });
