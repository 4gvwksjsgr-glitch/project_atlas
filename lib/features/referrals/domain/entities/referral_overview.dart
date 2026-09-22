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
    required this.isOwner,
    required this.items,
  });

  final String companyId;

  /// Present only for owners; null for members.
  final String? code;
  final int rewardedCount;
  final int maxRewards;

  /// Months earned and waiting for deferred provider redemption (class B).
  final int pendingRedemptionMonths;
  final bool isOwner;
  final List<ReferralHistoryItem> items;
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
