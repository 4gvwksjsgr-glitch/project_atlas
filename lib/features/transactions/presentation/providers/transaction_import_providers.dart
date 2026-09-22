import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/tabular_import/composite_tabular_import_parser.dart';
import '../../../../core/tabular_import/tabular_import_file_parser.dart';
import '../../data/repositories/transaction_import_repository_impl.dart';
import '../../domain/entities/cash_transaction.dart';
import '../../domain/repositories/transaction_import_repository.dart';
import '../../domain/usecases/import_transactions.dart';
import '../../domain/value_objects/transaction_filters.dart';
import 'transaction_providers.dart';

final transactionImportFileParserProvider = Provider<TabularImportFileParser>((
  ref,
) {
  return const CompositeTabularImportParser();
});

final transactionImportRepositoryProvider =
    Provider<TransactionImportRepository>((ref) {
      return TransactionImportRepositoryImpl(
        ref.watch(transactionRemoteDataSourceProvider),
      );
    });

final importTransactionsUseCaseProvider = Provider<ImportTransactions>((ref) {
  return ImportTransactions(ref.watch(transactionImportRepositoryProvider));
});

/// Movimenti già presenti in azienda, letti senza i filtri della lista: il
/// confronto duplicati non deve dipendere da cosa l'utente sta filtrando.
final transactionImportExistingTransactionsProvider =
    FutureProvider.autoDispose.family<List<CashTransaction>, String>((
      ref,
      companyId,
    ) async {
      final result = await ref.read(getTransactionsUseCaseProvider).call(
        companyId: companyId,
        filters: const TransactionFilters(),
      );

      return result.when(
        success: (transactions) => transactions,
        error: (failure) => throw StateError(failure.message),
      );
    });
