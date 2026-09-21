import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/result.dart';
import '../controllers/company_onboarding_controller.dart';
import '../providers/company_providers.dart';

class AcceptInviteControllerState {
  const AcceptInviteControllerState({
    this.actionStatus = CompanyActionStatus.idle,
    this.errorMessage,
  });

  final CompanyActionStatus actionStatus;
  final String? errorMessage;

  bool get isLoading => actionStatus == CompanyActionStatus.loading;
  bool get isSuccess => actionStatus == CompanyActionStatus.success;

  AcceptInviteControllerState copyWith({
    CompanyActionStatus? actionStatus,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AcceptInviteControllerState(
      actionStatus: actionStatus ?? this.actionStatus,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class AcceptInviteController
    extends AutoDisposeNotifier<AcceptInviteControllerState> {
  @override
  AcceptInviteControllerState build() {
    return const AcceptInviteControllerState();
  }

  Future<void> accept(String token) async {
    if (state.isLoading) {
      return;
    }

    state = state.copyWith(
      actionStatus: CompanyActionStatus.loading,
      clearError: true,
    );

    final result = await ref
        .read(acceptCompanyInviteUseCaseProvider)
        .call(token);

    switch (result) {
      case Success():
        state = state.copyWith(
          actionStatus: CompanyActionStatus.success,
          clearError: true,
        );
        ref.invalidate(userCompaniesProvider);
      case Error(:final failure):
        state = state.copyWith(
          actionStatus: CompanyActionStatus.error,
          errorMessage: failure.message,
        );
    }
  }

  void clearFeedback() {
    state = const AcceptInviteControllerState();
  }
}

final acceptInviteControllerProvider =
    NotifierProvider.autoDispose<
      AcceptInviteController,
      AcceptInviteControllerState
    >(AcceptInviteController.new);
