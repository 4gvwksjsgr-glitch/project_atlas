import '../entities/customer_import_issue.dart';
import '../entities/customer_import_mapping.dart';
import '../entities/customer_import_payload_row.dart';
import '../entities/customer_import_plan.dart';
import '../entities/customer_import_row.dart';
import '../entities/customer_import_source.dart';
import '../value_objects/customer_import_field.dart';
import '../value_objects/normalized_email.dart';

class CustomerImportValidator {
  const CustomerImportValidator();

  static final RegExp _emailPattern = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
  static final RegExp _digitsOnly = RegExp(r'^\d+$');

  static const Map<CustomerImportField, int> _maxLengths = {
    CustomerImportField.name: 200,
    CustomerImportField.email: 254,
    CustomerImportField.phone: 40,
    CustomerImportField.notes: 2000,
  };

  /// Applies [mapping] and returns all non-empty input rows.
  List<CustomerImportRow> applyMapping({
    required CustomerImportTable table,
    required CustomerImportMapping mapping,
  }) {
    final rows = <CustomerImportRow>[];

    for (var rowIndex = 0; rowIndex < table.dataRows.length; rowIndex++) {
      final rawCells = table.dataRows[rowIndex];
      if (_isEmptyRow(rawCells)) {
        continue;
      }

      final sourceRow = table.sourceRows[rowIndex];
      final values = <CustomerImportField, String?>{};
      final issues = <CustomerImportIssue>[];

      for (
        var columnIndex = 0;
        columnIndex < table.headers.length;
        columnIndex++
      ) {
        final field = mapping.fieldAt(columnIndex);
        if (field == CustomerImportField.ignore || values.containsKey(field)) {
          continue;
        }

        final rawValue = columnIndex < rawCells.length
            ? rawCells[columnIndex]
            : null;
        final trimmedValue = _trimOptional(rawValue);
        values[field] = trimmedValue;

        if (trimmedValue != null && trimmedValue.startsWith('=')) {
          issues.add(_error(sourceRow, 'formulaCell'));
        }

        final maxLength = _maxLengths[field];
        if (trimmedValue != null &&
            maxLength != null &&
            trimmedValue.length > maxLength) {
          issues.add(_error(sourceRow, '${field.name}TooLong'));
        }
      }

      final name = values[CustomerImportField.name];
      final rawEmail = values[CustomerImportField.email];
      final email = rawEmail == null ? null : normalizeEmail(rawEmail);
      final phone = values[CustomerImportField.phone];

      if (name == null) {
        issues.add(_error(sourceRow, 'missingName'));
      }
      if (email != null && !_emailPattern.hasMatch(email)) {
        issues.add(_error(sourceRow, 'invalidEmail'));
      }

      final wasNumericPhone = phone != null && _digitsOnly.hasMatch(phone);
      if (wasNumericPhone) {
        issues.add(_warning(sourceRow, 'leadingZeroRisk'));
      }

      rows.add(
        CustomerImportRow(
          sourceRow: sourceRow,
          rawCells: rawCells,
          name: name,
          email: email,
          phone: phone,
          notes: values[CustomerImportField.notes],
          issues: issues,
          wasNumericPhone: wasNumericPhone,
        ),
      );
    }

    return List.unmodifiable(rows);
  }

