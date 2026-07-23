import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/constants/app_ui_constants.dart';
import '../../../clients/domain/entities/customer.dart';
import '../../../clients/presentation/providers/customer_providers.dart';
import '../../domain/entities/cash_transaction.dart';
import '../../domain/value_objects/calendar_date.dart';
import '../../domain/value_objects/transaction_filters.dart';
import '../providers/transaction_providers.dart';

class TransactionFiltersBar extends ConsumerStatefulWidget {
  const TransactionFiltersBar({super.key, required this.companyId});

  /// Debounce prima di applicare il filtro descrizione alla query.
  @visibleForTesting
  static const descriptionDebounce = Duration(milliseconds: 300);

  final String companyId;

  @override
  ConsumerState<TransactionFiltersBar> createState() =>
      _TransactionFiltersBarState();
}

class _TransactionFiltersBarState extends ConsumerState<TransactionFiltersBar> {
  late final TextEditingController _descriptionController;
  late final FocusNode _descriptionFocusNode;
  final _dateFormat = DateFormat('dd/MM/yyyy');
  Timer? _descriptionDebounce;

  @override
  void initState() {
    super.initState();
    _descriptionFocusNode = FocusNode();
    _descriptionController = TextEditingController(
      text: ref
          .read(transactionFiltersProvider(widget.companyId))
          .descriptionQuery,
    );
  }

  @override
  void dispose() {
    _descriptionDebounce?.cancel();
    _descriptionController.dispose();
    _descriptionFocusNode.dispose();
    super.dispose();
  }

  void _scheduleDescriptionFilter(String value) {
    _descriptionDebounce?.cancel();
    _descriptionDebounce = Timer(TransactionFiltersBar.descriptionDebounce, () {
      if (!mounted) {
        return;
      }
      ref
          .read(transactionFiltersProvider(widget.companyId).notifier)
          .setDescriptionQuery(value);
    });
  }

  void _applyDescriptionFilterNow(String value) {
    _descriptionDebounce?.cancel();
    _descriptionDebounce = null;
    ref
        .read(transactionFiltersProvider(widget.companyId).notifier)
        .setDescriptionQuery(value);
  }

