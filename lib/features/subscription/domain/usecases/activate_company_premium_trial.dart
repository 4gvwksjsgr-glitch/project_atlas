import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../repositories/subscription_repository.dart';

class ActivateCompanyPremiumTrial {
  const ActivateCompanyPremiumTrial(this._repository);

  final SubscriptionRepository _repository;

  Future<Result<void>> call({required String companyId}) {
    final normalized = companyId.trim();
    if (normalized.isEmpty) {
      return Future.value(const Error(AtlasCompanyIdRequiredFailure()));
    }
    return _repository.activateCompanyPremiumTrial(companyId: normalized);
  }
}
