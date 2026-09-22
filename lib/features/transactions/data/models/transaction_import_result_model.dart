import '../../domain/entities/transaction_import_result.dart';

class TransactionImportResultModel {
  const TransactionImportResultModel({
    required this.batchId,
    required this.importedCount,
    required this.skippedInvalidCount,
    required this.skippedDuplicateCount,
    required this.transactionIds,
  });

  final String batchId;
  final int importedCount;
  final int skippedInvalidCount;
  final int skippedDuplicateCount;
  final List<String> transactionIds;

  factory TransactionImportResultModel.fromJson(Map<String, dynamic> json) {
    final idsRaw = json['transaction_ids'];
    final ids = <String>[];
    if (idsRaw is List) {
      for (final item in idsRaw) {
        if (item == null) {
          throw const FormatException('transaction_ids non valido');
        }
        final text = item.toString().trim();
        if (text.isEmpty) {
          throw const FormatException('transaction_ids non valido');
        }
        ids.add(text);
      }
    } else if (idsRaw != null) {
      throw const FormatException('transaction_ids non valido');
    }

    final batchId = (json['batch_id']?.toString() ?? '').trim();
    if (batchId.isEmpty) {
      throw const FormatException('batch_id non valido');
    }

    return TransactionImportResultModel(
      batchId: batchId,
      importedCount: _requireNonNegativeInt(
        json['imported_count'],
        'imported_count',
      ),
      skippedInvalidCount: _requireNonNegativeInt(
        json['skipped_invalid_count'],
        'skipped_invalid_count',
      ),
      skippedDuplicateCount: _requireNonNegativeInt(
        json['skipped_duplicate_count'],
        'skipped_duplicate_count',
      ),
      transactionIds: ids,
    );
  }

  TransactionImportResult toEntity() => TransactionImportResult(
    batchId: batchId,
    importedCount: importedCount,
    skippedInvalidCount: skippedInvalidCount,
    skippedDuplicateCount: skippedDuplicateCount,
    transactionIds: transactionIds,
  );

  static int _requireNonNegativeInt(Object? raw, String field) {
    if (raw is num) {
      final value = raw.toInt();
      if (value < 0) {
        throw FormatException('$field non valido');
      }
      return value;
    }
    throw FormatException('$field non valido');
  }
}
