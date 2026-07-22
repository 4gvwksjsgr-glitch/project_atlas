import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';

import '../../domain/entities/customer_import_sheet.dart';
import '../../domain/entities/customer_import_source.dart';
import '../../domain/repositories/customer_import_parser.dart';
import 'xlsx_customer_import_parser.dart';

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
  }) async {
    if (bytes.lengthInBytes > CustomerImportSource.maxFileBytes) {
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

class CsvCustomerImportParser {
  const CsvCustomerImportParser();

  CustomerImportSource parse({
    required String fileName,
    required Uint8List bytes,
  }) {
    final text = _decodeUtf8Strict(bytes);
    final delimiter = _detectDelimiter(text);

    final rows = Csv(
      fieldDelimiter: delimiter,
      autoDetect: false,
      dynamicTyping: false,
      skipEmptyLines: false,
    ).decode(_normalizeNewlines(text));

    if (rows.isEmpty) {
      throw const FormatException('missingHeaders');
    }

    final headers = rows.first
        .map((cell) => cell?.toString() ?? '')
        .map((h) => h.trim())
        .toList();
    _validateHeaders(headers);

    final dataRows = <List<String?>>[];
    final sourceRows = <int>[];
    for (var i = 1; i < rows.length; i++) {
      final raw = rows[i];
      final cells = List<String?>.generate(headers.length, (index) {
        if (index >= raw.length) {
          return null;
        }
        final value = raw[index]?.toString();
        if (value == null) {
          return null;
        }
        final trimmed = value.trim();
        return trimmed.isEmpty ? null : trimmed;
      });
      dataRows.add(cells);
      sourceRows.add(i + 1);
    }

    if (dataRows.isEmpty) {
      throw const FormatException('noDataRows');
    }

    final table = CustomerImportTable(
      headers: headers,
      dataRows: dataRows,
      sourceRows: sourceRows,
    );

    return CustomerImportSource(
      fileName: fileName,
      byteLength: bytes.lengthInBytes,
      kind: CustomerImportSourceKind.csv,
      sheets: [CustomerImportSheet(name: 'CSV', rowCount: table.rowCount)],
      selectedSheet: 'CSV',
      selectedTable: table,
    );
  }

  static String _decodeUtf8Strict(Uint8List bytes) {
    try {
      // strip BOM if present
      final hasBom =
          bytes.length >= 3 &&
          bytes[0] == 0xEF &&
          bytes[1] == 0xBB &&
          bytes[2] == 0xBF;
      final slice = hasBom ? bytes.sublist(3) : bytes;
      return utf8.decode(slice, allowMalformed: false);
    } on FormatException {
      throw const FormatException('undecodableEncoding');
    }
  }

  static String _normalizeNewlines(String text) =>
      text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  /// Returns a delimiter, or throws [FormatException] with
  /// `ambiguousDelimiter` / `delimiterUndetectable`.
  ///
  /// Ambiguous ties (same unquoted count > 0 for two separators) are never
  /// resolved silently: the caller must provide an unambiguous file.
  static String _detectDelimiter(String text) {
    final firstLine = _normalizeNewlines(text)
        .split('\n')
        .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) {
      throw const FormatException('delimiterUndetectable');
    }

    final candidates = <String, int>{
      ',': _countUnquoted(firstLine, ','),
      ';': _countUnquoted(firstLine, ';'),
      '\t': _countUnquoted(firstLine, '\t'),
    };

    final positive = candidates.entries.where((e) => e.value > 0).toList();
    if (positive.isEmpty) {
      // Single-column header: no field separators at all.
      if (!firstLine.contains(',') &&
          !firstLine.contains(';') &&
          !firstLine.contains('\t')) {
        return ',';
      }
      throw const FormatException('delimiterUndetectable');
    }

    final maxCount = positive
        .map((e) => e.value)
        .reduce((a, b) => a > b ? a : b);
    final winners = positive.where((e) => e.value == maxCount).toList();
    if (winners.length > 1) {
      throw const FormatException('ambiguousDelimiter');
    }
    return winners.single.key;
  }

  static int _countUnquoted(String line, String delimiter) {
    var count = 0;
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
        continue;
      }
      if (!inQuotes && ch == delimiter) {
        count += 1;
      }
    }
    return count;
  }

  static void _validateHeaders(List<String> headers) {
    if (headers.isEmpty) {
      throw const FormatException('missingHeaders');
    }
    if (headers.any((h) => h.trim().isEmpty)) {
      throw const FormatException('emptyHeader');
    }
    final normalized = headers
        .map((h) => h.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' '))
        .toList();
    if (normalized.toSet().length != normalized.length) {
      throw const FormatException('duplicateHeaders');
    }
  }
}
