import '../../../l10n/app_localizations.dart';
import '../domain/entities/transaction_import_issue.dart';

/// Traduce [TransactionImportIssue.code] in copy italiana senza dati del
/// movimento e senza codici tecnici.
String transactionImportIssueMessage(
  AppLocalizations l10n,
  TransactionImportIssue issue,
) {
  final message = _messageForCode(l10n, issue.code);
  final row = issue.sourceRow;
  if (row == null) {
    return message;
  }
  return l10n.transactionsImportIssueWithRow(row, message);
}

String transactionImportIssuesSubtitle(
  AppLocalizations l10n,
  Iterable<TransactionImportIssue> issues,
) {
  return issues
      .map((issue) => _messageForCode(l10n, issue.code))
      .toSet()
      .join(' · ');
}

String _messageForCode(AppLocalizations l10n, String code) {
  switch (code) {
    case 'dateMissing':
      return l10n.transactionsImportIssueDateMissing;
    case 'dateInvalid':
      return l10n.transactionsImportIssueDateInvalid;
    case 'dateUnsupportedFormat':
      return l10n.transactionsImportIssueDateUnsupportedFormat;
    case 'needsDateFormatSelection':
      return l10n.transactionsImportIssueNeedsDateFormat;
    case 'amountMissing':
      return l10n.transactionsImportIssueAmountMissing;
    case 'amountNotNumeric':
      return l10n.transactionsImportIssueAmountNotNumeric;
    case 'amountZero':
      return l10n.transactionsImportIssueAmountZero;
    case 'amountTooManyDecimals':
      return l10n.transactionsImportIssueAmountTooManyDecimals;
    case 'amountOutOfRange':
      return l10n.transactionsImportIssueAmountOutOfRange;
    case 'amountSignNotAllowed':
      return l10n.transactionsImportIssueAmountSignNotAllowed;
    case 'amountBothDebitAndCredit':
      return l10n.transactionsImportIssueAmountBothDebitAndCredit;
    case 'needsNumberFormatSelection':
      return l10n.transactionsImportIssueNeedsNumberFormat;
    case 'descriptionMissing':
      return l10n.transactionsImportIssueDescriptionMissing;
    case 'descriptionTooLong':
      return l10n.transactionsImportIssueDescriptionTooLong;
    case 'notesTooLong':
      return l10n.transactionsImportIssueNotesTooLong;
    case 'referenceTooLong':
      return l10n.transactionsImportIssueReferenceTooLong;
    case 'formulaCell':
      return l10n.transactionsImportIssueFormulaCell;
    case 'duplicateInFile':
      return l10n.transactionsImportIssueDuplicateInFile;
    case 'possibleDuplicateInDatabase':
      return l10n.transactionsImportIssuePossibleDuplicate;
    case 'dateMustBeMappedOnce':
      return l10n.transactionsImportIssueDateMappingRequired;
    case 'descriptionMustBeMappedOnce':
      return l10n.transactionsImportIssueDescriptionMappingRequired;
    case 'amountMappingRequired':
      return l10n.transactionsImportIssueAmountMappingRequired;
    case 'fieldMappedMoreThanOnce':
      return l10n.transactionsImportIssueFieldMappedMoreThanOnce;
    case 'fileTooLarge':
      return l10n.transactionsImportIssueFileTooLarge;
    case 'tooManyRows':
      return l10n.transactionsImportIssueTooManyRows;
    case 'tooManySheets':
      return l10n.transactionsImportIssueTooManySheets;
    default:
      // Mai codici tecnici in UI.
      return l10n.transactionsImportIssueGeneric;
  }
}
