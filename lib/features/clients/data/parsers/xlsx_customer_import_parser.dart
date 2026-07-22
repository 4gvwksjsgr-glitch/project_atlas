import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../../domain/entities/customer_import_sheet.dart';
import '../../domain/entities/customer_import_source.dart';

class XlsxCustomerImportParser {
  const XlsxCustomerImportParser();

  CustomerImportSource parse({
    required String fileName,
    required Uint8List bytes,
    String? preferredSheet,
  }) {
    final excel = Excel.decodeBytes(bytes);
    final nonEmptySheets = <({String name, Sheet sheet, int dataRows})>[];

    for (final entry in excel.tables.entries) {
      final sheet = entry.value;
      if (sheet.maxRows <= 0) {
        continue;
      }
      final hasAnyCell = sheet.rows.any(
        (row) => row.any((cell) => cell != null && cell.value != null),
      );
      if (!hasAnyCell) {
        continue;
      }
      final dataRowCount = sheet.maxRows > 0 ? sheet.maxRows - 1 : 0;
      nonEmptySheets.add((
        name: entry.key,
        sheet: sheet,
        dataRows: dataRowCount < 0 ? 0 : dataRowCount,
      ));
    }

    if (nonEmptySheets.isEmpty) {
      throw const FormatException('emptyWorkbook');
    }
    if (nonEmptySheets.length > CustomerImportSource.maxSheets) {
      throw const FormatException('tooManySheets');
    }

    final selected =
        nonEmptySheets.where((s) => s.name == preferredSheet).firstOrNull ??
        nonEmptySheets.first;

    final table = _sheetToTable(selected.sheet);
    if (table.rowCount == 0) {
      throw const FormatException('noDataRows');
    }

    return CustomerImportSource(
      fileName: fileName,
      byteLength: bytes.lengthInBytes,
      kind: CustomerImportSourceKind.xlsx,
      sheets: [
        for (final s in nonEmptySheets)
          CustomerImportSheet(name: s.name, rowCount: s.dataRows),
      ],
      selectedSheet: selected.name,
      selectedTable: table,
    );
  }

  static CustomerImportTable _sheetToTable(Sheet sheet) {
    if (sheet.maxRows < 1) {
      throw const FormatException('missingHeaders');
    }

    final headerRow = sheet.rows.first;
    final headers = <String>[];
    for (final cell in headerRow) {
      final text = _headerText(cell?.value);
      headers.add(text);
    }

    while (headers.isNotEmpty && headers.last.trim().isEmpty) {
      headers.removeLast();
    }

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

    final dataRows = <List<String?>>[];
    final sourceRows = <int>[];

    for (var r = 1; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];
      final cells = List<String?>.generate(headers.length, (c) {
        final data = c < row.length ? row[c] : null;
        return _cellToString(data?.value);
      });
      dataRows.add(cells);
      sourceRows.add(r + 1);
    }

    return CustomerImportTable(
      headers: headers,
      dataRows: dataRows,
      sourceRows: sourceRows,
    );
  }

  static String _headerText(CellValue? value) {
    if (value == null) {
      return '';
    }
    if (value is TextCellValue) {
      return value.toString().trim();
    }
    if (value is IntCellValue) {
      return value.value.toString();
    }
    if (value is DoubleCellValue) {
      return _formatNumber(value.value);
    }
    return value.toString().trim();
  }

  static String? _cellToString(CellValue? value) {
    if (value == null) {
      return null;
    }
    if (value is FormulaCellValue) {
      // Marker consumed by domain validator as formula error.
      return '=${value.formula}';
    }
    if (value is TextCellValue) {
      final text = value.toString().trim();
      return text.isEmpty ? null : text;
    }
    if (value is IntCellValue) {
      return value.value.toString();
    }
    if (value is DoubleCellValue) {
      return _formatNumber(value.value);
    }
    if (value is BoolCellValue) {
      return value.value ? 'true' : 'false';
    }
    if (value is DateCellValue) {
      return '${value.year.toString().padLeft(4, '0')}-'
          '${value.month.toString().padLeft(2, '0')}-'
          '${value.day.toString().padLeft(2, '0')}';
    }
    return value.toString();
  }

  /// Avoid scientific notation for typical phone-like doubles.
  static String _formatNumber(double value) {
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toInt().toString();
    }
    // Fixed decimal without exponential form for moderate magnitudes.
    final asFixed = value
        .toStringAsFixed(10)
        .replaceFirst(RegExp(r'\.?0+$'), '');
    return asFixed;
  }
}
