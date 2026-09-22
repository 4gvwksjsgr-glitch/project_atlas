import '../../../../core/tabular_import/tabular_import_source.dart';
import '../entities/cash_transaction.dart';
import '../entities/transaction_import_issue.dart';
import '../entities/transaction_import_mapping.dart';
import '../entities/transaction_import_payload_row.dart';
import '../entities/transaction_import_plan.dart';
import '../entities/transaction_import_row.dart';
import '../entities/transaction_import_source.dart';
import '../value_objects/calendar_date.dart';
import '../value_objects/money_amount.dart';
import '../value_objects/transaction_import_field.dart';
import '../value_objects/transaction_import_formats.dart';
import 'transaction_amount_parser.dart';
import 'transaction_date_parser.dart';
import 'transaction_import_fingerprint.dart';

class TransactionImportValidator {
  const TransactionImportValidator();

  static const int maxDescriptionLength = 500;
  static const int maxNotesLength = 2000;
  static const int maxReferenceLength = 120;

  /// Chiavi di confronto dei movimenti già presenti in azienda.
  static Set<String> existingMatchKeys(Iterable<CashTransaction> existing) {
    return {
      for (final transaction in existing)
        TransactionImportFingerprint.existingMatchKey(
          occurredOn: CalendarDate.toIsoDate(transaction.occurredOn),
          kind: transaction.kind.dbValue,
          amount: transaction.amount.toCanonicalDecimal(),
          description: transaction.description,
        ),
    };
  }

