import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../data/datasource/subscription_remote_datasource.dart';
import '../../data/repositories/subscription_repository_impl.dart';
import '../../domain/entities/company_subscription_overview.dart';
import '../../domain/repositories/subscription_repository.dart';
import '../../domain/usecases/activate_company_premium_trial.dart';
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
