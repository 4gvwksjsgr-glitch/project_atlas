import '../../../../core/errors/failures.dart';
import '../../../../core/errors/transaction_error_mapper.dart';
import '../../../../core/tabular_import/tabular_import_source.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/transaction_import_payload_row.dart';
import '../../domain/entities/transaction_import_result.dart';
import '../../domain/repositories/transaction_import_repository.dart';
import '../datasource/transaction_remote_datasource.dart';
import '../models/transaction_import_result_model.dart';

class TransactionImportRepositoryImpl implements TransactionImportRepository {
  const TransactionImportRepositoryImpl(this._remoteDataSource);

  static const Set<String> _supportedFormats = {'csv', 'xlsx'};

  final TransactionRemoteDataSource _remoteDataSource;

  @override
  Future<Result<TransactionImportResult>> importTransactions({
    required String companyId,
    required String sourceFileName,
    required String sourceFileSha256,
    required String sourceFormat,
    required List<TransactionImportPayloadRow> rows,
  }) async {
    if (companyId.isEmpty) {
      return const Error(ValidationFailure('Azienda non valida.'));
    }
    if (!_supportedFormats.contains(sourceFormat)) {
      return const Error(
        ValidationFailure('Formato del file di origine non valido.'),
      );
    }
    if (sourceFileSha256.length != 64) {
      return const Error(
        ValidationFailure('Impronta del file di origine non valida.'),
      );
    }
    if (rows.isEmpty || rows.length > TabularImportSource.maxDataRows) {
      return const Error(
        ValidationFailure('Numero di righe da importare non valido.'),
      );
    }

    try {
      final response = await _remoteDataSource.importTransactions(
        companyId: companyId,
        sourceFileName: sourceFileName,
        sourceFileSha256: sourceFileSha256,
        sourceFormat: sourceFormat,
        rows: rows.map((row) => row.toJson()).toList(growable: false),
      );
      return Success(
        TransactionImportResultModel.fromJson(response).toEntity(),
      );
    } on FormatException catch (error) {
      return Error(ValidationFailure(error.message));
    } on Object catch (error) {
      return Error(
        TransactionErrorMapper.mapException(
          error,
          TransactionOperation.importTransactions,
        ),
      );
    }
  }
}
