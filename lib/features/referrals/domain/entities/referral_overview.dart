/// Privacy-safe history row (no email / PII).
enum ReferralItemStatus {
  claimed,
  rewarded,
  notRewardedLimitReached,
  unknown;

  static ReferralItemStatus fromDb(String? value) {
    switch (value) {
      case 'claimed':
        return ReferralItemStatus.claimed;
      case 'rewarded':
        return ReferralItemStatus.rewarded;
      case 'not_rewarded_limit_reached':
        return ReferralItemStatus.notRewardedLimitReached;
      default:
        return ReferralItemStatus.unknown;
    }
  }
}

class ReferralHistoryItem {
  const ReferralHistoryItem({
    required this.referralId,
    required this.status,
    required this.claimedAt,
    this.qualifiedAt,
    required this.label,
  });

  final String referralId;
  final ReferralItemStatus status;
  final DateTime claimedAt;
  final DateTime? qualifiedAt;

  /// Server label; currently always `friend` (shown as "Amico iscritto").
  final String label;
}

class ReferralOverview {
  const ReferralOverview({
    required this.companyId,
    this.code,
    required this.rewardedCount,
    required this.maxRewards,
    required this.pendingRedemptionMonths,
    this.applyingRedemptionMonths = 0,
    this.redeemedRedemptionMonths = 0,
    this.redemptionBlockReason,
    this.openOperationStatus,
    required this.isOwner,
    required this.items,
  });

  /// Open-operation statuses for which the owner may trigger a retry.
  static const retryableOperationStatuses = {'retryable_failed', 'needs_reconcile'};

  /// Transient block reasons (not tied to subscription state) that a retry can clear.
  static const retryableBlockReasons = {
    'ATLAS_REFERRAL_NEAR_RENEWAL',
    'ATLAS_REFERRAL_PREVIEW_NOT_SAFE',
    'ATLAS_REFERRAL_PROVIDER_TIMEOUT_UNKNOWN',
    'ATLAS_REFERRAL_PROVIDER_STATE_CONFLICT',
    'ATLAS_REFERRAL_RECONCILE_REQUIRED',
  };

  final String companyId;

  /// Present only for owners; null for members.
  final String? code;
  final int rewardedCount;
  final int maxRewards;

  /// Months earned and waiting for deferred provider redemption (class B).
  final int pendingRedemptionMonths;

  /// Months claimed by an open redemption operation (provider apply in flight).
  final int applyingRedemptionMonths;

  /// Months confirmed as applied on the provider subscription.
  final int redeemedRedemptionMonths;

  /// Safe `ATLAS_*` classification; owner only (null for members).
  final String? redemptionBlockReason;

  /// Status of the open redemption operation; owner only (null for members).
  final String? openOperationStatus;
  final bool isOwner;
  final List<ReferralHistoryItem> items;

  int get earnedRedemptionMonths =>
      pendingRedemptionMonths +
      applyingRedemptionMonths +
      redeemedRedemptionMonths;

  bool get canRetryRedemption {
    if (!isOwner) {
      return false;
    }
    if (retryableOperationStatuses.contains(openOperationStatus)) {
      return true;
    }
    return openOperationStatus == null &&
        pendingRedemptionMonths > 0 &&
        retryableBlockReasons.contains(redemptionBlockReason);
  }
}

/// Result of [retry_referral_redemption] RPC (no operation id / provider ids).
class RetryReferralRedemptionResult {
  const RetryReferralRedemptionResult({
    required this.outcome,
    this.operationStatus,
    this.errorCode,
    required this.pendingMonths,
    required this.applyingMonths,
    required this.redeemedMonths,
  });

  /// `claimed` | `existing_open` | `blocked` | `no_pending` | `disabled` | `error`.
  final String outcome;
  final String? operationStatus;
  final String? errorCode;
  final int pendingMonths;
  final int applyingMonths;
  final int redeemedMonths;
}

/// Result of [claim_referral] RPC.
class ClaimReferralResult {
  const ClaimReferralResult({
    required this.referralId,
    required this.referringCompanyId,
    required this.status,
    required this.claimedAt,
    required this.alreadyClaimed,
  });

  final String referralId;
  final String referringCompanyId;
  final String status;
  final DateTime claimedAt;
  final bool alreadyClaimed;
}
