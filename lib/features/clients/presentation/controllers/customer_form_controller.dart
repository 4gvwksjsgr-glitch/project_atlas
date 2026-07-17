import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/result.dart';
import '../../../companies/presentation/controllers/company_onboarding_controller.dart';
import '../../domain/entities/customer.dart';
import '../providers/customer_providers.dart';

class CustomerFormControllerState {
  const CustomerFormControllerState({
    this.actionStatus = CompanyActionStatus.idle,
    this.savedCustomer,
    this.errorMessage,
  });

  final CompanyActionStatus actionStatus;
  final Customer? savedCustomer;
  final String? errorMessage;

  bool get isLoading => actionStatus == CompanyActionStatus.loading;

  CustomerFormControllerState copyWith({
    CompanyActionStatus? actionStatus,
    Customer? savedCustomer,
    String? errorMessage,
    bool clearError = false,
    bool clearCustomer = false,
  }) {
    return CustomerFormControllerState(
      actionStatus: actionStatus ?? this.actionStatus,
      savedCustomer: clearCustomer ? null : savedCustomer ?? this.savedCustomer,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

/// Chiave form: companyId + customerId (o `new` per creazione).
typedef CustomerFormKey = ({String companyId, String customerId});

class CustomerFormController
    extends
        AutoDisposeFamilyNotifier<
          CustomerFormControllerState,
          CustomerFormKey
        > {
  @override
  CustomerFormControllerState build(CustomerFormKey arg) {
    return const CustomerFormControllerState();
  }

  bool get isCreate => arg.customerId == 'new';

  Future<void> save({
    required String name,
    String? email,
    String? phone,
    String? notes,
  }) async {
    if (state.isLoading) {
      return;
    }

    state = state.copyWith(
      actionStatus: CompanyActionStatus.loading,
      clearError: true,
      clearCustomer: true,
    );

    try {
      final Result<Customer> result;
      if (isCreate) {
        result = await ref
            .read(createCustomerUseCaseProvider)
            .call(
              companyId: arg.companyId,
              name: name,
              email: email,
              phone: phone,
              notes: notes,
            );
      } else {
        result = await ref
            .read(updateCustomerUseCaseProvider)
            .call(
              companyId: arg.companyId,
              customerId: arg.customerId,
              name: name,
              email: email,
              phone: phone,
              notes: notes,
            );
      }

      switch (result) {
        case Success(:final value):
          ref.invalidate(customersProvider(arg.companyId));
          try {
            await ref.read(customersProvider(arg.companyId).future);
          } catch (_) {
            // Form già salvato; la lista si allineerà al prossimo load.
          }
          state = state.copyWith(
            actionStatus: CompanyActionStatus.success,
            savedCustomer: value,
            clearError: true,
          );
        case Error(:final failure):
          state = state.copyWith(
            actionStatus: CompanyActionStatus.error,
            errorMessage: failure.message,
            clearCustomer: true,
          );
      }
    } catch (_) {
      state = state.copyWith(
        actionStatus: CompanyActionStatus.error,
        errorMessage: isCreate
            ? 'Creazione cliente non riuscita. Riprova.'
            : 'Aggiornamento cliente non riuscito. Riprova.',
        clearCustomer: true,
      );
    } finally {
      if (state.actionStatus == CompanyActionStatus.loading) {
        state = state.copyWith(
          actionStatus: CompanyActionStatus.error,
          errorMessage: 'Operazione non completata. Riprova.',
          clearCustomer: true,
        );
      }
    }
  }

  void clearFeedback() {
    state = const CustomerFormControllerState();
  }
}

final customerFormControllerProvider = NotifierProvider.autoDispose
    .family<
      CustomerFormController,
      CustomerFormControllerState,
      CustomerFormKey
    >(CustomerFormController.new);
