import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/result.dart';
import '../../domain/entities/company.dart';
import '../controllers/active_company_controller.dart';
import '../providers/company_providers.dart';

enum CompanyActionStatus { idle, loading, success, error }

class CompanyOnboardingControllerState {
  const CompanyOnboardingControllerState({
    this.actionStatus = CompanyActionStatus.idle,
    this.createdCompany,
    this.errorMessage,
  });

  final CompanyActionStatus actionStatus;
  final Company? createdCompany;
  final String? errorMessage;

  bool get isLoading => actionStatus == CompanyActionStatus.loading;

  CompanyOnboardingControllerState copyWith({
    CompanyActionStatus? actionStatus,
    Company? createdCompany,
    String? errorMessage,
    bool clearError = false,
    bool clearCompany = false,
  }) {
    return CompanyOnboardingControllerState(
      actionStatus: actionStatus ?? this.actionStatus,
      createdCompany: clearCompany
          ? null
          : createdCompany ?? this.createdCompany,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class CompanyOnboardingController
    extends Notifier<CompanyOnboardingControllerState> {
  @override
  CompanyOnboardingControllerState build() {
    return const CompanyOnboardingControllerState();
  }

  Future<void> createCompany({
    required String name,
    required String slug,
  }) async {
    if (state.isLoading) {
      return;
    }

    state = state.copyWith(
      actionStatus: CompanyActionStatus.loading,
      clearError: true,
      clearCompany: true,
    );

    try {
      final result = await ref
          .read(createCompanyUseCaseProvider)
          .call(name: name, slug: slug);

      switch (result) {
        case Success(:final value):
          try {
            ref.invalidate(userCompaniesProvider);
            await ref.read(userCompaniesProvider.future);
            await ref
                .read(activeCompanyControllerProvider.notifier)
                .selectByCompanyId(value.id);
            state = state.copyWith(
              actionStatus: CompanyActionStatus.success,
              createdCompany: value,
              clearError: true,
            );
          } catch (error) {
            final message = error is StateError
                ? error.message
                : 'Caricamento aziende non riuscito. Riprova.';
            state = state.copyWith(
              actionStatus: CompanyActionStatus.error,
              errorMessage: message,
              clearCompany: true,
            );
          }
        case Error(:final failure):
          state = state.copyWith(
            actionStatus: CompanyActionStatus.error,
            errorMessage: failure.message,
            clearCompany: true,
          );
      }
    } catch (_) {
      state = state.copyWith(
        actionStatus: CompanyActionStatus.error,
        errorMessage: 'Creazione azienda non riuscita. Riprova.',
        clearCompany: true,
      );
    } finally {
      if (state.actionStatus == CompanyActionStatus.loading) {
        state = state.copyWith(
          actionStatus: CompanyActionStatus.error,
          errorMessage: 'Operazione non completata. Riprova.',
          clearCompany: true,
        );
      }
    }
  }

  void resetActionState() {
    state = const CompanyOnboardingControllerState();
  }
}

final companyOnboardingControllerProvider =
    NotifierProvider<
      CompanyOnboardingController,
      CompanyOnboardingControllerState
    >(CompanyOnboardingController.new);
