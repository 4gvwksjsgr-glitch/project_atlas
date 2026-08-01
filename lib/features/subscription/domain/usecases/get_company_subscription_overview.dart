import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../entities/company_subscription_overview.dart';
import '../repositories/subscription_repository.dart';

class GetCompanySubscriptionOverview {
  const GetCompanySubscriptionOverview(this._repository);

  final SubscriptionRepository _repository;

  Future<Result<CompanySubscriptionOverview>> call({
    required String companyId,
  }) {
    final normalized = companyId.trim();
    if (normalized.isEmpty) {
      return Future.value(
        const Error(ValidationFailure('Azienda non valida.')),
      );
    }
    return _repository.getCompanySubscriptionOverview(companyId: normalized);
  }
}
