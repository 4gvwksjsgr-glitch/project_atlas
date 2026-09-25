import '../../../../core/utils/result.dart';
import '../entities/referral_link.dart';
import '../entities/referral_overview.dart';

abstract class ReferralRepository {
  Future<Result<ReferralLink>> getOrCreateCompanyReferralLink({
    required String companyId,
  });

  Future<Result<ReferralLink>> regenerateCompanyReferralLink({
    required String companyId,
  });

  Future<Result<ClaimReferralResult>> claimReferral({required String code});

  Future<Result<ReferralOverview>> getReferralOverview({
    required String companyId,
  });

  Future<Result<RetryReferralRedemptionResult>> retryReferralRedemption({
    required String companyId,
  });
}
