import '../../../../core/utils/result.dart';
import '../entities/customer_import_payload_row.dart';
import '../entities/customer_import_result.dart';

/// Port for the persistence operation of a validated customer import.
abstract interface class CustomerImportRepository {
  Future<Result<CustomerImportResult>> importCustomers({
    required String companyId,
    required List<CustomerImportPayloadRow> rows,
  });
}
