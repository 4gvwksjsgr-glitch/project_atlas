import 'package:flutter_test/flutter_test.dart';
import 'package:project_atlas/features/referrals/domain/entities/referral_overview.dart';

void main() {
  ReferralOverview overview({
    int pending = 0,
    int applying = 0,
    int redeemed = 0,
    bool isOwner = true,
    String? block,
    String? opStatus,
  }) {
    return ReferralOverview(
      companyId: 'c1',
      rewardedCount: pending + applying + redeemed,
      maxRewards: 5,
      pendingRedemptionMonths: pending,
      applyingRedemptionMonths: applying,
      redeemedRedemptionMonths: redeemed,
      redemptionBlockReason: block,
      openOperationStatus: opStatus,
      isOwner: isOwner,
      items: const [],
    );
  }

  test('owner can retry when op needs_reconcile', () {
    expect(
      overview(opStatus: 'needs_reconcile').canRetryRedemption,
      isTrue,
    );
  });

  test('non-owner cannot retry', () {
    expect(
      overview(isOwner: false, opStatus: 'needs_reconcile').canRetryRedemption,
      isFalse,
    );
  });

  test('earned months sum pending+applying+redeemed', () {
    expect(overview(pending: 1, applying: 1, redeemed: 2).earnedRedemptionMonths, 4);
  });

  test('blocked free does not show retry without open op', () {
    expect(
      overview(
        pending: 2,
        block: 'ATLAS_REFERRAL_PROVIDER_UNLINKED',
      ).canRetryRedemption,
      isFalse,
    );
  });
}
