import '../../domain/entities/customer_import_result.dart';

class CustomerImportResultModel {
  const CustomerImportResultModel({
    required this.insertedCount,
    required this.skippedDuplicateCount,
    required this.skippedSourceRows,
  });

  final int insertedCount;
  final int skippedDuplicateCount;
  final List<int> skippedSourceRows;

  factory CustomerImportResultModel.fromJson(Map<String, dynamic> json) {
    final skippedRaw = json['skipped_source_rows'];
    final skipped = <int>[];
    if (skippedRaw is List) {
      for (final item in skippedRaw) {
        if (item is int) {
          skipped.add(item);
        } else if (item is num) {
          skipped.add(item.toInt());
        } else {
          throw FormatException('skipped_source_rows non valido');
        }
      }
    } else if (skippedRaw != null) {
      throw FormatException('skipped_source_rows non valido');
    }

    return CustomerImportResultModel(
      insertedCount: _requireNonNegativeInt(
        json['inserted_count'],
        'inserted_count',
      ),
      skippedDuplicateCount: _requireNonNegativeInt(
        json['skipped_duplicate_count'],
        'skipped_duplicate_count',
      ),
      skippedSourceRows: skipped,
    );
  }

  CustomerImportResult toEntity() => CustomerImportResult(
    insertedCount: insertedCount,
    skippedDuplicateCount: skippedDuplicateCount,
    skippedSourceRows: skippedSourceRows,
  );

  static int _requireNonNegativeInt(Object? raw, String field) {
    if (raw is int) {
      if (raw < 0) {
        throw FormatException('$field non valido');
      }
      return raw;
    }
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
