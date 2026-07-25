import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/result.dart';
import '../../../companies/presentation/controllers/company_onboarding_controller.dart';
import '../../../dashboard/presentation/providers/dashboard_cash_providers.dart';
import '../../domain/entities/cash_transaction.dart';
import '../../domain/value_objects/money_amount.dart';
import '../providers/transaction_providers.dart';

class TransactionFormControllerState {
  const TransactionFormControllerState({
    this.actionStatus = CompanyActionStatus.idle,
    this.savedTransaction,
    this.errorMessage,
  });

  final CompanyActionStatus actionStatus;
  final CashTransaction? savedTransaction;
  final String? errorMessage;

  bool get isLoading => actionStatus == CompanyActionStatus.loading;

  TransactionFormControllerState copyWith({
    CompanyActionStatus? actionStatus,
    CashTransaction? savedTransaction,
    String? errorMessage,
    bool clearError = false,
    bool clearTransaction = false,
  }) {
    return TransactionFormControllerState(
      actionStatus: actionStatus ?? this.actionStatus,
      savedTransaction: clearTransaction
          ? null
          : savedTransaction ?? this.savedTransaction,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

/// Chiave form: companyId + transactionId (o `new` per creazione).
typedef TransactionFormKey = ({String companyId, String transactionId});

class TransactionFormController
    extends
        AutoDisposeFamilyNotifier<
          TransactionFormControllerState,
          TransactionFormKey
        > {
  @override
  TransactionFormControllerState build(TransactionFormKey arg) {
    return const TransactionFormControllerState();
  }

  bool get isCreate => arg.transactionId == 'new';

  Future<void> save({
    String? clientId,
    String? categoryId,
    required TransactionKind kind,
    required MoneyAmount amount,
    required DateTime occurredOn,
    required String description,
    String? notes,
  }) async {
    if (state.isLoading) {
      return;
    }

    state = state.copyWith(
      actionStatus: CompanyActionStatus.loading,
      clearError: true,
      clearTransaction: true,
    );

    try {
      final Result<CashTransaction> result;
      if (isCreate) {
        result = await ref
            .read(createTransactionUseCaseProvider)
            .call(
              companyId: arg.companyId,
              clientId: clientId,
              categoryId: categoryId,
              kind: kind,
              amount: amount,
              occurredOn: occurredOn,
              description: description,
              notes: notes,
            );
      } else {
        result = await ref
            .read(updateTransactionUseCaseProvider)
            .call(
              companyId: arg.companyId,
              transactionId: arg.transactionId,
              clientId: clientId,
              categoryId: categoryId,
              kind: kind,
              amount: amount,
              occurredOn: occurredOn,
              description: description,
              notes: notes,
            );
      }

      switch (result) {
        case Success(:final value):
          ref.invalidate(transactionsProvider(arg.companyId));
          ref.invalidate(dashboardCashSummaryProvider(arg.companyId));
          try {
            await ref.read(transactionsProvider(arg.companyId).future);
          } catch (_) {
            // Form già salvato; la lista si allineerà al prossimo load.
          }
          state = state.copyWith(
            actionStatus: CompanyActionStatus.success,
            savedTransaction: value,
            clearError: true,
          );
        case Error(:final failure):
          state = state.copyWith(
            actionStatus: CompanyActionStatus.error,
            errorMessage: failure.message,
            clearTransaction: true,
          );
      }
    } catch (_) {
      state = state.copyWith(
        actionStatus: CompanyActionStatus.error,
        errorMessage: isCreate
            ? 'Creazione movimento non riuscita. Riprova.'
            : 'Aggiornamento movimento non riuscito. Riprova.',
        clearTransaction: true,
      );
    } finally {
      if (state.actionStatus == CompanyActionStatus.loading) {
        state = state.copyWith(
          actionStatus: CompanyActionStatus.error,
          errorMessage: 'Operazione non completata. Riprova.',
          clearTransaction: true,
        );
      }
    }
  }

  void clearFeedback() {
    state = const TransactionFormControllerState();
  }
}

final transactionFormControllerProvider = NotifierProvider.autoDispose
    .family<
      TransactionFormController,
      TransactionFormControllerState,
      TransactionFormKey
    >(TransactionFormController.new);
