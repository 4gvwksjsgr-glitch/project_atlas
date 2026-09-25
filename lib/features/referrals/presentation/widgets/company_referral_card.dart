import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/atlas_error_codes.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../../../companies/presentation/controllers/company_onboarding_controller.dart';
import '../../domain/entities/referral_overview.dart';
import '../controllers/referral_overview_controller.dart';
import '../providers/referral_providers.dart';

class CompanyReferralCard extends ConsumerWidget {
  const CompanyReferralCard({super.key, required this.companyId});

  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final async = ref.watch(referralOverviewProvider(companyId));
    final actionState = ref.watch(referralOverviewControllerProvider(companyId));

    ref.listen(referralOverviewControllerProvider(companyId), (previous, next) {
      if (next.actionStatus == CompanyActionStatus.error &&
          next.errorMessage != null &&
          next.errorMessage != previous?.errorMessage) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.errorMessage!)));
        ref
            .read(referralOverviewControllerProvider(companyId).notifier)
            .clearFeedback();
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.referralSectionTitle, style: theme.textTheme.titleLarge),
        const SizedBox(height: AppUiConstants.spacingMedium),
        async.when(
          loading: () => Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              l10n.referralLoading,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          error: (error, _) {
            final message = error is StateError
                ? error.message
                : l10n.referralLoadError;
            return Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            );
          },
          data: (overview) => _ReferralDetails(
            companyId: companyId,
            overview: overview,
            isActionLoading: actionState.isLoading,
          ),
        ),
      ],
    );
  }
}

class _ReferralDetails extends ConsumerStatefulWidget {
  const _ReferralDetails({
    required this.companyId,
    required this.overview,
    required this.isActionLoading,
  });

  final String companyId;
  final ReferralOverview overview;
  final bool isActionLoading;

  @override
  ConsumerState<_ReferralDetails> createState() => _ReferralDetailsState();
}

class _ReferralDetailsState extends ConsumerState<_ReferralDetails> {
  var _ensureRequested = false;

  @override
  void initState() {
    super.initState();
    _maybeEnsureLink();
  }

  @override
  void didUpdateWidget(covariant _ReferralDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.overview.code != widget.overview.code ||
        oldWidget.overview.isOwner != widget.overview.isOwner) {
      _ensureRequested = false;
      _maybeEnsureLink();
    }
  }

  void _maybeEnsureLink() {
    if (_ensureRequested ||
        !widget.overview.isOwner ||
        widget.overview.code != null) {
      return;
    }
    _ensureRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref
          .read(referralOverviewControllerProvider(widget.companyId).notifier)
          .ensureLink();
    });
  }

  String _referralUrl(String code) {
    final base = ref.read(referralAppBaseUrlProvider).replaceAll(RegExp(r'/$'), '');
    return '$base/ref/$code';
  }

  Future<void> _copyLink(String url) async {
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.referralLinkCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final overview = widget.overview;
    final code = overview.code;
    final url = code == null ? null : _referralUrl(code);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.referralProgressCount(
            overview.rewardedCount,
            overview.maxRewards,
          ),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AppUiConstants.spacingSmall),
        Text(
          l10n.referralPremiumMonthsEarned(overview.earnedRedemptionMonths),
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (overview.isOwner) ...[
          _RedemptionStatus(overview: overview),
          if (overview.canRetryRedemption) ...[
            const SizedBox(height: AppUiConstants.spacingSmall),
            OutlinedButton(
              onPressed: widget.isActionLoading
                  ? null
                  : () async {
                      await ref
                          .read(
                            referralOverviewControllerProvider(
                              widget.companyId,
                            ).notifier,
                          )
                          .retryRedemption();
                    },
              child: Text(l10n.referralRedemptionRetry),
            ),
          ],
          const SizedBox(height: AppUiConstants.spacingMedium),
          if (url != null) ...[
            Text(
              l10n.referralLinkLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppUiConstants.spacingSmall),
            SelectableText(url, style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppUiConstants.spacingMedium),
            Wrap(
              spacing: AppUiConstants.spacingSmall,
              runSpacing: AppUiConstants.spacingSmall,
              children: [
                OutlinedButton(
                  onPressed: widget.isActionLoading
                      ? null
                      : () => _copyLink(url),
                  child: Text(l10n.referralCopyLink),
                ),
                OutlinedButton(
                  onPressed: widget.isActionLoading
                      ? null
                      : () async {
                          await ref
                              .read(
                                referralOverviewControllerProvider(
                                  widget.companyId,
                                ).notifier,
                              )
                              .regenerateLink();
                        },
                  child: widget.isActionLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.referralRegenerateLink),
                ),
              ],
            ),
          ] else if (widget.isActionLoading) ...[
            Text(
              l10n.referralLoading,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (overview.items.isNotEmpty) ...[
            const SizedBox(height: AppUiConstants.spacingLarge),
            Text(
              l10n.referralHistoryTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppUiConstants.spacingSmall),
            for (final item in overview.items) ...[
              _HistoryRow(item: item),
              const SizedBox(height: AppUiConstants.spacingSmall),
            ],
          ],
        ],
      ],
    );
  }
}

