import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/di/providers.dart';
import '../../data/datasource/subscription_remote_datasource.dart';
import '../../data/repositories/subscription_repository_impl.dart';
import '../../data/services/url_launcher_billing_checkout_url_launcher.dart';
import '../../domain/entities/company_subscription_overview.dart';
import '../../domain/repositories/subscription_repository.dart';
import '../../domain/services/billing_checkout_url_launcher.dart';
import '../../domain/usecases/activate_company_premium_trial.dart';
import '../../domain/usecases/create_company_premium_checkout.dart';
import '../../domain/usecases/get_company_subscription_overview.dart';

final subscriptionRemoteDataSourceProvider =
    Provider<SubscriptionRemoteDataSource>((ref) {
      return SubscriptionRemoteDataSource(ref.watch(supabaseClientProvider));
    });

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  return SubscriptionRepositoryImpl(
    ref.watch(subscriptionRemoteDataSourceProvider),
  );
});

final getCompanySubscriptionOverviewUseCaseProvider =
    Provider<GetCompanySubscriptionOverview>((ref) {
      return GetCompanySubscriptionOverview(
        ref.watch(subscriptionRepositoryProvider),
      );
    });

final activateCompanyPremiumTrialUseCaseProvider =
    Provider<ActivateCompanyPremiumTrial>((ref) {
      return ActivateCompanyPremiumTrial(
        ref.watch(subscriptionRepositoryProvider),
      );
    });

final createCompanyPremiumCheckoutUseCaseProvider =
    Provider<CreateCompanyPremiumCheckout>((ref) {
      return CreateCompanyPremiumCheckout(
        ref.watch(subscriptionRepositoryProvider),
      );
    });

final billingCheckoutUrlLauncherProvider = Provider<BillingCheckoutUrlLauncher>(
  (ref) {
    return UrlLauncherBillingCheckoutUrlLauncher();
  },
);

/// Generatore UUID v4 per Idempotency-Key (override nei test).
final billingCheckoutIdempotencyKeyGeneratorProvider =
    Provider<String Function()>((ref) {
      const uuid = Uuid();
      return uuid.v4;
    });

/// Produzione: checkout Premium supportato su Web, Android e iOS.
/// Desktop (Windows/macOS/Linux) resta bloccato.
final isBillingCheckoutSupportedPlatformProvider = Provider<bool>((ref) {
  if (kIsWeb) {
    return true;
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };
});

/// @nodoc Backward-compatible name used in older tests; prefer
/// [isBillingCheckoutSupportedPlatformProvider].
@Deprecated('Use isBillingCheckoutSupportedPlatformProvider')
final isBillingCheckoutWebPlatformProvider =
    isBillingCheckoutSupportedPlatformProvider;

/// Overview piano keyed per company: al cambio companyId nuova query.
final companySubscriptionOverviewProvider = FutureProvider.autoDispose
    .family<CompanySubscriptionOverview, String>((ref, companyId) async {
      final result = await ref
          .read(getCompanySubscriptionOverviewUseCaseProvider)
          .call(companyId: companyId);

      return result.when(
        success: (overview) => overview,
        error: (failure) => throw StateError(failure.message),
      );
    });
