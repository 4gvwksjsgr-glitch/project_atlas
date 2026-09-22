import 'dart:typed_data';

import '../../../../core/tabular_import/composite_tabular_import_parser.dart';
import '../../../../core/tabular_import/csv_tabular_import_parser.dart';
import '../../domain/entities/customer_import_source.dart';
import '../../domain/repositories/customer_import_parser.dart';
import 'xlsx_customer_import_parser.dart';

/// Adapter sottile su [CompositeTabularImportParser].
class CompositeCustomerImportFileParser implements CustomerImportFileParser {
  const CompositeCustomerImportFileParser({
    this.csvParser = const CsvCustomerImportParser(),
    this.xlsxParser = const XlsxCustomerImportParser(),
  });

  final CsvCustomerImportParser csvParser;
  final XlsxCustomerImportParser xlsxParser;

  @override
  Future<CustomerImportSource> parseBytes({
    required String fileName,
    required Uint8List bytes,
    String? preferredSheet,
  }) {
    return CompositeTabularImportParser(
      csvParser: csvParser.delegate,
      xlsxParser: xlsxParser.delegate,
    ).parseBytes(
      fileName: fileName,
      bytes: bytes,
      preferredSheet: preferredSheet,
    );
  }
}

/// Adapter sottile su [CsvTabularImportParser].
class CsvCustomerImportParser {
  const CsvCustomerImportParser({
    this.delegate = const CsvTabularImportParser(),
  });

  final CsvTabularImportParser delegate;

  CustomerImportSource parse({
    required String fileName,
    required Uint8List bytes,
  }) {
    return delegate.parse(fileName: fileName, bytes: bytes);
  }
}
