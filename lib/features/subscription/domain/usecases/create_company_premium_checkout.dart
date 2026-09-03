import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../entities/premium_checkout_session.dart';
import '../repositories/subscription_repository.dart';

class CreateCompanyPremiumCheckout {
  const CreateCompanyPremiumCheckout(this._repository);

  final SubscriptionRepository _repository;

  Future<Result<PremiumCheckoutSession>> call({
    required String companyId,
    required String idempotencyKey,
  }) {
    final normalizedCompanyId = companyId.trim();
    if (normalizedCompanyId.isEmpty) {
      return Future.value(const Error(AtlasCompanyIdRequiredFailure()));
    }

    final normalizedKey = idempotencyKey.trim();
    if (normalizedKey.isEmpty) {
      return Future.value(
        const Error(
          ValidationFailure('Chiave di idempotenza checkout non valida.'),
        ),
      );
    }

    return _repository.createCompanyPremiumCheckout(
      companyId: normalizedCompanyId,
      idempotencyKey: normalizedKey,
    );
  }
}
