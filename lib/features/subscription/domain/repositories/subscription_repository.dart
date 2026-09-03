import '../../../../core/utils/result.dart';
import '../entities/company_subscription_overview.dart';
import '../entities/premium_checkout_session.dart';

abstract class SubscriptionRepository {
  Future<Result<CompanySubscriptionOverview>> getCompanySubscriptionOverview({
    required String companyId,
  });

  Future<Result<void>> activateCompanyPremiumTrial({required String companyId});

  Future<Result<PremiumCheckoutSession>> createCompanyPremiumCheckout({
    required String companyId,
    required String idempotencyKey,
  });
}
