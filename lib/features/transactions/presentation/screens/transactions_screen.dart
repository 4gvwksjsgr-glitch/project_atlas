import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../../../companies/presentation/controllers/active_company_controller.dart';
import '../../domain/entities/cash_transaction.dart';
import '../providers/transaction_providers.dart';
import '../widgets/transaction_list_tile.dart';

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
    final transactionsAsync = ref.watch(transactionsProvider(companyId));

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(AppUiConstants.spacingLarge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.transactionsTitle, style: theme.textTheme.headlineMedium),
            const SizedBox(height: AppUiConstants.spacingSmall),
            Text(
              l10n.transactionsSubtitle,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppUiConstants.spacingLarge),
            Expanded(
              child: transactionsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) {
                  final message = error is StateError
                      ? error.message
                      : l10n.transactionsLoadError;
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
                              ref.invalidate(transactionsProvider(companyId)),
                          child: Text(l10n.transactionsRetry),
                        ),
                      ],
                    ),
                  );
                },
                data: (transactions) {
                  if (transactions.isEmpty) {
                    return Center(
                      child: Text(
                        l10n.transactionsEmpty,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: transactions.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final transaction = transactions[index];
                      return TransactionListTile(
                        transaction: transaction,
                        kindLabel: transaction.kind == TransactionKind.income
                            ? l10n.transactionKindIncome
                            : l10n.transactionKindExpense,
                        onTap: () => context.push(
                          RoutePaths.transactionEdit(transaction.id),
                        ),
                      );
                    },
                  );
                },
              ),
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
