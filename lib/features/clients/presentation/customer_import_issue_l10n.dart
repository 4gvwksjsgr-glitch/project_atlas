import '../../../l10n/app_localizations.dart';
import '../domain/entities/customer_import_issue.dart';

/// Maps [CustomerImportIssue.code] to Italian UI copy without PII or raw codes.
String customerImportIssueMessage(
  AppLocalizations l10n,
  CustomerImportIssue issue,
) {
  final message = _messageForCode(l10n, issue.code);
  final row = issue.sourceRow;
  if (row == null) {
    return message;
  }
  return l10n.customersImportIssueWithRow(row, message);
}

String customerImportIssuesSubtitle(
  AppLocalizations l10n,
  Iterable<CustomerImportIssue> issues,
) {
  return issues
      .map((issue) => customerImportIssueMessage(l10n, issue))
      .join(' · ');
}

String _messageForCode(AppLocalizations l10n, String code) {
  switch (code) {
    case 'leadingZeroRisk':
      return l10n.customersImportIssueLeadingZeroRisk;
    case 'duplicateEmailInFile':
      return l10n.customersImportIssueDuplicateEmailInFile;
    case 'duplicateEmailInTenant':
    case 'duplicateEmailInDatabase':
      return l10n.customersImportIssueDuplicateEmailInDatabase;
    case 'missingName':
      return l10n.customersImportIssueMissingName;
    case 'invalidEmail':
      return l10n.customersImportIssueInvalidEmail;
    case 'nameTooLong':
      return l10n.customersImportIssueNameTooLong;
    case 'emailTooLong':
      return l10n.customersImportIssueEmailTooLong;
    case 'phoneTooLong':
      return l10n.customersImportIssuePhoneTooLong;
    case 'notesTooLong':
      return l10n.customersImportIssueNotesTooLong;
    case 'formulaCell':
    case 'formulaNotSupported':
      return l10n.customersImportIssueFormulaNotSupported;
    case 'invalidCellType':
      return l10n.customersImportIssueInvalidCellType;
    case 'similarName':
    case 'duplicateNameWarning':
      return l10n.customersImportIssueDuplicateNameWarning;
    default:
      // Never surface technical codes in the UI.
      return l10n.customersImportIssueGeneric;
  }
}
