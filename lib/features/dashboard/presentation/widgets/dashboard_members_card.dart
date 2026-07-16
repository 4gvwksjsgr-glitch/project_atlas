import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../providers/dashboard_providers.dart';

class DashboardMembersCard extends ConsumerWidget {
  const DashboardMembersCard({required this.companyId, super.key});

  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final summaryAsync = ref.watch(dashboardSummaryProvider(companyId));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppUiConstants.spacingLarge),
        child: summaryAsync.when(
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
                  l10n.dashboardMembersLoading,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          error: (error, _) {
            final message = error is StateError
                ? error.message
                : l10n.dashboardMembersError;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.dashboardMembersTitle,
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
                      ref.invalidate(dashboardSummaryProvider(companyId)),
                  child: Text(l10n.dashboardMembersRetry),
                ),
              ],
            );
          },
          data: (summary) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.dashboardMembersTitle,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppUiConstants.spacingSmall),
              Text(
                l10n.dashboardMemberCount(summary.memberCount),
                style: theme.textTheme.headlineSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
