import '../../../../core/utils/result.dart';
import '../entities/transaction_import_payload_row.dart';
import '../entities/transaction_import_result.dart';
import '../repositories/transaction_import_repository.dart';

class ImportTransactions {
  const ImportTransactions(this._repository);

  final TransactionImportRepository _repository;

  Future<Result<TransactionImportResult>> call({
    required String companyId,
    required String sourceFileName,
    required String sourceFileSha256,
    required String sourceFormat,
    required List<TransactionImportPayloadRow> rows,
  }) {
    return _repository.importTransactions(
      companyId: companyId,
      sourceFileName: sourceFileName,
      sourceFileSha256: sourceFileSha256,
      sourceFormat: sourceFormat,
      rows: rows,
    );
  }
}
