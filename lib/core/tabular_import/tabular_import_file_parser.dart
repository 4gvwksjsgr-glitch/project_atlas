import 'dart:typed_data';

import 'tabular_import_source.dart';

/// Porta implementata dagli adapter CSV/XLSX del layer core.
abstract interface class TabularImportFileParser {
  Future<TabularImportSource> parseBytes({
    required String fileName,
    required Uint8List bytes,
    String? preferredSheet,
  });
}
