import 'dart:typed_data';

import '../../../../core/tabular_import/xlsx_tabular_import_parser.dart';
import '../../domain/entities/customer_import_source.dart';

/// Adapter sottile su [XlsxTabularImportParser].
class XlsxCustomerImportParser {
  const XlsxCustomerImportParser({
    this.delegate = const XlsxTabularImportParser(),
  });

  final XlsxTabularImportParser delegate;

  CustomerImportSource parse({
    required String fileName,
    required Uint8List bytes,
    String? preferredSheet,
  }) {
    return delegate.parse(
      fileName: fileName,
      bytes: bytes,
      preferredSheet: preferredSheet,
    );
  }
}
