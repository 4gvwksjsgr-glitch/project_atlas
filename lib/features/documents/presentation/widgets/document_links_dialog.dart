import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/result.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../../../clients/domain/entities/customer.dart';
import '../../../clients/presentation/providers/customer_providers.dart';
import '../../../transactions/domain/entities/cash_transaction.dart';
import '../../../transactions/domain/value_objects/transaction_filters.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
import '../../domain/entities/company_document.dart';
import '../controllers/document_controllers.dart';

Future<void> showDocumentLinksDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String companyId,
  required CompanyDocument document,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) =>
        _DocumentLinksDialog(companyId: companyId, document: document),
  );
}

class _DocumentLinksDialog extends ConsumerStatefulWidget {
  const _DocumentLinksDialog({required this.companyId, required this.document});

  final String companyId;
  final CompanyDocument document;

  @override
  ConsumerState<_DocumentLinksDialog> createState() =>
      _DocumentLinksDialogState();
}

class _DocumentLinksDialogState extends ConsumerState<_DocumentLinksDialog> {
  late String? _selectedClientId;
  late String? _selectedTransactionId;
  final _clientQuery = TextEditingController();
  final _transactionQuery = TextEditingController();
  Timer? _transactionDebounce;
  List<CashTransaction> _transactions = const [];
  bool _transactionsLoading = true;
  String? _transactionsError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedClientId = widget.document.clientId;
    _selectedTransactionId = widget.document.transactionId;
    _loadTransactions();
  }

  @override
  void dispose() {
    _transactionDebounce?.cancel();
    _clientQuery.dispose();
    _transactionQuery.dispose();
    super.dispose();
  }

  Future<void> _loadTransactions({String query = ''}) async {
    setState(() {
      _transactionsLoading = true;
      _transactionsError = null;
    });
    final result = await ref
        .read(getTransactionsUseCaseProvider)
        .call(
          companyId: widget.companyId,
          filters: TransactionFilters(descriptionQuery: query),
        );
    if (!mounted) {
      return;
    }
    switch (result) {
      case Success(:final value):
        setState(() {
          _transactions = value;
          _transactionsLoading = false;
        });
      case Error(:final failure):
        setState(() {
          _transactionsError = failure.message;
          _transactionsLoading = false;
        });
    }
  }

  void _onTransactionQueryChanged(String value) {
    _transactionDebounce?.cancel();
    _transactionDebounce = Timer(const Duration(milliseconds: 300), () {
      _loadTransactions(query: value.trim());
    });
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    final ok = await ref
        .read(documentMutationControllerProvider(widget.companyId).notifier)
        .updateLinks(
          documentId: widget.document.id,
          clientId: _selectedClientId,
          transactionId: _selectedTransactionId,
        );
    if (!mounted) {
      return;
    }
    final state = ref.read(
      documentMutationControllerProvider(widget.companyId),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? l10n.documentLinksSuccess
              : (state.errorMessage ?? l10n.documentLinksError),
        ),
      ),
    );
    ref
        .read(documentMutationControllerProvider(widget.companyId).notifier)
        .clearFeedback();
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final customersAsync = ref.watch(customersProvider(widget.companyId));
    final clientQuery = _clientQuery.text.trim().toLowerCase();

    return AlertDialog(
      title: Text(l10n.documentManageLinks),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.documentLinksClient,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppUiConstants.spacingSmall),
              TextField(
                key: const Key('document-links-client-search'),
                controller: _clientQuery,
                enabled: !_saving,
                decoration: InputDecoration(
                  labelText: l10n.documentLinksSearchClient,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppUiConstants.spacingSmall),
              customersAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Text(
                  error is StateError ? error.message : l10n.customersLoadError,
                ),
                data: (customers) {
                  final filtered = customers.where((customer) {
                    if (clientQuery.isEmpty) {
                      return true;
                    }
                    return customer.name.toLowerCase().contains(clientQuery);
                  }).toList();
                  return _ClientPickerList(
                    customers: filtered,
                    selectedId: _selectedClientId,
                    enabled: !_saving,
                    onSelect: (id) => setState(() => _selectedClientId = id),
                    noClientLabel: l10n.documentLinksNoClient,
                    emptyLabel: l10n.documentLinksEmptyClients,
                  );
                },
              ),
              const SizedBox(height: AppUiConstants.spacingLarge),
              Text(
                l10n.documentLinksTransaction,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppUiConstants.spacingSmall),
              TextField(
                key: const Key('document-links-transaction-search'),
                controller: _transactionQuery,
                enabled: !_saving,
                decoration: InputDecoration(
                  labelText: l10n.documentLinksSearchTransaction,
                  border: const OutlineInputBorder(),
                ),
                onChanged: _onTransactionQueryChanged,
              ),
              const SizedBox(height: AppUiConstants.spacingSmall),
              if (_transactionsLoading)
                const Center(child: CircularProgressIndicator())
              else if (_transactionsError != null)
                Text(_transactionsError!)
              else
                _TransactionPickerList(
                  transactions: _transactions,
                  selectedId: _selectedTransactionId,
                  enabled: !_saving,
                  onSelect: (id) => setState(() => _selectedTransactionId = id),
                  noTransactionLabel: l10n.documentLinksNoTransaction,
                  emptyLabel: l10n.documentLinksEmptyTransactions,
                  incomeLabel: l10n.transactionKindIncome,
                  expenseLabel: l10n.transactionKindExpense,
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('document-links-save'),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.documentLinksSave),
        ),
      ],
    );
  }
}

