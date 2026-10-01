import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../../../companies/presentation/controllers/active_company_controller.dart';
import '../../../transactions/domain/entities/cash_transaction.dart';
import '../../domain/entities/transaction_category.dart';
import '../controllers/category_mutation_controller.dart';
import '../providers/category_providers.dart';

double _categoriesDialogWidth(BuildContext context) {
  final screenWidth = MediaQuery.sizeOf(context).width;
  return math.min(420.0, math.max(0.0, screenWidth - 48.0));
}

/// Clears [FloatingActionButton.extended] + [kFloatingActionButtonMargin]
/// so the last list rows remain reachable above the FAB.
const double _categoriesFabClearance = 96;

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final activeCompany = ref.watch(activeCompanyProvider);

    if (activeCompany == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.categoriesTitle)),
        body: Padding(
          padding: const EdgeInsets.all(AppUiConstants.spacingLarge),
          child: Text(
            l10n.categoriesNoActiveCompany,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return CategoriesBody(
      key: ValueKey(activeCompany.companyId),
      companyId: activeCompany.companyId,
      canManage: activeCompany.role.canManageCategories,
    );
  }
}

class CategoriesBody extends ConsumerWidget {
  const CategoriesBody({
    super.key,
    required this.companyId,
    required this.canManage,
  });

  final String companyId;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final categoriesAsync = ref.watch(categoriesProvider(companyId));
    final mutation = ref.watch(categoryMutationControllerProvider(companyId));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.categoriesTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(RoutePaths.settingsCompany);
            }
          },
        ),
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: mutation.isLoading
                  ? null
                  : () => _showCreateDialog(context, ref),
              icon: const Icon(Icons.add),
              label: Text(l10n.categoriesNewButton),
            )
          : null,
      body: Padding(
        padding: const EdgeInsets.all(AppUiConstants.spacingLarge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.categoriesSubtitle,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (!canManage) ...[
              const SizedBox(height: AppUiConstants.spacingMedium),
              Text(
                l10n.categoriesReadOnlyMessage,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (mutation.errorMessage != null) ...[
              const SizedBox(height: AppUiConstants.spacingMedium),
              Text(
                mutation.errorMessage!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: AppUiConstants.spacingMedium),
            Expanded(
              child: categoriesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) {
                  final message = error is StateError
                      ? error.message
                      : l10n.categoriesLoadError;
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: AppUiConstants.spacingMedium),
                        FilledButton(
                          onPressed: () =>
                              ref.invalidate(categoriesProvider(companyId)),
                          child: Text(l10n.categoriesRetry),
                        ),
                      ],
                    ),
                  );
                },
                data: (categories) {
                  if (categories.isEmpty) {
                    return Center(
                      child: Text(
                        l10n.categoriesEmpty,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }

                  final income = categories
                      .where((c) => c.kind == TransactionKind.income)
                      .toList();
                  final expense = categories
                      .where((c) => c.kind == TransactionKind.expense)
                      .toList();

                  return ListView(
                    children: [
                      _CategoryKindSection(
                        title: l10n.categoriesIncomeSection,
                        categories: income,
                        emptyLabel: l10n.categoriesSectionEmpty,
                        canManage: canManage,
                        companyId: companyId,
                      ),
                      const SizedBox(height: AppUiConstants.spacingLarge),
                      _CategoryKindSection(
                        title: l10n.categoriesExpenseSection,
                        categories: expense,
                        emptyLabel: l10n.categoriesSectionEmpty,
                        canManage: canManage,
                        companyId: companyId,
                      ),
                      if (canManage)
                        const SizedBox(
                          key: Key('categories-fab-clearance'),
                          height: _categoriesFabClearance,
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<_CreateCategoryDialogResult>(
      context: context,
      builder: (dialogContext) => const _CreateCategoryDialog(),
    );
    if (result == null || !context.mounted) {
      return;
    }

    final ok = await ref
        .read(categoryMutationControllerProvider(companyId).notifier)
        .create(name: result.name, kind: result.kind);
    if (ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.categoriesCreateSuccess)));
      ref
          .read(categoryMutationControllerProvider(companyId).notifier)
          .clearFeedback();
    }
  }
}

/// Result returned by [_CreateCategoryDialog] after a confirmed save.
class _CreateCategoryDialogResult {
  const _CreateCategoryDialogResult({required this.name, required this.kind});

  final String name;
  final TransactionKind kind;
}

class _CreateCategoryDialog extends StatefulWidget {
  const _CreateCategoryDialog();

  @override
  State<_CreateCategoryDialog> createState() => _CreateCategoryDialogState();
}

class _CreateCategoryDialogState extends State<_CreateCategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  TransactionKind _kind = TransactionKind.income;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop(
      _CreateCategoryDialogResult(name: _nameController.text, kind: _kind),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.categoriesCreateTitle),
      content: SizedBox(
        width: _categoriesDialogWidth(context),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<TransactionKind>(
                  segments: [
                    ButtonSegment(
                      value: TransactionKind.income,
                      label: Text(l10n.transactionKindIncome),
                    ),
                    ButtonSegment(
                      value: TransactionKind.expense,
                      label: Text(l10n.transactionKindExpense),
                    ),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (selection) {
                    setState(() => _kind = selection.first);
                  },
                ),
                const SizedBox(height: AppUiConstants.spacingMedium),
                TextFormField(
                  key: const Key('categories-create-name-field'),
                  controller: _nameController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: l10n.categoriesNameLabel,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final normalized = (value ?? '').trim();
                    if (normalized.isEmpty) {
                      return l10n.categoriesNameRequired;
                    }
                    if (normalized.length > 80) {
                      return l10n.categoriesNameTooLong;
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.categoriesCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.categoriesSave),
        ),
      ],
    );
  }
}