  TransactionImportPlan buildPlan({
    required TransactionImportSource source,
    required TransactionImportMapping mapping,
    NumberFormatPreference numberFormat = NumberFormatPreference.auto,
    DateFormatPreference dateFormat = DateFormatPreference.auto,
    Set<String> existingKeys = const {},
    Set<int> includedDuplicateRows = const {},
  }) {
    final sourceIssues = <TransactionImportIssue>[
      ...source.constraintIssues.map(
        (issue) => TransactionImportIssue(
          severity: issue.severity == TabularImportIssueSeverity.error
              ? TransactionImportIssueSeverity.error
              : TransactionImportIssueSeverity.warning,
          code: issue.code,
        ),
      ),
      ...mapping.validationCodes.map(
        (code) => TransactionImportIssue(
          severity: TransactionImportIssueSeverity.error,
          code: code,
        ),
      ),
    ];

    final table = source.selectedTable;
    final rows = <TransactionImportRow>[];
    final seenFingerprints = <String>{};
    var emptyIgnored = 0;
    var needsNumberFormat = false;
    var needsDateFormat = false;

    for (var rowIndex = 0; rowIndex < table.dataRows.length; rowIndex++) {
      final rawCells = table.dataRows[rowIndex];
      if (rawCells.every((cell) => _trimOptional(cell) == null)) {
        emptyIgnored += 1;
        continue;
      }

      final sourceRow = table.sourceRows[rowIndex];
      final issues = <TransactionImportIssue>[];

      String? cellFor(TransactionImportField field) {
        final index = mapping.headerIndexOf(field);
        if (index == null || index >= rawCells.length) {
          return null;
        }
        final value = _trimOptional(rawCells[index]);
        if (value != null && value.startsWith('=')) {
          issues.add(_error(sourceRow, 'formulaCell'));
          return null;
        }
        return value;
      }

      final rawDate = cellFor(TransactionImportField.date);
      final rawDescription = cellFor(TransactionImportField.description);
      final rawSigned = cellFor(TransactionImportField.signedAmount);
      final rawDebit = cellFor(TransactionImportField.debit);
      final rawCredit = cellFor(TransactionImportField.credit);
      final reference = cellFor(TransactionImportField.reference);
      final notes = cellFor(TransactionImportField.notes);

      var rowNeedsNumberFormat = false;
      var rowNeedsDateFormat = false;

      // --- Data -------------------------------------------------------
      DateTime? occurredOn;
      if (rawDate == null) {
        issues.add(_error(sourceRow, 'dateMissing'));
      } else {
        switch (TransactionDateParser.parse(rawDate, preference: dateFormat)) {
          case DateParsed(:final value):
            occurredOn = value;
          case DateAmbiguous():
            rowNeedsDateFormat = true;
            needsDateFormat = true;
            issues.add(_error(sourceRow, 'needsDateFormatSelection'));
          case DateInvalid(:final code):
            issues.add(_error(sourceRow, code));
        }
      }

      // --- Importo ----------------------------------------------------
      TransactionKind? kind;
      MoneyAmount? amount;
      final amountOutcome = _resolveAmount(
        mode: mapping.amountMode,
        signed: rawSigned,
        debit: rawDebit,
        credit: rawCredit,
        preference: numberFormat,
      );
      switch (amountOutcome) {
        case _ResolvedAmount(:final cents, :final resolvedKind):
          kind = resolvedKind;
          amount = MoneyAmount.fromCents(cents);
        case _AmbiguousAmount():
          rowNeedsNumberFormat = true;
          needsNumberFormat = true;
          issues.add(_error(sourceRow, 'needsNumberFormatSelection'));
        case _InvalidAmount(:final code):
          issues.add(_error(sourceRow, code));
      }

      // --- Descrizione e testi ---------------------------------------
      if (rawDescription == null) {
        issues.add(_error(sourceRow, 'descriptionMissing'));
      } else if (rawDescription.length > maxDescriptionLength) {
        issues.add(_error(sourceRow, 'descriptionTooLong'));
      }
      if (notes != null && notes.length > maxNotesLength) {
        issues.add(_error(sourceRow, 'notesTooLong'));
      }
      if (reference != null && reference.length > maxReferenceLength) {
        issues.add(_error(sourceRow, 'referenceTooLong'));
      }

      final hasErrors = issues.any(
        (issue) => issue.severity == TransactionImportIssueSeverity.error,
      );

      if (hasErrors ||
          occurredOn == null ||
          kind == null ||
          amount == null ||
          rawDescription == null) {
        rows.add(
          TransactionImportRow(
            sourceRow: sourceRow,
            rawCells: rawCells,
            status: TransactionImportRowStatus.invalid,
            occurredOn: occurredOn,
            kind: kind,
            amount: amount,
            description: rawDescription,
            notes: notes,
            reference: reference,
            issues: issues,
            needsNumberFormatSelection: rowNeedsNumberFormat,
            needsDateFormatSelection: rowNeedsDateFormat,
          ),
        );
        continue;
      }

      final isoDate = CalendarDate.toIsoDate(occurredOn);
      final canonicalAmount = amount.toCanonicalDecimal();
      final fingerprint = TransactionImportFingerprint.rowFingerprint(
        occurredOn: isoDate,
        kind: kind.dbValue,
        amount: canonicalAmount,
        description: rawDescription,
        reference: reference,
      );
      final existingKey = TransactionImportFingerprint.existingMatchKey(
        occurredOn: isoDate,
        kind: kind.dbValue,
        amount: canonicalAmount,
        description: rawDescription,
      );

      var status = TransactionImportRowStatus.valid;
      var selected = true;

      if (!seenFingerprints.add(fingerprint)) {
        status = TransactionImportRowStatus.duplicateInFile;
        // Segnalato ma escluso per default: l'utente può includerlo esplicitamente.
        selected = includedDuplicateRows.contains(sourceRow);
        issues.add(_warning(sourceRow, 'duplicateInFile'));
      } else if (existingKeys.contains(existingKey)) {
        status = TransactionImportRowStatus.possibleDuplicate;
        // Segnalato ma escluso per default: l'utente può includerlo.
        selected = includedDuplicateRows.contains(sourceRow);
        issues.add(_warning(sourceRow, 'possibleDuplicateInDatabase'));
      }

      rows.add(
        TransactionImportRow(
          sourceRow: sourceRow,
          rawCells: rawCells,
          status: status,
          occurredOn: occurredOn,
          kind: kind,
          amount: amount,
          description: rawDescription,
          notes: notes,
          reference: reference,
          rowFingerprint: fingerprint,
          selectedForImport: selected,
          issues: issues,
        ),
      );
    }

    final blocked =
        sourceIssues.any(
          (issue) => issue.severity == TransactionImportIssueSeverity.error,
        ) ||
        needsNumberFormat ||
        needsDateFormat;

    final rowsToImport = blocked
        ? const <TransactionImportPayloadRow>[]
        : [
            for (final row in rows)
              if (row.selectedForImport)
                TransactionImportPayloadRow(
                  sourceRow: row.sourceRow,
                  occurredOn: CalendarDate.toIsoDate(row.occurredOn!),
                  kind: row.kind!.dbValue,
                  amount: row.amount!.toCanonicalDecimal(),
                  description: row.description!,
                  notes: row.notes,
                  reference: row.reference,
                  rowFingerprint: row.rowFingerprint!,
                ),
          ];

    int countOf(TransactionImportRowStatus status) =>
        rows.where((row) => row.status == status).length;

    return TransactionImportPlan(
      total: rows.length,
      valid: countOf(TransactionImportRowStatus.valid),
      invalid: countOf(TransactionImportRowStatus.invalid),
      possibleDuplicate: countOf(TransactionImportRowStatus.possibleDuplicate),
      duplicateInFile: countOf(TransactionImportRowStatus.duplicateInFile),
      selectedForImport: rowsToImport.length,
      emptyIgnored: emptyIgnored,
      warnings: rows
          .expand((row) => row.issues)
          .where(
            (issue) =>
                issue.severity == TransactionImportIssueSeverity.warning,
          )
          .length,
      needsNumberFormatSelection: needsNumberFormat,
      needsDateFormatSelection: needsDateFormat,
      rows: rows,
      rowsToImport: rowsToImport,
      sourceIssues: sourceIssues,
    );
  }

