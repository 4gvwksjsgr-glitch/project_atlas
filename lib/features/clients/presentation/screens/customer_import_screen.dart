import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../../../companies/presentation/controllers/active_company_controller.dart';
import '../../domain/value_objects/customer_import_field.dart';
import '../controllers/customer_import_controller.dart';
import '../customer_import_issue_l10n.dart';

class CustomerImportScreen extends ConsumerWidget {
  const CustomerImportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final activeCompany = ref.watch(activeCompanyProvider);

    if (activeCompany == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.customersImportTitle)),
        body: Center(child: Text(l10n.customersNoActiveCompany)),
      );
    }

    if (!activeCompany.role.canManageCustomers) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          context.go(RoutePaths.clients);
        }
      });
      return Scaffold(
        appBar: AppBar(title: Text(l10n.customersImportTitle)),
        body: Center(child: Text(l10n.customersImportForbidden)),
      );
    }

    return _CustomerImportBody(
      key: ValueKey(activeCompany.companyId),
      companyId: activeCompany.companyId,
    );
  }
}

class _CustomerImportBody extends ConsumerWidget {
  const _CustomerImportBody({super.key, required this.companyId});

  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(customerImportControllerProvider(companyId));
    final controller = ref.read(
      customerImportControllerProvider(companyId).notifier,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.customersImportTitle),
        leading: BackButton(
          onPressed: state.isBusy
              ? null
              : () {
                  controller.reset();
                  context.go(RoutePaths.clients);
                },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppUiConstants.spacingLarge),
        child: switch (state.step) {
          CustomerImportWizardStep.info || CustomerImportWizardStep.pickFile =>
            _InfoStep(companyId: companyId, state: state),
          CustomerImportWizardStep.pickSheet => _SheetStep(
            companyId: companyId,
            state: state,
          ),
          CustomerImportWizardStep.mapping => _MappingStep(
            companyId: companyId,
            state: state,
          ),
          CustomerImportWizardStep.preview ||
          CustomerImportWizardStep.confirm => _PreviewStep(
            companyId: companyId,
            state: state,
          ),
          CustomerImportWizardStep.importing => const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: AppUiConstants.spacingMedium),
                Text('Importazione in corso...'),
              ],
            ),
          ),
          CustomerImportWizardStep.result => _ResultStep(
            companyId: companyId,
            state: state,
          ),
        },
      ),
    );
  }
}

class _InfoStep extends ConsumerWidget {
  const _InfoStep({required this.companyId, required this.state});

  final String companyId;
  final CustomerImportControllerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final controller = ref.read(
      customerImportControllerProvider(companyId).notifier,
    );

    return ListView(
      children: [
        Text(l10n.customersImportIntro, style: theme.textTheme.bodyLarge),
        const SizedBox(height: AppUiConstants.spacingMedium),
        Text(
          l10n.customersImportFieldsNotice,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppUiConstants.spacingMedium),
        Text(l10n.customersImportLimits, style: theme.textTheme.bodyMedium),
        if (state.errorMessage != null) ...[
          const SizedBox(height: AppUiConstants.spacingMedium),
          Text(
            state.errorMessage!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: AppUiConstants.spacingLarge),
        FilledButton.icon(
          onPressed: state.isBusy
              ? null
              : () async {
                  final result = await FilePicker.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: const ['csv', 'xlsx'],
                    withData: true,
                  );
                  if (result == null || result.files.isEmpty) {
                    return;
                  }
                  final file = result.files.single;
                  final bytes = file.bytes;
                  if (bytes == null) {
                    return;
                  }
                  await controller.loadFile(fileName: file.name, bytes: bytes);
                },
          icon: const Icon(Icons.upload_file),
          label: Text(l10n.customersImportPickFile),
        ),
      ],
    );
  }
}

class _SheetStep extends ConsumerWidget {
  const _SheetStep({required this.companyId, required this.state});

  final String companyId;
  final CustomerImportControllerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final source = state.source;
    final controller = ref.read(
      customerImportControllerProvider(companyId).notifier,
    );

    if (source == null) {
      return const SizedBox.shrink();
    }

