import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../../../companies/presentation/controllers/company_onboarding_controller.dart';
import '../../domain/entities/company_subscription_overview.dart';
import '../controllers/activate_premium_trial_controller.dart';
import '../controllers/create_premium_checkout_controller.dart';
import '../providers/subscription_providers.dart';

class CompanyPlanCard extends ConsumerWidget {
  const CompanyPlanCard({super.key, required this.companyId});

  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final async = ref.watch(companySubscriptionOverviewProvider(companyId));

    ref.listen(activatePremiumTrialControllerProvider(companyId), (
      previous,
      next,
    ) {
      if (next.actionStatus == CompanyActionStatus.success &&
          previous?.actionStatus != CompanyActionStatus.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.subscriptionTrialActivatedSuccess)),
        );
        ref
            .read(activatePremiumTrialControllerProvider(companyId).notifier)
            .clearFeedback();
      } else if (next.actionStatus == CompanyActionStatus.error &&
          next.errorMessage != null &&
          next.errorMessage != previous?.errorMessage) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.errorMessage!)));
      }
    });

    ref.listen(createPremiumCheckoutControllerProvider(companyId), (
      previous,
      next,
    ) {
      if (next.actionStatus == CompanyActionStatus.error &&
          next.errorMessage != null &&
          next.errorMessage != previous?.errorMessage) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.errorMessage!)));
        ref
            .read(createPremiumCheckoutControllerProvider(companyId).notifier)
            .clearFeedback();
      } else if (next.actionStatus == CompanyActionStatus.success &&
          previous?.actionStatus != CompanyActionStatus.success) {
        ref
            .read(createPremiumCheckoutControllerProvider(companyId).notifier)
            .clearFeedback();
      }
    });

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
          data: (overview) =>
              _PlanDetails(companyId: companyId, overview: overview),
        ),
      ],
    );
  }
}

class _PlanDetails extends ConsumerWidget {
  const _PlanDetails({required this.companyId, required this.overview});

  final String companyId;
  final CompanySubscriptionOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final trialState = ref.watch(
      activatePremiumTrialControllerProvider(companyId),
    );
    final checkoutState = ref.watch(
      createPremiumCheckoutControllerProvider(companyId),
    );
    final isWebCheckoutPlatform = ref.watch(
      isBillingCheckoutWebPlatformProvider,
    );

    final planTitle = overview.isTrialActive
        ? l10n.subscriptionPlanTrialPremium
        : overview.isEffectivePremium
        ? l10n.subscriptionPlanPremium
        : l10n.subscriptionPlanFree;

    final usageLines = _usageLines(l10n);

    final statusLabel = switch (overview.status) {
      SubscriptionStatus.free => l10n.subscriptionStatusFree,
      SubscriptionStatus.trialing =>
        overview.isTrialActive
            ? l10n.subscriptionStatusTrialing
            : l10n.subscriptionStatusFree,
      SubscriptionStatus.active => l10n.subscriptionStatusActive,
      SubscriptionStatus.unknown => l10n.subscriptionStatusUnknown,
    };

    final showTrialCta = overview.canActivateTrial;
    final showCheckoutCta =
        !showTrialCta && isWebCheckoutPlatform && overview.isCheckoutEligible;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(planTitle, style: theme.textTheme.titleMedium),
        if (overview.isTrialActive) ...[
          const SizedBox(height: AppUiConstants.spacingSmall),
          Text(
            l10n.subscriptionTrialActiveLabel,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: AppUiConstants.spacingSmall),
        for (final line in usageLines) ...[
          Text(
            line,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppUiConstants.spacingSmall),
        ],
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
        if (showTrialCta)
          _ActivateTrialButton(
            companyId: companyId,
            isLoading: trialState.isLoading,
          )
        else if (showCheckoutCta)
          _UpgradeToPremiumButton(
            companyId: companyId,
            isLoading: checkoutState.isLoading,
          )
        else
          Text(
            l10n.subscriptionPlanManagementComingSoon,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  List<String> _usageLines(AppLocalizations l10n) {
    if (overview.isUnlimited) {
      final lines = <String>[l10n.subscriptionDocumentsUnlimited];
      if (overview.documentsUsed > 0) {
        lines.add(l10n.subscriptionDocumentsUsedInfo(overview.documentsUsed));
      }
      return lines;
    }

    final limit = overview.documentMonthlyLimit;
    if (limit == null) {
      return [l10n.subscriptionDocumentsUnlimited];
    }

    final lines = <String>[];
    if (overview.isQuotaExhausted) {
      lines.add(l10n.subscriptionQuotaExhausted);
    }
    lines.add(
      l10n.subscriptionDocumentsUsedThisMonth(overview.documentsUsed, limit),
    );
    return lines;
  }
}

class _ActivateTrialButton extends ConsumerWidget {
  const _ActivateTrialButton({
    required this.companyId,
    required this.isLoading,
  });

  final String companyId;
  final bool isLoading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return FilledButton(
      onPressed: isLoading
          ? null
          : () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: Text(l10n.subscriptionActivateTrialDialogTitle),
                    content: Text(l10n.subscriptionActivateTrialDialogBody),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(l10n.subscriptionActivateTrialCancel),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(l10n.subscriptionActivateTrialConfirm),
                      ),
                    ],
                  );
                },
              );
              if (confirmed != true || !context.mounted) {
                return;
              }
              await ref
                  .read(
                    activatePremiumTrialControllerProvider(companyId).notifier,
                  )
                  .activate();
            },
      child: isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(l10n.subscriptionActivateTrialCta),
    );
  }
}

class _UpgradeToPremiumButton extends ConsumerWidget {
  const _UpgradeToPremiumButton({
    required this.companyId,
    required this.isLoading,
  });

  final String companyId;
  final bool isLoading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return FilledButton(
      onPressed: isLoading
          ? null
          : () async {
              await ref
                  .read(
                    createPremiumCheckoutControllerProvider(companyId).notifier,
                  )
                  .startCheckout();
            },
      child: isLoading
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: AppUiConstants.spacingSmall),
                Text(l10n.subscriptionCheckoutPreparing),
              ],
            )
          : Text(l10n.subscriptionUpgradeToPremiumCta),
    );
  }
}
