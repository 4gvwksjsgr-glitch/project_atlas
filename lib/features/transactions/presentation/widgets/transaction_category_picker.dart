import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../../../categories/domain/entities/transaction_category.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../domain/entities/cash_transaction.dart';

/// Picker categorie operative per il form movimenti (feature transactions).
class TransactionCategoryPicker extends ConsumerWidget {
  const TransactionCategoryPicker({
    super.key,
    required this.companyId,
    required this.kind,
    required this.selectedCategoryId,
    this.keptArchivedCategory,
    required this.canEdit,
    required this.onSelected,
  });

  /// Sentinel: PopupMenuButton non invoca onSelected se value è null.
  static const _noneSentinel = '';

  final String companyId;
  final TransactionKind kind;
  final String? selectedCategoryId;

  /// Categoria archiviata già assegnata al movimento (edit); può essere mantenuta.
  final TransactionCategory? keptArchivedCategory;
  final bool canEdit;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final categoriesAsync = ref.watch(categoriesProvider(companyId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.transactionCategoryLabel, style: theme.textTheme.titleSmall),
        const SizedBox(height: AppUiConstants.spacingSmall),
        categoriesAsync.when(
          loading: () => Text(l10n.transactionCategoriesLoading),
          error: (_, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.transactionCategoriesLoadError,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: AppUiConstants.spacingSmall),
              TextButton(
                key: const Key('transaction-categories-retry'),
                onPressed: () => ref.invalidate(categoriesProvider(companyId)),
                child: Text(l10n.transactionsRetry),
              ),
            ],
          ),
          data: (categories) {
            final activeForKind =
                categories.where((c) => c.kind == kind && c.isActive).toList()
                  ..sort(
                    (a, b) =>
                        a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                  );

            final archivedOption =
                keptArchivedCategory != null &&
                    keptArchivedCategory!.kind == kind &&
                    !keptArchivedCategory!.isActive
                ? keptArchivedCategory
                : null;

            if (activeForKind.isEmpty && archivedOption == null) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.transactionCategoryNone),
                  const SizedBox(height: AppUiConstants.spacingSmall),
                  Text(
                    l10n.transactionCategoriesEmpty,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  TextButton(
                    key: const Key('transaction-categories-manage-link'),
                    onPressed: () =>
                        context.push(RoutePaths.settingsCategories),
                    child: Text(l10n.transactionCategoriesManageLink),
                  ),
                ],
              );
            }

            final selectedLabel = _labelForSelection(
              l10n: l10n,
              selectedCategoryId: selectedCategoryId,
              activeForKind: activeForKind,
              archivedOption: archivedOption,
            );

            return InputDecorator(
              decoration: const InputDecoration(border: OutlineInputBorder()),
              child: PopupMenuButton<String>(
                key: const Key('transaction-category-menu'),
                enabled: canEdit,
                onSelected: (value) =>
                    onSelected(value == _noneSentinel ? null : value),
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    value: _noneSentinel,
                    child: Text(l10n.transactionCategoryNone),
                  ),
                  if (archivedOption != null)
                    PopupMenuItem<String>(
                      value: archivedOption.id,
                      child: Text(
                        '${archivedOption.name} '
                        '(${l10n.transactionCategoryArchived})',
                      ),
                    ),
                  ...activeForKind.map(
                    (category) => PopupMenuItem<String>(
                      value: category.id,
                      child: Text(category.name),
                    ),
                  ),
                ],
                child: Row(
                  children: [
                    Expanded(child: Text(selectedLabel)),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  static String _labelForSelection({
    required AppLocalizations l10n,
    required String? selectedCategoryId,
    required List<TransactionCategory> activeForKind,
    required TransactionCategory? archivedOption,
  }) {
    if (selectedCategoryId == null) {
      return l10n.transactionCategoryNone;
    }
    for (final category in activeForKind) {
      if (category.id == selectedCategoryId) {
        return category.name;
      }
    }
    if (archivedOption != null && archivedOption.id == selectedCategoryId) {
      return '${archivedOption.name} (${l10n.transactionCategoryArchived})';
    }
    return l10n.transactionCategoryNone;
  }
}
