import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../../../companies/presentation/controllers/active_company_controller.dart';
import '../../domain/entities/cash_transaction.dart';
import '../providers/transaction_providers.dart';
import '../widgets/transaction_filters_bar.dart';
import '../widgets/transaction_list_tile.dart';

/// Clears [FloatingActionButton.extended] + [kFloatingActionButtonMargin]
/// so the last list rows remain reachable above the FAB.
const double _transactionsFabClearance = 96;

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final activeCompany = ref.watch(activeCompanyProvider);

    if (activeCompany == null) {
      return Padding(
        padding: const EdgeInsets.all(AppUiConstants.spacingLarge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.transactionsTitle, style: theme.textTheme.headlineMedium),
            const SizedBox(height: AppUiConstants.spacingMedium),
            Text(
              l10n.transactionsNoActiveCompany,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return TransactionsListBody(
      key: ValueKey(activeCompany.companyId),
      companyId: activeCompany.companyId,
      canManage: activeCompany.role.canManageTransactions,
    );
  }
}

class TransactionsListBody extends ConsumerWidget {
  const TransactionsListBody({
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
    final filters = ref.watch(transactionFiltersProvider(companyId));
    final transactionsAsync = ref.watch(transactionsProvider(companyId));

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(AppUiConstants.spacingLarge),
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.transactionsTitle,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppUiConstants.spacingSmall),
                  Text(
                    l10n.transactionsSubtitle,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (canManage) ...[
                    const SizedBox(height: AppUiConstants.spacingMedium),
                    OutlinedButton.icon(
                      onPressed: () =>
                          context.push(RoutePaths.transactionsImport),
                      icon: const Icon(Icons.upload_file),
                      label: Text(l10n.transactionsImportButton),
                    ),
                  ],
                  const SizedBox(height: AppUiConstants.spacingMedium),
                  // Fuori da async.when: non viene ricreato al refetch (focus ricerca).
                  TransactionFiltersBar(companyId: companyId),
                  const SizedBox(height: AppUiConstants.spacingMedium),
                ],
              ),
            ),
            ...transactionsAsync.when(
              skipLoadingOnReload: true,
              loading: () => [
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              ],
              error: (error, _) {
                final message = error is StateError
                    ? error.message
                    : l10n.transactionsLoadError;
                return [
                  SliverToBoxAdapter(
                    child: Column(
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
                          onPressed: () => ref.invalidate(
                            transactionsProvider(companyId),
                          ),
                          child: Text(l10n.transactionsRetry),
                        ),
                      ],
                    ),
                  ),
                ];
              },
              data: (transactions) {
                if (transactions.isEmpty) {
                  return [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          filters.hasActiveFilters
                              ? l10n.transactionsFilterEmpty
                              : l10n.transactionsEmpty,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    if (canManage)
                      const SliverToBoxAdapter(
                        child: SizedBox(
                          key: Key('transactions-fab-clearance'),
                          height: _transactionsFabClearance,
                        ),
                      ),
                  ];
                }

                return [
                  SliverToBoxAdapter(
                    child: Text(
                      l10n.transactionsResultsCount(transactions.length),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: AppUiConstants.spacingSmall),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index.isOdd) {
                          return const Divider(height: 1);
                        }
                        final itemIndex = index ~/ 2;
                        final transaction = transactions[itemIndex];
                        return TransactionListTile(
                          transaction: transaction,
                          kindLabel:
                              transaction.kind == TransactionKind.income
                              ? l10n.transactionKindIncome
                              : l10n.transactionKindExpense,
                          onTap: () => context.push(
                            RoutePaths.transactionEdit(transaction.id),
                          ),
                        );
                      },
                      childCount: transactions.length * 2 - 1,
                    ),
                  ),
                  if (canManage)
                    const SliverToBoxAdapter(
                      child: SizedBox(
                        key: Key('transactions-fab-clearance'),
                        height: _transactionsFabClearance,
                      ),
                    ),
                ];
              },
            ),
          ],
        ),
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => context.push(RoutePaths.transactionNew),
              icon: const Icon(Icons.add),
              label: Text(l10n.transactionsNewButton),
            )
          : null,
    );
  }
}