  CustomerImportPlan buildPlan({
    required CustomerImportSource source,
    required CustomerImportMapping mapping,
    required Set<String> existingEmailsNormalized,
  }) {
    final sourceIssues = <CustomerImportIssue>[
      ...source.constraintIssues,
      ...mapping.validationCodes.map(
        (code) => CustomerImportIssue(
          severity: CustomerImportIssueSeverity.error,
          code: code,
        ),
      ),
    ];
    final mappedRows = applyMapping(
      table: source.selectedTable,
      mapping: mapping,
    );
    final emptyIgnored = source.selectedTable.rowCount - mappedRows.length;
    final rows = _addSimilarNameWarnings(mappedRows);
    final existingEmails = existingEmailsNormalized.map(normalizeEmail).toSet();
    final fileEmails = <String>{};
    final excludedDuplicates = <CustomerImportExcludedDuplicate>[];
    final rowsToImport = <CustomerImportPayloadRow>[];
    final plannedRows = <CustomerImportRow>[];

    for (var row in rows) {
      if (row.hasErrors) {
        plannedRows.add(row);
        continue;
      }

      final email = row.email;
      if (email != null && existingEmails.contains(email)) {
        row = _withIssue(
          row,
          _warning(row.sourceRow, 'duplicateEmailInTenant'),
        );
        excludedDuplicates.add(
          CustomerImportExcludedDuplicate(sourceRow: row.sourceRow),
        );
      } else if (email != null && !fileEmails.add(email)) {
        row = _withIssue(row, _warning(row.sourceRow, 'duplicateEmailInFile'));
        excludedDuplicates.add(
          CustomerImportExcludedDuplicate(sourceRow: row.sourceRow),
        );
      }

      plannedRows.add(row);
      if (!excludedDuplicates.any(
        (duplicate) => duplicate.sourceRow == row.sourceRow,
      )) {
        rowsToImport.add(
          CustomerImportPayloadRow(
            sourceRow: row.sourceRow,
            name: row.name!,
            email: email,
            phone: row.phone,
            notes: row.notes,
          ),
        );
      }
    }

    final hasBlockingSourceIssue = sourceIssues.any(
      (issue) => issue.severity == CustomerImportIssueSeverity.error,
    );
    final importableRows = hasBlockingSourceIssue
        ? const <CustomerImportPayloadRow>[]
        : rowsToImport;
    final errorRows = plannedRows.where((row) => row.hasErrors).length;
    final warnings = plannedRows
        .expand((row) => row.issues)
        .where((issue) => issue.severity == CustomerImportIssueSeverity.warning)
        .length;

    return CustomerImportPlan(
      readCount: source.selectedTable.rowCount,
      validToImport: importableRows.length,
      skippedDuplicates: excludedDuplicates.length,
      errorRows: errorRows,
      emptyIgnored: emptyIgnored,
      warnings: warnings,
      rowsToImport: importableRows,
      excludedDuplicates: excludedDuplicates,
      rows: plannedRows,
      sourceIssues: sourceIssues,
    );
  }

  List<CustomerImportRow> _addSimilarNameWarnings(
    List<CustomerImportRow> rows,
  ) {
    final namesWithoutEmail = <String, int>{};
    for (final row in rows) {
      if (!row.hasErrors && row.email == null && row.name != null) {
        final normalizedName = row.name!.toLowerCase();
        namesWithoutEmail[normalizedName] =
            (namesWithoutEmail[normalizedName] ?? 0) + 1;
      }
    }

    return rows
        .map((row) {
          final hasSimilarName =
              !row.hasErrors &&
              row.email == null &&
              row.name != null &&
              namesWithoutEmail[row.name!.toLowerCase()]! > 1;
          return hasSimilarName
              ? _withIssue(row, _warning(row.sourceRow, 'similarName'))
              : row;
        })
        .toList(growable: false);
  }

  static CustomerImportRow _withIssue(
    CustomerImportRow row,
    CustomerImportIssue issue,
  ) {
    return CustomerImportRow(
      sourceRow: row.sourceRow,
      rawCells: row.rawCells,
      name: row.name,
      email: row.email,
      phone: row.phone,
      notes: row.notes,
      issues: [...row.issues, issue],
      wasNumericPhone: row.wasNumericPhone,
    );
  }

  static bool _isEmptyRow(List<String?> cells) =>
      cells.every((cell) => _trimOptional(cell) == null);

  static String? _trimOptional(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static CustomerImportIssue _error(int sourceRow, String code) =>
      CustomerImportIssue(
        severity: CustomerImportIssueSeverity.error,
        sourceRow: sourceRow,
        code: code,
      );

  static CustomerImportIssue _warning(int sourceRow, String code) =>
      CustomerImportIssue(
        severity: CustomerImportIssueSeverity.warning,
        sourceRow: sourceRow,
        code: code,
      );
}
