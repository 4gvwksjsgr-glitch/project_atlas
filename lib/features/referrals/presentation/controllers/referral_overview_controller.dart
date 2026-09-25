import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/referral_error_mapper.dart';
import '../../../../core/utils/result.dart';
import '../../../companies/presentation/controllers/company_onboarding_controller.dart';
import '../providers/referral_providers.dart';

class ReferralOverviewControllerState {
  const ReferralOverviewControllerState({
    this.actionStatus = CompanyActionStatus.idle,
    this.errorMessage,
  });

  final CompanyActionStatus actionStatus;
  final String? errorMessage;

  bool get isLoading => actionStatus == CompanyActionStatus.loading;

  ReferralOverviewControllerState copyWith({
    CompanyActionStatus? actionStatus,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ReferralOverviewControllerState(
      actionStatus: actionStatus ?? this.actionStatus,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class ReferralOverviewController
    extends AutoDisposeFamilyNotifier<ReferralOverviewControllerState, String> {
  bool _disposed = false;

  @override
  ReferralOverviewControllerState build(String companyId) {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
    });
    return const ReferralOverviewControllerState();
  }

  /// Ensures an active code exists for owners (no-op if overview already has one).
  Future<bool> ensureLink() async {
    if (state.isLoading) {
      return false;
    }

    state = state.copyWith(
      actionStatus: CompanyActionStatus.loading,
      clearError: true,
    );

    final result = await ref
        .read(referralRepositoryProvider)
        .getOrCreateCompanyReferralLink(companyId: arg);

    switch (result) {
      case Success():
        ref.invalidate(referralOverviewProvider(arg));
        try {
          await ref.read(referralOverviewProvider(arg).future);
        } catch (_) {}
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

  Future<bool> regenerateLink() async {
    if (state.isLoading) {
      return false;
    }

    state = state.copyWith(
      actionStatus: CompanyActionStatus.loading,
      clearError: true,
    );

    final result = await ref
        .read(referralRepositoryProvider)
        .regenerateCompanyReferralLink(companyId: arg);

    switch (result) {
      case Success():
        ref.invalidate(referralOverviewProvider(arg));
        try {
          await ref.read(referralOverviewProvider(arg).future);
        } catch (_) {}
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

  /// Owner-only retry; the server chooses months and dates.
  Future<bool> retryRedemption() async {
    if (state.isLoading) {
      return false;
    }

    state = state.copyWith(
      actionStatus: CompanyActionStatus.loading,
      clearError: true,
    );

    final result = await ref
        .read(referralRepositoryProvider)
        .retryReferralRedemption(companyId: arg);
    if (_disposed) {
      return false;
    }

    switch (result) {
      case Success(value: final data):
        ref.invalidate(referralOverviewProvider(arg));
        try {
          await ref.read(referralOverviewProvider(arg).future);
        } catch (_) {}
        if (_disposed) {
          return false;
        }
        final errorCode = data.errorCode;
        if ((data.outcome == 'disabled' || data.outcome == 'error') &&
            errorCode != null) {
          state = state.copyWith(
            actionStatus: CompanyActionStatus.error,
            errorMessage: ReferralErrorMapper.mapAtlasCode(errorCode).message,
          );
          return false;
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
    state = const ReferralOverviewControllerState();
  }
}

final referralOverviewControllerProvider = NotifierProvider.autoDispose
    .family<
      ReferralOverviewController,
      ReferralOverviewControllerState,
      String
    >(ReferralOverviewController.new);
