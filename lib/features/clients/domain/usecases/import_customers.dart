import '../../../../core/utils/result.dart';
import '../entities/customer_import_payload_row.dart';
import '../entities/customer_import_result.dart';
import '../repositories/customer_import_repository.dart';

class ImportCustomers {
  const ImportCustomers(this._repository);

  final CustomerImportRepository _repository;

  Future<Result<CustomerImportResult>> call({
    required String companyId,
    required List<CustomerImportPayloadRow> rows,
  }) {
    return _repository.importCustomers(companyId: companyId, rows: rows);
  }
}
