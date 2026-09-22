import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/files/app_file_pick_result.dart';
import '../../../../core/router/route_paths.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../../../companies/presentation/controllers/active_company_controller.dart';
import '../../domain/entities/cash_transaction.dart';
import '../../domain/entities/transaction_import_row.dart';
import '../../domain/value_objects/transaction_import_field.dart';
import '../../domain/value_objects/transaction_import_formats.dart';
import '../controllers/transaction_import_controller.dart';
import '../transaction_import_issue_l10n.dart';

/// Numero massimo di righe mostrate in anteprima: la lista resta leggibile
/// anche con un file da 500 righe.
const int _previewRowLimit = 20;

class TransactionImportScreen extends ConsumerWidget {
  const TransactionImportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final activeCompany = ref.watch(activeCompanyProvider);

    if (activeCompany == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.transactionsImportTitle)),
        body: Center(child: Text(l10n.transactionsNoActiveCompany)),
      );
    }

    if (!activeCompany.role.canManageTransactions) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          context.go(RoutePaths.transactions);
        }
      });
      return Scaffold(
        appBar: AppBar(title: Text(l10n.transactionsImportTitle)),
        body: Center(child: Text(l10n.transactionsImportForbidden)),
      );
    }

    return _TransactionImportBody(
      key: ValueKey(activeCompany.companyId),
      companyId: activeCompany.companyId,
    );
  }
}

class _TransactionImportBody extends ConsumerWidget {
  const _TransactionImportBody({super.key, required this.companyId});

  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(transactionImportControllerProvider(companyId));
    final controller = ref.read(
      transactionImportControllerProvider(companyId).notifier,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.transactionsImportTitle),
        leading: BackButton(
          onPressed: state.isBusy
              ? null
              : () {
                  controller.reset();
                  context.go(RoutePaths.transactions);
                },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppUiConstants.spacingLarge),
        child: switch (state.step) {
          TransactionImportWizardStep.info ||
          TransactionImportWizardStep.pickFile => _InfoStep(
            companyId: companyId,
            state: state,
          ),
          TransactionImportWizardStep.pickSheet => _SheetStep(
            companyId: companyId,
            state: state,
          ),
          TransactionImportWizardStep.mapping => _MappingStep(
            companyId: companyId,
            state: state,
          ),
          TransactionImportWizardStep.formatConfiguration => _FormatStep(
            companyId: companyId,
            state: state,
          ),
          TransactionImportWizardStep.preview ||
          TransactionImportWizardStep.confirm => _PreviewStep(
            companyId: companyId,
            state: state,
          ),
          TransactionImportWizardStep.importing => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: AppUiConstants.spacingMedium),
                Text(l10n.transactionsImportInProgress),
              ],
            ),
          ),
          TransactionImportWizardStep.result => _ResultStep(
            companyId: companyId,
            state: state,
          ),
        },
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppUiConstants.spacingSmall),
      child: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
    );
  }
}

class _InfoStep extends ConsumerWidget {
  const _InfoStep({required this.companyId, required this.state});

  final String companyId;
  final TransactionImportControllerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final controller = ref.read(
      transactionImportControllerProvider(companyId).notifier,
    );

    return ListView(
      children: [
        Text(l10n.transactionsImportIntro, style: theme.textTheme.bodyLarge),
        const SizedBox(height: AppUiConstants.spacingMedium),
        Text(
          l10n.transactionsImportFieldsNotice,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppUiConstants.spacingMedium),
        Text(l10n.transactionsImportLimits, style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppUiConstants.spacingMedium),
        Text(
          l10n.transactionsImportDeferredNotice,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (state.errorMessage != null) _ErrorText(state.errorMessage!),
        const SizedBox(height: AppUiConstants.spacingLarge),
        FilledButton.icon(
          onPressed: state.isBusy
              ? null
              : () async {
                  final pickResult = await ref
                      .read(appFilePickerProvider)
                      .pickTransactionImportFile();
                  switch (pickResult) {
                    case AppFilePickCancelled():
                      return;
                    case AppFilePickFailure(:final message):
                      if (!context.mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(message)));
                      return;
                    case AppFilePickSuccess(:final file):
                      await controller.loadFile(
                        fileName: file.name,
                        bytes: file.bytes,
                      );
                  }
                },
          icon: const Icon(Icons.upload_file),
          label: Text(l10n.transactionsImportPickFile),
        ),
      ],
    );
  }
}

