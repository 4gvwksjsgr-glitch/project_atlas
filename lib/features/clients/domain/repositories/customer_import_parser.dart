import 'dart:typed_data';

import '../entities/customer_import_source.dart';

/// Domain port implemented by the data layer with CSV/XLSX libraries.
abstract interface class CustomerImportFileParser {
  Future<CustomerImportSource> parseBytes({
    required String fileName,
    required Uint8List bytes,
    String? preferredSheet,
  });
}
