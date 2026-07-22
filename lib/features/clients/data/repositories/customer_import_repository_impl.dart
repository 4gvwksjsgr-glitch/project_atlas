import '../../../../core/errors/customer_error_mapper.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/customer_import_payload_row.dart';
import '../../domain/entities/customer_import_result.dart';
import '../../domain/repositories/customer_import_repository.dart';
import '../datasource/customer_remote_datasource.dart';
import '../models/customer_import_result_model.dart';

class CustomerImportRepositoryImpl implements CustomerImportRepository {
  const CustomerImportRepositoryImpl(this._remoteDataSource);

  final CustomerRemoteDataSource _remoteDataSource;

  @override
  Future<Result<CustomerImportResult>> importCustomers({
    required String companyId,
    required List<CustomerImportPayloadRow> rows,
  }) async {
    if (companyId.isEmpty) {
      return const Error(ValidationFailure('Azienda non valida.'));
    }
    if (rows.isEmpty || rows.length > 500) {
      return const Error(
        ValidationFailure('Numero di righe da importare non valido.'),
      );
    }

    try {
      final response = await _remoteDataSource.importCustomers(
        companyId: companyId,
        rows: rows.map((row) => row.toJson()).toList(growable: false),
      );
      final model = CustomerImportResultModel.fromJson(response);
      return Success(model.toEntity());
    } on FormatException catch (error) {
      return Error(ValidationFailure(error.message));
    } on Object catch (error) {
      return Error(
        CustomerErrorMapper.mapException(
          error,
          CustomerOperation.importCustomers,
        ),
      );
    }
  }
}