class _SheetStep extends ConsumerWidget {
  const _SheetStep({required this.companyId, required this.state});

  final String companyId;
  final TransactionImportControllerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final source = state.source;
    final controller = ref.read(
      transactionImportControllerProvider(companyId).notifier,
    );

    if (source == null) {
      return const SizedBox.shrink();
    }

    return ListView(
      children: [
        Text(l10n.transactionsImportPickSheet),
        if (state.errorMessage != null) _ErrorText(state.errorMessage!),
        const SizedBox(height: AppUiConstants.spacingMedium),
        for (final sheet in source.sheets)
          ListTile(
            title: Text(sheet.name),
            subtitle: Text(l10n.transactionsImportSheetRows(sheet.rowCount)),
            selected: sheet.name == source.selectedSheet,
            onTap: state.isBusy
                ? null
                : () => controller.selectSheet(sheet.name),
          ),
      ],
    );
  }
}

class _MappingStep extends ConsumerWidget {
  const _MappingStep({required this.companyId, required this.state});

  final String companyId;
  final TransactionImportControllerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final source = state.source;
    final mapping = state.mapping;
    final controller = ref.read(
      transactionImportControllerProvider(companyId).notifier,
    );

    if (source == null || mapping == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.transactionsImportMappingTitle,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AppUiConstants.spacingSmall),
        Text(l10n.transactionsImportMappingHint),
        if (state.errorMessage != null) _ErrorText(state.errorMessage!),
        const SizedBox(height: AppUiConstants.spacingMedium),
        Expanded(
          child: ListView.separated(
            itemCount: source.selectedTable.headers.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final header = source.selectedTable.headers[index];
              return ListTile(
                title: Text(header),
                trailing: DropdownButton<TransactionImportField>(
                  value: mapping.fieldAt(index),
                  onChanged: state.isBusy
                      ? null
                      : (value) {
                          if (value != null) {
                            controller.updateMapping(index, value);
                          }
                        },
                  items: [
                    for (final option in TransactionImportField.values)
                      DropdownMenuItem(
                        value: option,
                        child: Text(transactionImportFieldLabel(l10n, option)),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        FilledButton(
          onPressed: state.isBusy ? null : controller.buildPlan,
          child: Text(l10n.transactionsImportContinue),
        ),
      ],
    );
  }
}

String transactionImportFieldLabel(
  AppLocalizations l10n,
  TransactionImportField field,
) {
  return switch (field) {
    TransactionImportField.date => l10n.transactionsImportFieldDate,
    TransactionImportField.description =>
      l10n.transactionsImportFieldDescription,
    TransactionImportField.signedAmount =>
      l10n.transactionsImportFieldSignedAmount,
    TransactionImportField.debit => l10n.transactionsImportFieldDebit,
    TransactionImportField.credit => l10n.transactionsImportFieldCredit,
    TransactionImportField.reference => l10n.transactionsImportFieldReference,
    TransactionImportField.notes => l10n.transactionsImportFieldNotes,
    TransactionImportField.ignore => l10n.transactionsImportFieldIgnore,
  };
}

/// Scelta esplicita di separatore decimale e ordine dei campi data: nessun
/// valore ambiguo viene interpretato in autonomia.
class _FormatStep extends ConsumerWidget {
  const _FormatStep({required this.companyId, required this.state});

  final String companyId;
  final TransactionImportControllerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final plan = state.plan;
    final controller = ref.read(
      transactionImportControllerProvider(companyId).notifier,
    );

    if (plan == null) {
      return const SizedBox.shrink();
    }

    return ListView(
      children: [
        Text(
          l10n.transactionsImportFormatTitle,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AppUiConstants.spacingSmall),
        Text(l10n.transactionsImportFormatHint),
        const SizedBox(height: AppUiConstants.spacingMedium),
        if (plan.needsNumberFormatSelection) ...[
          Text(
            l10n.transactionsImportNumberFormatRequired,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: AppUiConstants.spacingSmall),
        ],
        DropdownButtonFormField<NumberFormatPreference>(
          initialValue: state.numberFormat,
          decoration: InputDecoration(
            labelText: l10n.transactionsImportNumberFormatLabel,
          ),
          onChanged: state.isBusy
              ? null
              : (value) {
                  if (value != null) {
                    controller.setNumberFormat(value);
                  }
                },
          items: [
            for (final option in NumberFormatPreference.values)
              DropdownMenuItem(
                value: option,
                child: Text(_numberFormatLabel(l10n, option)),
              ),
          ],
        ),
        const SizedBox(height: AppUiConstants.spacingMedium),
        if (plan.needsDateFormatSelection) ...[
          Text(
            l10n.transactionsImportDateFormatRequired,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: AppUiConstants.spacingSmall),
        ],
        DropdownButtonFormField<DateFormatPreference>(
          initialValue: state.dateFormat,
          decoration: InputDecoration(
            labelText: l10n.transactionsImportDateFormatLabel,
          ),
          onChanged: state.isBusy
              ? null
              : (value) {
                  if (value != null) {
                    controller.setDateFormat(value);
                  }
                },
          items: [
            for (final option in DateFormatPreference.values)
              DropdownMenuItem(
                value: option,
                child: Text(_dateFormatLabel(l10n, option)),
              ),
          ],
        ),
        if (state.errorMessage != null) _ErrorText(state.errorMessage!),
        const SizedBox(height: AppUiConstants.spacingLarge),
        OutlinedButton(
          onPressed: state.isBusy
              ? null
              : () =>
                    controller.goToStep(TransactionImportWizardStep.mapping),
          child: Text(l10n.transactionsImportBack),
        ),
      ],
    );
  }

  static String _numberFormatLabel(
    AppLocalizations l10n,
    NumberFormatPreference preference,
  ) {
    return switch (preference) {
      NumberFormatPreference.auto => l10n.transactionsImportNumberFormatAuto,
      NumberFormatPreference.commaDecimal =>
        l10n.transactionsImportNumberFormatComma,
      NumberFormatPreference.dotDecimal =>
        l10n.transactionsImportNumberFormatDot,
    };
  }

  static String _dateFormatLabel(
    AppLocalizations l10n,
    DateFormatPreference preference,
  ) {
    return switch (preference) {
      DateFormatPreference.auto => l10n.transactionsImportDateFormatAuto,
      DateFormatPreference.ymd => l10n.transactionsImportDateFormatYmd,
      DateFormatPreference.dmy => l10n.transactionsImportDateFormatDmy,
      DateFormatPreference.mdy => l10n.transactionsImportDateFormatMdy,
    };
  }
}

class _PreviewStep extends ConsumerWidget {
  const _PreviewStep({required this.companyId, required this.state});

  final String companyId;
  final TransactionImportControllerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final plan = state.plan;
    final controller = ref.read(
      transactionImportControllerProvider(companyId).notifier,
    );

    if (plan == null) {
      return const SizedBox.shrink();
    }

    final previewRows = plan.rows.take(_previewRowLimit).toList();
    final dateFormat = DateFormat('dd/MM/yyyy');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.transactionsImportSummaryTitle,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AppUiConstants.spacingSmall),
        Text(l10n.transactionsImportSummaryRead(plan.total)),
        Text(l10n.transactionsImportSummaryValid(plan.valid)),
        Text(l10n.transactionsImportSummaryInvalid(plan.invalid)),
        Text(
          l10n.transactionsImportSummaryPossibleDuplicates(
            plan.possibleDuplicate,
          ),
        ),
        Text(
          l10n.transactionsImportSummaryDuplicatesInFile(plan.duplicateInFile),
        ),
        Text(l10n.transactionsImportSummaryEmpty(plan.emptyIgnored)),
        Text(l10n.transactionsImportSummaryWarnings(plan.warnings)),
        Text(
          l10n.transactionsImportSummarySelected(plan.selectedForImport),
          style: theme.textTheme.titleSmall,
        ),
        if (state.errorMessage != null) _ErrorText(state.errorMessage!),
        const SizedBox(height: AppUiConstants.spacingMedium),
        Text(
          l10n.transactionsImportPreviewTitle,
          style: theme.textTheme.titleSmall,
        ),
        Expanded(
          child: ListView.builder(
            itemCount: previewRows.length,
            itemBuilder: (context, index) {
              final row = previewRows[index];
              return _PreviewRowTile(
                row: row,
                dateFormat: dateFormat,
                isIncluded: state.includedDuplicateRows.contains(row.sourceRow),
                onToggleDuplicate:
                    state.isBusy ||
                        row.status !=
                            TransactionImportRowStatus.possibleDuplicate
                    ? null
                    : () => controller.toggleDuplicateRow(row.sourceRow),
              );
            },
          ),
        ),
        FilledButton(
          onPressed: state.isBusy || plan.selectedForImport == 0
              ? null
              : controller.confirmImport,
          child: Text(l10n.transactionsImportConfirm),
        ),
      ],
    );
  }
}