    return ListView(
      children: [
        Text(l10n.customersImportPickSheet),
        const SizedBox(height: AppUiConstants.spacingMedium),
        for (final sheet in source.sheets)
          ListTile(
            title: Text(sheet.name),
            subtitle: Text('${sheet.rowCount} righe dati'),
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
  final CustomerImportControllerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final source = state.source;
    final mapping = state.mapping;
    final controller = ref.read(
      customerImportControllerProvider(companyId).notifier,
    );

    if (source == null || mapping == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.customersImportMappingTitle,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AppUiConstants.spacingSmall),
        Text(l10n.customersImportMappingHint),
        if (state.errorMessage != null) ...[
          const SizedBox(height: AppUiConstants.spacingSmall),
          Text(
            state.errorMessage!,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: AppUiConstants.spacingMedium),
        Expanded(
          child: ListView.separated(
            itemCount: source.selectedTable.headers.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final header = source.selectedTable.headers[index];
              final field = mapping.fieldAt(index);
              return ListTile(
                title: Text(header),
                trailing: DropdownButton<CustomerImportField>(
                  value: field,
                  onChanged: state.isBusy
                      ? null
                      : (value) {
                          if (value != null) {
                            controller.updateMapping(index, value);
                          }
                        },
                  items: [
                    for (final option in CustomerImportField.values)
                      DropdownMenuItem(
                        value: option,
                        child: Text(_fieldLabel(l10n, option)),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        FilledButton(
          onPressed: state.isBusy ? null : controller.buildPlan,
          child: Text(l10n.customersImportContinue),
        ),
      ],
    );
  }

  static String _fieldLabel(AppLocalizations l10n, CustomerImportField field) {
    return switch (field) {
      CustomerImportField.name => l10n.customersImportFieldName,
      CustomerImportField.email => l10n.customersImportFieldEmail,
      CustomerImportField.phone => l10n.customersImportFieldPhone,
      CustomerImportField.notes => l10n.customersImportFieldNotes,
      CustomerImportField.ignore => l10n.customersImportFieldIgnore,
    };
  }
}

class _PreviewStep extends ConsumerWidget {
  const _PreviewStep({required this.companyId, required this.state});

  final String companyId;
  final CustomerImportControllerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final plan = state.plan;
    final controller = ref.read(
      customerImportControllerProvider(companyId).notifier,
    );

    if (plan == null) {
      return const SizedBox.shrink();
    }

    final previewRows = plan.rows.take(20).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.customersImportSummaryTitle,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AppUiConstants.spacingSmall),
        Text(l10n.customersImportSummaryRead(plan.readCount)),
        Text(l10n.customersImportSummaryValid(plan.validToImport)),
        Text(l10n.customersImportSummaryDuplicates(plan.skippedDuplicates)),
        Text(l10n.customersImportSummaryErrors(plan.errorRows)),
        Text(l10n.customersImportSummaryEmpty(plan.emptyIgnored)),
        Text(l10n.customersImportSummaryWarnings(plan.warnings)),
        if (state.errorMessage != null) ...[
          const SizedBox(height: AppUiConstants.spacingSmall),
          Text(
            state.errorMessage!,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: AppUiConstants.spacingMedium),
        Text(
          l10n.customersImportPreviewTitle,
          style: theme.textTheme.titleSmall,
        ),
        Expanded(
          child: ListView.builder(
            itemCount: previewRows.length,
            itemBuilder: (context, index) {
              final row = previewRows[index];
              final status = row.hasErrors
                  ? l10n.customersImportPreviewStatusError
                  : plan.excludedDuplicates.any(
                      (d) => d.sourceRow == row.sourceRow,
                    )
                  ? l10n.customersImportPreviewStatusDuplicate
                  : l10n.customersImportPreviewStatusOk;
              return ListTile(
                dense: true,
                title: Text(
                  l10n.customersImportPreviewRowTitle(row.sourceRow, status),
                ),
                subtitle: row.issues.isEmpty
                    ? null
                    : Text(
                        customerImportIssuesSubtitle(l10n, row.issues),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
              );
            },
          ),
        ),
        FilledButton(
          onPressed: state.isBusy || plan.validToImport == 0
              ? null
              : controller.confirmImport,
          child: Text(l10n.customersImportConfirm),
        ),
      ],
    );
  }
}

class _ResultStep extends ConsumerWidget {
  const _ResultStep({required this.companyId, required this.state});

  final String companyId;
  final CustomerImportControllerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final result = state.result;
    final controller = ref.read(
      customerImportControllerProvider(companyId).notifier,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.customersImportResultTitle),
        const SizedBox(height: AppUiConstants.spacingMedium),
        if (result != null) ...[
          Text(l10n.customersImportResultInserted(result.insertedCount)),
          Text(l10n.customersImportResultSkipped(result.skippedDuplicateCount)),
        ],
        const Spacer(),
        FilledButton(
          onPressed: () {
            controller.reset();
            context.go(RoutePaths.clients);
          },
          child: Text(l10n.customersImportBackToList),
        ),
      ],
    );
  }
}
