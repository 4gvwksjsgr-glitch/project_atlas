import '../../../../core/utils/result.dart';
import '../entities/company_subscription_overview.dart';

abstract class SubscriptionRepository {
  Future<Result<CompanySubscriptionOverview>> getCompanySubscriptionOverview({
    required String companyId,
  });
}
