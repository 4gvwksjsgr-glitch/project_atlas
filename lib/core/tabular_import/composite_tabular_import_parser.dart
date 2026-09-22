import 'dart:typed_data';

import 'csv_tabular_import_parser.dart';
import 'tabular_import_file_parser.dart';
import 'tabular_import_source.dart';
import 'xlsx_tabular_import_parser.dart';

/// Instrada sull'adapter corretto in base all'estensione del file.
class CompositeTabularImportParser implements TabularImportFileParser {
  const CompositeTabularImportParser({
    this.csvParser = const CsvTabularImportParser(),
    this.xlsxParser = const XlsxTabularImportParser(),
  });

  final CsvTabularImportParser csvParser;
  final XlsxTabularImportParser xlsxParser;

  @override
  Future<TabularImportSource> parseBytes({
    required String fileName,
    required Uint8List bytes,
    String? preferredSheet,
  }) async {
    if (bytes.lengthInBytes > TabularImportSource.maxFileBytes) {
      throw const FormatException('fileTooLarge');
    }

    final lower = fileName.trim().toLowerCase();
    if (lower.endsWith('.csv')) {
      return csvParser.parse(fileName: fileName, bytes: bytes);
    }
    if (lower.endsWith('.xlsx')) {
      return xlsxParser.parse(
        fileName: fileName,
        bytes: bytes,
        preferredSheet: preferredSheet,
      );
    }
    throw const FormatException('unsupportedExtension');
  }
}
