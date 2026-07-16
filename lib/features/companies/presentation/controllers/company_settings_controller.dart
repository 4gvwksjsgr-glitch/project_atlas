import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/result.dart';
import '../../domain/entities/company.dart';
import '../controllers/active_company_controller.dart';
import '../providers/company_providers.dart';
import 'company_onboarding_controller.dart';

class CompanySettingsControllerState {
  const CompanySettingsControllerState({
    this.actionStatus = CompanyActionStatus.idle,
    this.updatedCompany,
    this.errorMessage,
  });

  final CompanyActionStatus actionStatus;
  final Company? updatedCompany;
  final String? errorMessage;

  bool get isLoading => actionStatus == CompanyActionStatus.loading;

  CompanySettingsControllerState copyWith({
    CompanyActionStatus? actionStatus,
    Company? updatedCompany,
    String? errorMessage,
    bool clearError = false,
    bool clearCompany = false,
  }) {
    return CompanySettingsControllerState(
      actionStatus: actionStatus ?? this.actionStatus,
      updatedCompany: clearCompany
          ? null
          : updatedCompany ?? this.updatedCompany,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class CompanySettingsController
    extends AutoDisposeFamilyNotifier<CompanySettingsControllerState, String> {
  @override
  CompanySettingsControllerState build(String companyId) {
    return const CompanySettingsControllerState();
  }

  Future<void> save({required String name, required String slug}) async {
    if (state.isLoading) {
      return;
    }

    final active = ref.read(activeCompanyProvider);
    if (active == null || active.companyId != arg) {
      state = state.copyWith(
        actionStatus: CompanyActionStatus.error,
        errorMessage: 'Nessuna azienda attiva.',
        clearCompany: true,
      );
      return;
    }

    if (!active.role.canEditCompanyProfile) {
      state = state.copyWith(
        actionStatus: CompanyActionStatus.error,
        errorMessage: 'Non hai i permessi per modificare questa azienda.',
        clearCompany: true,
      );
      return;
    }

    state = state.copyWith(
      actionStatus: CompanyActionStatus.loading,
      clearError: true,
      clearCompany: true,
    );

    try {
      final result = await ref
          .read(updateCompanyUseCaseProvider)
          .call(companyId: arg, name: name, slug: slug);

      switch (result) {
        case Success(:final value):
          ref
              .read(activeCompanyControllerProvider.notifier)
              .applyCompanyProfile(name: value.name, slug: value.slug);

          ref.invalidate(userCompaniesProvider);
          try {
            await ref.read(userCompaniesProvider.future);
          } catch (_) {
            // Contesto già aggiornato; il selector si allineerà al prossimo load.
          }

          state = state.copyWith(
            actionStatus: CompanyActionStatus.success,
            updatedCompany: value,
            clearError: true,
          );
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
        errorMessage: 'Aggiornamento azienda non riuscito. Riprova.',
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

  void clearFeedback() {
    state = const CompanySettingsControllerState();
  }
}

final companySettingsControllerProvider = NotifierProvider.autoDispose
    .family<CompanySettingsController, CompanySettingsControllerState, String>(
      CompanySettingsController.new,
    );