class _ClientPickerList extends StatelessWidget {
  const _ClientPickerList({
    required this.customers,
    required this.selectedId,
    required this.enabled,
    required this.onSelect,
    required this.noClientLabel,
    required this.emptyLabel,
  });

  final List<Customer> customers;
  final String? selectedId;
  final bool enabled;
  final ValueChanged<String?> onSelect;
  final String noClientLabel;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SelectableRow(
          key: const Key('document-links-no-client'),
          title: noClientLabel,
          selected: selectedId == null,
          enabled: enabled,
          onTap: () => onSelect(null),
        ),
        if (customers.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppUiConstants.spacingSmall),
            child: Text(emptyLabel),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: customers.length,
              itemBuilder: (context, index) {
                final customer = customers[index];
                return _SelectableRow(
                  key: Key('document-links-client-${customer.id}'),
                  title: customer.name,
                  selected: selectedId == customer.id,
                  enabled: enabled,
                  onTap: () => onSelect(customer.id),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _TransactionPickerList extends StatelessWidget {
  const _TransactionPickerList({
    required this.transactions,
    required this.selectedId,
    required this.enabled,
    required this.onSelect,
    required this.noTransactionLabel,
    required this.emptyLabel,
    required this.incomeLabel,
    required this.expenseLabel,
  });

  final List<CashTransaction> transactions;
  final String? selectedId;
  final bool enabled;
  final ValueChanged<String?> onSelect;
  final String noTransactionLabel;
  final String emptyLabel;
  final String incomeLabel;
  final String expenseLabel;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat.yMMMd('it');
    return Column(
      children: [
        _SelectableRow(
          key: const Key('document-links-no-transaction'),
          title: noTransactionLabel,
          selected: selectedId == null,
          enabled: enabled,
          onTap: () => onSelect(null),
        ),
        if (transactions.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppUiConstants.spacingSmall),
            child: Text(emptyLabel),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: transactions.length,
              itemBuilder: (context, index) {
                final tx = transactions[index];
                final kindLabel = tx.kind == TransactionKind.income
                    ? incomeLabel
                    : expenseLabel;
                final subtitle =
                    '${dateFormat.format(tx.occurredOn)} · '
                    '${tx.amount.formatEuro()} € · $kindLabel';
                return _SelectableRow(
                  key: Key('document-links-transaction-${tx.id}'),
                  title: tx.description,
                  subtitle: subtitle,
                  selected: selectedId == tx.id,
                  enabled: enabled,
                  onTap: () => onSelect(tx.id),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _SelectableRow extends StatelessWidget {
  const _SelectableRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      enabled: enabled,
      selected: selected,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: Icon(
        selected ? Icons.check_circle : Icons.circle_outlined,
        size: 20,
      ),
      onTap: enabled ? onTap : null,
    );
  }
}
