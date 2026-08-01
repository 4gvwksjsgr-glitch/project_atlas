import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../../domain/entities/company_subscription_overview.dart';
import '../providers/subscription_providers.dart';

class CompanyPlanCard extends ConsumerWidget {
  const CompanyPlanCard({super.key, required this.companyId});

  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final async = ref.watch(companySubscriptionOverviewProvider(companyId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.subscriptionPlanSectionTitle,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: AppUiConstants.spacingMedium),
        async.when(
          loading: () => Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              l10n.subscriptionLoading,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          error: (error, _) {
            final message = error is StateError
                ? error.message
                : l10n.subscriptionLoadError;
            return Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            );
          },
          data: (overview) => _PlanDetails(overview: overview),
        ),
      ],
    );
  }
}

class _PlanDetails extends StatelessWidget {
  const _PlanDetails({required this.overview});

  final CompanySubscriptionOverview overview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final planTitle = overview.isTrialActive
        ? l10n.subscriptionPlanTrialPremium
        : overview.isEffectivePremium
        ? l10n.subscriptionPlanPremium
        : l10n.subscriptionPlanFree;

    // Limit comes from server effective plan only; null means unlimited.
    // Do not invent "30" for incomplete/unknown payloads.
    final limit = overview.documentMonthlyLimit;
    final limitLabel = limit == null
        ? l10n.subscriptionDocumentsUnlimited
        : l10n.subscriptionDocumentsMonthlyLimit(limit);

    final statusLabel = switch (overview.status) {
      SubscriptionStatus.free => l10n.subscriptionStatusFree,
      SubscriptionStatus.trialing =>
        overview.isTrialActive
            ? l10n.subscriptionStatusTrialing
            : l10n.subscriptionStatusFree,
      SubscriptionStatus.active => l10n.subscriptionStatusActive,
      SubscriptionStatus.unknown => l10n.subscriptionStatusUnknown,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(planTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: AppUiConstants.spacingSmall),
        Text(
          limitLabel,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppUiConstants.spacingSmall),
        Text(
          l10n.subscriptionStatusLabel(statusLabel),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (overview.isTrialActive && overview.trialEndsAt != null) ...[
          const SizedBox(height: AppUiConstants.spacingSmall),
          Text(
            l10n.subscriptionTrialValidUntil(
              DateFormat.yMMMd('it').format(overview.trialEndsAt!.toLocal()),
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: AppUiConstants.spacingMedium),
        Text(
          l10n.subscriptionPlanManagementComingSoon,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
