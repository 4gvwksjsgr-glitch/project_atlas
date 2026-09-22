import '../../../../core/utils/result.dart';
import '../entities/transaction_import_payload_row.dart';
import '../entities/transaction_import_result.dart';

/// Porta per la persistenza di un import movimenti già validato.
abstract interface class TransactionImportRepository {
  Future<Result<TransactionImportResult>> importTransactions({
    required String companyId,
    required String sourceFileName,
    required String sourceFileSha256,
    required String sourceFormat,
    required List<TransactionImportPayloadRow> rows,
  });
}