class _CategoryKindSection extends ConsumerWidget {
  const _CategoryKindSection({
    required this.title,
    required this.categories,
    required this.emptyLabel,
    required this.canManage,
    required this.companyId,
  });

  final String title;
  final List<TransactionCategory> categories;
  final String emptyLabel;
  final bool canManage;
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final active = categories.where((c) => c.isActive).toList();
    final archived = categories.where((c) => !c.isActive).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: AppUiConstants.spacingSmall),
        if (categories.isEmpty)
          Text(
            emptyLabel,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else ...[
          if (active.isNotEmpty) ...[
            Text(l10n.categoriesActiveGroup, style: theme.textTheme.labelLarge),
            ...active.map(
              (category) => _CategoryTile(
                category: category,
                canManage: canManage,
                companyId: companyId,
              ),
            ),
          ],
          if (archived.isNotEmpty) ...[
            const SizedBox(height: AppUiConstants.spacingSmall),
            Text(
              l10n.categoriesArchivedGroup,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            ...archived.map(
              (category) => _CategoryTile(
                category: category,
                canManage: canManage,
                companyId: companyId,
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _CategoryTile extends ConsumerWidget {
  const _CategoryTile({
    required this.category,
    required this.canManage,
    required this.companyId,
  });

  final TransactionCategory category;
  final bool canManage;
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = !category.isActive;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        category.name,
        style: muted
            ? theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                decoration: TextDecoration.lineThrough,
              )
            : null,
      ),
      subtitle: muted
          ? Text(
              l10n.categoriesArchivedBadge,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      trailing: canManage
          ? PopupMenuButton<String>(
              onSelected: (value) async {
                switch (value) {
                  case 'rename':
                    await _rename(context, ref);
                  case 'archive':
                    await _setActive(context, ref, false);
                  case 'reactivate':
                    await _setActive(context, ref, true);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'rename',
                  child: Text(l10n.categoriesRenameAction),
                ),
                if (category.isActive)
                  PopupMenuItem(
                    value: 'archive',
                    child: Text(l10n.categoriesArchiveAction),
                  )
                else
                  PopupMenuItem(
                    value: 'reactivate',
                    child: Text(l10n.categoriesReactivateAction),
                  ),
              ],
            )
          : null,
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) =>
          _RenameCategoryDialog(initialName: category.name),
    );
    if (name == null || !context.mounted) {
      return;
    }

    final ok = await ref
        .read(categoryMutationControllerProvider(companyId).notifier)
        .rename(categoryId: category.id, name: name);
    if (ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.categoriesRenameSuccess)));
      ref
          .read(categoryMutationControllerProvider(companyId).notifier)
          .clearFeedback();
    }
  }

  Future<void> _setActive(
    BuildContext context,
    WidgetRef ref,
    bool isActive,
  ) async {
    final l10n = AppLocalizations.of(context);
    final ok = await ref
        .read(categoryMutationControllerProvider(companyId).notifier)
        .setActive(categoryId: category.id, isActive: isActive);
    if (ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isActive
                ? l10n.categoriesReactivateSuccess
                : l10n.categoriesArchiveSuccess,
          ),
        ),
      );
      ref
          .read(categoryMutationControllerProvider(companyId).notifier)
          .clearFeedback();
    }
  }
}

class _RenameCategoryDialog extends StatefulWidget {
  const _RenameCategoryDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameCategoryDialog> createState() => _RenameCategoryDialogState();
}

class _RenameCategoryDialogState extends State<_RenameCategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop(_nameController.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.categoriesRenameTitle),
      content: SizedBox(
        width: _categoriesDialogWidth(context),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: TextFormField(
              key: const Key('categories-rename-name-field'),
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.categoriesNameLabel,
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                final normalized = (value ?? '').trim();
                if (normalized.isEmpty) {
                  return l10n.categoriesNameRequired;
                }
                if (normalized.length > 80) {
                  return l10n.categoriesNameTooLong;
                }
                return null;
              },
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.categoriesCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.categoriesSave),
        ),
      ],
    );
  }
}
