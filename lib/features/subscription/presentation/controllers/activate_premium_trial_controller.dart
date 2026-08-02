import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/result.dart';
import '../../../companies/presentation/controllers/company_onboarding_controller.dart';
import '../providers/subscription_providers.dart';

class ActivatePremiumTrialState {
  const ActivatePremiumTrialState({
    this.actionStatus = CompanyActionStatus.idle,
    this.errorMessage,
  });

  final CompanyActionStatus actionStatus;
  final String? errorMessage;

  bool get isLoading => actionStatus == CompanyActionStatus.loading;

  ActivatePremiumTrialState copyWith({
    CompanyActionStatus? actionStatus,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ActivatePremiumTrialState(
      actionStatus: actionStatus ?? this.actionStatus,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class ActivatePremiumTrialController
    extends AutoDisposeFamilyNotifier<ActivatePremiumTrialState, String> {
  @override
  ActivatePremiumTrialState build(String companyId) {
    return const ActivatePremiumTrialState();
  }

  Future<bool> activate() async {
    if (state.isLoading) {
      return false;
    }

    state = state.copyWith(
      actionStatus: CompanyActionStatus.loading,
      clearError: true,
    );

    final result = await ref
        .read(activateCompanyPremiumTrialUseCaseProvider)
        .call(companyId: arg);

    switch (result) {
      case Success():
        ref.invalidate(companySubscriptionOverviewProvider(arg));
        try {
          await ref.read(companySubscriptionOverviewProvider(arg).future);
        } catch (_) {
          // Trial attiva lato server; la card si allinea al prossimo load.
        }
        state = state.copyWith(
          actionStatus: CompanyActionStatus.success,
          clearError: true,
        );
        return true;
      case Error(:final failure):
        state = state.copyWith(
          actionStatus: CompanyActionStatus.error,
          errorMessage: failure.message,
        );
        return false;
    }
  }

  void clearFeedback() {
    state = const ActivatePremiumTrialState();
  }
}

final activatePremiumTrialControllerProvider = NotifierProvider.autoDispose
    .family<ActivatePremiumTrialController, ActivatePremiumTrialState, String>(
      ActivatePremiumTrialController.new,
    );
