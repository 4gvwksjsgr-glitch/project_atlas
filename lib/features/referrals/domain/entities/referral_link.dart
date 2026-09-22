/// Active company referral link (owner-managed).
class ReferralLink {
  const ReferralLink({
    required this.companyId,
    required this.code,
    required this.createdAt,
    required this.rewardedCount,
    required this.maxRewards,
  });

  final String companyId;
  final String code;
  final DateTime createdAt;
  final int rewardedCount;
  final int maxRewards;
}