  void _clearAllFilters(TransactionFiltersNotifier filtersNotifier) {
    _descriptionDebounce?.cancel();
    _descriptionDebounce = null;
    _descriptionController.clear();
    filtersNotifier.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final filters = ref.watch(transactionFiltersProvider(widget.companyId));
    final filtersNotifier = ref.read(
      transactionFiltersProvider(widget.companyId).notifier,
    );
    final customersAsync = ref.watch(customersProvider(widget.companyId));
    final hasPendingDescription = _descriptionController.text.trim().isNotEmpty;
    final canClearFilters = filters.hasActiveFilters || hasPendingDescription;

    ref.listen<TransactionFilters>(
      transactionFiltersProvider(widget.companyId),
      (previous, next) {
        if (previous?.descriptionQuery != next.descriptionQuery &&
            _descriptionController.text != next.descriptionQuery) {
          _descriptionController.text = next.descriptionQuery;
        }
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.transactionsFiltersTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: AppUiConstants.spacingSmall),
        Wrap(
          spacing: AppUiConstants.spacingSmall,
          runSpacing: AppUiConstants.spacingSmall,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _DateFilterChip(
              label: l10n.transactionsFilterFromDate,
              value: filters.fromDate,
              emptyLabel: l10n.transactionsFilterPickDate,
              dateFormat: _dateFormat,
              onPick: () => _pickDate(
                initial: filters.fromDate,
                onSelected: filtersNotifier.setFromDate,
              ),
              onClear: () => filtersNotifier.setFromDate(null),
            ),
            _DateFilterChip(
              label: l10n.transactionsFilterToDate,
              value: filters.toDate,
              emptyLabel: l10n.transactionsFilterPickDate,
              dateFormat: _dateFormat,
              onPick: () => _pickDate(
                initial: filters.toDate,
                onSelected: filtersNotifier.setToDate,
              ),
              onClear: () => filtersNotifier.setToDate(null),
            ),
          ],
        ),
        const SizedBox(height: AppUiConstants.spacingSmall),
        SegmentedButton<TransactionKind?>(
          segments: [
            ButtonSegment(
              value: null,
              label: Text(l10n.transactionsFilterKindAll),
            ),
            ButtonSegment(
              value: TransactionKind.income,
              label: Text(l10n.transactionKindIncome),
            ),
            ButtonSegment(
              value: TransactionKind.expense,
              label: Text(l10n.transactionKindExpense),
            ),
          ],
          emptySelectionAllowed: false,
          showSelectedIcon: false,
          selected: {filters.kind},
          onSelectionChanged: (selection) {
            filtersNotifier.setKind(selection.first);
          },
        ),
        const SizedBox(height: AppUiConstants.spacingSmall),
        customersAsync.when(
          loading: () => InputDecorator(
            decoration: InputDecoration(
              labelText: l10n.transactionClientLabel,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            child: Text(l10n.transactionClientsLoading),
          ),
          error: (_, _) => InputDecorator(
            decoration: InputDecoration(
              labelText: l10n.transactionClientLabel,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            child: Text(l10n.transactionClientsLoadError),
          ),
          data: (customers) => DropdownButtonFormField<String?>(
            key: ValueKey<String>(filters.clientId ?? 'all-clients'),
            initialValue: _selectedClientId(filters.clientId, customers),
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.transactionClientLabel,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(l10n.transactionsFilterClientAll),
              ),
              ...customers.map(
                (customer) => DropdownMenuItem<String?>(
                  value: customer.id,
                  child: Text(customer.name, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: filtersNotifier.setClientId,
          ),
        ),
        const SizedBox(height: AppUiConstants.spacingSmall),
        TextField(
          key: const Key('transaction-description-filter'),
          controller: _descriptionController,
          focusNode: _descriptionFocusNode,
          decoration: InputDecoration(
            labelText: l10n.transactionsFilterDescriptionHint,
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: hasPendingDescription
                ? IconButton(
                    tooltip: l10n.transactionsFilterClear,
                    onPressed: () {
                      _descriptionController.clear();
                      _applyDescriptionFilterNow('');
                      setState(() {});
                    },
                    icon: const Icon(Icons.clear),
                  )
                : null,
          ),
          textInputAction: TextInputAction.search,
          onChanged: (value) {
            setState(() {});
            _scheduleDescriptionFilter(value);
          },
          onSubmitted: _applyDescriptionFilterNow,
        ),
        const SizedBox(height: AppUiConstants.spacingSmall),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: canClearFilters
                ? () => _clearAllFilters(filtersNotifier)
                : null,
            icon: const Icon(Icons.filter_alt_off_outlined),
            label: Text(l10n.transactionsFilterClear),
          ),
        ),
      ],
    );
  }

  String? _selectedClientId(String? clientId, List<Customer> customers) {
    if (clientId == null || clientId.isEmpty) {
      return null;
    }
    final exists = customers.any((customer) => customer.id == clientId);
    return exists ? clientId : null;
  }

  Future<void> _pickDate({
    required DateTime? initial,
    required ValueChanged<DateTime?> onSelected,
  }) async {
    final now = CalendarDate.todayLocal();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      onSelected(CalendarDate.dateOnly(picked));
    }
  }
}

class _DateFilterChip extends StatelessWidget {
  const _DateFilterChip({
    required this.label,
    required this.value,
    required this.emptyLabel,
    required this.dateFormat,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final String emptyLabel;
  final DateFormat dateFormat;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final text = value == null ? emptyLabel : dateFormat.format(value!);
    return InputChip(
      label: Text('$label: $text'),
      onPressed: onPick,
      onDeleted: value == null ? null : onClear,
    );
  }
}