  static _AmountResolution _resolveAmount({
    required TransactionImportAmountMode mode,
    required String? signed,
    required String? debit,
    required String? credit,
    required NumberFormatPreference preference,
  }) {
    switch (mode) {
      case TransactionImportAmountMode.none:
        return const _InvalidAmount('amountMissing');

      case TransactionImportAmountMode.signed:
        if (signed == null) {
          return const _InvalidAmount('amountMissing');
        }
        final outcome = TransactionAmountParser.parse(
          signed,
          preference: preference,
        );
        switch (outcome) {
          case AmountAmbiguous():
            return const _AmbiguousAmount();
          case AmountInvalid(:final code):
            return _InvalidAmount(code);
          case AmountParsed(:final cents, :final isNegative):
            if (cents == 0) {
              return const _InvalidAmount('amountZero');
            }
            return _ResolvedAmount(
              cents: cents,
              resolvedKind: isNegative
                  ? TransactionKind.expense
                  : TransactionKind.income,
            );
        }

      case TransactionImportAmountMode.debitCredit:
        final debitOutcome = debit == null
            ? null
            : TransactionAmountParser.parse(debit, preference: preference);
        final creditOutcome = credit == null
            ? null
            : TransactionAmountParser.parse(credit, preference: preference);

        if (debitOutcome is AmountAmbiguous ||
            creditOutcome is AmountAmbiguous) {
          return const _AmbiguousAmount();
        }
        if (debitOutcome is AmountInvalid) {
          return _InvalidAmount(debitOutcome.code);
        }
        if (creditOutcome is AmountInvalid) {
          return _InvalidAmount(creditOutcome.code);
        }

        final debitValue = debitOutcome as AmountParsed?;
        final creditValue = creditOutcome as AmountParsed?;
        if (debitValue?.isNegative == true ||
            creditValue?.isNegative == true) {
          // Un segno in dare/avere renderebbe il verso ambiguo.
          return const _InvalidAmount('amountSignNotAllowed');
        }

        // Le colonne valorizzate a zero contano come vuote (uso comune
        // negli estratti conto).
        final hasDebit = debitValue != null && !debitValue.isZero;
        final hasCredit = creditValue != null && !creditValue.isZero;

        if (hasDebit && hasCredit) {
          return const _InvalidAmount('amountBothDebitAndCredit');
        }
        if (!hasDebit && !hasCredit) {
          return const _InvalidAmount('amountMissing');
        }

        return _ResolvedAmount(
          cents: hasDebit ? debitValue.cents : creditValue!.cents,
          resolvedKind: hasDebit
              ? TransactionKind.expense
              : TransactionKind.income,
        );
    }
  }

  static String? _trimOptional(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static TransactionImportIssue _error(int sourceRow, String code) =>
      TransactionImportIssue(
        severity: TransactionImportIssueSeverity.error,
        sourceRow: sourceRow,
        code: code,
      );

  static TransactionImportIssue _warning(int sourceRow, String code) =>
      TransactionImportIssue(
        severity: TransactionImportIssueSeverity.warning,
        sourceRow: sourceRow,
        code: code,
      );
}

sealed class _AmountResolution {
  const _AmountResolution();
}

final class _ResolvedAmount extends _AmountResolution {
  const _ResolvedAmount({required this.cents, required this.resolvedKind});

  final int cents;
  final TransactionKind resolvedKind;
}

final class _AmbiguousAmount extends _AmountResolution {
  const _AmbiguousAmount();
}

final class _InvalidAmount extends _AmountResolution {
  const _InvalidAmount(this.code);

  final String code;
}