/// Owner-only redemption lines; never shows provider/operation ids or raw errors.
class _RedemptionStatus extends StatelessWidget {
  const _RedemptionStatus({required this.overview});

  static const _inFlightStatuses = {
    'claimed',
    'previewing',
    'ready_to_apply',
    'provider_accepted',
    'needs_reconcile',
  };

  final ReferralOverview overview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = overview.openOperationStatus;
    final lines = <String>[
      if (overview.redeemedRedemptionMonths > 0)
        l10n.referralRedemptionRedeemed(overview.redeemedRedemptionMonths),
      if (status == 'retryable_failed')
        l10n.referralRedemptionRetryableFailed
      else if (overview.applyingRedemptionMonths > 0 ||
          _inFlightStatuses.contains(status))
        l10n.referralRedemptionApplying,
      if (overview.pendingRedemptionMonths > 0)
        l10n.referralRedemptionPendingAvailable(
          overview.pendingRedemptionMonths,
        ),
    ];

    if (status == null && overview.pendingRedemptionMonths > 0) {
      final blocked = _blockMessage(l10n, overview.redemptionBlockReason);
      if (blocked != null) {
        lines.add(blocked);
      }
    }

    if (lines.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppUiConstants.spacingSmall),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Text(
              line,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  static String? _blockMessage(AppLocalizations l10n, String? reason) {
    return switch (reason) {
      null || AtlasErrorCodes.referralNoPendingRewards => null,
      AtlasErrorCodes.referralProviderUnlinked ||
      AtlasErrorCodes.referralProviderNotActive =>
        l10n.referralRedemptionBlockedInactive,
      AtlasErrorCodes.referralProviderTrialing =>
        l10n.referralRedemptionBlockedTrial,
      AtlasErrorCodes.referralProviderPastDue =>
        l10n.referralRedemptionBlockedPastDue,
      AtlasErrorCodes.referralScheduledCancel =>
        l10n.referralRedemptionBlockedScheduledCancel,
      AtlasErrorCodes.referralProviderCanceled =>
        l10n.referralRedemptionBlockedCanceled,
      AtlasErrorCodes.referralNearRenewal =>
        l10n.referralRedemptionBlockedNearRenewal,
      AtlasErrorCodes.referralRedemptionDisabled =>
        l10n.referralRedemptionDisabled,
      _ => l10n.referralRedemptionDelayed,
    };
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.item});

  final ReferralHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final date = DateFormat.yMMMd('it').format(item.claimedAt.toLocal());
    final statusLabel = switch (item.status) {
      ReferralItemStatus.claimed => l10n.referralStatusClaimed,
      ReferralItemStatus.rewarded => l10n.referralStatusRewarded,
      ReferralItemStatus.notRewardedLimitReached =>
        l10n.referralStatusLimitReached,
      ReferralItemStatus.unknown => l10n.referralStatusUnknown,
    };

    return Text(
      '${l10n.referralFriendLabel} · $date · $statusLabel',
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
