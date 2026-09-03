import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../../../companies/presentation/controllers/company_onboarding_controller.dart';
import '../../domain/services/sandbox_billing_checkout_url.dart';
import '../providers/subscription_providers.dart';

class CreatePremiumCheckoutState {
  const CreatePremiumCheckoutState({
    this.actionStatus = CompanyActionStatus.idle,
    this.errorMessage,
  });

  final CompanyActionStatus actionStatus;
  final String? errorMessage;

  bool get isLoading => actionStatus == CompanyActionStatus.loading;

  CreatePremiumCheckoutState copyWith({
    CompanyActionStatus? actionStatus,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CreatePremiumCheckoutState(
      actionStatus: actionStatus ?? this.actionStatus,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class CreatePremiumCheckoutController
    extends AutoDisposeFamilyNotifier<CreatePremiumCheckoutState, String> {
  String? _inFlightIdempotencyKey;

  @override
  CreatePremiumCheckoutState build(String companyId) {
    return const CreatePremiumCheckoutState();
  }

  /// Avvia una creazione checkout. Un solo invoke per tentativo in-flight.
  Future<bool> startCheckout() async {
    if (state.isLoading) {
      return false;
    }

    final idempotencyKey = _inFlightIdempotencyKey ??= ref.read(
      billingCheckoutIdempotencyKeyGeneratorProvider,
    )();

    state = state.copyWith(
      actionStatus: CompanyActionStatus.loading,
      clearError: true,
    );

    final result = await ref
        .read(createCompanyPremiumCheckoutUseCaseProvider)
        .call(companyId: arg, idempotencyKey: idempotencyKey);

    switch (result) {
      case Error(:final failure):
        _clearAttempt();
        state = state.copyWith(
          actionStatus: CompanyActionStatus.error,
          errorMessage: failure.message,
        );
        return false;
      case Success(:final value):
        final session = value;
        final urlResult = SandboxBillingCheckoutUrl.validate(
          session.checkoutUrl,
        );
        switch (urlResult) {
          case Error(:final failure):
            _clearAttempt();
            state = state.copyWith(
              actionStatus: CompanyActionStatus.error,
              errorMessage: failure.message,
            );
            return false;
          case Success(:final value):
            final checkoutUri = value;
            try {
              final opened = await ref
                  .read(billingCheckoutUrlLauncherProvider)
                  .launch(checkoutUri);
              if (!opened) {
                _clearAttempt();
                state = state.copyWith(
                  actionStatus: CompanyActionStatus.error,
                  errorMessage: const AtlasCheckoutOpenFailure().message,
                );
                return false;
              }
            } catch (_) {
              _clearAttempt();
              state = state.copyWith(
                actionStatus: CompanyActionStatus.error,
                errorMessage: const AtlasCheckoutOpenFailure().message,
              );
              return false;
            }

            _clearAttempt();
            state = state.copyWith(
              actionStatus: CompanyActionStatus.success,
              clearError: true,
            );
            return true;
        }
    }
  }

  void clearFeedback() {
    state = const CreatePremiumCheckoutState();
  }

  void _clearAttempt() {
    _inFlightIdempotencyKey = null;
  }

  /// Solo per test: chiave corrente del tentativo in-flight (null se idle).
  @visibleForTesting
  String? get debugInFlightIdempotencyKey => _inFlightIdempotencyKey;
}

final createPremiumCheckoutControllerProvider = NotifierProvider.autoDispose
    .family<
      CreatePremiumCheckoutController,
      CreatePremiumCheckoutState,
      String
    >(CreatePremiumCheckoutController.new);