class _PreviewRowTile extends StatelessWidget {
  const _PreviewRowTile({
    required this.row,
    required this.dateFormat,
    required this.isIncluded,
    required this.onToggleDuplicate,
  });

  final TransactionImportRow row;
  final DateFormat dateFormat;
  final bool isIncluded;
  final VoidCallback? onToggleDuplicate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final status = switch (row.status) {
      TransactionImportRowStatus.invalid =>
        l10n.transactionsImportPreviewStatusError,
      TransactionImportRowStatus.possibleDuplicate =>
        l10n.transactionsImportPreviewStatusPossibleDuplicate,
      TransactionImportRowStatus.duplicateInFile =>
        l10n.transactionsImportPreviewStatusDuplicateInFile,
      TransactionImportRowStatus.valid =>
        l10n.transactionsImportPreviewStatusOk,
    };

    final occurredOn = row.occurredOn;
    final amount = row.amount;
    final kind = row.kind;
    final detail = occurredOn != null && amount != null && kind != null
        ? l10n.transactionsImportPreviewRowDetail(
            dateFormat.format(occurredOn),
            kind == TransactionKind.income
                ? l10n.transactionKindIncome
                : l10n.transactionKindExpense,
            amount.formatEuro(),
            row.description ?? '',
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          dense: true,
          title: Text(
            l10n.transactionsImportPreviewRowTitle(row.sourceRow, status),
            style: row.status == TransactionImportRowStatus.invalid
                ? theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  )
                : null,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (detail != null)
                Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (row.issues.isNotEmpty)
                Text(
                  transactionImportIssuesSubtitle(l10n, row.issues),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        if (onToggleDuplicate != null)
          Padding(
            padding: const EdgeInsets.only(left: AppUiConstants.spacingMedium),
            child: CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: isIncluded,
              onChanged: (_) => onToggleDuplicate!(),
              title: Text(l10n.transactionsImportIncludeDuplicate),
            ),
          ),
      ],
    );
  }
}

class _ResultStep extends ConsumerWidget {
  const _ResultStep({required this.companyId, required this.state});

  final String companyId;
  final TransactionImportControllerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final result = state.result;
    final controller = ref.read(
      transactionImportControllerProvider(companyId).notifier,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.transactionsImportResultTitle,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AppUiConstants.spacingMedium),
        if (result != null) ...[
          Text(l10n.transactionsImportResultImported(result.importedCount)),
          Text(
            l10n.transactionsImportResultSkippedInvalid(
              result.skippedInvalidCount,
            ),
          ),
          Text(
            l10n.transactionsImportResultSkippedDuplicate(
              result.skippedDuplicateCount,
            ),
          ),
        ],
        const Spacer(),
        FilledButton(
          onPressed: () {
            controller.reset();
            context.go(RoutePaths.transactions);
          },
          child: Text(l10n.transactionsImportBackToList),
        ),
      ],
    );
  }
}
