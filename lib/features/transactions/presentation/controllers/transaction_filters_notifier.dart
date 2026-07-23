import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/cash_transaction.dart';
import '../../domain/value_objects/transaction_filters.dart';

/// Filtri della lista movimenti, isolati per `companyId`.
///
/// Al cambio azienda il family key cambia: lo stato riparte da filtri vuoti.
class TransactionFiltersNotifier
    extends AutoDisposeFamilyNotifier<TransactionFilters, String> {
  @override
  TransactionFilters build(String companyId) => const TransactionFilters();

  void setFromDate(DateTime? value) {
    state = value == null
        ? state.copyWith(clearFromDate: true)
        : state.copyWith(fromDate: value);
  }

  void setToDate(DateTime? value) {
    state = value == null
        ? state.copyWith(clearToDate: true)
        : state.copyWith(toDate: value);
  }

  void setKind(TransactionKind? value) {
    state = value == null
        ? state.copyWith(clearKind: true)
        : state.copyWith(kind: value);
  }

  void setClientId(String? value) {
    final trimmed = value?.trim();
    state = (trimmed == null || trimmed.isEmpty)
        ? state.copyWith(clearClientId: true)
        : state.copyWith(clientId: trimmed);
  }

  void setDescriptionQuery(String value) {
    state = state.copyWith(descriptionQuery: value);
  }

  void clear() {
    state = const TransactionFilters();
  }
}

final transactionFiltersProvider = NotifierProvider.autoDispose
    .family<TransactionFiltersNotifier, TransactionFilters, String>(
      TransactionFiltersNotifier.new,
    );
