import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../../domain/entities/dashboard_cash_summary.dart';
import '../../domain/value_objects/money_total.dart';
import '../providers/dashboard_cash_providers.dart';

class DashboardCashCard extends ConsumerWidget {
  const DashboardCashCard({required this.companyId, super.key});

  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cashAsync = ref.watch(dashboardCashSummaryProvider(companyId));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppUiConstants.spacingLarge),
        child: cashAsync.when(
          loading: () => Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppUiConstants.spacingMedium),
              Expanded(
                child: Text(
                  l10n.dashboardCashLoading,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          error: (error, _) {
            final message = error is StateError
                ? error.message
                : l10n.dashboardCashError;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.dashboardCashTitle,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppUiConstants.spacingSmall),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: AppUiConstants.spacingMedium),
                OutlinedButton(
                  onPressed: () =>
                      ref.invalidate(dashboardCashSummaryProvider(companyId)),
                  child: Text(l10n.dashboardCashRetry),
                ),
              ],
            );
          },
          data: (summary) => _CashSummaryBody(summary: summary),
        ),
      ),
    );
  }
}

class _CashSummaryBody extends StatelessWidget {
  const _CashSummaryBody({required this.summary});

  final DashboardCashSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.dashboardCashTitle, style: theme.textTheme.titleMedium),
        if (summary.hasNoMovements) ...[
          const SizedBox(height: AppUiConstants.spacingSmall),
          Text(
            l10n.dashboardCashEmpty,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: AppUiConstants.spacingMedium),
        Text(l10n.dashboardCashTotalSection, style: theme.textTheme.titleSmall),
        const SizedBox(height: AppUiConstants.spacingSmall),
        _MetricRow(
          label: l10n.dashboardCashIncome,
          value: _euro(summary.totalIncome),
        ),
        _MetricRow(
          label: l10n.dashboardCashExpense,
          value: _euro(summary.totalExpense),
        ),
        _MetricRow(
          label: l10n.dashboardCashBalance,
          value: summary.totalBalance.formatEuroSigned(),
        ),
        _MetricRow(
          label: l10n.dashboardCashMovements,
          value: '${summary.movementCount}',
        ),
        const SizedBox(height: AppUiConstants.spacingMedium),
        Text(l10n.dashboardCashMonthSection, style: theme.textTheme.titleSmall),
        const SizedBox(height: AppUiConstants.spacingSmall),
        _MetricRow(
          label: l10n.dashboardCashIncome,
          value: _euro(summary.monthIncome),
        ),
        _MetricRow(
          label: l10n.dashboardCashExpense,
          value: _euro(summary.monthExpense),
        ),
        _MetricRow(
          label: l10n.dashboardCashBalance,
          value: summary.monthBalance.formatEuroSigned(),
        ),
        _MetricRow(
          label: l10n.dashboardCashMovements,
          value: '${summary.monthMovementCount}',
        ),
        const SizedBox(height: AppUiConstants.spacingMedium),
        TextButton(
          onPressed: () => context.go(RoutePaths.transactions),
          child: Text(l10n.dashboardCashSeeTransactions),
        ),
      ],
    );
  }

  static String _euro(MoneyTotal total) => '${total.formatEuro()} €';
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
